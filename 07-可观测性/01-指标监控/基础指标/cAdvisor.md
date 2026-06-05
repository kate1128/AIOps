# cAdvisor — 容器资源监控

## 概述

cAdvisor（Container Advisor）是 Google 开源的容器指标采集器，自动发现宿主机上运行的所有容器，采集 CPU、内存、网络、磁盘 IO 等资源使用数据，并以 Prometheus 格式暴露。

- GitHub: [google/cadvisor](https://github.com/google/cadvisor) ⭐ ~17k
- 默认端口: `8080/metrics`
- K8s 场景：**已内置于 kubelet**，无需独立部署

---

## 核心能力

- **零配置自动发现**：读取 `/sys/fs/cgroup` 和 Docker API，自动采集所有容器
- **多运行时支持**：Docker、containerd、CRI-O、Podman
- **资源隔离感知**：识别 CPU/内存 Limit 和 Request，计算使用率百分比
- **多层级标签**：容器名、镜像名、Pod 名、Namespace 自动打标签

---

## 核心指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `container_cpu_usage_seconds_total` | 容器 CPU 累计使用时间 | `rate > limit × 0.9` 持续 5m 告警 |
| `container_memory_working_set_bytes` | 容器实际使用内存（不可回收）| > limit × 90% 告警 |
| `container_memory_usage_bytes` | 容器内存使用（含 cache）| 参考用 |
| `container_memory_cache` | 容器 Page Cache | — |
| `container_network_receive_bytes_total` | 容器网络入流量 | — |
| `container_network_transmit_bytes_total` | 容器网络出流量 | — |
| `container_network_receive_errors_total` | 网络接收错误数 | > 0 持续增长关注 |
| `container_fs_usage_bytes` | 容器镜像层磁盘使用 | — |
| `container_cpu_cfs_throttled_seconds_total` | CPU 被限流时间 | `rate > 0` 持续增长 → limit 设置过低 |
| `container_restarts_total` | 容器重启次数 | > 3 次/10min P1 告警 |
| `container_last_seen` | 容器最后存活时间 | 用于检测容器消失 |

---

## 在本项目中的使用

### K8s 场景（已自动覆盖）

> K8s 的 kubelet 内置 cAdvisor，Prometheus 通过 `https://NODE_IP:10250/metrics/cadvisor` 直接采集，**无需单独部署**。

```yaml
# kube-prometheus-stack 已自动配置此 scrape job
# 手动配置示例：
scrape_configs:
  - job_name: kubelet-cadvisor
    scheme: https
    kubernetes_sd_configs:
      - role: node
    tls_config:
      insecure_skip_verify: true
    authorization:
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    metrics_path: /metrics/cadvisor
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
```

### Docker 宿主机（纯 Docker 非 K8s 场景）

> 当前状态：🔴 未部署。需要在以下节点独立部署 cAdvisor：ai-backend 容器宿主机。

```bash
# Docker 部署（特权模式必须，读取 cgroup 数据）
docker run -d \
  --name cadvisor \
  --privileged \
  --restart=always \
  -p 8080:8080 \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  -v /dev/disk/:/dev/disk:ro \
  gcr.io/cadvisor/cadvisor:v0.49.1
```

### 方案一 Alloy 采集配置

```river
// 方案一中通过 kubelet 抓取 cAdvisor（K8s 内置）
prometheus.scrape "kubelet_cadvisor" {
  targets = [{ __address__ = "NODE_IP:10250" }]
  metrics_path  = "/metrics/cadvisor"
  scheme        = "https"
  tls_config    { insecure_skip_verify = true }
  authorization { credentials_file = "/var/run/secrets/kubernetes.io/serviceaccount/token" }
  forward_to = [prometheus.remote_write.central.receiver]
}

// Docker 宿主机上独立部署的 cAdvisor
prometheus.scrape "docker_cadvisor" {
  targets = [
    { __address__ = "10.0.1.50:8080", service = "cadvisor", node = "docker-host-1" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

---

## 常用告警规则

```yaml
groups:
  - name: container
    rules:
      - alert: ContainerHighMemory
        expr: |
          (container_memory_working_set_bytes{container!=""} /
           container_spec_memory_limit_bytes{container!=""}) > 0.9
        for: 5m
        annotations:
          summary: "容器内存使用超过 Limit 90%: {{ $labels.pod }}/{{ $labels.container }}"

      - alert: ContainerHighCPUThrottle
        expr: |
          rate(container_cpu_cfs_throttled_seconds_total{container!=""}[5m]) > 0.1
        for: 10m
        annotations:
          summary: "容器 CPU 持续被限流: {{ $labels.pod }}/{{ $labels.container }}"

      - alert: ContainerRestartTooFrequent
        expr: |
          increase(container_restarts_total{container!=""}[10m]) > 3
        annotations:
          summary: "容器 10 分钟内重启 3 次以上: {{ $labels.pod }}/{{ $labels.container }}"
```

---

## Grafana Dashboard

| Dashboard | ID | 说明 |
|-----------|-----|------|
| Kubernetes / Compute Resources / Pod | 已含于 kube-prometheus-stack | 内置面板 |
| Docker and system monitoring | 893 | 纯 Docker 场景 |
