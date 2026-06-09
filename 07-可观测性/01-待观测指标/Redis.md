# Redis 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. GitHub：[oliver006/redis_exporter](https://github.com/oliver006/redis_exporter)（~3k stars）
2. 官方文档：[redis_exporter README](https://github.com/oliver006/redis_exporter#readme)
3. Redis 官方监控文档：[Redis monitoring](https://redis.io/docs/latest/operate/oss_and_stack/management/monitoring/)
4. Alloy 内置集成：[prometheus.exporter.redis](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.redis/)
5. Netdata Redis Collector：[Redis collector](https://learn.netdata.cloud/docs/collecting-metrics/databases/redis)

> Star 数会持续变化。正式对外汇报前建议以 GitHub 实时数据复核。

---

## 1. 结论摘要

Redis 的 Prometheus 指标采集通常通过 **redis_exporter** 实现，它连接 Redis 实例执行 `INFO`、`CONFIG`、`SLOWLOG` 等命令，并以 `/metrics` 格式暴露。在 Grafana Alloy 体系下，**无需单独部署 redis_exporter Pod**，Alloy 内置了等价的 `prometheus.exporter.redis` 组件，直接连接 Redis 即可采集核心指标。

| 关键信息 | 值 |
| --- | --- |
| 主流采集器 | oliver006/redis_exporter |
| 暴露端口 | TCP `9121` `/metrics` |
| 采集方式 | 连接 Redis，执行 `INFO` / `SLOWLOG` / `CONFIG` 等命令 |
| Alloy 内置替代 | `prometheus.exporter.redis`（无需独立 Pod）|
| 支持部署形态 | 单实例、哨兵、Cluster、托管 Redis |
| 推荐 Grafana Dashboard | ID 763 |

---

## 2. 产品概况（redis_exporter）

| 项目 | 内容 |
| --- | --- |
| 产品名称 | redis_exporter |
| 维护方 | oliver006（社区维护）|
| 开源协议 | MIT |
| 部署形态 | 二进制 / Docker / Helm / Alloy 内置 |
| 数据来源 | Redis `INFO`、`CONFIG`、`SLOWLOG`、`CLIENT LIST`、Keyspace 统计 |
| 兼容版本 | Redis 2.x+，支持 Redis 6 ACL |
| 集群支持 | 支持 Redis Sentinel / Redis Cluster |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `redis_up` | Redis 实例是否可达 | `== 0` 立即告警 |
| `redis_connected_clients` | 当前客户端连接数 | > 80% `maxclients` 告警 |
| `redis_memory_used_bytes` | 当前已用内存 | > 80% `maxmemory` 告警 |
| `redis_memory_max_bytes` | Redis 最大内存配置 | 作为内存利用率分母 |
| `redis_keyspace_hits_total` / `redis_keyspace_misses_total` | 缓存命中 / 未命中次数 | 命中率 < 90% 需排查 |
| `redis_commands_processed_total` | 命令处理总量 | 用于计算 QPS，突增需关注 |
| `redis_rejected_connections_total` | 被拒绝连接数 | > 0 告警，说明连接数打满 |
| `redis_evicted_keys_total` | 被淘汰 Key 数 | 持续增长说明内存压力大 |
| `redis_expired_keys_total` | 过期 Key 数 | 结合业务 TTL 判断是否异常 |
| `redis_connected_slaves` | 已连接从节点数 | 主从架构下低于预期告警 |
| `redis_master_repl_offset` / `redis_slave_repl_offset` | 主从复制偏移量 | 差值持续增大说明复制延迟 |
| `redis_slowlog_length` | 慢查询日志长度 | > 0 且持续增长需排查慢命令 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 多实例支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| **Grafana Alloy**（内置）| `prometheus.exporter.redis` | Redis INFO / Slowlog / Keyspace | foreach / 多组件声明 | **本项目首选，已部署 Alloy** |
| redis_exporter | 独立容器 / 二进制 | Redis INFO / Slowlog / Keyspace | 需多实例或动态发现 | 未用 Alloy 的 Prometheus 标准方案 |
| Netdata | 一键安装 | 内置 Redis collector | 自动发现 | 快速验证、秒级实时监控 |
| Redis 原生命令 | `INFO` / `SLOWLOG` / `LATENCY` | 手动诊断 | — | 故障排查，不适合作为长期指标管道 |

> Grafana 官方回答与本调研一致：Alloy 内置 `prometheus.exporter.redis`，可直接采集 Redis 指标，无需单独部署 redis_exporter。区别是官方回答补充了 Grafana Cloud 集成写法、`foreach` 多实例采集方式和常用参数列表。

---

## 5. Alloy 集成方案（推荐）

Alloy 内置 `prometheus.exporter.redis`，直接连接 Redis 实例采集指标，并通过 `prometheus.scrape` 转发到 Prometheus / Mimir / Grafana Cloud。该能力等价于独立 redis_exporter，适合在本项目的统一 Alloy 采集体系中使用。

### 5.1 方案一：Alloy 内置 Exporter（推荐）

```alloy
// Graph 视图：
// prometheus.exporter.redis.main
//         ↓
// prometheus.scrape.redis
//         ↓
// prometheus.remote_write.central

prometheus.exporter.redis "main" {
  redis_addr = "redis://redis-master.cache.svc.cluster.local:6379"
  // Redis 6 ACL 用户名（可选）
  // redis_user = sys.env("REDIS_USER")
  // 密码通过环境变量注入，不写死在配置文件
  redis_password = sys.env("REDIS_PASSWORD")
}

prometheus.scrape "redis" {
  targets         = prometheus.exporter.redis.main.targets
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

### 5.2 方案二：Grafana Cloud 集成配置

Grafana 官方 Redis 集成推荐通过 `discovery.relabel` 统一补充 `instance` 和 `job` 标签：

```alloy
prometheus.exporter.redis "integrations_redis_exporter" {
  redis_addr = "localhost:6379"
}

discovery.relabel "integrations_redis_exporter" {
  targets = prometheus.exporter.redis.integrations_redis_exporter.targets

  rule {
    target_label = "instance"
    replacement  = constants.hostname
  }

  rule {
    target_label = "job"
    replacement  = "integrations/redis_exporter"
  }
}

prometheus.scrape "integrations_redis_exporter" {
  targets    = discovery.relabel.integrations_redis_exporter.output
  forward_to = [prometheus.remote_write.metrics_service.receiver]
  job_name   = "integrations/redis_exporter"
}
```

### 5.3 方案三：多实例采集（foreach）

如需监控多个 Redis 实例，可用 `foreach` 按目标循环创建采集管道：

```alloy
discovery.relabel "redis" {
  targets = [
    { __address__ = "redis://redis-master.cache.svc.cluster.local:6379", role = "master" },
    { __address__ = "redis://redis-replica.cache.svc.cluster.local:6379", role = "replica" },
  ]
}

foreach "redis" {
  collection = discovery.relabel.redis.output
  var        = "each"

  template {
    prometheus.exporter.redis "default" {
      redis_addr = each["__address__"]
    }

    prometheus.scrape "default" {
      targets    = prometheus.exporter.redis.default.targets
      forward_to = [prometheus.remote_write.central.receiver]
    }
  }
}
```

### 5.4 常用参数

| 参数 | 类型 | 说明 | 默认值 | 必填 |
| --- | --- | --- | --- | --- |
| `redis_addr` | string | Redis 实例地址（`host:port` 或 `redis://host:port`）| — | 是 |
| `redis_password` | secret | Redis 密码 | — | 否 |
| `redis_user` | string | Redis 6.0+ ACL 用户名 | — | 否 |
| `connection_timeout` | duration | 连接超时时间 | `15s` | 否 |
| `is_cluster` | bool | 是否为 Redis Cluster 模式 | `false` | 否 |
| `skip_tls_verification` | bool | 是否跳过 TLS 验证 | `false` | 否 |
| `namespace` | string | 指标命名空间前缀 | `redis` | 否 |

### 5.5 抓取独立 redis_exporter（兼容已有部署）

已有独立 redis_exporter Pod 时，Alloy 可直接 scrape，无需立即迁移：

```alloy
prometheus.scrape "redis_exporter" {
  targets = [
    { __address__ = "redis-exporter.cache.svc.cluster.local:9121", service = "redis" },
  ]
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
}
```

---

## 6. 独立 redis_exporter 部署（备选）

不使用 Alloy 或需要独立部署时的参考。

### 6.1 Docker 启动

```bash
docker run -d --name redis-exporter \
  -p 9121:9121 \
  -e REDIS_ADDR="redis://redis-master:6379" \
  -e REDIS_PASSWORD="password" \
  oliver006/redis_exporter:latest
```

### 6.2 K8s Deployment + ServiceMonitor

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-exporter
  template:
    metadata:
      labels:
        app: redis-exporter
    spec:
      containers:
      - name: redis-exporter
        image: oliver006/redis_exporter:latest
        ports:
        - name: metrics
          containerPort: 9121
        env:
        - name: REDIS_ADDR
          value: redis://redis-master.cache.svc.cluster.local:6379
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: password
---
apiVersion: v1
kind: Service
metadata:
  name: redis-exporter
  namespace: monitoring
  labels:
    app: redis-exporter
spec:
  selector:
    app: redis-exporter
  ports:
  - name: metrics
    port: 9121
    targetPort: metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: redis-exporter
  endpoints:
  - port: metrics
    interval: 30s
```

### 6.3 部署方式对比

| 部署方式 | 采集配置 |
| --- | --- |
| 二进制 Redis | 宿主机起 redis_exporter，连接 `localhost:6379` |
| Docker Redis | redis_exporter 容器化，同 network 连接 Redis |
| K8s Redis | ServiceMonitor 自动发现 redis_exporter Service |
| Redis Sentinel | 配置 sentinel 地址和 master name |
| Redis Cluster | 设置 `is_cluster=true` 或 redis_exporter cluster 参数 |
| 托管 Redis | 使用只读账号连接托管实例，注意 VPC / 白名单 |

---

## 7. 告警规则

```yaml
groups:
- name: redis.rules
  rules:
  - alert: RedisDown
    expr: redis_up == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Redis 实例不可达"
      description: "实例 {{ $labels.instance }} 连续 1 分钟不可达，请检查 Redis 进程、网络和认证配置。"

  - alert: RedisMemoryHigh
    expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.8
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Redis 内存使用率过高"
      description: "实例 {{ $labels.instance }} 内存使用率超过 80%，可能触发 Key 淘汰。"

  - alert: RedisCacheHitRateLow
    expr: rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) < 0.9
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Redis 缓存命中率低于 90%"
      description: "实例 {{ $labels.instance }} 缓存命中率持续偏低，请检查热点 Key、TTL 和淘汰策略。"

  - alert: RedisRejectedConnections
    expr: increase(redis_rejected_connections_total[5m]) > 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Redis 出现连接拒绝"
      description: "实例 {{ $labels.instance }} 过去 5 分钟存在连接拒绝，可能已达到 maxclients。"

  - alert: RedisEvictedKeysHigh
    expr: increase(redis_evicted_keys_total[5m]) > 100
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Redis Key 淘汰数量异常"
      description: "实例 {{ $labels.instance }} 过去 5 分钟淘汰 Key 超过 100 个，请检查内存容量和淘汰策略。"

  - alert: RedisSlowLogGrowing
    expr: redis_slowlog_length > 0
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Redis 慢查询日志持续存在"
      description: "实例 {{ $labels.instance }} slowlog_length={{ $value }}，请检查慢命令和大 Key。"
```

---

## 8. Grafana Dashboard

推荐使用 Dashboard ID [763](https://grafana.com/grafana/dashboards/763)（Redis Dashboard for Prometheus Redis Exporter），数据源选 Prometheus，与 redis_exporter 和 Alloy 内置 exporter 指标兼容。

| Dashboard ID | 名称 | 适用场景 |
| --- | --- | --- |
| [763](https://grafana.com/grafana/dashboards/763) | Redis Dashboard for Prometheus Redis Exporter | Redis 基础运行状态、内存、命令、Keyspace |
| [11835](https://grafana.com/grafana/dashboards/11835) | Redis Exporter Quickstart and Dashboard | 快速接入 redis_exporter 指标 |

Grafana Cloud Redis 集成还提供 1 个预置 Dashboard 和 6 个预置告警规则，可在 Grafana Cloud 的 Connections → Redis 中一键安装。

---

## 9. KAgent 集成（Redis 运维 Agent）

官方 MCP 仓库（`modelcontextprotocol/servers`）目前**无官方 Redis MCP Server**。推荐通过以下两种方式将 Redis 运维能力引入 KAgent：

1. **绑定 KAgent 内置 PrometheusServer**：直接执行 PromQL 查询 Prometheus 中的 Redis 指标，无需额外组件。
2. **通过 KAgent Skills 注入 Redis 运维规范**：将 SOP、Runbook 写成 Markdown，让 Agent 回答时自动遵循团队规范。

### 9.1 使用内置 PrometheusServer 查询 Redis 指标

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: redis-ops-agent
  namespace: kagent
spec:
  description: "Redis 运维助手，可查询内存、命中率、连接数和慢查询状态"
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    stream: true
    systemMessage: |
      你是一个 Redis 运维助手。
      当工程师询问 Redis 状态时，使用 prometheus_query 工具查询指标。
      常用查询：
      - 实例可用性: redis_up
      - 内存使用率: redis_memory_used_bytes / redis_memory_max_bytes
      - 缓存命中率: rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
      - 慢查询长度: redis_slowlog_length
      回答用中文，数据以表格展示。
    tools:
    - type: ToolServer
      toolServer:
        apiGroup: kagent.dev
        kind: ToolServer
        name: prometheus
        toolNames: ["prometheus_query", "prometheus_query_range"]
```

### 9.2 KAgent Skills：注入 Redis 运维规范

KAgent 的 **Git-Based Skills** 机制可将 Markdown 运维 SOP 注入 Agent 上下文，让 Agent 的回答符合团队规范：

**Skill 文档示例（存放在 Git 仓库）：**

```markdown
<!-- skills/redis-ops.md -->
# Redis 运维规范

## 告警处理
- RedisDown 立即升级为 P1，先确认实例进程和网络连通性
- 内存使用率 > 80% 时，先检查 maxmemory-policy 和 evicted_keys，不要直接 flushdb
- 缓存命中率 < 90% 时，检查热点 Key、TTL 设置和业务缓存穿透风险
- slowlog_length 持续增长时，优先检查大 Key、阻塞命令和 Lua 脚本

## 禁止操作
- 生产环境禁止执行 FLUSHALL / FLUSHDB
- 禁止在高峰期执行 KEYS *，使用 SCAN 分批检查
- 删除大 Key 前需评估阻塞风险，优先使用 UNLINK
```

**在 Agent CRD 中引用 Skill：**

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: redis-ops-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    gitSkills:
    - repoURL: "https://gitlab.internal/ops/runbooks.git"
      branch: main
      paths:
      - "skills/redis-ops.md"
    tools:
    - type: ToolServer
      toolServer:
        kind: ToolServer
        name: prometheus
        toolNames: ["prometheus_query", "prometheus_query_range"]
```

---

## 10. 常见问题

### Grafana Alloy 能采集 Redis 指标吗？

**可以。** Alloy 内置 `prometheus.exporter.redis` 组件，无需单独部署 redis_exporter。它直接连接 Redis 实例采集 `redis_up`、连接数、内存、命令数、Keyspace 命中率、慢查询等指标，并通过 `prometheus.scrape` 转发到 Prometheus / Mimir / Grafana Cloud。

### Alloy 能完全替代 redis_exporter 吗？

在本项目场景下可以替代独立 redis_exporter 容器。`prometheus.exporter.redis` 的目标就是在 Alloy 内运行 redis_exporter 等价能力，减少组件数量。若已有 redis_exporter 存量部署，Alloy 也可先作为 scrape 网关抓取 `:9121/metrics`，后续再逐步迁移。

### Redis Cluster 怎么采集？

Alloy 的 `prometheus.exporter.redis` 支持 `is_cluster` 配置；独立 redis_exporter 则通过 cluster 参数开启集群模式。生产中建议为每个 Redis Cluster 单独声明 exporter 配置，并通过 `job`、`cluster`、`namespace` 等 Label 区分不同集群，避免多个集群指标混在一起。

### Redis 命中率应该怎么计算？

常用 PromQL：

```promql
rate(redis_keyspace_hits_total[5m])
/
(rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
```

命中率低于 90% 不一定都是 Redis 问题，也可能是业务缓存策略不合理、TTL 过短、热点 Key 缺失、缓存穿透或预热不足，需要结合业务请求量一起分析。

### 为什么不推荐用 Netdata 作为长期主监控？

Netdata 适合快速验证和秒级实时排查，但本项目已经采用 Prometheus / Grafana / Alloy 技术栈，长期监控、统一告警和跨组件关联分析应优先进入 Prometheus 指标体系。Netdata 可以作为临时诊断工具，而不是主采集链路。