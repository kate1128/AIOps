# Nginx 可观测性

> 通过 stub_status + nginx-prometheus-exporter 或 nginx-ingress-controller 内置指标采集。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| stub_status | Nginx 原生状态页（活跃连接/请求数） | TCP 8080 /basic_status |
| nginx-prometheus-exporter | 读取 stub_status 转为 Prometheus 格式 | TCP 9113 /metrics |
| nginx-ingress-controller | K8s Ingress 内置 Prometheus 指标 | TCP 10254 /metrics |
| OpenResty / lua-resty | lua 自定义指标，暴露给 Prometheus | 自定义端点 |

---

## 核心指标

### 基础 Nginx

| 指标（exporter 采集） | 含义 | 告警建议 |
|----------------------|------|---------|
| `nginx_connections_active` | 活跃连接数 | > 90% worker_connections 告警 |
| `nginx_connections_accepted` | 累计接受连接数 | — |
| `nginx_http_requests_total` | HTTP 请求总数 | — |
| `nginx_up` | Nginx 进程是否存活 | == 0 告警 |

### Ingress Controller

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `nginx_ingress_controller_requests` | Ingress 请求数（按 host/status 分）| — |
| `nginx_ingress_controller_ingress_upstream_latency_seconds` | 上游延迟 | P99 > 2s 告警 |
| `nginx_ingress_controller_ssl_expire_time_seconds` | 证书过期时间 | < 30 天告警 |

### Access Log → Loki

| 维度 | 说明 |
|------|------|
| 状态码分布 | 4xx/5xx 比例异常告警 |
| 热点接口 | Top 10 URI 请求量 |
| 客户端 IP 分布 | DDoS / 爬虫识别 |

---

## 采集集成

```yaml
# Nginx stub_status 配置
server {
  listen 8080;
  location /basic_status {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    allow 10.0.0.0/8;
    deny all;
  }
}

# nginx-prometheus-exporter 启动
nginx-prometheus-exporter --nginx.scrape-uri=http://nginx:8080/basic_status

# Prometheus scrape
- job_name: nginx
  static_configs:
    - targets:
        - "nginx-exporter:9113"
      labels:
        service: nginx
        env: prod

# K8s Ingress Controller 内置
- job_name: nginx-ingress
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
      regex: ingress-nginx
      action: keep
    - source_labels: [__address__]
      action: replace
      regex: (.+):(\d+)
      replacement: $1:10254
      target_label: __address__
```

---

## 告警规则

```yaml
- alert: NginxConnectionsHigh
  expr: nginx_connections_active > 1000
  for: 5m
  annotations:
    summary: "Nginx 活跃连接数 {{ $value }}"

- alert: NginxUpstreamLatencyHigh
  expr: histogram_quantile(0.99, rate(nginx_ingress_controller_ingress_upstream_latency_seconds_bucket[5m])) > 2
  for: 3m
  annotations:
    summary: "Nginx 上游 P99 延迟 > 2s"

- alert: NginxSSLCertExpiring
  expr: nginx_ingress_controller_ssl_expire_time_seconds - time() < 2592000
  annotations:
    summary: "SSL 证书将在 30 天内过期"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 Nginx | stub_status + nginx-prometheus-exporter 同机部署 |
| Docker Nginx | nginx-prometheus-exporter 容器 sidecar |
| K8s Ingress Controller | 10254/metrics 默认暴露，ServiceMonitor 自动发现 |

Access log 通过 Promtail 采集到 Loki，可做流量分析和用户行为追踪。
