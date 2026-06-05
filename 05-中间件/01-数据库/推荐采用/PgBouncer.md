# PgBouncer - PostgreSQL 连接池

> 推荐原因：SmartVision 在 K8s 上运行多副本服务，每个 Pod 直连 PostgreSQL 会导致连接数爆炸（100+ Pod × 5 连接 = 500+ 并发连接），PgBouncer 作为连接池代理可将实际后端连接控制在 20-50 个。
> 当前状态：❌ 未部署，推荐在 PostgreSQL 使用规模扩大后引入。

---

## 现状与问题

| 项目 | 现状 |
|------|------|
| PostgreSQL 连接方式 | 各服务直连（无连接池）|
| K8s Pod 数量（预估）| 业务服务 50-100 个 Pod |
| 潜在最大连接数 | 200-500 个 |
| PostgreSQL max_connections 默认值 | 100（超过则报错）|
| 已触发的问题 | 压测/灰度期间偶发 "too many connections" |

---

## PgBouncer 是什么

PgBouncer 是 PostgreSQL 专用的轻量级连接池中间件，以 **transaction pooling 模式** 为主，可将上层的 N 个短连接复用到后端的 M 个长连接（通常 M << N），大幅减少 PostgreSQL 的连接压力。

```
K8s Pods (500 连接) ──→ PgBouncer (20 后端连接) ──→ PostgreSQL
```

---

## 核心对比

| 维度 | 无连接池 | PgBouncer (transaction) | PgBouncer (session) |
|------|----------|------------------------|---------------------|
| 并发连接数 | Pod 数 × 连接数 | 固定小数字（如 20）| 介于两者之间 |
| 延迟 | 极低 | 极低（纯代理）| 极低 |
| 兼容性 | 100% | 不支持 SET/prepared statements | 完整支持 |
| 适合场景 | 小规模、低并发 | 高并发、无状态 API | 需要事务外 SET 的服务 |
| 内存占用 | 无 | < 10MB | < 10MB |

---

## K8s 部署

```yaml
# pgbouncer-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
  namespace: prod
spec:
  replicas: 2  # 高可用，2 副本
  selector:
    matchLabels:
      app: pgbouncer
  template:
    metadata:
      labels:
        app: pgbouncer
    spec:
      containers:
      - name: pgbouncer
        image: bitnami/pgbouncer:1.22.1
        env:
        - name: POSTGRESQL_HOST
          value: "postgresql.prod.svc.cluster.local"
        - name: POSTGRESQL_PORT
          value: "5432"
        - name: PGBOUNCER_DATABASE
          value: "smartvision"
        - name: PGBOUNCER_POOL_MODE
          value: "transaction"
        - name: PGBOUNCER_MAX_CLIENT_CONN
          value: "500"
        - name: PGBOUNCER_DEFAULT_POOL_SIZE
          value: "20"
        - name: PGBOUNCER_MIN_POOL_SIZE
          value: "5"
        - name: POSTGRESQL_USERNAME
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: username
        - name: POSTGRESQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: password
        ports:
        - containerPort: 5432
        resources:
          requests: { cpu: "50m", memory: "32Mi" }
          limits:   { cpu: "200m", memory: "128Mi" }
---
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer
  namespace: prod
spec:
  selector:
    app: pgbouncer
  ports:
  - port: 5432
    targetPort: 5432
```

---

## 关键参数说明

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `pool_mode` | transaction | 大多数无状态 API 适用，连接利用率最高 |
| `max_client_conn` | 500 | 最多允许 500 个上游客户端连接 |
| `default_pool_size` | 20 | 每个 db/user 对 维持 20 个后端连接 |
| `server_idle_timeout` | 600 | 后端空闲连接 10 分钟后关闭 |
| `query_wait_timeout` | 10 | 等待连接超过 10s 则报错（防止雪崩）|

---

## 不适合 PgBouncer transaction 模式的场景

> ⚠️ 以下 PostgreSQL 功能在 transaction pooling 下会报错：

```sql
-- 不兼容：
SET search_path = 'myschema';         -- session 级别 SET
LISTEN/NOTIFY                          -- 长连接推送
Prepared statements (PREPARE/EXECUTE)  -- 跨事务不保留
Advisory Locks                         -- session 级别锁

-- 解决方案：
-- 1. 改用 session pooling（适合上述场景，但连接节省效果弱）
-- 2. 单独为这些服务保留直连 PostgreSQL
```

---

## 监控指标

```bash
# pgbouncer SHOW STATS 暴露的关键指标（通过 pgbouncer_exporter 接入 Prometheus）
pgbouncer_pools_cl_active    # 活跃客户端连接数
pgbouncer_pools_sv_active    # 活跃服务端连接数
pgbouncer_pools_sv_idle      # 空闲服务端连接数
pgbouncer_pools_cl_waiting   # 等待连接的客户端数（>0 说明连接不够用）

# 告警规则
- alert: PgBouncerClientWaiting
  expr: pgbouncer_pools_cl_waiting > 10
  for: 1m
  labels: { severity: warning }
  annotations:
    summary: "PgBouncer 有 {{ $value }} 个客户端在等待连接"
```

---

## 引入优先级

| 触发条件 | 优先级 |
|---------|--------|
| PostgreSQL 报 "too many connections" | 🔴 立即引入 |
| K8s Pod 数 > 50，预估连接 > 200 | 🟡 计划引入 |
| 当前 Pod 数 < 30，连接稳定 | ⚪ 暂缓 |

---

## 参考

- 官方文档：https://www.pgbouncer.org/config.html
- Bitnami 镜像：https://hub.docker.com/r/bitnami/pgbouncer
- pgbouncer_exporter：https://github.com/prometheus-community/pgbouncer_exporter
