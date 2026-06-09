# Harbor 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Harbor 官方文档：[Harbor metrics](https://goharbor.io/docs/)
2. Harbor GitHub：[goharbor/harbor](https://github.com/goharbor/harbor)
3. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)
4. Grafana Dashboard：[Harbor Overview](https://grafana.com/grafana/dashboards/)

---

## 1. 结论摘要

Harbor 内置 Prometheus 指标端点，覆盖 Harbor exporter、Core、Registry、Jobservice 等组件。在 Alloy 体系下，没有 `prometheus.exporter.harbor` 专用组件，**直接使用 `prometheus.scrape` 抓取 Harbor 原生 Prometheus 端点即可**。Harbor 依赖 PostgreSQL、Redis、Trivy/Scanner、Registry 存储，完整监控需同步覆盖这些依赖。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | Harbor 内置 metrics |
| Alloy 集成 | `prometheus.scrape` 直接抓取 |
| 主要组件 | harbor-exporter、core、registry、jobservice |
| 依赖监控 | PostgreSQL、Redis、对象存储/文件存储、Trivy |
| 推荐 Dashboard | Harbor / Harbor Overview |

---

## 2. 产品概况（Harbor metrics）

| 组件 | 指标内容 | 说明 |
| --- | --- | --- |
| harbor-exporter | Harbor 汇总指标 | Grafana 官方示例核心目标 |
| harbor-core | API 请求、DB 连接 | 控制面核心 |
| harbor-registry | 镜像拉取/推送、错误 | 镜像分发链路 |
| harbor-jobservice | GC、复制、扫描任务 | 后台任务队列 |
| PostgreSQL / Redis | 元数据 / 缓存 | 需独立采集 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `harbor_core_request_total` | Core 请求总数 | 错误率分母 |
| `harbor_core_request_duration_seconds_bucket` | Core 请求延迟 | P99 > 1s 告警 |
| `harbor_core_db_in_use` | DB 连接使用 | > 80% 告警 |
| `harbor_jobservice_task_total` | 任务总数 | — |
| `harbor_jobservice_task_failed_total` | 任务失败数 | 10m 内增长告警 |
| `harbor_jobservice_task_duration_seconds` | 任务耗时 | GC/复制异常变慢关注 |
| `harbor_registry_requests_total` | Registry 请求总数 | 错误率分母 |
| `harbor_registry_errors_total` | Registry 错误数 | 错误率 > 1% 告警 |
| `harbor_registry_storage_total_bytes` | Registry 存储用量 | > 85% 告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 适用场景 |
| --- | --- | --- | --- |
| Harbor 内置 metrics | Harbor 配置启用 | Core / Registry / Jobservice | 标准方案 |
| **Grafana Alloy** | `prometheus.scrape` | 抓取 Harbor 原生端点 | **本项目首选** |
| Netdata | Agent | 部分 Harbor/主机指标 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

Grafana 官方回答建议按组件拆分 scrape job，并通过 `comp` 参数区分 Core / Registry。

```alloy
prometheus.scrape "harbor_exporter" {
  targets = [{ __address__ = "harbor.harbor.svc:9090" }]
  scrape_interval = "20s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "harbor-exporter"
}

prometheus.scrape "harbor_core" {
  targets = [{ __address__ = "harbor.harbor.svc:9090", __param_comp = "core" }]
  scrape_interval = "20s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "harbor-core"
}

prometheus.scrape "harbor_registry" {
  targets = [{ __address__ = "harbor.harbor.svc:9090", __param_comp = "registry" }]
  scrape_interval = "20s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "harbor-registry"
}
```

---

## 6. Harbor 配置要点

```yaml
# harbor.yml
metric:
  enabled: true
  port: 9090
  path: /metrics
```

| 部署方式 | 采集方式 |
| --- | --- |
| Docker Compose Harbor | 启用 metric 后映射 `9090` |
| K8s Harbor | ServiceMonitor 或 Alloy scrape Service |
| 旧版本 Harbor | 确认是否支持 metrics，必要时升级 |

---

## 7. 告警规则

```yaml
groups:
- name: harbor.rules
  rules:
  - alert: HarborJobFailed
    expr: increase(harbor_jobservice_task_failed_total[10m]) > 0
    for: 2m
    labels: { severity: warning }
    annotations: { summary: "Harbor Jobservice 任务失败" }

  - alert: HarborRegistryErrorRateHigh
    expr: rate(harbor_registry_errors_total[5m]) / rate(harbor_registry_requests_total[5m]) > 0.01
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Harbor Registry 错误率超过 1%" }

  - alert: HarborStorageHigh
    expr: harbor_registry_storage_total_bytes / harbor_registry_storage_limit_bytes > 0.85
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Harbor 存储使用率超过 85%" }
```

---

## 8. Grafana Dashboard

Grafana 社区提供 Harbor 和 Harbor Overview Dashboard，适合 Harbor 2.4+ / 2.9+ 场景。核心面板应包含 Core 延迟、Registry 错误率、Jobservice 失败、存储容量、镜像拉取/推送速率。

---

## 9. KAgent 集成（Harbor 运维 Agent）

推荐绑定 PrometheusServer 查询 Harbor 指标，并用 Skills 注入镜像 GC、复制失败、扫描失败、存储清理 SOP。

---

## 10. 常见问题

### Grafana Alloy 能采集 Harbor 指标吗？

**可以。** Harbor 内置 Prometheus 指标端点，Alloy 通过 `prometheus.scrape` 直接抓取，无需额外 exporter。

### Alloy 有内置 Harbor exporter 吗？

没有。Harbor 已原生暴露 metrics，Alloy 的职责是 scrape 和转发。
# Harbor 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Harbor 官方文档：[Harbor Metrics](https://goharbor.io/docs/)
2. Harbor GitHub：[goharbor/harbor](https://github.com/goharbor/harbor)
3. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)
4. Grafana Dashboard：[Harbor dashboards](https://grafana.com/grafana/dashboards/)

---

## 1. 结论摘要

Harbor 内置 Prometheus 指标端点，覆盖 exporter、core、registry、jobservice 等组件。Grafana Alloy **没有内置 `prometheus.exporter.harbor`**，但可通过 `prometheus.scrape` 抓取 Harbor 原生 Prometheus 端点，无需额外 exporter。Harbor 的 PostgreSQL、Redis、Trivy 等依赖也需纳入对应中间件监控。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | Harbor 原生 Prometheus metrics |
| Alloy 集成 | `prometheus.scrape` 抓取各组件端点 |
| 关键组件 | exporter / core / registry / jobservice |
| 依赖组件 | PostgreSQL、Redis、Trivy、对象存储 |
| Dashboard | Harbor / Harbor Overview |

---

## 2. 产品概况（Harbor Metrics）

| 组件 | 指标内容 | 说明 |
| --- | --- | --- |
| harbor-exporter | Harbor 聚合指标 | 常用入口 |
| harbor-core | API、鉴权、DB 连接 | 核心服务 |
| harbor-registry | 镜像拉取/推送、错误 | Registry 服务 |
| jobservice | GC、复制、扫描任务 | 任务队列 |
| Trivy | 漏洞扫描 | 通常由 jobservice 间接观察 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `harbor_core_request_total` | Core 请求总数 | 错误率分母 |
| `harbor_core_request_duration_seconds_bucket` | Core 请求延迟 | P99 > 1s 告警 |
| `harbor_core_db_in_use` | DB 连接占用 | > 80% 告警 |
| `harbor_jobservice_task_total` | 任务总数 | — |
| `harbor_jobservice_task_failed_total` | 任务失败数 | 增长告警 |
| `harbor_registry_requests_total` | Registry 请求数 | — |
| `harbor_registry_errors_total` | Registry 错误数 | 错误率 > 1% 告警 |
| `harbor_registry_storage_total_bytes` | Registry 存储用量 | > 85% 告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| Harbor 内置 metrics | 原生端点 | Harbor 多组件 | 无 | 标准方案 |
| **Grafana Alloy** | `prometheus.scrape` | 抓取原生端点 | Loki 采集容器日志 | **本项目首选** |
| Netdata | Agent | 部分 Harbor/系统指标 | 内置 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 Harbor 官方 comp 参数方式

```alloy
prometheus.scrape "harbor_exporter" {
  targets = [{ __address__ = "harbor.harbor.svc:9090" }]
  job_name = "harbor-exporter"
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.scrape "harbor_core" {
  targets = [{ __address__ = "harbor.harbor.svc:9090", __param_comp = "core" }]
  job_name = "harbor-core"
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.scrape "harbor_registry" {
  targets = [{ __address__ = "harbor.harbor.svc:9090", __param_comp = "registry" }]
  job_name = "harbor-registry"
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.2 多服务端点方式

```alloy
prometheus.scrape "harbor_services" {
  targets = [
    { __address__ = "harbor-core.harbor.svc:8080", component = "core" },
    { __address__ = "harbor-jobservice.harbor.svc:9090", component = "jobservice" },
    { __address__ = "harbor-registry.harbor.svc:5000", component = "registry" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

---

## 6. Harbor 配置要点

```yaml
# harbor.yml
metric:
  enabled: true
  port: 9090
  path: /metrics
```

K8s/Helm/Operator 部署时优先开启 ServiceMonitor 或暴露 metrics Service。

---

## 7. 告警规则

```yaml
groups:
- name: harbor.rules
  rules:
  - alert: HarborJobFailed
    expr: increase(harbor_jobservice_task_failed_total[10m]) > 0
    for: 2m
    labels: { severity: warning }
    annotations: { summary: "Harbor 任务执行失败" }

  - alert: HarborRegistryErrorRateHigh
    expr: rate(harbor_registry_errors_total[5m]) / rate(harbor_registry_requests_total[5m]) > 0.01
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Harbor Registry 错误率超过 1%" }

  - alert: HarborStorageHigh
    expr: harbor_registry_storage_total_bytes / harbor_registry_storage_limit_bytes > 0.85
    for: 10m
    labels: { severity: warning }
    annotations: { summary: "Harbor 存储使用率超过 85%" }
```

---

## 8. Grafana Dashboard

推荐导入 Harbor / Harbor Overview Dashboard。Grafana 社区 Dashboard 通常支持 Harbor 2.4+ 或 2.9+，导入前需核对指标名。

---

## 9. KAgent 集成（Harbor 运维 Agent）

推荐绑定 PrometheusServer 查询 Harbor 任务失败、Registry 错误率、存储容量，并用 Skills 注入镜像清理、复制失败、扫描失败处理 SOP。

---

## 10. 常见问题

### Grafana Alloy 能采集 Harbor 指标吗？

**可以。** Harbor 内置 Prometheus 指标端点，Alloy 通过 `prometheus.scrape` 直接抓取即可，无需额外 exporter。

### Alloy 有内置 Harbor exporter 吗？

没有。Harbor 自身已经暴露 Prometheus 格式指标，Alloy 负责 scrape 和转发。

### Harbor 只监控自身够吗？

不够。Harbor 强依赖 PostgreSQL、Redis、Registry 存储和漏洞扫描任务，这些依赖的可观测性也必须纳入。
