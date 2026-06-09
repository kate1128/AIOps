# PostgreSQL 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、社区实践
**参考地址：**

1. GitHub：[prometheus-community/postgres_exporter](https://github.com/prometheus-community/postgres_exporter)（~3k stars）
2. 官方文档：[postgres_exporter README](https://github.com/prometheus-community/postgres_exporter#readme)
3. Alloy 内置集成：[prometheus.exporter.postgres](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.postgres/)
4. Grafana Dashboard：[PostgreSQL Database #9628](https://grafana.com/grafana/dashboards/9628)

> Star 数会持续变化。正式对外汇报前建议以 GitHub 实时数据复核。

---

## 1. 结论摘要

PostgreSQL 的 Prometheus 指标采集通过 **postgres_exporter** 实现，它连接 PostgreSQL 查询 `pg_stat_*` 系统视图并以 `/metrics` 格式暴露。在 Grafana Alloy 体系下，**无需单独部署 postgres_exporter Pod**，Alloy 内置了等价的 `prometheus.exporter.postgres` 组件，直接连接数据库即可采集全量指标。

| 关键信息 | 值 |
| --- | --- |
| 主流采集器 | prometheus-community/postgres_exporter |
| 暴露端口 | TCP `9187` `/metrics` |
| 采集方式 | 连接 PostgreSQL，查询 `pg_stat_*` 视图，无需修改 PG 配置 |
| Alloy 内置替代 | `prometheus.exporter.postgres`（无需独立 Pod）|
| 推荐 Grafana Dashboard | ID 9628 |

---

## 2. 产品概况（postgres_exporter）

| 项目 | 内容 |
| --- | --- |
| 产品名称 | postgres_exporter |
| 维护方 | prometheus-community（社区维护）|
| 开源协议 | Apache-2.0 |
| 部署形态 | 二进制 / Docker / Helm / Alloy 内置 |
| 数据来源 | PostgreSQL `pg_stat_*` 系统视图、`pg_settings`、`pg_replication` |
| 兼容版本 | PostgreSQL 9.4+ |
| 多库支持 | 支持，通过 `--extend.query-path` 指定自定义查询文件 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `pg_stat_activity_count` | 当前活跃连接数 | > 80% `max_connections` 告警 |
| `pg_stat_database_blks_hit` / `blks_read` | 缓存命中率 | 命中率 < 90% 需调优 `shared_buffers` |
| `pg_stat_database_xact_commit` / `xact_rollback` | 事务提交 / 回滚比 | 回滚率 > 5% 关注 |
| `pg_replication_lag` | 流复制延迟（秒）| > 10s 告警 |
| `pg_stat_user_tables_seq_scan` | 全表扫描次数 | 持续增长说明缺少索引 |
| `pg_stat_activity_max_tx_duration` | 最长运行事务时间 | > 5min 告警（可能死锁）|
| `pg_database_size_bytes` | 数据库磁盘占用 | 超出容量阈值预警 |
| `pg_locks_count` | 锁等待数量 | 持续高值说明锁竞争 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 多库支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| **Grafana Alloy**（内置）| `prometheus.exporter.postgres` | pg_stat_* 全量 | 多实例配置 | **本项目首选，已部署 Alloy** |
| **Grafana Alloy**（深度）| `database_observability.postgres` | 查询执行计划、慢查询样本、Schema 结构 | 单实例声明 | 需要 SQL 级别深度可观测性时 |
| postgres_exporter | 独立容器 / 二进制 | pg_stat_* 全量 | 需多实例 | 未用 Alloy 的 Prometheus 标准方案 |
| Netdata | 一键安装 | 内置 postgres collector | 自动发现 | 快速验证，不在本项目技术栈内 |
| pg_stat_statements | PostgreSQL 扩展 | 查询级 SQL 性能 | — | 深度 SQL 调优，与 exporter 互补 |

---

## 5. Alloy 集成方案（推荐）

Alloy 内置 `prometheus.exporter.postgres`，基于 wrouesnel/postgres_exporter 实现，**直接连接 PostgreSQL，无需额外部署 exporter Pod**。

### 5.1 方案一：Alloy 内置 Exporter（推荐）

```alloy
// Graph 视图：
// prometheus.exporter.postgres.main
//         ↓
// prometheus.scrape.postgres
//         ↓
// prometheus.remote_write.central

prometheus.exporter.postgres "main" {
  // DSN 格式：postgresql://user:pass@host:5432/dbname?sslmode=disable
  // 密码通过环境变量注入，不写死在配置文件
  data_source_names = [sys.env("POSTGRES_DSN")]
}

prometheus.scrape "postgres" {
  targets         = prometheus.exporter.postgres.main.targets
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
}
```

多数据库实例（每个实例单独声明）：

```alloy
prometheus.exporter.postgres "prod" {
  data_source_names = [sys.env("POSTGRES_DSN_PROD")]
}

prometheus.exporter.postgres "staging" {
  data_source_names = [sys.env("POSTGRES_DSN_STAGING")]
}

prometheus.scrape "postgres_all" {
  targets = concat(
    prometheus.exporter.postgres.prod.targets,
    prometheus.exporter.postgres.staging.targets,
  )
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
}
```

### 5.2 方案二：Alloy 抓取独立 postgres_exporter（兼容已有部署）

已有独立 postgres_exporter Pod 时，直接 scrape，无需迁移：

```alloy
prometheus.scrape "postgres" {
  targets = [
    { __address__ = "postgres-exporter.db.svc.cluster.local:9187", service = "postgresql" },
  ]
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
}
```

### 5.3 方案三：深度可观测性（database_observability.postgres）

适用于需要 SQL 级别诊断的场景（慢查询分析、执行计划、Schema 审查）。与 `prometheus.exporter.postgres` 互补，通常同时启用：

```alloy
database_observability.postgres "main" {
  data_source_name  = sys.env("POSTGRES_DSN")
  forward_to        = [loki.write.default.receiver]
  targets           = prometheus.exporter.postgres.main.targets
  // 按需启用采集器
  enable_collectors = ["query_samples", "explain_plans", "schema_details"]
}
```

| 采集器 | 默认启用 | 说明 |
| --- | --- | --- |
| `query_details` | ✅ | 查询信息（SQL 文本、执行次数）|
| `query_samples` | ❌ | 查询样本和等待事件（慢查询诊断）|
| `explain_plans` | ❌ | 查询执行计划（索引命中分析）|
| `schema_details` | ❌ | Schema、表、列结构信息 |
| `logs` | ❌ | PostgreSQL 日志和错误指标 |

> **前提**：需要 PostgreSQL 开启 `pg_stat_statements` 扩展，且 Alloy 连接账号有 `pg_monitor` 权限。采集数据通过 `forward_to` 发送到 Loki，在 Grafana 中查询。

---

## 6. 独立 postgres_exporter 部署（备选）

不使用 Alloy 或需要独立部署时的参考。

### 6.1 Helm 安装

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --namespace monitoring \
  --set config.datasource.host=postgres.db.svc.cluster.local \
  --set config.datasource.user=postgres \
  --set config.datasource.passwordSecret.name=postgres-secret \
  --set config.datasource.passwordSecret.key=password
```

### 6.2 K8s ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgresql
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: postgres-exporter
  endpoints:
    - port: metrics
      interval: 30s
```

### 6.3 部署方式对比

| 部署方式 | 采集配置 |
| --- | --- |
| 二进制 PostgreSQL | 宿主机起 postgres_exporter，`static_configs` 指向同一台机器 |
| Docker PostgreSQL | postgres_exporter 容器化，同 network 连接 |
| K8s PostgreSQL | ServiceMonitor 自动发现 |
| 托管 RDS | 云厂商一般已暴露 Prometheus 端点，直接配置 scrape |

---

## 7. 告警规则

```yaml
groups:
  - name: postgresql
    rules:
      - alert: PostgresConnectionsHigh
        expr: pg_stat_activity_count / pg_settings_max_connections * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL 连接使用率过高（{{ $value | humanizePercentage }}）"

      - alert: PostgresReplicationLag
        expr: pg_replication_lag > 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL 复制延迟 {{ $value }}s"

      - alert: PostgresLongRunningTransaction
        expr: pg_stat_activity_max_tx_duration > 300
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL 事务运行超过 5 分钟（可能死锁）"

      - alert: PostgresCacheHitRateLow
        expr: |
          pg_stat_database_blks_hit /
          (pg_stat_database_blks_hit + pg_stat_database_blks_read) < 0.90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL 缓存命中率低于 90%（{{ $value | humanizePercentage }}）"
```

---

## 8. Grafana Dashboard

推荐使用 Dashboard ID [9628](https://grafana.com/grafana/dashboards/9628)（PostgreSQL Database），数据源选 Prometheus，与 postgres_exporter 和 Alloy 内置 exporter 指标兼容。

---

## 9. KAgent 集成（PostgreSQL MCP Server + Skills）

官方 MCP 仓库提供了 **PostgreSQL MCP Server**，可让 KAgent 通过自然语言直接查询 PostgreSQL，实现"问数据库"的运维交互。

> **注意：PostgreSQL MCP Server 已归档**
> 原仓库 `modelcontextprotocol/servers` 中的 PostgreSQL 实现已迁移至存档仓库：
> [`modelcontextprotocol/servers-archived/src/postgres`](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/postgres)
> npm 包 `@modelcontextprotocol/server-postgres` 仍可正常使用（`npx` 方式部署），功能稳定但不再主动迭代新特性。

### 9.1 能力说明

| 能力 | 说明 |
| --- | --- |
| 查询 schema | 自动暴露所有表名、字段名、类型给 LLM，无需手动描述 |
| 执行只读 SQL | LLM 自主构造 SELECT 查询并执行，返回结果 |
| 安全限制 | 官方实现**只支持只读操作**，不执行 INSERT / UPDATE / DELETE |

### 9.2 典型对话场景

```
工程师: "orders 表最近 1 天的写入量是多少？"
工程师: "当前有哪些长时间未提交的事务？"
工程师: "payment_logs 表结构是什么？"
工程师: "查一下最近 1 小时执行次数最多的 TOP 10 SQL（需开启 pg_stat_statements）"
```

### 9.3 部署与注册

**Step 1：部署 PostgreSQL MCP Server**

```bash
kubectl -n kagent apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-mcp
  namespace: kagent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-mcp
  template:
    metadata:
      labels:
        app: postgres-mcp
    spec:
      containers:
      - name: postgres-mcp
        image: node:20-slim
        command: ["npx", "-y", "@modelcontextprotocol/server-postgres", "$(POSTGRES_DSN)"]
        env:
        - name: POSTGRES_DSN
          valueFrom:
            secretKeyRef:
              name: postgres-secret   # 提前创建 Secret，key 为 dsn
              key: dsn
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-mcp
  namespace: kagent
spec:
  selector:
    app: postgres-mcp
  ports:
    - port: 3000
      targetPort: 3000
EOF
```

**Step 2：注册为 RemoteMCPServer**

```bash
kubectl -n kagent apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: postgres-mcp
  namespace: kagent
spec:
  protocol: STREAMABLE_HTTP
  url: http://postgres-mcp.kagent:3000/
  description: "PostgreSQL MCP Server，允许 Agent 查询数据库 schema 和执行只读 SQL"
EOF
```

**Step 3：在 Agent 中绑定工具**

```bash
kubectl -n kagent apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: db-ops-agent
  namespace: kagent
spec:
  description: "数据库运维助手，可查询 PostgreSQL schema 和执行只读 SQL"
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    stream: true
    systemMessage: |
      你是一个数据库运维助手。
      当工程师询问数据库相关问题时，使用 postgres-mcp 工具查询数据库 schema 和执行 SQL。
      只执行 SELECT 查询，不执行任何写操作。
      回答用中文，SQL 结果以表格形式展示。
    tools:
    - type: McpServer
      mcpServer:
        apiGroup: kagent.dev
        kind: RemoteMCPServer
        name: postgres-mcp
        toolNames: ["query", "list_tables", "describe_table"]
EOF
```

### 9.4 创建 DSN Secret

```bash
kubectl create secret generic postgres-secret \
  -n kagent \
  --from-literal=dsn="postgresql://readonly_user:password@postgres.db.svc.cluster.local:5432/appdb?sslmode=disable"
```

> **建议使用只读账号**，在 PostgreSQL 中单独创建 `readonly` 角色并 GRANT SELECT：
> ```sql
> CREATE USER readonly_user WITH PASSWORD 'password';
> GRANT CONNECT ON DATABASE appdb TO readonly_user;
> GRANT USAGE ON SCHEMA public TO readonly_user;
> GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
> ```

### 9.5 KAgent Skills：为 Agent 注入 PostgreSQL 运维知识

KAgent 的 **Git-Based Skills** 机制允许将 Markdown 文档从 Git 仓库加载到 Agent 的 System Prompt，相当于给 Agent 一本随时参考的运维手册。PostgreSQL 运维 SOP 可以作为 Skill 注入，让 Agent 的回答符合团队规范，而不是依赖 LLM 的通用知识。

**Skill 文档示例（存放在 Git 仓库）：**

```markdown
<!-- skills/postgres-ops.md -->
# PostgreSQL 运维规范

## 告警处理
- 连接数超过 max_connections 的 80% 时，通知 DBA，不要直接 kill 连接
- 复制延迟 > 30s 升级为 P1 告警，立即通知值班
- 慢查询阈值：执行时间 > 5s 的 SQL 需记录并分析

## 日常检查
- 查询慢 SQL 优先检查 pg_stat_statements
- 磁盘使用 > 70% 时触发 VACUUM ANALYZE
- 死锁发生时查 pg_locks 和 pg_stat_activity
```

**在 Agent CRD 中引用 Skill：**

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: db-ops-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    gitSkills:
    - repoURL: "https://gitlab.internal/ops/runbooks.git"
      branch: main
      paths:
      - "skills/postgres-ops.md"
    tools:
    - type: McpServer
      mcpServer:
        kind: RemoteMCPServer
        name: postgres-mcp
        toolNames: ["query", "list_tables", "describe_table"]
```

> KAgent 的 **Agent Memory** 同样依赖 PostgreSQL（需开启 `pgvector` 扩展）作为向量存储后端，用于保存跨会话的历史记忆。如果团队已部署 PostgreSQL，可复用同一实例同时支持 MCP 工具查询和 Memory 向量存储（建议单独创建 schema/数据库隔离）。

---

## 10. 常见问题

### 为什么推荐 Alloy 内置而不是独立 postgres_exporter？

本项目已部署 Grafana Alloy DaemonSet，Alloy 内置的 `prometheus.exporter.postgres` 直接连接数据库采集，无需额外容器，减少运维组件数量。指标名称和独立 postgres_exporter 完全一致，Grafana Dashboard 通用。

### 连接多个 PostgreSQL 实例怎么配？

在 Alloy 中为每个实例单独声明 `prometheus.exporter.postgres` 块（设置不同 Label），然后在 `prometheus.scrape` 中用 `concat()` 合并 targets（见 §5.1）。

### pg_stat_statements 和 postgres_exporter 是什么关系？

两者互补：postgres_exporter 采集数据库级别的运行时状态（连接数、锁、复制延迟等）；`pg_stat_statements` 是 PostgreSQL 扩展，记录每条 SQL 的执行次数和耗时，适合 SQL 性能调优，不能被 exporter 替代。

### Grafana Alloy 支持采集 PostgreSQL 指标吗？

**完全支持。** Alloy 内置了 `prometheus.exporter.postgres` 组件，无需单独部署 postgres_exporter。此外还提供 `database_observability.postgres` 组件，可采集查询执行计划、慢查询样本等更深层次的数据库可观测性数据。

> 来源：Grafana 官方文档（2026年6月）

#### 方式一：基础指标采集（prometheus.exporter.postgres）

适合监控 PostgreSQL 服务器运行状态和性能指标：

```alloy
prometheus.exporter.postgres "example" {
  data_source_names = ["postgresql://username:password@localhost:5432/database_name?sslmode=disable"]
}

prometheus.scrape "default" {
  targets    = prometheus.exporter.postgres.example.targets
  forward_to = [prometheus.remote_write.demo.receiver]
}

prometheus.remote_write "demo" {
  endpoint {
    url = "<PROMETHEUS_REMOTE_WRITE_URL>"
    basic_auth {
      username = "<USERNAME>"
      password = "<PASSWORD>"
    }
  }
}
```

#### 方式二：Grafana Cloud 集成配置（含 enabled_collectors）

通过 `enabled_collectors` 精确控制采集哪些指标模块：

```alloy
prometheus.exporter.postgres "integrations_postgres_exporter" {
  data_source_names  = ["postgresql://localhost:5432/postgres"]
  enabled_collectors = ["database", "locks", "long_running_transactions", "postmaster",
                        "replication", "stat_bgwriter", "stat_database", "stat_statements",
                        "stat_user_tables", "statio_user_indexes"]
}

discovery.relabel "integrations_postgres_exporter" {
  targets = prometheus.exporter.postgres.integrations_postgres_exporter.targets

  rule {
    target_label = "instance"
    replacement  = constants.hostname
  }
  rule {
    target_label = "job"
    replacement  = "integrations/postgres_exporter"
  }
}

prometheus.scrape "integrations_postgres_exporter" {
  targets    = discovery.relabel.integrations_postgres_exporter.output
  forward_to = [prometheus.remote_write.metrics_service.receiver]
  job_name   = "integrations/postgres_exporter"
}
```

**`enabled_collectors` 完整列表：**

| 采集器 | 默认启用 | 说明 |
| --- | --- | --- |
| `database` | ✅ | 数据库级别统计（大小、事务、缓存命中）|
| `locks` | ✅ | 锁等待统计 |
| `stat_bgwriter` | ✅ | 后台写进程统计 |
| `stat_database` | ✅ | 数据库连接和事务统计 |
| `stat_user_tables` | ✅ | 用户表扫描和 DML 统计 |
| `replication` | ✅ | 流复制延迟和状态 |
| `wal` | ✅ | WAL 日志写入统计 |
| `stat_statements` | ❌ | SQL 级别执行统计（需开启 pg_stat_statements 扩展）|
| `long_running_transactions` | ❌ | 长时间运行的事务 |
| `postmaster` | ❌ | PostgreSQL 进程启动时间 |

#### 方式三：深度可观测性（database_observability.postgres）

如果需要采集查询详情、执行计划、Schema 信息等更深层次的数据：

```alloy
database_observability.postgres "orders_db" {
  data_source_name  = "postgres://user:pass@localhost:5432/dbname"
  forward_to        = [loki.relabel.orders_db.receiver]
  targets           = prometheus.exporter.postgres.orders_db.targets
  enable_collectors = ["query_samples", "explain_plans"]
}
```

| 采集器 | 说明 |
| --- | --- |
| `query_details` | 查询信息 |
| `query_samples` | 查询样本和等待事件 |
| `explain_plans` | 查询执行计划（慢查询分析）|
| `schema_details` | Schema、表、列结构信息 |
| `logs` | PostgreSQL 日志和错误指标 |

#### 快速体验（官方示例仓库）

```bash
git clone https://github.com/grafana/alloy-scenarios.git
cd alloy-scenarios/postgres-monitoring
docker compose up -d
```

| 服务 | URL |
| --- | --- |
| Grafana | http://localhost:3000 |
| Alloy UI | http://localhost:12345 |
| Prometheus | http://localhost:9090 |

#### 三种方式汇总

| 方式 | 组件 | 适用场景 |
| --- | --- | --- |
| 基础指标 | `prometheus.exporter.postgres` | 服务器性能监控（连接数、锁、复制延迟）|
| 深度可观测性 | `database_observability.postgres` | 查询分析、慢查询、执行计划 |
| 日志采集 | `loki.source.file` | PostgreSQL 日志收集 |
