# GPU 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. NVIDIA DCGM Exporter：[NVIDIA/dcgm-exporter](https://github.com/NVIDIA/dcgm-exporter)
2. NVIDIA DCGM 文档：[DCGM Documentation](https://docs.nvidia.com/datacenter/dcgm/latest/)
3. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)
4. nvidia-gpu-exporter：[utkuozdemir/nvidia_gpu_exporter](https://github.com/utkuozdemir/nvidia_gpu_exporter)
5. Ingero Agent：[ingero-io/ingero](https://github.com/ingero-io/ingero)

---

## 1. 结论摘要

NVIDIA GPU 监控的标准方案是 **DCGM Exporter**，它暴露 GPU 利用率、显存、温度、功耗、ECC/XID 错误等硬件指标。在 Grafana Alloy 体系下，Alloy 不直接读取 GPU 设备，而是通过 `prometheus.scrape` 抓取 DCGM Exporter `:9400/metrics`。若需要 CUDA 调用延迟、NCCL 集合通信、按方向区分的 memcpy 带宽、显存碎片等更细粒度数据，可补充 nvidia-gpu-exporter 或 Ingero Agent 这类 eBPF GPU tracing 工具。

| 关键信息 | 值 |
| --- | --- |
| 主流采集器 | NVIDIA DCGM Exporter |
| 暴露端口 | TCP `9400` `/metrics` |
| Alloy 集成 | `prometheus.scrape` 抓取 DCGM Exporter |
| 进程级显存 | nvidia-gpu-exporter / Ingero Agent |
| 深度 tracing | Ingero Agent（CUDA / NCCL / memcpy / 显存碎片）|
| 推荐组合 | DCGM Exporter + Alloy + vLLM 指标；性能诊断补 Ingero Agent |

---

## 2. 产品概况（DCGM Exporter）

| 项目 | 内容 |
| --- | --- |
| 产品名称 | DCGM Exporter |
| 维护方 | NVIDIA |
| 部署形态 | Docker / K8s DaemonSet / Helm |
| 数据来源 | NVIDIA DCGM / NVML |
| 支持能力 | GPU 利用率、显存、温度、功耗、ECC、XID、MIG |
| 适用场景 | NVIDIA GPU 生产监控标准方案 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `DCGM_FI_DEV_GPU_UTIL` | GPU 算力利用率 | < 10% 持续 30min 资源浪费；>95% 长期满载需扩容 |
| `DCGM_FI_DEV_FB_USED` / `DCGM_FI_DEV_FB_FREE` | 显存使用 / 剩余 | 使用率 > 95% 告警 |
| `DCGM_FI_DEV_GPU_TEMP` | GPU 温度 | > 85°C 告警 |
| `DCGM_FI_DEV_POWER_USAGE` | 当前功耗 | 接近 TDP 关注 |
| `DCGM_FI_DEV_XID_ERRORS` | NVIDIA XID 错误 | > 0 立即排查 |
| `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | 不可纠正 ECC 错误 | > 0 摘除节点 |
| `DCGM_FI_DEV_SM_CLOCK` / `DCGM_FI_DEV_MEM_CLOCK` | SM / 显存频率 | 异常降频排查散热/功耗 |
| `gpu_cuda_operation_duration_microseconds` | CUDA 调用延迟百分位（Ingero）| P95/P99 异常升高时排查 Kernel / 同步调用 |
| `gpu_memcpy_bytes_total{direction}` | H2D/D2H/D2D memcpy 字节数（Ingero）| 数据搬运异常突增关注 |
| `gpu_nccl_collective_count` / `gpu_nccl_collective_bytes_total` | NCCL 集合通信统计（Ingero）| 多卡通信瓶颈排查 |
| `gpu_memory_fragmentation_estimate` | 显存碎片估算（Ingero）| 碎片升高时排查显存分配模式 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 适用场景 |
| --- | --- | --- | --- |
| **DCGM Exporter** | DaemonSet / Docker | GPU 硬件全量 | **NVIDIA 标准方案** |
| nvidia-gpu-exporter | 宿主机二进制 | 进程级显存 | 需要进程归因 |
| Ingero Agent | eBPF uprobes / kprobe | CUDA 调用延迟、memcpy、NCCL、显存碎片、限速事件 | 深度 GPU tracing / 性能诊断 |
| Grafana Alloy | `prometheus.scrape` | 抓取上述 exporter | Grafana 全栈 |
| Netdata | Agent | 基础 nvidia-smi | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 抓取 DCGM Exporter

```alloy
prometheus.scrape "dcgm" {
  targets = [
    { __address__ = "gpu-node-1:9400", service = "dcgm" },
    { __address__ = "gpu-node-2:9400", service = "dcgm" },
  ]
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "integrations/dcgm-exporter"
}
```

### 5.2 k8s-monitoring Helm 集成

```yaml
integrations:
  dcgm-exporter:
    instances:
      - name: dcgm-exporter
        labelSelectors:
          app: nvidia-dcgm-exporter
```

### 5.3 进程级显存补充

```alloy
prometheus.scrape "nvidia_process" {
  targets = [{ __address__ = "gpu-node-1:9835", service = "nvidia-process" }]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.4 抓取 Ingero Agent（可选深度 tracing）

Grafana Alloy 支持 Ingero Agent，但不是通过内置 `prometheus.exporter.ingero` 组件支持，而是通过 `prometheus.scrape` 抓取 Ingero Agent 暴露的标准 Prometheus 指标端点。两者的关系与 Alloy 和 JMX Exporter 类似：Ingero Agent 负责生成 GPU tracing 指标，Alloy 负责抓取、加标签和转发。

```text
NVIDIA GPU（libcudart / libcuda / libnccl）
  -> eBPF uprobes
Ingero Agent（:9090/metrics）
  -> prometheus.scrape
Grafana Alloy
  -> prometheus.remote_write
Grafana Cloud / Mimir / Prometheus
```

```alloy
prometheus.scrape "ingero_gpu" {
  targets = [{ __address__ = "gpu-node-1:9090", service = "ingero-agent" }]
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "integrations/ingero-agent"
}
```

| 注意事项 | 说明 |
| --- | --- |
| Alloy 组件 | 没有内置 `prometheus.exporter.ingero`，使用 `prometheus.scrape` 抓取 HTTP metrics 端点 |
| Ingero 端点 | 需启动 `sudo ingero trace --prometheus :9090` |
| 支持平台 | Linux only，amd64 / arm64 |
| 指标命名 | Prometheus 格式为 `gpu_*`，OTLP 格式为 `gpu.*` |
| Dashboard | 可使用 GPU Trace Overview、CUDA Op Profiler、GPU Data Movement、GPU Memory & Throttle |

---

## 6. DCGM Exporter 部署

```bash
docker run -d --name dcgm-exporter \
  --gpus all \
  -p 9400:9400 \
  nvcr.io/nvidia/k8s/dcgm-exporter:latest
```

```bash
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace observability \
  --set serviceMonitor.enabled=true
```

### 6.1 Ingero Agent 可选部署

Ingero Agent 适合用于专项性能诊断，不建议替代 DCGM Exporter 作为基础 GPU 监控。它通过 eBPF uprobes 挂载到 `libcudart.so`、`libcuda.so`、`libnccl.so`，采集 CUDA Runtime API、CUDA Driver API、NCCL 集合通信，并结合 NVML / nvidia-smi 轮询采集显存、温度和限速状态。

```bash
# 安装 Agent
curl -sSL https://github.com/ingero-io/ingero/releases/latest/download/install.sh | bash

# 启动并暴露 Prometheus 端点
sudo ingero trace --prometheus :9090

# 启用 NCCL 采集
sudo ingero trace --nccl --prometheus :9090

# 启用实验性 kprobe 采集显存碎片 IOCTL 事件
sudo ingero trace --enable-experimental-kprobes --prometheus :9090
```

| 采集方式 | 说明 |
| --- | --- |
| eBPF uprobes on `libcudart.so` | 采集 `cudaMemcpy`、`cudaMalloc`、`cudaLaunchKernel` 等 CUDA Runtime API 调用 |
| eBPF uprobes on `libcuda.so` | 采集 `cuLaunchKernel`、`cuCtxSynchronize`、`cuMemAlloc_v2` 等 CUDA Driver API 调用 |
| eBPF uprobes on `libnccl.so` | 采集 NCCL 集合通信操作，需启用 `--nccl` |
| NVML / nvidia-smi 轮询 | 采集 GPU 显存、温度、限速状态 |
| kprobe on `nvidia_unlocked_ioctl` | 采集显存碎片 IOCTL 事件，实验能力，需启用 `--enable-experimental-kprobes` |

支持平台：Linux only，amd64 / arm64；指标格式包括 Prometheus `gpu_*` 和 OTLP `gpu.*`。

在 Grafana Alloy 场景下，Ingero Agent 启动后只需要暴露 Prometheus 端点，Alloy 通过 `prometheus.scrape` 抓取并通过 `prometheus.remote_write` 转发到 Grafana Cloud、Mimir 或自建 Prometheus。该模式适合把 Ingero 的 per-call tracing 指标纳入统一 GPU 可观测体系。

---

## 7. 告警规则

```yaml
groups:
- name: gpu.rules
  rules:
  - alert: GPUTemperatureHigh
    expr: DCGM_FI_DEV_GPU_TEMP > 85
    for: 2m
    labels: { severity: critical }
    annotations: { summary: "GPU 温度过高" }

  - alert: GPUMemoryHigh
    expr: DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.95
    for: 5m
    labels: { severity: critical }
    annotations: { summary: "GPU 显存使用率超过 95%" }

  - alert: GPUXIDError
    expr: increase(DCGM_FI_DEV_XID_ERRORS[5m]) > 0
    for: 0m
    labels: { severity: critical }
    annotations: { summary: "GPU 出现 XID 错误" }
```

---

## 8. Grafana Dashboard

推荐使用 NVIDIA DCGM Exporter Dashboard，并与 vLLM Dashboard 联动：GPU 硬件层看 DCGM，推理层看 vLLM。若引入 Ingero Agent，可补充 GPU Trace Overview、CUDA Op Profiler、GPU Data Movement、GPU Memory & Throttle 等 Dashboard；多节点场景可结合 Ingero Fleet 查看 GPU Cluster Overview、NCCL Stragglers、Per-Node GPU Drill-Down。

---

## 9. KAgent 集成（GPU 运维 Agent）

推荐绑定 PrometheusServer 查询 DCGM 指标，并通过 Skills 注入 GPU 故障处理 SOP，例如 XID/ECC 错误摘除节点、温度过高检查散热、显存满载排查 vLLM KV Cache。若部署 Ingero Agent，可让 KAgent 进一步查询 CUDA 调用延迟、memcpy 方向带宽、NCCL 通信速率和显存碎片指标，用于定位“GPU 利用率不低但推理/训练很慢”的深层原因。

---

## 10. 常见问题

### Grafana Alloy 能采集 GPU 指标吗？

**可以。** 推荐通过 NVIDIA DCGM Exporter 暴露 Prometheus 指标，Alloy 使用 `prometheus.scrape` 抓取 `:9400/metrics`。

### Alloy 有内置 GPU exporter 吗？

没有专门内置 GPU exporter。GPU 硬件指标由 DCGM Exporter 负责，Alloy 负责抓取和转发。

### DCGM Exporter 和 eBPF GPU Agent 有什么区别？

DCGM Exporter 采集设备级硬件指标；eBPF Agent 可采集 CUDA 调用延迟、NCCL 通信、显存碎片等更细粒度指标。生产基础监控优先 DCGM，深度性能分析再补 eBPF。

### Ingero Agent 是什么？

Ingero Agent 是一个面向 NVIDIA GPU 的开源深度采集工具，通过 eBPF uprobes 对 CUDA Runtime API、CUDA Driver API、NCCL 集合通信进行 per-call tracing，并补充 NVML / nvidia-smi 轮询指标。它能弥补 DCGM/nvidia-smi 只能轮询设备状态、难以解释单次 CUDA 调用延迟和数据搬运瓶颈的问题。

### Ingero Agent 适合替代 DCGM Exporter 吗？

不建议替代。DCGM Exporter 是生产基础监控的标准方案，适合稳定采集 GPU 硬件健康指标；Ingero Agent 更适合作为深度性能诊断补充，用于排查 CUDA 调用慢、memcpy 带宽异常、NCCL 通信瓶颈、显存碎片和限速事件。

### Alloy 怎么采集 Ingero Agent？

Ingero Agent 启动 `sudo ingero trace --prometheus :9090` 后会暴露 Prometheus 端点，Alloy 通过 `prometheus.scrape` 抓取 `:9090/metrics`，再通过 `prometheus.remote_write` 转发到 Grafana Cloud、Mimir 或 Prometheus。

### Grafana Alloy 支持 Ingero Agent 吗？

**支持。** Ingero Agent 暴露标准 Prometheus 格式指标端点，Alloy 可以通过 `prometheus.scrape` 直接抓取。需要注意的是，Alloy 没有内置 `prometheus.exporter.ingero`；集成方式是 Ingero Agent 生成 GPU 指标，Alloy 抓取并转发。
