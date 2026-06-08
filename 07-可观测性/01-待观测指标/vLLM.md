# vLLM — AI 推理服务指标

## 概述

vLLM 是高性能大语言模型推理引擎（PagedAttention + 连续批处理），内置 Prometheus 指标端点，无需额外 Exporter 即可直接被 Prometheus 采集。

- GitHub: [vllm-project/vllm](https://github.com/vllm-project/vllm) ⭐ ~43k
- 默认指标端口: 与服务端口相同，路径 `/metrics`（默认 8000）
- CNCF 状态: 非 CNCF 项目，但已是 AI 推理事实标准

---

## 核心能力（可观测性维度）

- **推理性能全覆盖**：TTFT（首 Token 延迟）、TPOT（Token 间延迟）、E2E 延迟、吞吐量
- **KV Cache 状态**：缓存命中率、占用率是判断推理瓶颈的关键指标
- **请求队列**：等待/运行/完成请求数，用于判断负载压力
- **GPU 显存**：通过 KV Cache 使用量间接反映，配合 DCGM Exporter 形成完整视图

---

## 核心指标

### 推理性能

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `vllm:time_to_first_token_seconds` | 首 Token 延迟（TTFT，Histogram）| P99 > 5s 告警（正常应 < 2s）|
| `vllm:time_per_output_token_seconds` | 每个输出 Token 的生成间隔（TPOT）| P99 > 500ms 关注 |
| `vllm:e2e_request_latency_seconds` | 端到端请求延迟 | P99 > 30s 告警 |
| `vllm:request_success_total` | 成功完成的请求数 | — |
| `vllm:request_prompt_tokens_total` | 总输入 Token 数 | 用于成本核算 |
| `vllm:request_generation_tokens_total` | 总输出 Token 数 | 用于成本核算 |

### 请求队列

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `vllm:num_requests_waiting` | 等待调度的请求数 | > 50 持续 5m 说明 GPU 算力不足 |
| `vllm:num_requests_running` | 正在执行批处理的请求数 | 接近 `max_batch_size` 关注 |
| `vllm:num_requests_swapped` | 被换出到 CPU 的请求数 | > 0 说明 KV Cache 满了，性能严重下降 |

### KV Cache（核心 GPU 显存指标）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `vllm:gpu_cache_usage_perc` | GPU KV Cache 占用百分比 | > 90% 持续 5m P1 告警 |
| `vllm:cpu_cache_usage_perc` | CPU KV Cache 占用百分比 | > 50% 说明已开始 Swap，需扩容 GPU |
| `vllm:gpu_prefix_cache_hit_rate` | 前缀 KV Cache 命中率 | < 30% 可考虑调整 `enable_prefix_caching` |

### 系统健康

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `vllm:num_preemptions_total` | 被抢占（换出）的请求次数 | > 0 持续增长 P2 告警 |
| `vllm:avg_generation_throughput_toks_per_s` | 平均生成吞吐量（Tokens/s）| 骤降说明 GPU 异常或负载过高 |
| `vllm:avg_prompt_throughput_toks_per_s` | 平均输入 Token 处理速率 | — |

---

## 在本项目中的使用

### 当前状态

> 🟡 vLLM `/metrics` 端点已就绪，但 Prometheus ServiceMonitor 未配置，指标未纳入 Grafana 可视化。

### 启动参数

```bash
# vLLM 服务启动（指标端点默认随 HTTP 端口一起开启）
python -m vllm.entrypoints.openai.api_server \
  --model /models/Qwen2.5-7B-Instruct \
  --served-model-name qwen2-7b \
  --host 0.0.0.0 \
  --port 8000 \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --enable-prefix-caching
  # 指标自动在 http://0.0.0.0:8000/metrics 暴露
```

### K8s ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm
  namespace: observability
spec:
  namespaceSelector:
    matchNames:
      - ai
  selector:
    matchLabels:
      app: vllm
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

### Alloy 采集配置（方案一）

```river
prometheus.scrape "vllm" {
  targets = [
    { __address__ = "vllm-qwen.ai.svc:8000",   model = "qwen2-7b" },
    { __address__ = "vllm-deepseek.ai.svc:8000", model = "deepseek-v3" },
  ]
  metrics_path = "/metrics"
  forward_to   = [prometheus.remote_write.central.receiver]
}
```

### 关键 PromQL 查询

```promql
# TTFT P99（过去 5 分钟）
histogram_quantile(0.99,
  rate(vllm:time_to_first_token_seconds_bucket[5m])
)

# KV Cache 使用率（各实例）
vllm:gpu_cache_usage_perc

# 请求积压量
vllm:num_requests_waiting

# Token 吞吐量（每秒生成 Token 数）
rate(vllm:request_generation_tokens_total[5m])

# 各模型输入/输出 Token 用量（成本核算）
sum by (model_name) (
  rate(vllm:request_prompt_tokens_total[1h])
)
sum by (model_name) (
  rate(vllm:request_generation_tokens_total[1h])
)
```

---

## 告警规则

```yaml
groups:
  - name: vllm
    rules:
      - alert: VLLMHighFirstTokenLatency
        expr: |
          histogram_quantile(0.99,
            rate(vllm:time_to_first_token_seconds_bucket[5m])
          ) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "vLLM TTFT P99 超过 5 秒"

      - alert: VLLMKVCacheAlmostFull
        expr: vllm:gpu_cache_usage_perc > 0.90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "vLLM GPU KV Cache 占用超过 90%，即将出现请求 Swap"

      - alert: VLLMRequestQueueBuildup
        expr: vllm:num_requests_waiting > 50
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "vLLM 请求队列积压 {{ $value }} 个，GPU 算力可能不足"
```

---

## 与 DCGM Exporter 的配合

> vLLM 指标反映的是推理层的业务状态，DCGM Exporter 反映的是 GPU 硬件层状态。两者互补：

| 场景 | vLLM 指标 | DCGM 指标 |
|------|---------|----------|
| 请求延迟高 | TTFT 升高，queue waiting 增加 | GPU 利用率是否满载 |
| 显存耗尽 | KV Cache 100%，请求被 Swap | FB_USED 达到上限 |
| GPU 故障 | 吞吐量骤降 | XID 错误，ECC 错误 |
| 算力不足 | waiting 请求堆积 | 利用率长期 > 95% |

---

## Grafana Dashboard

| Dashboard | 说明 |
|-----------|------|
| vLLM 官方 Dashboard | 导入 ID 21766，包含吞吐量 / KV Cache / 延迟分布 |
| 自建 AI 推理大盘 | 结合 DCGM 指标，GPU 层 + 推理层联动 |

---

## 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 适用场景 |
|--------|---------|---------|---------|
| vLLM 内置 /metrics | 内置端点 | 推理性能 + KV Cache + 队列 | 标准方案（无需 Exporter） |
| Grafana Alloy | prometheus.scrape | 同上 | Grafana 全栈 |
| Netdata | 一键安装 | 内置 vLLM collector（社区） | 快速验证 |

> vLLM 内置端点已足够完善，推荐直接使用。配合 DCGM Exporter 形成 GPU 硬件 + 推理层完整视图。
