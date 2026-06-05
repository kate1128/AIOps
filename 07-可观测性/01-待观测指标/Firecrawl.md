# Firecrawl 可观测性

> Firecrawl 是 AI 爬虫服务，指标需要从应用层自行暴露（无标准 Exporter）。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| 应用内 metrics | 自行埋点暴露爬虫运行指标 | TCP（自定义端口）/metrics |
| 应用日志 | 爬虫任务日志（stdout → Loki）| 容器 stdout |
| 外部探活 | 可用性拨测 | Blackbox Exporter HTTP probe |

Firecrawl 目前无社区 Prometheus Exporter，需在代码中集成 Prometheus 客户端库（Python：`prometheus_client`）。

---

## 核心指标

### 建议埋点指标

| 指标 | 类型 | 含义 | 建议 |
|------|------|------|------|
| `firecrawl_crawl_requests_total` | Counter | 爬取请求总数（按 domain/status 分）| 必埋 |
| `firecrawl_crawl_duration_seconds` | Histogram | 单次爬取耗时 | 必埋 |
| `firecrawl_pages_scraped_total` | Counter | 已抓取页面数 | 推荐 |
| `firecrawl_tokens_consumed_total` | Counter | 爬取消耗的 Token 数 | 推荐 |
| `firecrawl_errors_total` | Counter | 错误数（按错误类型分）| 必埋 |
| `firecrawl_queue_depth` | Gauge | 当前爬取队列深度 | 推荐 |
| `firecrawl_concurrent_requests` | Gauge | 当前并发爬取数 | 推荐 |

### 日志监控

| 维度 | 说明 |
|------|------|
| 错误日志频率 | `ERROR` 级别日志率 > 阈值告警 |
| 爬取失败率 | 连续失败数 > 阈值告警 |
| 目标站点不可达 | DNS 解析失败 / 连接超时 |

---

## 采集集成

```yaml
# Firecrawl 代码中集成 metrics 端点
# Python 示例
from prometheus_client import start_http_server, Counter, Histogram

FIRE_UP = Counter('firecrawl_crawl_requests_total', '爬取请求', ['domain'])
FIRE_DURATION = Histogram('firecrawl_crawl_duration_seconds', '爬取耗时', ['domain'],
                          buckets=[1, 5, 10, 30, 60, 120])

# 启动 metrics server
start_http_server(9100)

# Prometheus scrape
- job_name: firecrawl
  static_configs:
    - targets:
        - "firecrawl-host:9100"
      labels:
        service: firecrawl
        env: prod

# 可用性拨测
- job_name: firecrawl-blackbox
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
        - "http://firecrawl-host:8080/health"
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: blackbox-exporter:9115
```

---

## 告警规则

```yaml
- alert: FirecrawlErrorRateHigh
  expr: rate(firecrawl_errors_total[5m]) / rate(firecrawl_crawl_requests_total[5m]) * 100 > 10
  for: 5m
  annotations:
    summary: "Firecrawl 错误率超过 10%"

- alert: FirecrawlHighLatency
  expr: histogram_quantile(0.95, rate(firecrawl_crawl_duration_seconds_bucket[5m])) > 30
  for: 5m
  annotations:
    summary: "Firecrawl P95 爬取耗时超过 30s"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| Docker Firecrawl | 容器内集成 prometheus_client 暴露 9100 |
| K8s Firecrawl | Pod 中集成 metrics + ServiceMonitor |

Firecrawl 本身不提供指标端点，所有监控能力需要从代码层面自行埋点。建议至少埋入请求计数、错误计数和延迟分布三个基础指标。
