# Harbor 可观测性

> Harbor 内置 Prometheus 指标端点，覆盖服务级和任务级指标。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| Harbor 内置 /metrics | 多 endpoint 暴露各服务指标 | TCP（各服务端口）/metrics |
| Jobservice | 任务队列状态（GC/复制/扫描）| TCP 9090 /metrics |
| Registry | Docker 分发指标 | TCP 5000 /metrics（需额外配置）|
| Database | Harbor 使用 PostgreSQL，由 PostgreSQL exporter 覆盖 | — |
| Redis | Harbor 使用 Redis 做缓存，由 Redis exporter 覆盖 | — |

Harbor 由多个微服务组成（core/portal/registry/jobservice/trivy），每个服务需单独采集 metrics。

---

## 核心指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `harbor_core_request_total` | Core 服务请求总数 | — |
| `harbor_core_request_duration_seconds_bucket` | 请求延迟分布 | P99 > 1s 关注 |
| `harbor_core_db_in_use` | Core 数据库连接数 | > 80% 告警 |
| `harbor_jobservice_task_total` | 任务总数 | — |
| `harbor_jobservice_task_failed_total` | 任务失败数 | > 0 告警 |
| `harbor_jobservice_task_duration_seconds` | 任务执行时长 | — |
| `harbor_registry_storage_total_bytes` | Registry 存储总量 | > 85% 告警 |
| `harbor_registry_requests_total` | Registry 请求总数 | — |
| `harbor_registry_errors_total` | Registry 请求错误数 | 错误率 > 1% 告警 |

---

## 采集集成

```yaml
# Prometheus static_configs
- job_name: harbor-core
  static_configs:
    - targets:
        - "harbor-core:8080"
      labels:
        service: harbor
        component: core

- job_name: harbor-jobservice
  static_configs:
    - targets:
        - "harbor-jobservice:9090"
      labels:
        service: harbor
        component: jobservice

- job_name: harbor-registry
  static_configs:
    - targets:
        - "harbor-registry:5000"
      labels:
        service: harbor
        component: registry

# K8s ServiceMonitor（Harbor Operator）
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: harbor
  namespace: observability
spec:
  selector:
    matchLabels:
      app: harbor
  endpoints:
    - port: metrics
      interval: 15s
```

---

## 告警规则

```yaml
- alert: HarborJobFailed
  expr: rate(harbor_jobservice_task_failed_total[10m]) > 0
  for: 2m
  annotations:
    summary: "Harbor 任务执行失败，需检查 jobservice 日志"

- alert: HarborStorageHigh
  expr: harbor_registry_storage_total_bytes > 0.85 * harbor_registry_storage_limit_bytes
  for: 5m
  annotations:
    summary: "Harbor 存储使用率超过 85%，需清理旧镜像"

- alert: HarborRequestErrors
  expr: rate(harbor_registry_errors_total[5m]) / rate(harbor_registry_requests_total[5m]) * 100 > 1
  for: 5m
  annotations:
    summary: "Harbor Registry 错误率 {{ $value }}%"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 Harbor | 各组件独立进程，分别配置 static_configs |
| Docker Harbor | docker-compose 部署，各服务端口映射后抓取 |
| K8s Harbor（Operator）| Operator 自动暴露 metrics |

Harbor 5.x 默认开启 Prometheus metrics，旧版本需在 `harbor.yml` 中启用 `metrics: enabled: true`。Trivy 漏洞扫描器的指标也通过 jobservice 暴露。

---

## 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
|--------|---------|---------|---------|---------|
| Harbor 内置 /metrics | 多端点 | Core/Jobservice/Registry | 无 | 标准方案（需启用配置） |
| Grafana Alloy | 抓取各服务端口 | 同上 | 内置 loki.source | Grafana 全栈 |
| Netdata | 一键安装 | 内置 harbor collector（社区） | 内置日志查看 | 快速部署 |

---

## Alloy 采集配置

```alloy
prometheus.scrape "harbor" {
  targets = [
    { __address__ = "harbor-core.harbor.svc:8080", service = "harbor-core" },
    { __address__ = "harbor-jobservice.harbor.svc:9090", service = "harbor-jobservice" },
    { __address__ = "harbor-registry.harbor.svc:5000", service = "harbor-registry" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

---

## 方案对比

| 维度 | Harbor 内置 + Prometheus | Alloy | Netdata |
|------|------------------------|-------|---------|
| 部署复杂度 | 低（内置端点） | 低 | 低 |
| 多服务覆盖 | 需配置多个 target | ✅ 统一配置 | 自动发现 |
| 配置改动 | 需启用 `metric.enabled` | 需启用 | 需启用 |
| Grafana 兼容 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 推荐场景 | 已有 Prometheus 栈 | Grafana 全栈 | 快速验证 |
