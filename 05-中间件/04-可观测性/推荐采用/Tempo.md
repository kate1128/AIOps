# Tempo - 分布式链路追踪

> 推荐原因：SmartVision 已有 Prometheus（指标）+ Loki（日志），链路追踪是可观测性三大支柱最后缺失的一环。Tempo 与 Grafana 原生集成，可在同一 Dashboard 中关联 metrics → logs → traces，无需学习新工具。
> 当前状态：❌ 未部署，推荐在 07-可观测性 体系建设 Phase 2 引入。

---

## 现状与问题

| 项目 | 现状 |
|------|------|
| 指标监控 | ✅ Prometheus + Grafana |
| 日志采集 | 🟡 Loki（规划中）|
| 链路追踪 | ❌ 完全缺失 |
| 跨服务调用排查 | 靠日志手动关联，效率极低 |
| AI 推理请求追踪 | 无法追踪单次推理在多服务间的耗时分布 |

---

## Tempo 是什么

Grafana Tempo 是分布式链路追踪后端，支持 Jaeger、Zipkin、OTLP、Zipkin 等协议接收 Trace 数据，可直接在 Grafana 中展示 Trace，并实现 Metrics ↔ Logs ↔ Traces 三者相互跳转（Grafana Explore 联动）。

```
业务服务（OpenTelemetry SDK）
    │ 发送 Trace 数据（OTLP）
    ▼
Tempo（Trace 存储与查询）
    │ Grafana 查询
    ▼
Grafana Dashboard（TraceQL 查询 + 跳转 Loki 日志）
```

---

## 与 Jaeger 的核心对比

| 维度 | Jaeger | Tempo |
|------|--------|-------|
| 存储 | Cassandra / Elasticsearch | 对象存储（S3/MinIO）|
| 成本 | 高（Elasticsearch 很贵）| 低（MinIO 对象存储）|
| Grafana 集成 | 插件支持 | 原生内置，体验更好 |
| 查询语言 | Jaeger UI | TraceQL（强大）|
| 与 Loki/Prometheus 联动 | 无 | 原生联动 |
| 运维复杂度 | 高 | 低（单二进制模式）|

---

## K8s 部署

```bash
# 使用 Helm 部署（单体模式，适合中小规模）
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install tempo grafana/tempo \
  --namespace observability \
  --create-namespace \
  --set tempo.storage.trace.backend=s3 \
  --set tempo.storage.trace.s3.bucket=smartvision-traces \
  --set tempo.storage.trace.s3.endpoint=minio.prod.svc.cluster.local:9000 \
  --set tempo.storage.trace.s3.access_key=minio-admin \
  --set tempo.storage.trace.s3.secret_key=minio-secret \
  --set tempo.storage.trace.s3.insecure=true  # 内网 HTTP
```

---

## 服务接入 OpenTelemetry

```python
# Python 服务接入示例（vLLM / FastAPI 业务服务）
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# 初始化 Tracer
provider = TracerProvider()
exporter = OTLPSpanExporter(
    endpoint="http://tempo.observability.svc.cluster.local:4317"
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# 在代码中使用
tracer = trace.get_tracer("smartvision.inference")

def inference(prompt: str):
    with tracer.start_as_current_span("llm.inference") as span:
        span.set_attribute("model.name", "qwen2.5-7b")
        span.set_attribute("prompt.length", len(prompt))
        # ... 推理逻辑
        span.set_attribute("tokens.generated", output_tokens)
```

---

## Grafana 数据源配置

```yaml
# grafana-datasources.yaml（添加到 Grafana ConfigMap）
- name: Tempo
  type: tempo
  url: http://tempo.observability.svc.cluster.local:3100
  jsonData:
    tracesToLogsV2:
      datasourceUid: loki        # 关联 Loki（Trace → Log 跳转）
      spanStartTimeShift: -1m
      spanEndTimeShift: 1m
      filterByTraceID: true
    tracesToMetrics:
      datasourceUid: prometheus  # 关联 Prometheus（Trace → Metric 跳转）
    serviceMap:
      datasourceUid: prometheus  # 服务拓扑图来自 Prometheus
```

---

## 关键使用场景

| 场景 | 说明 |
|------|------|
| 推理请求全链路耗时 | 用户请求 → API 网关 → vLLM → 输出，各段耗时 |
| 跨服务调用错误定位 | 某请求报错，Trace 直接定位是哪个服务哪行代码 |
| 慢请求分析 | TraceQL 查询 P99 耗时最高的 Trace |
| 关联日志查询 | 点击 Trace，直接跳转到该请求在 Loki 中的日志 |

---

## 存储估算

| 服务 QPS | 每天 Trace 量 | 存储（7 天保留）|
|---------|-------------|--------------|
| 100 QPS | ~860 万条 | ~5-10 GB（MinIO）|
| 1000 QPS | ~8600 万条 | ~50-100 GB |

*建议保留 7-14 天，存储成本极低（MinIO 对象存储）*

---

## 引入优先级

| 触发条件 | 优先级 |
|---------|--------|
| 出现跨服务调用性能问题，日志难以定位 | 🔴 高优 |
| 产品需要 AI 推理链路可观测（QA/SRE）| 🟡 中优 |
| Loki 日志体系已稳定运行 | 🟡 按体系建设计划推进 |

---

## 参考

- 官方文档：https://grafana.com/docs/tempo/latest/
- TraceQL 查询语法：https://grafana.com/docs/tempo/latest/traceql/
- K8s 采样策略：https://opentelemetry.io/docs/concepts/sampling/
