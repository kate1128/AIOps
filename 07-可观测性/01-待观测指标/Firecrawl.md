# Firecrawl 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Firecrawl GitHub：[mendableai/firecrawl](https://github.com/mendableai/firecrawl)
2. Firecrawl 文档：[Firecrawl Docs](https://docs.firecrawl.dev/)
3. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)
4. Blackbox Exporter：[prometheus/blackbox_exporter](https://github.com/prometheus/blackbox_exporter)

> Grafana 官方知识来源没有 Firecrawl 专用集成。以下方案基于通用 Prometheus 端点、应用埋点、日志采集和 HTTP 拨测设计。

---

## 1. 结论摘要

Firecrawl 是网页抓取/爬虫服务，通常没有标准 Prometheus exporter。生产可观测性需要应用侧主动暴露 `/metrics`，并结合日志与外部拨测。Grafana Alloy **可以采集 Firecrawl 指标**，前提是 Firecrawl 或自定义 exporter 暴露 Prometheus 格式端点；否则只能采集日志和做 HTTP 探活。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | 应用自定义 Prometheus 埋点 |
| 指标端口 | 自定义，例如 TCP `9100` `/metrics` |
| Alloy 集成 | `prometheus.scrape` 抓取自定义端点 |
| 可用性监控 | Blackbox Exporter / Alloy scrape blackbox |
| 日志采集 | 容器 stdout -> Loki |

---

## 2. 产品概况（应用自定义指标）

| 项目 | 内容 |
| --- | --- |
| 产品名称 | Firecrawl |
| 类型 | AI 爬虫 / 网页抓取服务 |
| 指标来源 | 应用代码埋点、任务队列、HTTP 健康检查、日志 |
| 标准 exporter | 暂无官方 Prometheus exporter |
| 推荐方式 | `prometheus_client` / OpenTelemetry SDK 暴露业务指标 |

---

## 3. 核心指标

| 指标 | 类型 | 含义 | 告警建议 |
| --- | --- | --- | --- |
| `firecrawl_crawl_requests_total` | Counter | 爬取请求总数 | 错误率分母 |
| `firecrawl_crawl_duration_seconds` | Histogram | 单次爬取耗时 | P95 > 30s 告警 |
| `firecrawl_pages_scraped_total` | Counter | 已抓取页面数 | 吞吐量骤降关注 |
| `firecrawl_errors_total` | Counter | 错误数（按类型）| 错误率 > 10% 告警 |
| `firecrawl_queue_depth` | Gauge | 当前队列深度 | 持续增长告警 |
| `firecrawl_concurrent_requests` | Gauge | 当前并发数 | 接近上限关注 |
| `firecrawl_tokens_consumed_total` | Counter | Token 消耗 | 成本核算 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| 自定义 Prometheus 埋点 | 应用内集成 | 业务指标全量 | 无 | **生产推荐** |
| Grafana Alloy | `prometheus.scrape` | 抓取自定义端点 | Loki 采集 stdout | Grafana 全栈 |
| Blackbox Exporter | 外部探活 | HTTP 可用性 | 无 | 补充拨测 |
| OpenTelemetry SDK | 应用内集成 | 指标 / Trace / 日志 | 支持 | 需要链路追踪时 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 抓取 Firecrawl 自定义指标端点

```alloy
prometheus.scrape "firecrawl" {
  targets = [{ __address__ = "firecrawl.ai.svc.cluster.local:9100", service = "firecrawl" }]
  metrics_path = "/metrics"
  scrape_interval = "30s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "firecrawl"
}
```

### 5.2 HTTP 可用性拨测

```alloy
prometheus.scrape "firecrawl_blackbox" {
  targets      = [{ __address__ = "blackbox-exporter.observability.svc:9115" }]
  metrics_path = "/probe"
  params       = { module = ["http_2xx"], target = ["http://firecrawl.ai.svc:8080/health"] }
  forward_to   = [prometheus.remote_write.central.receiver]
}
```

### 5.3 容器日志采集

```logql
{app="firecrawl"} |= "ERROR"
```

---

## 6. 应用埋点示例

```python
from prometheus_client import Counter, Histogram, Gauge, start_http_server

REQUESTS = Counter("firecrawl_crawl_requests_total", "Crawl requests", ["domain", "status"])
ERRORS = Counter("firecrawl_errors_total", "Crawl errors", ["type"])
DURATION = Histogram("firecrawl_crawl_duration_seconds", "Crawl duration", ["domain"], buckets=[1, 5, 10, 30, 60, 120])
QUEUE_DEPTH = Gauge("firecrawl_queue_depth", "Crawl queue depth")

start_http_server(9100)
```

---

## 7. 告警规则

```yaml
groups:
- name: firecrawl.rules
  rules:
  - alert: FirecrawlErrorRateHigh
    expr: rate(firecrawl_errors_total[5m]) / rate(firecrawl_crawl_requests_total[5m]) > 0.1
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "Firecrawl 错误率超过 10%"

  - alert: FirecrawlHighLatency
    expr: histogram_quantile(0.95, rate(firecrawl_crawl_duration_seconds_bucket[5m])) > 30
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "Firecrawl P95 爬取耗时超过 30s"

  - alert: FirecrawlQueueBacklogHigh
    expr: firecrawl_queue_depth > 1000
    for: 10m
    labels: { severity: warning }
    annotations:
      summary: "Firecrawl 队列积压过高"
```

---

## 8. Grafana Dashboard

建议自建 Firecrawl Dashboard，包含请求量、错误率、P95/P99 延迟、队列深度、并发数、Token 消耗、Top Domain 错误分布。

---

## 9. KAgent 集成（Firecrawl 运维 Agent）

推荐绑定 PrometheusServer 查询爬虫指标，并用 Git-Based Skills 注入失败重试、站点限流、 robots.txt 和成本控制规范。

---

## 10. 常见问题

### Grafana Alloy 能采集 Firecrawl 指标吗？

**可以，但前提是 Firecrawl 暴露 Prometheus 指标端点。** Grafana 官方知识来源没有 Firecrawl 专用集成，因此 Alloy 只能使用通用 `prometheus.scrape` 抓取自定义 `/metrics`。

### Firecrawl 没有指标端点怎么办？

需要在应用代码中集成 Prometheus SDK，或写一个外部 exporter 调用 Firecrawl API 并转换为 Prometheus 格式。短期可先用 Blackbox Exporter 做 HTTP 可用性探测。

### 最少需要埋哪些指标？

至少包含请求总数、错误总数、请求耗时 Histogram、队列深度和当前并发数。这 5 类指标能覆盖可用性、性能、容量和成本分析的基础面。
