# Blackbox Exporter — 外部探测与服务可用性

## 概述

Blackbox Exporter 是 Prometheus 官方维护的黑盒探测工具，模拟外部用户从网络层发起 HTTP/HTTPS、TCP、ICMP、DNS 探测，将探测结果（是否可达、延迟、证书过期时间等）转换为 Prometheus 指标。

- GitHub: [prometheus/blackbox_exporter](https://github.com/prometheus/blackbox_exporter) ⭐ ~4.5k
- 默认端口: `9115/metrics`
- 核心定位：**被动健康检查**补充——node-exporter 监控的是机器内部状态，Blackbox 监控的是外部可见的服务可用性

---

## 核心能力

| 探测模块 | 协议 | 典型用途 |
|---------|------|---------|
| `http_2xx` | HTTP/HTTPS | API 端点可用性、SSL 证书过期 |
| `http_post_2xx` | HTTP POST | 带 body 的接口健康检查 |
| `tcp_connect` | TCP | 端口是否可连接 |
| `icmp` | ICMP | 主机存活探测（需 root 或 capabilities）|
| `dns` | DNS | 域名解析是否正常 |

---

## 核心指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `probe_success` | 探测是否成功（1=成功，0=失败）| == 0 持续 2m → P1 告警 |
| `probe_duration_seconds` | 探测耗时 | HTTP > 3s 持续 5m 告警 |
| `probe_http_status_code` | HTTP 响应状态码 | 非 2xx 告警 |
| `probe_ssl_earliest_cert_expiry` | SSL 证书最早过期时间（Unix 时间戳）| `< now + 30天` 告警 |
| `probe_dns_lookup_time_seconds` | DNS 解析耗时 | > 1s 关注 |
| `probe_tcp_connect_duration_seconds` | TCP 连接建立耗时 | > 1s 关注 |

---

## 在本项目中的使用

### 当前状态

> 🔴 未部署。当前无从外部视角检测服务可用性。建议在一台与生产网络不同的节点（或 DMZ）部署 Blackbox Exporter。

### 探测目标规划

| 目标 | 探测模块 | 告警阈值 |
|------|---------|---------|
| SmartVision API 网关 | `http_2xx` | probe_success == 0 |
| vLLM 推理服务 /health | `http_2xx` | probe_success == 0 |
| MinIO Console | `http_2xx` | probe_success == 0 |
| Harbor 仓库 | `http_2xx` + SSL 证书 | probe_success == 0 / 证书 < 30 天 |
| GitLab | `http_2xx` + SSL 证书 | probe_success == 0 |
| PostgreSQL 端口 | `tcp_connect` | probe_success == 0 |
| Redis 端口 | `tcp_connect` | probe_success == 0 |

### 部署

```yaml
# blackbox-exporter ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: blackbox-exporter-config
  namespace: observability
data:
  config.yml: |
    modules:
      http_2xx:
        prober: http
        timeout: 10s
        http:
          valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
          valid_status_codes: []   # 默认 2xx
          follow_redirects: true
          tls_config:
            insecure_skip_verify: false

      http_post_2xx:
        prober: http
        timeout: 10s
        http:
          method: POST
          valid_status_codes: [200, 201, 204]

      tcp_connect:
        prober: tcp
        timeout: 5s

      icmp:
        prober: icmp
        timeout: 5s

      ssl_check:
        prober: http
        timeout: 10s
        http:
          fail_if_ssl: false
          fail_if_not_ssl: true
```

### Prometheus 采集配置（动态多目标）

```yaml
# prometheus.yml — 使用 relabeling 从目标列表动态生成探测
scrape_configs:
  - job_name: blackbox
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://smartvision.example.com/health
          - https://vllm.ai.svc/health
          - https://harbor.devops.svc
          - https://gitlab.devops.svc
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter.observability.svc:9115

  - job_name: blackbox_tcp
    metrics_path: /probe
    params:
      module: [tcp_connect]
    static_configs:
      - targets:
          - "postgresql.db.svc:5432"
          - "redis.cache.svc:6379"
          - "kafka.kafka.svc:9092"
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter.observability.svc:9115
```

---

## 证书过期告警规则

```yaml
groups:
  - name: ssl_cert
    rules:
      - alert: SSLCertExpiringSoon
        expr: |
          probe_ssl_earliest_cert_expiry - time() < 86400 * 30
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL 证书即将过期（30 天内）: {{ $labels.instance }}"

      - alert: SSLCertExpiryCritical
        expr: |
          probe_ssl_earliest_cert_expiry - time() < 86400 * 7
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "SSL 证书将在 7 天内过期！: {{ $labels.instance }}"

      - alert: ServiceProbeDown
        expr: probe_success == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "服务探测失败: {{ $labels.instance }}"
```

---

## 与 Gatus / UptimeKuma 的对比

| 维度 | Blackbox Exporter | Gatus | UptimeKuma |
|------|------------------|-------|------------|
| 定位 | Prometheus 生态原生黑盒探测 | GitOps YAML 健康检查 | UI 友好的状态页 |
| 集成 Prometheus | ✅ 原生 | ✅ 暴露 /metrics | ❌ 无 |
| 告警灵活性 | PromQL 规则（极灵活）| 自带告警通知 | 自带告警通知 |
| 配置方式 | YAML + Prometheus relabeling | YAML（GitOps）| Web UI |
| 适用场景 | 已有 Prometheus 体系，需要精细 PromQL 分析 | 希望 GitOps 管理探测规则 | 非技术团队友好的状态页面 |
| **推荐选择** | SmartVision 告警体系主力 | 补充（SLA 状态页）| 补充（对外状态页）|
