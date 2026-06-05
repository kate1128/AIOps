# MinIO 可观测性

> MinIO 内置 Prometheus 指标端点，暴露集群和存储桶级别指标。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| MinIO 内置 /metrics v2 | 集群、节点、存储桶级指标 | TCP 9000 /minio/v2/metrics/cluster |
| MinIO Console | Web UI 查看存储桶/访问日志 | TCP 9001 |
| Audit Log | 操作审计日志（S3 API 调用）| JSON 格式写入文件或 Webhook |

---

## 核心指标

### 集群级

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `minio_cluster_capacity_raw_total_bytes` | 集群原始总容量 | — |
| `minio_cluster_capacity_usable_total_bytes` | 集群可用总容量 | — |
| `minio_cluster_usage_total_bytes` | 集群已用容量 | > 85% 告警 |
| `minio_cluster_drive_offline_total` | 离线磁盘数 | > 0 告警 |
| `minio_cluster_nodes_online_total` | 在线节点数 | < 预期节点数告警 |

### 节点级

| 指标 | 含义 |
|------|------|
| `minio_node_drive_offline_total` | 节点内离线磁盘 |
| `minio_node_syscall_read_total` | 系统调用读次数 |
| `minio_node_syscall_write_total` | 系统调用写次数 |

### 性能

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `minio_s3_traffic_received_bytes` | S3 入流量 | — |
| `minio_s3_traffic_sent_bytes` | S3 出流量 | — |
| `minio_s3_requests_total` | 总请求数 | — |
| `minio_s3_errors_total` | 请求错误数 | 错误率 > 1% 告警 |

---

## 采集集成

```yaml
# MinIO 启动后自动暴露 /metrics（需要认证）
# 创建 Prometheus 专用用户
mc admin user add myminio prometheus mysecretpassword
mc admin policy set myminio prometheus prometheus user prometheus

# Prometheus scrape（需 bearer token）
- job_name: minio
  metrics_path: /minio/v2/metrics/cluster
  static_configs:
    - targets:
        - "minio-host:9000"
      labels:
        service: minio
        env: prod
  authorization:
    type: Bearer
    credentials: "mysecretpassword"  # 建议从 Secret 注入

# K8s ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: minio
  namespace: observability
spec:
  selector:
    matchLabels:
      app: minio
  endpoints:
    - port: metrics
      interval: 15s
      path: /minio/v2/metrics/cluster
  authorization:
    type: Bearer
    credentials:
      name: minio-prometheus-secret
      key: token
```

---

## 告警规则

```yaml
- alert: MinioDiskOffline
  expr: minio_cluster_drive_offline_total > 0
  for: 1m
  annotations:
    summary: "MinIO 有 {{ $value }} 个磁盘离线，需要立即处理"

- alert: MinioStorageHigh
  expr: minio_cluster_usage_total_bytes / minio_cluster_capacity_usable_total_bytes * 100 > 85
  for: 5m
  annotations:
    summary: "MinIO 存储使用率 {{ $value | humanizePercentage }}"

- alert: MinioNodeOffline
  expr: minio_cluster_nodes_online_total < minio_cluster_nodes_offline_total + minio_cluster_nodes_online_total
  for: 2m
  annotations:
    summary: "MinIO 节点离线"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 MinIO | `/minio/v2/metrics/cluster` 默认暴露，需配置 Prometheus 认证 |
| Docker MinIO | 容器内暴露 9000，同 network 抓取 |
| K8s MinIO Operator | Operator 自动创建 ServiceMonitor |

MinIO /metrics v2 需要认证，不能在 Prometheus 用 bare token，建议通过 K8s Secret 注入或配置 `MINIO_PROMETHEUS_AUTH_TYPE=public`（仅内网环境）。
