# Nginx 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. nginx-prometheus-exporter：[nginxinc/nginx-prometheus-exporter](https://github.com/nginxinc/nginx-prometheus-exporter)
2. NGINX stub_status：[Module ngx_http_stub_status_module](https://nginx.org/en/docs/http/ngx_http_stub_status_module.html)
3. Ingress NGINX metrics：[ingress-nginx monitoring](https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/)
4. Alloy NGINX 场景：[alloy-scenarios/nginx-monitoring](https://github.com/grafana/alloy-scenarios/tree/main/nginx-monitoring)

---

## 1. 结论摘要

Nginx 指标采集有两类主流场景：独立 Nginx 使用 `stub_status + nginx-prometheus-exporter`，Kubernetes Ingress NGINX 使用 Controller 内置 `:10254/metrics`。Grafana Alloy **完全支持采集 NGINX 指标和日志**：指标通过 `prometheus.scrape` 抓取 exporter/Ingress 端点，访问日志通过 `loki.source.file` 采集 JSON access log。官方回答与调研结论一致，并补充了 Grafana Cloud NGINX 集成的 2 个 Dashboard、日志分析和 GeoIP2 能力。

| 关键信息 | 值 |
| --- | --- |
| 独立 Nginx 指标 | stub_status + nginx-prometheus-exporter `:9113/metrics` |
| Ingress 指标 | NGINX Ingress Controller `:10254/metrics` |
| 日志采集 | JSON access log -> Loki |
| Alloy 集成 | `prometheus.scrape` + `loki.source.file` |
| 官方示例 | `alloy-scenarios/nginx-monitoring` |

---

## 2. 产品概况

| 组件 | 指标内容 | 说明 |
| --- | --- | --- |
| stub_status | 活跃连接、请求数 | Nginx 原生状态页 |
| nginx-prometheus-exporter | Prometheus 格式转换 | 独立 Nginx 标准方案 |
| NGINX Ingress Controller | Ingress 请求、上游延迟、证书 | K8s 标准方案 |
| Loki access log | 状态码、URI、IP、User-Agent、耗时 | 流量分析 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `nginx_up` | Nginx exporter 是否正常 | == 0 告警 |
| `nginx_connections_active` | 活跃连接 | > 90% worker_connections 告警 |
| `nginx_connections_accepted` | 已接受连接数 | QPS 基线 |
| `nginx_http_requests_total` | HTTP 请求总量 | 错误率分母 |
| `nginx_ingress_controller_requests` | Ingress 请求数 | 按 status/host 分析 |
| `nginx_ingress_controller_ingress_upstream_latency_seconds` | 上游延迟 | P99 > 2s 告警 |
| `nginx_ingress_controller_ssl_expire_time_seconds` | 证书过期时间 | < 30 天告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| nginx-prometheus-exporter | Sidecar / 二进制 | stub_status | 无 | 独立 Nginx |
| NGINX Ingress Controller metrics | 内置端点 | Ingress 全量 | 无 | K8s Ingress |
| **Grafana Alloy** | `prometheus.scrape` + Loki | exporter/Ingress 指标 | JSON access log | **本项目首选** |
| OpenResty + lua | 应用内指标 | 自定义细粒度 | 无 | 深度定制 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 独立 Nginx exporter

```alloy
discovery.relabel "nginx" {
  targets = [{ __address__ = "nginx-exporter.web.svc:9113" }]
  rule { target_label = "instance" replacement = "nginx-main" }
}

prometheus.scrape "nginx" {
  targets = discovery.relabel.nginx.output
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "integrations/nginx"
}
```

### 5.2 多实例采集
```alloy
discovery.relabel "nginx_node1" {
  targets = [{ __address__ = "nginx-node1:9113" }]
  rule { target_label = "instance" replacement = "nginx-node1" }
}

discovery.relabel "nginx_node2" {
  targets = [{ __address__ = "nginx-node2:9113" }]
  rule { target_label = "instance" replacement = "nginx-node2" }
}

prometheus.scrape "nginx_cluster" {
  targets = concat(discovery.relabel.nginx_node1.output, discovery.relabel.nginx_node2.output)
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "integrations/nginx"
}
```

### 5.3 Ingress NGINX
```alloy
prometheus.scrape "nginx_ingress" {
  targets = [{ __address__ = "ingress-nginx-controller.ingress.svc:10254" }]
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "nginx-ingress"
}
```

### 5.4 JSON access log 采集
```alloy
local.file_match "nginx_access" {
  path_targets = [{ __path__ = "/var/log/nginx/json_access.log", job = "integrations/nginx" }]
}

loki.source.file "nginx_access" {
  targets = local.file_match.nginx_access.targets
  forward_to = [loki.write.default.receiver]
}
```

---

## 6. Nginx 前置配置

```nginx
server {
  listen 127.0.0.1:8080;
  location /stub_status {
    stub_status on;
    access_log off;
  }
}

log_format json_analytics escape=json '{"msec":"$msec","request":"$request","status":"$status","request_time":"$request_time","http_user_agent":"$http_user_agent"}';
access_log /var/log/nginx/json_access.log json_analytics;
```

---

## 7. 告警规则

```yaml
groups:
- name: nginx.rules
  rules:
  - alert: NginxDown
    expr: nginx_up == 0
    for: 1m
    labels: { severity: critical }
    annotations: { summary: "Nginx exporter 不可达" }

  - alert: NginxUpstreamLatencyHigh
    expr: histogram_quantile(0.99, rate(nginx_ingress_controller_ingress_upstream_latency_seconds_bucket[5m])) > 2
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Nginx Ingress 上游 P99 延迟超过 2s" }

  - alert: NginxSSLCertExpiring
    expr: nginx_ingress_controller_ssl_expire_time_seconds - time() < 2592000
    for: 1h
    labels: { severity: warning }
    annotations: { summary: "Nginx Ingress 证书将在 30 天内过期" }
```

---

## 8. Grafana Dashboard

Grafana Cloud NGINX 集成提供 2 个预置 Dashboard（指标 + 日志），支持访问日志可视化、错误率、独立访客、GeoIP 国家映射。官方示例可通过 `alloy-scenarios/nginx-monitoring` 快速体验。

---

## 9. KAgent 集成（Nginx 运维 Agent）

推荐绑定 PrometheusServer 查询 QPS、5xx、上游延迟、证书过期，并结合 Loki 查询 access log；用 Git-Based Skills 注入 502/504、上游慢、证书过期、限流、访问日志排查 SOP。

---

## 10. 常见问题

### Grafana Alloy 支持采集 NGINX 指标吗？

**完全支持。** Alloy 通过 `prometheus.scrape` 抓取 nginx-prometheus-exporter 或 NGINX Ingress Controller 指标，通过 Loki 组件采集访问日志。

### 为什么需要 nginx-prometheus-exporter？

Nginx `stub_status` 不是 Prometheus 格式，需要 nginx-prometheus-exporter 转换；Ingress Controller 通常已内置 Prometheus 指标端点。

### Grafana Cloud NGINX 集成还提供什么？

提供预置 Dashboard、告警、日志采集与 GeoIP2 相关的访问分析能力，适合从指标和访问日志两个角度定位 4xx/5xx、慢请求和异常来源。
