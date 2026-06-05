# PostgreSQL - 关系型数据库

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 业务主库，存储核心业务数据|
| 部署方式 | 待确认（自建 / 托管 RDS）|
| 版本 | - |
| 高可用| 未确认|
| 备份 | 未确认|

---

## 核心配置

```sql
-- PostgreSQL 15+ 推荐参数
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET effective_cache_size = '3GB';
ALTER SYSTEM SET work_mem = '16MB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET log_min_duration_statement = 1000;
```

---

## 高可用方案
| 方案 | 自动切换 | 一致性| 复杂性|
|------|---------|--------|--------|
| Patroni + etcd | 是 | 强一致性 | 高 |
| Repmgr | 是 | 最终一致性 | 中 |
| 云RDS | 是 | 强一致性 | 低 |
| 流复制手动 | 否 | 最终一致性 | 高 |

---

## 备份

```bash
# pg_dump 逻辑备份（中小库）pg_dump -h localhost -U app_user -d smartvision --format=custom --compress=9 \
  -f /backup/smartvision_$(date +%Y%m%d).dump

# WAL-G 物理备份（大库推荐）
wal-g backup-push /var/lib/postgresql/data
wal-g backup-fetch /var/lib/postgresql/data LATEST
```

---

## 监控

```promql
pg_stat_activity_count{datname="smartvision"} / pg_settings_max_connections * 100
rate(pg_stat_database_blks_hit[5m]) / (rate(pg_stat_database_blks_read[5m]) + rate(pg_stat_database_blks_hit[5m])) * 100
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 确认高可用方案（Patroni / RDS）|
| P0 | 开启自动备份 + 每月恢复演练 |
| P1 | 慢查询治理|
| P1 | PgBouncer 连接池|
| P2 | 读写分离 |
