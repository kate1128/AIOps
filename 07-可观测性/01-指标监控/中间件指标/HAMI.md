# HAMI 可观测性

> HAMI 是 K8s GPU Device Plugin，支持显存虚拟化与隔离；其指标通过 K8s 设备插件 API 和节点级 Prometheus 端点暴露。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| HAMI 内置 metrics | GPU 分配状态、显存池、vGPU 调度指标 | TCP 8080 /metrics（HAMI 进程）|
| HAMI Core API | 查询 GPU 分配情况和节点状态 | REST API |
| DCGM Exporter | GPU 硬件指标（与 HAMI 互补）| TCP 9400 /metrics |
| nvidia-gpu-exporter | 进程级 GPU 显存归因 | TCP 9835 /metrics |

---

## 核心指标

### HAMI 指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `hami_node_gpu_total` | 节点 GPU 总数 | — |
| `hami_node_gpu_allocated` | 已分配 GPU 数 | == total 说明无可用 GPU |
| `hami_node_gpu_memory_total` | GPU 显存总量 | — |
| `hami_node_gpu_memory_allocated` | 已分配显存 | > 90% 告警 |
| `hami_pod_gpu_memory` | Pod 分配的显存 | — |
| `hami_vgpu_count` | 虚拟 GPU 实例数 | — |
| `hami_container_pending` | 等待 GPU 分配的容器数 | > 0 说明 GPU 资源不足 |

### 与 DCGM 配合的 GPU 硬件指标

| 指标（DCGM Exporter） | 含义 |
|----------------------|------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU 算力利用率 |
| `DCGM_FI_DEV_FB_USED` | GPU 显存使用量 |
| `DCGM_FI_DEV_GPU_TEMP` | GPU 温度 |

HAMI 分配的显存 vs DCGM 实际显存使用：差值 = 宿主机裸进程消耗的显存（不受 HAMI 管控的部分）。

---

## 采集集成

```yaml
# Prometheus scrape（HAMI 进程 metrics）
- job_name: hami
  static_configs:
    - targets:
        - "gpu-node-1:8080"
        - "gpu-node-2:8080"
      labels:
        service: hami
        env: prod

# K8s ServiceMonitor（使用 HAMI 的 Pod 自动发现）
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: hami-gpu-pods
  namespace: observability
spec:
  selector:
    matchLabels:
      hami: enabled
  podMetricsEndpoints:
    - port: metrics
      interval: 15s

# 配合 DCGM Exporter 采集 GPU 硬件指标
- job_name: dcgm
  static_configs:
    - targets:
        - "gpu-node-1:9400"
        - "gpu-node-2:9400"
      labels:
        service: dcgm
        env: prod
```

---

## 告警规则

```yaml
- alert: HAMIGpuFullyAllocated
  expr: hami_node_gpu_allocated == hami_node_gpu_total
  for: 5m
  annotations:
    summary: "节点 {{ $labels.node }} GPU 已全部分配，新增 Pod 将 pending"

- alert: HAMIMemoryHigh
  expr: hami_node_gpu_memory_allocated / hami_node_gpu_memory_total * 100 > 90
  for: 5m
  annotations:
    summary: "节点 {{ $labels.node }} GPU 显存分配率 > 90%"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| K8s + HAMI | HAMI 部署为 DaemonSet，自动暴露 /metrics 端口 |
| Docker + GPU（无 HAMI）| 无法使用 HAMI 指标，直接依赖 DCGM Exporter 和 nvidia-gpu-exporter |
| 宿主机直跑 GPU 进程（无 HAMI）| 无 HAMI 管控，仅通过 DCGM Exporter 看总显存使用 |

**关键公式：** `DCGM显存使用 − HAMI分配显存 = 宿主机裸进程显存消耗（需关注的部分）`
