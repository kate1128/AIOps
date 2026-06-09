# RabbitMQ 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. RabbitMQ 官方监控文档：[Monitoring](https://www.rabbitmq.com/docs/monitoring)
2. RabbitMQ Prometheus 插件：[Prometheus plugin](https://www.rabbitmq.com/docs/prometheus)
3. RabbitMQ Management 插件：[Management plugin](https://www.rabbitmq.com/docs/management)
4. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)
5. Grafana Dashboard：[RabbitMQ Overview #10991](https://grafana.com/grafana/dashboards/10991)

> RabbitMQ 3.8+ 内置 `rabbitmq_prometheus` 插件，优先使用内置 `/metrics` 端点，不再建议新部署独立 rabbitmq_exporter。

---

## 1. 结论摘要

RabbitMQ 3.8+ 通过 **rabbitmq_prometheus** 插件原生暴露 Prometheus 指标端点，默认监听 TCP `15692` 并提供 `/metrics`。在 Grafana Alloy 体系下，**不需要独立 RabbitMQ exporter**，Alloy 使用 `prometheus.scrape` 抓取 RabbitMQ 内置指标即可；如需日志可再通过 `loki.source.file` 或 `loki.source.docker` 采集 RabbitMQ 日志。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | RabbitMQ 内置 `rabbitmq_prometheus` 插件 |
| 暴露端口 | TCP `15692` `/metrics` |
| 采集方式 | RabbitMQ 节点原生暴露 Prometheus 指标，Alloy / Prometheus 直接 scrape |
| Alloy 内置替代 | 无专用 RabbitMQ exporter，使用 `prometheus.scrape` 抓取内置端点 |
| 旧版本兼容 | RabbitMQ < 3.8 可部署独立 rabbitmq_exporter |
| 推荐 Grafana Dashboard | ID 10991（RabbitMQ Overview）|

---

## 2. 产品概况（rabbitmq_prometheus）

| 项目 | 内容 |
| --- | --- |
| 产品名称 | rabbitmq_prometheus |
| 维护方 | RabbitMQ 官方 |
| 部署形态 | RabbitMQ 内置插件 |
| 默认端口 | `15692` |
| 数据来源 | RabbitMQ 节点、队列、连接、Channel、Exchange、Erlang VM 指标 |
| 支持版本 | RabbitMQ 3.8+ |
| 旧版方案 | RabbitMQ < 3.8 使用独立 rabbitmq_exporter |

启用插件：

```bash
rabbitmq-plugins enable rabbitmq_prometheus
```

RabbitMQ 配置示例：

```ini
# rabbitmq.conf
prometheus.tcp.port = 15692
prometheus.return_per_object_metrics = false
```

> `prometheus.return_per_object_metrics=true` 会暴露队列、Exchange、Channel 等对象级指标，排障更细但基数更高。生产建议默认关闭，按需临时开启或独立配置低频采集。

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `rabbitmq_up` | RabbitMQ 节点是否在线 | `== 0` 立即告警 |
| `rabbitmq_queue_messages_ready` | 队列待消费消息数 | > 10000 告警，按业务调整 |
| `rabbitmq_queue_messages_unacked` | 已投递但未确认消息数 | 持续增长说明消费者处理慢或异常 |
| `rabbitmq_queue_messages` | 队列总消息数 | Ready + Unacked 总积压 |
| `rabbitmq_connections` | 当前连接数 | 骤降说明客户端大面积断开 |
| `rabbitmq_channels` | 当前 Channel 数 | 持续上涨需排查连接泄漏 |
| `rabbitmq_consumers` | 当前消费者数 | 队列消费者为 0 告警 |
| `rabbitmq_process_resident_memory_bytes` | Erlang VM 进程常驻内存 | > 80% 内存水位告警 |
| `rabbitmq_disk_space_available_bytes` | 节点剩余磁盘空间 | < 5GB 或低于磁盘水位告警 |
| `rabbitmq_channel_messages_published_total` | 消息发布总量 | 用于计算生产速率 |
| `rabbitmq_channel_messages_delivered_total` | 消息投递总量 | 用于计算消费速率 |
| `rabbitmq_channel_messages_unroutable_returned_total` | 无法路由且被退回消息 | > 0 说明 Exchange / Routing Key 配置异常 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| **rabbitmq_prometheus（内置）** | RabbitMQ 插件 | 节点 / 队列 / 连接 / Channel / Erlang VM | 无 | **RabbitMQ 3.8+ 标准方案** |
| **Grafana Alloy** | `prometheus.scrape` 抓取 15692 | 同内置插件 | `loki.source.file` / `loki.source.docker` | **本项目首选，已部署 Alloy** |
| rabbitmq_exporter | 独立容器 | 通过 Management API 抓取 | 无 | RabbitMQ 旧版本兼容 |
| Netdata | 一键安装 | 内置 RabbitMQ collector | 内置日志查看 | 快速验证、临时诊断 |

> Grafana 官方回答与本调研一致：Alloy 不需要专用 RabbitMQ exporter，通过 `prometheus.scrape` 抓取 RabbitMQ 内置 Prometheus 端点即可；日志由 Loki 组件单独采集。

---

## 5. Alloy 集成方案（推荐）

Alloy 通过 `prometheus.scrape` 抓取 RabbitMQ `:15692/metrics`，并通过 `prometheus.remote_write` 转发到 Prometheus / Mimir / Grafana Cloud。RabbitMQ 指标采集链路不需要额外 exporter。

### 5.1 方案一：单节点采集

```alloy
// Graph 视图：
// RabbitMQ :15692/metrics
//         ↓
// prometheus.scrape.rabbitmq
//         ↓
// prometheus.remote_write.central

prometheus.scrape "rabbitmq" {
  targets = [
    { __address__ = "rabbitmq.mq.svc.cluster.local:15692", service = "rabbitmq" },
  ]
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
  job_name        = "integrations/rabbitmq"
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

### 5.2 方案二：多节点集群采集（避免 instance 冲突）

多节点 RabbitMQ 集群建议每个节点单独创建 `discovery.relabel`，显式设置 `instance`，再用 `concat()` 合并：

```alloy
discovery.relabel "rabbitmq_node1" {
  targets = [{ __address__ = "rabbitmq-node1.mq.svc.cluster.local:15692" }]

  rule {
    target_label = "instance"
    replacement  = "rabbitmq-node1"
  }
}

discovery.relabel "rabbitmq_node2" {
  targets = [{ __address__ = "rabbitmq-node2.mq.svc.cluster.local:15692" }]

  rule {
    target_label = "instance"
    replacement  = "rabbitmq-node2"
  }
}

prometheus.scrape "rabbitmq" {
  targets = concat(
    discovery.relabel.rabbitmq_node1.output,
    discovery.relabel.rabbitmq_node2.output,
  )
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
  job_name        = "integrations/rabbitmq"
}
```

### 5.3 方案三：Kubernetes ServiceMonitor 兼容配置

如果仍使用 Prometheus Operator，可通过 ServiceMonitor 抓取 RabbitMQ Service：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rabbitmq
  namespace: observability
spec:
  selector:
    matchLabels:
      app: rabbitmq
  endpoints:
  - port: prometheus
    interval: 30s
    path: /metrics
```

### 5.4 方案四：采集 RabbitMQ 容器日志

RabbitMQ 指标与日志分开采集。Docker 部署可使用 `loki.source.docker`：

```alloy
loki.source.docker "rabbitmq" {
  host       = "unix:///var/run/docker.sock"
  targets    = [{ container = "rabbitmq" }]
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint { url = "http://loki.observability.svc:3100/loki/api/v1/push" }
}
```

Kubernetes 部署通常由 Alloy 的 Pod 日志采集链路统一采集，可通过 Label 过滤：

```logql
{app="rabbitmq"}
```

### 5.5 旧版本兼容：抓取独立 rabbitmq_exporter

RabbitMQ < 3.8 或未启用内置插件时，可先部署独立 rabbitmq_exporter，再由 Alloy scrape：

```alloy
prometheus.scrape "rabbitmq_exporter" {
  targets = [
    { __address__ = "rabbitmq-exporter.mq.svc.cluster.local:9419", service = "rabbitmq" },
  ]
  scrape_interval = "30s"
  forward_to      = [prometheus.remote_write.central.receiver]
  job_name        = "rabbitmq-exporter"
}
```

---

## 6. 独立 rabbitmq_exporter 部署（备选）

适用于 RabbitMQ 3.8 以前版本，或无法启用 `rabbitmq_prometheus` 插件的存量环境。

### 6.1 Docker 启动

```bash
docker run -d --name rabbitmq-exporter \
  -p 9419:9419 \
  -e RABBIT_URL="http://rabbitmq:15672" \
  -e RABBIT_USER="monitoring" \
  -e RABBIT_PASSWORD="password" \
  kbudde/rabbitmq-exporter:latest
```

### 6.2 K8s Deployment + ServiceMonitor

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq-exporter
  template:
    metadata:
      labels:
        app: rabbitmq-exporter
    spec:
      containers:
      - name: rabbitmq-exporter
        image: kbudde/rabbitmq-exporter:latest
        ports:
        - name: metrics
          containerPort: 9419
        env:
        - name: RABBIT_URL
          value: http://rabbitmq.mq.svc.cluster.local:15672
        - name: RABBIT_USER
          value: monitoring
        - name: RABBIT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: rabbitmq-monitoring-secret
              key: password
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq-exporter
  namespace: monitoring
  labels:
    app: rabbitmq-exporter
spec:
  selector:
    app: rabbitmq-exporter
  ports:
  - name: metrics
    port: 9419
    targetPort: metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rabbitmq-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: rabbitmq-exporter
  endpoints:
  - port: metrics
    interval: 30s
```

### 6.3 部署方式对比

| 部署方式 | 采集配置 |
| --- | --- |
| 二进制 RabbitMQ | 启用 `rabbitmq_prometheus`，抓取 `localhost:15692/metrics` |
| Docker RabbitMQ | 启用插件并暴露 `15692` 端口 |
| K8s RabbitMQ | RabbitMQ Operator / Helm 暴露 prometheus Service |
| RabbitMQ < 3.8 | 独立 rabbitmq_exporter 通过 Management API 抓取 |
| 托管 RabbitMQ | 优先使用云厂商暴露的 Prometheus 指标或 Management API |

---

## 7. 告警规则

```yaml
groups:
- name: rabbitmq.rules
  rules:
  - alert: RabbitMQDown
    expr: rabbitmq_up == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "RabbitMQ 节点不可达"
      description: "节点 {{ $labels.instance }} 连续 1 分钟不可达，请检查 RabbitMQ 进程、网络和 Prometheus 插件。"

  - alert: RabbitMQQueueBacklogHigh
    expr: rabbitmq_queue_messages_ready > 10000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "RabbitMQ 队列积压过高"
      description: "队列 {{ $labels.queue }} 待消费消息数 {{ $value }}，请检查消费者处理能力。"

  - alert: RabbitMQUnackedMessagesHigh
    expr: rabbitmq_queue_messages_unacked > 1000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "RabbitMQ 未确认消息过高"
      description: "队列 {{ $labels.queue }} unacked={{ $value }}，可能存在消费者处理慢或 ack 异常。"

  - alert: RabbitMQNoConsumers
    expr: rabbitmq_consumers == 0 and rabbitmq_queue_messages_ready > 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "RabbitMQ 队列有积压但无消费者"
      description: "队列 {{ $labels.queue }} 存在积压但消费者数为 0，请检查消费服务。"

  - alert: RabbitMQMemoryHigh
    expr: rabbitmq_process_resident_memory_bytes / rabbitmq_resident_memory_limit_bytes > 0.8
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "RabbitMQ 节点内存使用率过高"
      description: "节点 {{ $labels.instance }} 内存使用率超过 80%，可能触发内存水位保护。"

  - alert: RabbitMQDiskFreeLow
    expr: rabbitmq_disk_space_available_bytes < 5 * 1024 * 1024 * 1024
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "RabbitMQ 节点磁盘空间不足"
      description: "节点 {{ $labels.instance }} 可用磁盘空间低于 5GB，可能触发磁盘水位保护。"
```

---

## 8. Grafana Dashboard

推荐使用 Dashboard ID [10991](https://grafana.com/grafana/dashboards/10991)（RabbitMQ Overview），数据源选 Prometheus，与 RabbitMQ 内置 Prometheus 插件指标兼容。

| Dashboard | 适用场景 |
| --- | --- |
| RabbitMQ Overview | 集群整体状态、节点、连接、队列积压 |
| Erlang Memory Allocators | Erlang VM 内存分配详情 |
| RabbitMQ Per Object | 按队列 / Exchange / Channel 维度调试 |

Grafana Cloud RabbitMQ 集成提供 2 个预置 Dashboard，并包含 RabbitMQ Per Object 排障视图。

---

## 9. KAgent 集成（RabbitMQ 运维 Agent）

官方 MCP 仓库（`modelcontextprotocol/servers`）目前**无官方 RabbitMQ MCP Server**。推荐通过以下两种方式将 RabbitMQ 运维能力引入 KAgent：

1. **绑定 KAgent 内置 PrometheusServer**：直接执行 PromQL 查询 RabbitMQ 指标，无需额外组件。
2. **通过 KAgent Skills 注入 RabbitMQ 运维规范**：将 SOP、Runbook 写成 Markdown，让 Agent 回答时自动遵循团队规范。

### 9.1 使用内置 PrometheusServer 查询 RabbitMQ 指标

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: rabbitmq-ops-agent
  namespace: kagent
spec:
  description: "RabbitMQ 运维助手，可查询队列积压、消费者、连接和节点资源状态"
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    stream: true
    systemMessage: |
      你是一个 RabbitMQ 运维助手。
      当工程师询问 RabbitMQ 状态时，使用 prometheus_query 工具查询指标。
      常用查询：
      - 节点可用性: rabbitmq_up
      - 队列积压: rabbitmq_queue_messages_ready
      - 未确认消息: rabbitmq_queue_messages_unacked
      - 消费者数量: rabbitmq_consumers
      - 连接数量: rabbitmq_connections
      回答用中文，数据以表格展示。
    tools:
    - type: ToolServer
      toolServer:
        apiGroup: kagent.dev
        kind: ToolServer
        name: prometheus
        toolNames: ["prometheus_query", "prometheus_query_range"]
```

### 9.2 KAgent Skills：注入 RabbitMQ 运维规范

KAgent 的 **Git-Based Skills** 机制可将 Markdown 运维 SOP 注入 Agent 上下文，让 Agent 的回答符合团队规范：

**Skill 文档示例（存放在 Git 仓库）：**

```markdown
<!-- skills/rabbitmq-ops.md -->
# RabbitMQ 运维规范

## 告警处理
- 队列 ready 消息 > 10000 时，先确认消费者实例是否存活，再扩容消费者
- unacked 持续增长时，检查消费者 ack 逻辑、处理耗时和异常重试
- 队列有积压且 consumers=0 时，升级为 P1，通知业务负责人
- 内存或磁盘水位触发时，不要盲目重启节点，先扩容磁盘或清理积压

## 禁止操作
- 生产环境禁止直接 purge 队列，必须经过业务确认
- 禁止在未确认业务影响前删除 Exchange / Queue / Binding
- 大批量重放消息前需评估下游承载能力
```

**在 Agent CRD 中引用 Skill：**

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: rabbitmq-ops-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    gitSkills:
    - repoURL: "https://gitlab.internal/ops/runbooks.git"
      branch: main
      paths:
      - "skills/rabbitmq-ops.md"
    tools:
    - type: ToolServer
      toolServer:
        kind: ToolServer
        name: prometheus
        toolNames: ["prometheus_query", "prometheus_query_range"]
```

---

## 10. 常见问题

### Grafana Alloy 能采集 RabbitMQ 指标吗？

**可以。** Alloy 支持通过 `prometheus.scrape` 采集 RabbitMQ 内置 Prometheus 指标端点。RabbitMQ 3.8+ 启用 `rabbitmq_prometheus` 插件后，默认在 `:15692/metrics` 暴露指标，Alloy 直接抓取即可。

### Alloy 有内置 RabbitMQ exporter 吗？

没有。与 Redis / Kafka 不同，Alloy 没有专门的 `prometheus.exporter.rabbitmq` 组件。RabbitMQ 官方已经内置 Prometheus 插件，因此 Alloy 的职责是 scrape 和转发，不需要再内置 exporter。

### RabbitMQ 旧版本怎么采集？

RabbitMQ 3.8 以前版本没有内置 Prometheus 插件，建议部署独立 rabbitmq_exporter，通过 Management API 抓取指标，再由 Prometheus 或 Alloy scrape `:9419/metrics`。如果可以升级，优先升级到 3.8+ 并启用内置插件。

### 队列积压和 unacked 有什么区别？

`rabbitmq_queue_messages_ready` 表示还没投递给消费者的待消费消息；`rabbitmq_queue_messages_unacked` 表示已经投递给消费者但尚未 ack 的消息。Ready 高通常说明消费者不足或处理速度慢；Unacked 高通常说明消费者处理耗时长、ack 逻辑异常或下游阻塞。

### 为什么不建议长期打开 per-object metrics？

per-object metrics 会按队列、Exchange、Channel 等对象维度暴露指标，排障时很有价值，但对象数量大时会显著增加指标基数和 Prometheus 存储压力。生产建议默认关闭，或仅对关键集群低频采集。

### RabbitMQ 日志怎么采集？

RabbitMQ 指标通过 `rabbitmq_prometheus` + `prometheus.scrape` 采集，日志通过 Loki 链路采集。Docker 环境可用 `loki.source.docker`，Kubernetes 环境可由 Alloy 的 Pod 日志采集规则统一收集，再用 `{app="rabbitmq"}` 查询。