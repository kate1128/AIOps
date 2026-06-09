# Docker 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Docker Daemon metrics：[Configure Docker daemon metrics](https://docs.docker.com/config/daemon/prometheus/)
2. cAdvisor：[google/cadvisor](https://github.com/google/cadvisor)
3. Alloy 内置集成：[prometheus.exporter.cadvisor](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.cadvisor/)
4. Alloy Docker 日志：[loki.source.docker](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/)
5. 官方示例：[alloy-scenarios/docker-monitoring](https://github.com/grafana/alloy-scenarios/tree/main/docker-monitoring)

---

## 1. 结论摘要

Docker 可观测性分为两层：Docker Daemon 自身健康指标和容器资源指标。Daemon 指标需在 `daemon.json` 中开启 `metrics-addr`；容器 CPU、内存、网络、磁盘等指标通常由 cAdvisor 采集。在 Grafana Alloy 体系下，**无需单独部署 cAdvisor 和 Promtail**，Alloy 内置 `prometheus.exporter.cadvisor` 采集容器指标，并通过 `loki.source.docker` 采集容器日志。

| 关键信息 | 值 |
| --- | --- |
| Daemon 指标端口 | TCP `9323` `/metrics`（需手动开启）|
| 容器指标采集 | cAdvisor / Alloy 内置 `prometheus.exporter.cadvisor` |
| 日志采集 | Docker json-file / Alloy `loki.source.docker` |
| Alloy 内置替代 | 替代独立 cAdvisor + Promtail |
| 推荐方案 | Alloy 统一采集 Docker 指标和日志 |

---

## 2. 产品概况（Docker + cAdvisor）

| 项目 | 内容 |
| --- | --- |
| Docker Daemon metrics | Docker 引擎状态、事件、容器状态分布 |
| cAdvisor | 容器级 CPU、内存、网络、磁盘、重启指标 |
| Alloy 集成 | `prometheus.exporter.cadvisor` + `loki.source.docker` |
| 数据来源 | Docker socket、cgroup、Docker json log |
| 部署形态 | 宿主机二进制 / 容器 / Alloy 单采集器 |

### 2.1 开启 Docker Daemon metrics

Docker Daemon 默认不开启 Prometheus metrics，需要在宿主机 `/etc/docker/daemon.json` 中配置 `metrics-addr`，然后重启 `dockerd`。单机本地采集建议绑定 `127.0.0.1:9323`；需要远程 Prometheus / Alloy 抓取时再绑定 `0.0.0.0:9323`，并通过防火墙或安全组限制访问来源。

```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

Linux systemd 环境重启 Docker：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl status docker --no-pager
```

验证 metrics 端点：

```bash
curl http://127.0.0.1:9323/metrics | head
```

如果 Alloy 与 Docker Daemon 在同一宿主机，Alloy 抓取地址可以写 `127.0.0.1:9323`；如果 Alloy 以容器方式运行，需要确认容器网络能访问宿主机的 `9323` 端口。

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `engine_daemon_container_states_containers` | Docker 容器状态分布 | stopped 异常增长需关注 |
| `engine_daemon_container_start_latency_seconds` | 容器启动延迟 | P99 > 30s 告警 |
| `engine_daemon_container_creation_errors_total` | 容器创建失败次数 | 5m 内增长告警 |
| `container_cpu_usage_seconds_total` | 容器 CPU 使用总量 | 与 quota 比值 > 90% 告警 |
| `container_cpu_cfs_throttled_seconds_total` | CPU 被限流时长 | 限流比例 > 20% 告警 |
| `container_memory_usage_bytes` | 容器内存使用 | > 90% limit 告警 |
| `container_network_receive_bytes_total` / `container_network_transmit_bytes_total` | 容器网络流量 | 突增排查异常流量 |
| `container_fs_usage_bytes` | 容器文件系统使用 | > 85% 告警 |
| `container_last_seen` | 容器最后可见时间 | absent 检测容器消失 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| cAdvisor | 独立容器 | 容器资源全量 | 无 | Prometheus 传统标准方案 |
| Docker Daemon metrics | Docker 内置 | Docker 引擎状态 | 无 | 补充 Docker 引擎健康 |
| **Grafana Alloy** | 单采集器 | cAdvisor + Docker 日志 | `loki.source.docker` | **本项目首选** |
| Netdata | 一键安装 | 系统 + Docker + 应用插件 | 内置 | 快速验证、小规模环境 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 容器指标采集

```alloy
prometheus.exporter.cadvisor "docker" {
  docker_host      = "unix:///var/run/docker.sock"
  docker_only      = true
  storage_duration = "5m"
}

prometheus.scrape "docker_containers" {
  targets         = prometheus.exporter.cadvisor.docker.targets
  scrape_interval = "10s"
  forward_to      = [prometheus.remote_write.central.receiver]
  job_name        = "integrations/docker"
}
```

### 5.2 Docker Daemon 指标采集

```alloy
prometheus.scrape "docker_daemon" {
  targets = [{ __address__ = "docker-host:9323", service = "docker-daemon" }]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.3 Docker 容器日志采集

```alloy
discovery.docker "linux" {
  host = "unix:///var/run/docker.sock"
}

loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.linux.targets
  labels     = { platform = "docker" }
  forward_to = [loki.write.default.receiver]
}
```

---

## 6. 独立 cAdvisor 部署（备选）

```bash
docker run -d --name cadvisor \
  -p 8080:8080 \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:latest
```

---

## 7. 告警规则

```yaml
groups:
- name: docker.rules
  rules:
  - alert: DockerContainerRestarting
    expr: increase(container_restart_count[10m]) > 3
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "容器频繁重启"
      description: "容器 {{ $labels.name }} 10 分钟内重启超过 3 次。"

  - alert: DockerContainerMemoryHigh
    expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "容器内存使用率过高"

  - alert: DockerContainerCpuThrottlingHigh
    expr: rate(container_cpu_cfs_throttled_seconds_total[5m]) / rate(container_cpu_cfs_periods_total[5m]) > 0.2
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "容器 CPU 限流过高"
```

---

## 8. Grafana Dashboard

| Dashboard | 适用场景 |
| --- | --- |
| Docker and system monitoring | Docker 容器资源总览 |
| cAdvisor exporter dashboard | 容器 CPU / 内存 / 网络 / 磁盘 |
| Loki Docker logs | 容器日志检索与错误分析 |

---

## 9. KAgent 集成（Docker 运维 Agent）

官方 MCP 仓库无 Docker 运维专用 MCP。推荐绑定 PrometheusServer 查询 Docker/cAdvisor 指标，并用 Git-Based Skills 注入容器运维规范。

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: docker-ops-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    systemMessage: "你是 Docker 运维助手，优先通过 Prometheus 查询容器资源和重启指标。"
    tools:
    - type: ToolServer
      toolServer:
        kind: ToolServer
        name: prometheus
        toolNames: ["prometheus_query", "prometheus_query_range"]
```

---

## 10. 常见问题

### Grafana Alloy 能采集 Docker 指标吗？

**可以。** Alloy 内置 `prometheus.exporter.cadvisor`，可直接采集 Docker 容器资源指标；同时通过 `loki.source.docker` 采集容器日志，无需单独部署 cAdvisor 和 Promtail。

### Alloy 能采集 Docker Daemon 指标吗？

可以，但 Docker Daemon 默认不开启 metrics，需先在 `/etc/docker/daemon.json` 配置 `metrics-addr` 并重启 `dockerd`。Alloy 使用 `prometheus.scrape` 抓取 `:9323/metrics`，这部分不是 cAdvisor 指标。

### Docker 和 Kubernetes 迁移期间会重复采集吗？

可能会。Kubernetes 中 kubelet 已内置 cAdvisor 指标，迁移期间应逐步关闭独立 cAdvisor，避免容器指标重复进入 Prometheus。
