# 异构计算（GPU / NPU / TPU）可观测性

> 异构算力的可观测性由 DCGM Exporter（NVIDIA GPU）和其他厂商采集器覆盖；NPU/TPU 需要有对应的厂商驱动/采集器。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| DCGM Exporter | NVIDIA GPU 硬件指标（官方推荐）| TCP 9400 /metrics |
| nvidia-smi | 命令行工具，调试用 | CLI，可被脚本转成 metrics |
| nvidia-gpu-exporter | 进程级 GPU 显存归因 | TCP 9835 /metrics |
| dcgm-exporter（K8s）| K8s DaemonSet 部署，自动 GPU 节点调度 | ServiceMonitor |
| NPU/TPU 厂商采集器 | 华为昇腾 / 寒武纪 / Google TPU 专有工具 | 厂商 SDK |

---

## 核心指标

### NVIDIA GPU（DCGM Exporter）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU 算力利用率（%）| < 10% 持续 30min → 资源浪费 |
| `DCGM_FI_DEV_FB_USED` | GPU 显存使用量（MiB）| > 90% → P1 告警 |
| `DCGM_FI_DEV_GPU_TEMP` | GPU 温度 | L20 > 80°C，A100 > 85°C → P1 |
| `DCGM_FI_DEV_POWER_USAGE` | GPU 功耗（W）| 接近 TDP → P2 关注 |
| `DCGM_FI_DEV_XID_ERRORS` | NVIDIA XID 错误 | 任何出现 → P1 立即排查 |
| `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | 不可纠正 ECC 错误 | > 0 → P0 立即摘除节点 |
| `DCGM_FI_DEV_MEM_CLOCK` | 显存频率 | — |
| `DCGM_FI_DEV_SM_CLOCK` | SM 频率 | — |

### 进程级显存归因（nvidia-gpu-exporter）

| 指标 | 含义 |
|------|------|
| `nvidia_smi_memory_used_bytes{process_name="vllm"}` | vLLM 进程显存使用 |
| `nvidia_smi_memory_used_bytes{process_name="python"}` | Python 推理脚本显存使用 |

### NPU / TPU（厂商通用维度）

| 维度 | 说明 |
|------|------|
| 算力利用率 | NPU/TPU 的核心利用率 |
| 内存使用 | NPU HBM 使用量 |
| 温度 | NPU 温度（通常限制 < 100°C）|
| 内存带宽 | HBM 带宽利用率 |

---

## 采集集成

```yaml
# DCGM Exporter 部署（K8s）
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace observability \
  --set serviceMonitor.enabled=true

# DCGM Exporter（Docker）
docker run -d \
  --name=dcgm-exporter \
  --restart=always \
  --gpus all \
  --publish 9400:9400 \
  nvidia/dcgm-exporter:latest

# nvidia-gpu-exporter（宿主机裸进程显存）
# 下载二进制
wget https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/latest/download/nvidia_gpu_exporter_linux_amd64
chmod +x nvidia_gpu_exporter_linux_amd64
nohup ./nvidia_gpu_exporter_linux_amd64 --port 9835 &

# Prometheus scrape
- job_name: dcgm
  static_configs:
    - targets:
        - "gpu-node-1:9400"
      labels:
        service: dcgm
        env: prod

- job_name: nvidia-process
  static_configs:
    - targets:
        - "gpu-node-1:9835"
      labels:
        service: nvidia-process
        env: prod
```

---

## 告警规则

```yaml
- alert: GPUTemperatureHigh
  expr: DCGM_FI_DEV_GPU_TEMP > 85
  for: 2m
  annotations:
    summary: "GPU {{ $labels.gpu }} 温度 {{ $value }}°C"

- alert: GPUMemoryHigh
  expr: DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100 > 95
  for: 5m
  annotations:
    summary: "GPU {{ $labels.gpu }} 显存使用超过 95%"

- alert: GPUECCError
  expr: DCGM_FI_DEV_ECC_DBE_VOL_TOTAL > 0
  labels:
    severity: critical
  annotations:
    summary: "GPU {{ $labels.gpu }} 出现 ECC 不可纠正错误，需要摘除"

- alert: GPUUtilizationLow
  expr: DCGM_FI_DEV_GPU_UTIL < 10
  for: 30m
  annotations:
    summary: "GPU {{ $labels.gpu }} 利用率低于 10% 已 30 分钟"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| K8s GPU 节点 | DCGM Exporter DaemonSet + ServiceMonitor 自动发现 |
| Docker GPU 容器 | DCGM Exporter 容器同机部署，static_configs 指到宿主机 |
| 宿主机直跑推理脚本 | DCGM Exporter 同机部署 + nvidia-gpu-exporter 获取进程级显存 |
| 非 NVIDIA（NPU/TPU）| 使用厂商 SDK（华为昇腾：npu-exporter，寒武纪：cambricon-exporter）|

**混合部署的显存计算：**
- K8s Pod（HAMI 分配）：`DCGM 总显存 = Σ HAMI Pod 分配显存 + 裸进程显存`
- Docker / 宿主机（无 HAMI）：`DCGM 总显存 = Σ 所有进程显存`（由 nvidia-gpu-exporter 拆解）

---

## 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
|--------|---------|---------|---------|---------|
| DCGM Exporter | DaemonSet/容器 | GPU 硬件全量（温度/利用率/显存/ECC） | 无 | NVIDIA GPU 标准方案 |
| nvidia-gpu-exporter | 宿主机二进制 | 进程级 GPU 显存归因 | 无 | 需进程级显存拆解 |
| DCGM + nvidia-gpu-exporter | 组合 | 全量覆盖 | 无 | 生产推荐 |
| Grafana Alloy | 抓取 exporter 端口 | 同上 | 内置 loki.source | Grafana 全栈 |
| Netdata | 一键安装 | 内置 nvidia_smi collector | 内置日志查看 | 快速部署 |

---

## Alloy 采集配置

```alloy
// DCGM Exporter
prometheus.scrape "dcgm" {
  targets = [
    { __address__ = "gpu-node-1:9400", service = "dcgm" },
    { __address__ = "gpu-node-2:9400", service = "dcgm" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
}

// nvidia-gpu-exporter（进程级显存）
prometheus.scrape "nvidia_process" {
  targets = [
    { __address__ = "gpu-node-1:9835", service = "nvidia-process" },
    { __address__ = "gpu-node-2:9835", service = "nvidia-process" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

---

## 方案对比

| 维度 | DCGM Exporter + Prometheus | Alloy | Netdata |
|------|--------------------------|-------|---------|
| 部署复杂度 | 中（需 GPU 节点调度） | 中 | 低 |
| 进程级显存 | 需额外 nvidia-gpu-exporter | 同左 | ❌ |
| 非 NVIDIA GPU | ❌ 需厂商 exporter | 同左 | ❌ |
| Grafana 兼容 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 推荐场景 | K8s GPU 集群标准方案 | Grafana 全栈 | 快速验证 |
