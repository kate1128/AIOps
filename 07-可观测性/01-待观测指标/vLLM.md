# vLLM 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. vLLM GitHub：[vllm-project/vllm](https://github.com/vllm-project/vllm)
2. vLLM Metrics：[vLLM Production Metrics](https://docs.vllm.ai/)
3. KServe vLLM：[KServe vLLM runtime](https://kserve.github.io/website/)
4. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus.scrape/)
5. Grafana Dashboard：[vLLM Dashboard #21766](https://grafana.com/grafana/dashboards/21766)

---

## 1. 结论摘要

vLLM 内置 Prometheus `/metrics` 端点，指标以 `vllm:` 为前缀，覆盖 TTFT、TPOT、端到端延迟、请求队列、Token 吞吐、KV Cache、抢占/Swap 等推理层状态。Grafana Alloy **可以直接通过 `prometheus.scrape` 采集 vLLM 指标**。完整 AI 推理可观测性应将 vLLM 指标与 DCGM GPU 硬件指标联动分析。官方回答与调研结论一致，并补充了 KServe + vLLM 的 Helm、InferenceService annotation、ServiceMonitor 场景。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | vLLM 内置 `/metrics` |
| 默认端口 | 与 OpenAI API 服务同端口，常见 `8000` |
| 指标前缀 | `vllm:` |
| Alloy 集成 | `prometheus.scrape` 直接抓取 |
| 推荐组合 | vLLM 推理指标 + DCGM GPU 指标 |
| 推荐 Dashboard | vLLM Dashboard ID 21766 / KServe vLLM Dashboard |

---

## 2. 产品概况（vLLM metrics）

| 维度 | 指标内容 |
| --- | --- |
| 推理延迟 | TTFT、TPOT、E2E latency |
| 吞吐量 | prompt/generation tokens per second |
| 请求队列 | waiting / running / swapped requests |
| KV Cache | GPU/CPU cache usage、prefix hit rate |
| 成本核算 | prompt tokens、generation tokens |
| 硬件互补 | DCGM GPU 利用率、显存、温度、XID 错误 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `vllm:time_to_first_token_seconds` | 首 Token 延迟 TTFT | P99 > 5s 告警 |
| `vllm:time_per_output_token_seconds` | Token 间延迟 TPOT | P99 > 500ms 关注 |
| `vllm:e2e_request_latency_seconds` | 端到端延迟 | P99 > 30s 告警 |
| `vllm:num_requests_waiting` | 等待请求数 | > 50 持续 5m 告警 |
| `vllm:num_requests_running` | 运行中请求数 | 接近并发上限关注 |
| `vllm:num_requests_swapped` | 被换出请求数 | > 0 告警 |
| `vllm:gpu_cache_usage_perc` | GPU KV Cache 使用率 | > 90% P1 |
| `vllm:cpu_cache_usage_perc` | CPU KV Cache 使用率 | > 50% 说明 Swap 风险 |
| `vllm:request_generation_tokens_total` | 输出 Token 总数 | 成本/吞吐核算 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 适用场景 |
| --- | --- | --- | --- |
| vLLM 内置 `/metrics` | 原生端点 | 推理层全量 | 标准方案 |
| **Grafana Alloy** | `prometheus.scrape` | 抓取 vLLM 指标 | **本项目首选** |
| KServe ServiceMonitor | 注解 / CRD | KServe + vLLM | 模型服务平台 |
| DCGM Exporter | DaemonSet | GPU 硬件指标 | 必配互补 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 独立部署 vLLM

```alloy
prometheus.scrape "vllm" {
  targets = [
    { __address__ = "vllm-qwen.ai.svc:8000", model = "qwen2-7b" },
    { __address__ = "vllm-deepseek.ai.svc:8000", model = "deepseek-v3" },
  ]
  metrics_path = "/metrics"
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "vllm"
}
```

### 5.2 KServe + vLLM
```bash
helm upgrade kserve oci://ghcr.io/kserve/charts/kserve \
  --reuse-values \
  --set metricsaggregator.enablePrometheusScraping=true
```

```yaml
metadata:
  annotations:
    serving.kserve.io/enable-prometheus-scraping: "true"
```

### 5.3 ServiceMonitor 示例
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm-model
spec:
  selector:
    matchLabels:
      serving.kserve.io/inferenceservice: qwen
  endpoints:
  - port: qwen-predictor
    path: /metrics
    interval: 15s
```

### 5.4 与 DCGM 联动
```alloy
prometheus.scrape "dcgm" {
  targets = [{ __address__ = "dcgm-exporter.gpu.svc:9400", service = "dcgm" }]
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "dcgm"
}
```

---

## 6. 启动配置要点

```bash
python -m vllm.entrypoints.openai.api_server \
  --model /models/Qwen2.5-7B-Instruct \
  --served-model-name qwen2-7b \
  --host 0.0.0.0 \
  --port 8000 \
  --gpu-memory-utilization 0.90 \
  --enable-prefix-caching
```

---

## 7. 告警规则

```yaml
groups:
- name: vllm.rules
  rules:
  - alert: VLLMHighFirstTokenLatency
    expr: histogram_quantile(0.99, rate(vllm:time_to_first_token_seconds_bucket[5m])) > 5
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "vLLM TTFT P99 超过 5s" }

  - alert: VLLMKVCacheAlmostFull
    expr: vllm:gpu_cache_usage_perc > 0.90
    for: 5m
    labels: { severity: critical }
    annotations: { summary: "vLLM GPU KV Cache 使用率超过 90%" }

  - alert: VLLMRequestQueueBuildup
    expr: vllm:num_requests_waiting > 50
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "vLLM 请求队列积压" }
```

---

## 8. Grafana Dashboard

推荐使用 vLLM Dashboard ID 21766 或 KServe vLLM Dashboard，并与 DCGM Dashboard 联动展示：GPU 利用率、显存、KV Cache、TTFT、TPOT、Token 吞吐、XID 错误。

---

## 9. KAgent 集成（vLLM 运维 Agent）

推荐绑定 PrometheusServer 查询 vLLM、DCGM、Kubernetes 指标，并用 Git-Based Skills 注入 TTFT 高、KV Cache 满、请求积压、模型副本扩缩容、prefix cache 命中率排查 SOP。

---

## 10. 常见问题

### Grafana Alloy 能采集 vLLM 指标吗？

**可以。** vLLM 内置 Prometheus `/metrics`，Alloy 可用 `prometheus.scrape` 直接抓取。

### KServe 场景有什么区别？

KServe 需要启用 Prometheus 抓取，并给 InferenceService 添加 `serving.kserve.io/enable-prometheus-scraping: "true"` 注解，再通过 ServiceMonitor 或 Alloy 抓取 predictor 端口。

### vLLM 指标能替代 DCGM 吗？

不能。vLLM 指标反映推理层队列、延迟和 KV Cache；DCGM 反映 GPU 硬件层利用率、显存、温度和错误。两者必须联动分析。
