# PostgreSQL 可观测性

> 通过 postgres_exporter 采集 PostgreSQL 运行时指标。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| postgres_exporter | PostgreSQL 指标采集器，连接数据库查询 pg_stat_* 视图 | TCP 9187 /metrics |

无需改 PostgreSQL 配置，exporter 通过连接数据库获取指标。

---

## 核心指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `pg_stat_activity_count` | 当前活跃连接数 | > 80% max_connections 告警 |
| `pg_stat_database_blks_hit` / `pg_stat_database_blks_read` | 缓存命中率 | < 90% 需调优 shared_buffers |
| `pg_stat_database_xact_commit` / `xact_rollback` | 事务提交/回滚比 | 回滚率 > 5% 关注 |
| `pg_replication_lag` | 流复制延迟 | > 10s 告警 |
| `pg_stat_user_tables_seq_scan` | 全表扫描次数 | 持续增长说明缺少索引 |
| `pg_stat_activity_max_tx_duration` | 最长运行事务时间 | > 5min 告警（可能死锁）|

---

## 采集集成

```yaml
# Prometheus static_configs（二进制/Docker 部署）
- job_name: postgresql
  static_configs:
    - targets:
        - "db-host:9187"
      labels:
        service: postgresql
        env: prod

# K8s ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgresql
  namespace: observability
spec:
  selector:
    matchLabels:
      app: postgres-exporter
  endpoints:
    - port: metrics
      interval: 15s
```

---

## 告警规则

```yaml
- alert: PostgresConnectionsHigh
  expr: pg_stat_activity_count / pg_settings_max_connections * 100 > 80
  for: 5m
  annotations:
    summary: "PostgreSQL 连接使用率 {{ $value | humanizePercentage }}"

- alert: PostgresReplicationLag
  expr: pg_replication_lag > 10
  for: 2m
  annotations:
    summary: "PostgreSQL 复制延迟 {{ $value }}s"

- alert: PostgresLongRunningTransaction
  expr: pg_stat_activity_max_tx_duration > 300
  for: 1m
  annotations:
    summary: "PostgreSQL 事务运行超过 5 分钟"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 PostgreSQL | 宿主机起 postgres_exporter，static_configs 指向同一台机器 |
| Docker PostgreSQL | postgres_exporter 也容器化，同 network 连接 |
| K8s PostgreSQL | ServiceMonitor 自动发现 |
| 托管 RDS | 一般云厂商已暴露 Prometheus 端点，直接配置 scrape |

默认 postgres_exporter 不开启自动发现数据库，如需监控多个库需在启动时加 `--extend.query-path` 指定自定义查询文件。

---

## 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
|--------|---------|---------|---------|---------|
| postgres_exporter | 容器/二进制 | pg_stat_* 视图全量 | 无 | Prometheus 标准方案 |
| Grafana Alloy | 需 postgres_exporter | 通过 prometheus.scrape 抓 exporter | 内置 loki.source | Grafana 全栈 |
| Netdata | 一键安装 | 内置 postgres collector | 内置日志查看 | 快速部署 |
| pg_stat_statements | PostgreSQL 扩展 | 查询级性能分析 | 无 | 深度 SQL 调优 |

---

## Alloy 采集配置

```alloy
prometheus.scrape "postgresql" {
  targets = [{ __address__ = "postgres-exporter.db.svc:9187", service = "postgresql" }]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

---

## Netdata 方案

Netdata 内置 postgres collector，自动连接 PostgreSQL 采集指标：

```bash
docker run -d --name=netdata \
  -p 19999:19999 \
  --cap-add SYS_PTRACE \
  netdata/netdata
```

自动采集：连接数、缓存命中率、事务提交/回滚、复制延迟、全表扫描等。无需额外部署 postgres_exporter。

---

## 方案对比

| 维度 | postgres_exporter + Prometheus | Alloy | Netdata |
|------|------------------------------|-------|---------|
| 部署复杂度 | 中 | 中 | 低 |
| 指标精度 | 15s | 10s | 1s |
| 多库支持 | 需 `--extend.query-path` | 需多 exporter 实例 | 自动发现 |
| Grafana 兼容 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 推荐场景 | 已有 Prometheus 栈 | Grafana 全栈 | 快速验证 |
