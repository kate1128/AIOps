# MinIO 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. MinIO Metrics：[MinIO Prometheus Metrics](https://min.io/docs/minio/linux/operations/monitoring/collect-minio-metrics-using-prometheus.html)
2. MinIO GitHub：[minio/minio](https://github.com/minio/minio)
3. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus.scrape/)
4. Grafana Dashboard：[MinIO dashboards](https://grafana.com/grafana/dashboards/)

---

## 1. 结论摘要

MinIO 内置 Prometheus 指标端点，覆盖集群、节点、磁盘、Bucket、S3 API、复制等维度。Grafana Alloy **完全支持采集 MinIO 指标**，通过 `prometheus.scrape` 抓取 MinIO metrics 端点即可。官方回答与调研结论一致：关键不是 Alloy 能否采集，而是 MinIO metrics 端点路径和认证方式要配置正确。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | MinIO 内置 Prometheus metrics |
| 常用路径 | `/minio/v2/metrics/cluster` 或 `/minio/prometheus/metrics` |
| 默认端口 | TCP `9000` |
| Alloy 集成 | `prometheus.scrape` + Bearer Token |
| 推荐 Dashboard | MinIO distributed cluster metrics、Object Storage、Bucket、Replication |

---

## 2. 产品概况（MinIO metrics）

| 项目 | 内容 |
| --- | --- |
| 产品名称 | MinIO |
| 类型 | S3 兼容对象存储 |
| 指标来源 | MinIO Server 内置 metrics |
| 指标维度 | Cluster、Node、Drive、Bucket、S3、Replication |
| 日志来源 | Audit Log / Server Log，经 Loki 采集 |
| 认证方式 | Public / Bearer Token |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `minio_cluster_capacity_raw_total_bytes` | 集群原始容量 | 容量规划 |
| `minio_cluster_capacity_usable_total_bytes` | 集群可用容量 | 容量分母 |
| `minio_cluster_usage_total_bytes` | 集群已用容量 | > 85% 告警 |
| `minio_cluster_drive_offline_total` | 离线磁盘数 | > 0 立即告警 |
| `minio_cluster_nodes_online_total` | 在线节点数 | 低于预期告警 |
| `minio_s3_requests_total` | S3 请求总数 | QPS 基线、错误率分母 |
| `minio_s3_errors_total` | S3 错误总数 | 错误率 > 1% 告警 |
| `minio_s3_traffic_received_bytes` / `minio_s3_traffic_sent_bytes` | S3 入/出流量 | 异常突增关注 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| MinIO 内置 metrics | 原生端点 | 集群/节点/Bucket/S3 | 无 | 标准方案 |
| **Grafana Alloy** | `prometheus.scrape` | 抓取 MinIO metrics | Loki 采集审计日志 | **本项目首选** |
| Prometheus Operator | ServiceMonitor | 抓取 MinIO metrics | 无 | K8s 监控栈 |
| Netdata | Agent | 内置 MinIO collector | 内置 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 单实例 / 单集群采集

```alloy
discovery.relabel "minio" {
  targets = [{ __address__ = "minio.storage.svc:9000" }]
  rule { target_label = "instance" replacement = "minio-prod" }
}

prometheus.scrape "minio" {
  targets = discovery.relabel.minio.output
  metrics_path = "/minio/v2/metrics/cluster"
  authorization {
    type = "Bearer"
    credentials = sys.env("MINIO_PROMETHEUS_TOKEN")
  }
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "integrations/minio"
}
```

### 5.2 Grafana Cloud 示例路径

```alloy
prometheus.scrape "minio" {
  targets = [{ __address__ = "localhost:9000" }]
  metrics_path = "/minio/prometheus/metrics"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "integrations/minio"
}
```

### 5.3 多节点采集

```alloy
discovery.relabel "minio_node1" {
  targets = [{ __address__ = "minio-node1:9000" }]
  rule { target_label = "instance" replacement = "minio-node1" }
}

discovery.relabel "minio_node2" {
  targets = [{ __address__ = "minio-node2:9000" }]
  rule { target_label = "instance" replacement = "minio-node2" }
}

prometheus.scrape "minio_cluster" {
  targets = concat(discovery.relabel.minio_node1.output, discovery.relabel.minio_node2.output)
  metrics_path = "/minio/prometheus/metrics"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "integrations/minio"
}
```

---

## 6. 认证与部署配置

```bash
# 开发/内网环境：公开 Prometheus 指标
export MINIO_PROMETHEUS_AUTH_TYPE="public"

# 生产环境：生成 Prometheus Bearer Token
mc admin prometheus generate myminio
```

生产环境不建议长期使用 public metrics，应将 `mc admin prometheus generate` 生成的 token 放入 Secret，再以环境变量或密钥文件方式注入 Alloy。

---

## 7. 告警规则

```yaml
groups:
- name: minio.rules
  rules:
  - alert: MinioDiskOffline
    expr: minio_cluster_drive_offline_total > 0
    for: 1m
    labels: { severity: critical }
    annotations: { summary: "MinIO 存在离线磁盘" }

  - alert: MinioStorageHigh
    expr: minio_cluster_usage_total_bytes / minio_cluster_capacity_usable_total_bytes > 0.85
    for: 10m
    labels: { severity: warning }
    annotations: { summary: "MinIO 存储使用率超过 85%" }

  - alert: MinioS3ErrorRateHigh
    expr: rate(minio_s3_errors_total[5m]) / rate(minio_s3_requests_total[5m]) > 0.01
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "MinIO S3 错误率超过 1%" }
```

---

## 8. Grafana Dashboard

Grafana Cloud MinIO 集成提供预置 Dashboard 和告警规则。社区常用 Dashboard 包括 MinIO distributed cluster metrics、MinIO Object Storage、MinIO Bucket Dashboard、MinIO Replication Dashboard。

---

## 9. KAgent 集成（MinIO 运维 Agent）

推荐绑定 PrometheusServer 查询容量、离线磁盘、S3 错误率、复制状态，并用 Git-Based Skills 注入磁盘替换、Bucket 增长、对象清理、审计日志排查 SOP。

---

## 10. 常见问题

### Grafana Alloy 支持采集 MinIO 指标吗？

**完全支持。** Grafana Cloud 提供 MinIO 集成，Alloy 使用 `prometheus.scrape` 抓取 MinIO Prometheus 指标端点。

### `/minio/v2/metrics/cluster` 和 `/minio/prometheus/metrics` 用哪个？

两者都在实践中出现过，取决于 MinIO 版本、部署方式和集成模板。建议以当前 MinIO 实例实际暴露路径为准，用 `curl` 或 `mc admin prometheus generate` 输出确认。

### public metrics 适合生产吗？

不建议。生产环境应使用 Bearer Token，并限制 Alloy 到 MinIO metrics 端点的网络访问。
