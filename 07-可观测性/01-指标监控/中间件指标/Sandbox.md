# Sandbox 可观测性

> Sandbox（gVisor / RunC）运行在容器底层，指标通过容器运行时接口和节点级监控覆盖。
> langgenius/dify-sandbox:0.2.1

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| gVisor (runsc) metrics | gVisor Sentry 进程级指标 | Sentry HTTP /metrics（需启用）|
| cAdvisor | 容器资源使用（覆盖 Sandbox 容器）| TCP 8080 /metrics |
| K8s kubelet | Pod 资源使用统计 | TCP 10250 /metrics/cadvisor |
| RunC（默认）| 直接使用宿主机内核，无额外 metrics | 依赖 cAdvisor + node-exporter |

---

## 核心指标

### gVisor (runsc) — Sentry 级

| 指标（启用后） | 含义 |
|---------------|------|
| `runsc_sentry_resident_set_size_bytes` | Sentry 进程 RSS 内存 |
| `runsc_sentry_cpu_usage_seconds` | Sentry CPU 使用 |
| `runsc_go_memstats_alloc_bytes` | Go runtime 内存分配 |
| `runsc_go_goroutines` | Go 协程数 |

### 容器级（cAdvisor / kubelet）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `container_memory_working_set_bytes{pod=~".*sandbox.*"}` | Sandbox 容器内存 | > 90% limit 告警 |
| `container_cpu_cfs_throttled_seconds_total{pod=~".*sandbox.*"}` | CPU 限流时间 | > 0 说明 CPU limit 不足 |
| `container_network_receive_bytes_total{pod=~".*sandbox.*"}` | 网络入流量 | — |
| `container_network_transmit_bytes_total{pod=~".*sandbox.*"}` | 网络出流量 | — |

---

## 采集集成

```yaml
# gVisor 启用 metrics（runsc 启动参数）
runsc --platform=kvm \
      --metrics-server=:9001 \
      run sandbox

# Prometheus scrape
- job_name: gvisor-sandbox
  static_configs:
    - targets:
        - "sandbox-node:9001"
      labels:
        service: gvisor
        env: prod

# cAdvisor 已覆盖容器级指标
- job_name: cadvisor-sandbox
  static_configs:
    - targets:
        - "node:8080"
      labels:
        service: sandbox-container
  # 通过 relabel 过滤 Sandbox Pod
  metric_relabel_configs:
    - source_labels: [pod]
      regex: .*sandbox.*
      action: keep
```

---

## 告警规则

```yaml
- alert: SandboxMemoryHigh
  expr: container_memory_working_set_bytes{pod=~".*sandbox.*"} / on(pod) container_spec_memory_limit_bytes{pod=~".*sandbox.*"} * 100 > 90
  for: 3m
  annotations:
    summary: "Sandbox 容器 {{ $labels.pod }} 内存使用率 > 90%"

- alert: SandboxCPULimitReached
  expr: rate(container_cpu_cfs_throttled_seconds_total{pod=~".*sandbox.*"}[5m]) > 0
  for: 10m
  annotations:
    summary: "Sandbox 容器 CPU 被限流（可能 limit 设置过小）"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| gVisor (runsc) | 启动时加 `--metrics-server` 暴露 Go/系统指标 |
| RunC（默认）| 无 sandbox 专用指标，完全由 cAdvisor + node-exporter 覆盖 |
| K8s + gVisor RuntimeClass | Sandbox Pod 的指标由 kubelet /metrics/cadvisor 统一采集 |
| Docker + gVisor | 不常用，建议 K8s 统一管理 |

gVisor 的 Sentry 级指标（runsc_*）默认不启用，需在 containerd 配置中转递 `--metrics-server` 参数才能采集。
