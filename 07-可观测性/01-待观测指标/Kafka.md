# Kafka 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. JMX Exporter：[prometheus/jmx_exporter](https://github.com/prometheus/jmx_exporter)
2. kafka-exporter：[danielqsj/kafka_exporter](https://github.com/danielqsj/kafka_exporter)（Grafana fork：[grafana/kafka_exporter](https://github.com/grafana/kafka_exporter)）
3. Alloy 内置集成：[prometheus.exporter.kafka](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.kafka/)
4. Grafana Dashboard：[Kafka Overview #7589](https://grafana.com/grafana/dashboards/7589)
5. Strimzi 内置指标：[Strimzi Kafka Metrics 文档](https://strimzi.io/docs/operators/latest/deploying.html#assembly-metrics-setup-str)

> Star 数会持续变化。正式对外汇报前建议以 GitHub 实时数据复核。

---

## 1. 结论摘要

Kafka 是 Java 进程，原生通过 JMX 暴露运行时指标。Prometheus 采集需通过 **JMX Exporter**（Broker/JVM 指标）和 **kafka-exporter**（Consumer Lag）两个工具协同完成。在 Grafana Alloy 体系下，**kafka-exporter 功能已内置**（`prometheus.exporter.kafka`），无需单独部署；JMX Exporter 仍需以 `-javaagent` 方式嵌入 Kafka 进程（这是获取 JVM 指标的唯一途径）。

| 关键信息 | 值 |
| --- | --- |
| Broker/JVM 指标采集 | JMX Exporter（`-javaagent`，嵌入 Kafka 进程）|
| Consumer Lag 采集 | kafka-exporter 或 Alloy 内置 `prometheus.exporter.kafka` |
| JMX Exporter 暴露端口 | TCP `9999` `/metrics`（可自定义）|
| kafka-exporter 暴露端口 | TCP `9308` `/metrics` |
| Alloy 内置替代范围 | 替代独立 kafka-exporter，**不能替代** JMX Exporter |
| 生产推荐组合 | JMX Exporter（JVM 指标）+ Alloy 内置 Kafka Exporter（Lag/Topic 指标）|
| 推荐 Grafana Dashboard | ID 7589（Kafka Overview）|

---

## 2. 产品概况

### JMX Exporter

| 项目 | 内容 |
| --- | --- |
| 产品名称 | JMX Exporter |
| 维护方 | prometheus 官方 |
| 开源协议 | Apache-2.0 |
| 部署形态 | `-javaagent` 嵌入 JVM 进程（也支持独立 HTTP 模式）|
| 数据来源 | Kafka JMX MBeans（Broker 性能、副本状态、JVM 堆内存、GC 等）|
| 适用版本 | 所有 Kafka 版本（2.x ~ 4.x）|

### kafka-exporter

| 项目 | 内容 |
| --- | --- |
| 产品名称 | kafka_exporter |
| 维护方 | danielqsj（社区）/ Grafana fork |
| 开源协议 | Apache-2.0 |
| 部署形态 | 独立容器 / Alloy 内置 `prometheus.exporter.kafka` |
| 数据来源 | Kafka Admin API（Consumer Group Offset、Topic Partition 偏移）|
| 核心用途 | Consumer Lag 监控、Topic 级别偏移追踪 |

---

## 3. 核心指标

### Broker 层（JMX Exporter）

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `kafka_server_brokertopicmetrics_messagesin_total` | 消息写入速率 | — |
| `kafka_server_brokertopicmetrics_bytesin_total` | 写入流量速率 | — |
| `kafka_server_brokertopicmetrics_bytesout_total` | 读出流量速率 | — |
| `kafka_controller_kafkacontroller_offlinepartitionscount` | 离线分区数 | > 0 立即告警 |
| `kafka_controller_kafkacontroller_underreplicatedpartitionscount` | 副本不足分区数 | > 0 告警 |
| `kafka_server_replicamanager_underreplicatedpartitions` | 未同步副本数 | > 0 告警 |
| `kafka_network_requestmetrics_totaltimems` | 请求处理延迟（ms）| p99 > 500ms 告警 |

### JVM 层（JMX Exporter）

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `jvm_memory_bytes_used{area="heap"}` | JVM 堆内存使用量 | > 85% 堆上限告警 |
| `jvm_gc_collection_seconds_sum` | GC 累计时间 | Full GC 频率 > 1次/分钟告警 |
| `jvm_threads_current` | 当前线程数 | 持续增长说明线程泄漏 |

### Consumer 层（kafka-exporter）

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `kafka_consumergroup_lag` | 消费者 Lag（条数）| > 10000 告警，视业务调整 |
| `kafka_consumergroup_current_offset` | 当前消费偏移 | — |
| `kafka_topic_partition_current_offset` | 分区最新偏移 | — |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | Broker/JVM 指标 | Consumer Lag | 适用场景 |
| --- | --- | --- | --- | --- |
| JMX Exporter | `-javaagent` 嵌入 Kafka 进程 | ✅ 全量 | ❌ | Broker 级别监控必选 |
| kafka-exporter | 独立容器 | ❌ | ✅ | 只关注消费延迟 |
| JMX + kafka-exporter | 组合部署 | ✅ | ✅ | 非 Alloy 体系的生产方案 |
| **Alloy 内置** | `prometheus.exporter.kafka` | ❌（需配合 JMX）| ✅ | **已用 Alloy 体系，替代独立 kafka-exporter** |
| Strimzi Operator | K8s CRD 自动配置 | ✅ | ✅ | K8s 上用 Strimzi 部署的 Kafka |

> Alloy 内置的 `prometheus.exporter.kafka` 基于 [grafana/kafka_exporter](https://github.com/grafana/kafka_exporter) 实现，覆盖 Consumer Lag 和 Topic 级别指标。它**无法替代 JMX Exporter**——JVM 堆内存、GC、线程等指标必须通过 `-javaagent` 方式获取。

---

## 5. Alloy 集成方案（推荐）

Alloy 内置 `prometheus.exporter.kafka`，无需单独部署 kafka_exporter 即可采集 Consumer Lag、Topic、Partition 偏移等指标。但 Kafka Broker / JVM 指标仍需通过 JMX Exporter 转成 Prometheus 格式，再由 Alloy 使用 `prometheus.scrape` 抓取。

### 5.1 方案一：Alloy 内置 Kafka Exporter（Consumer Lag + Topic 指标）

```alloy
// Graph 视图：
// prometheus.exporter.kafka.prod
//         ↓
// prometheus.scrape.kafka_exporter
//         ↓
// prometheus.remote_write.central

prometheus.exporter.kafka "prod" {
  kafka_uris         = ["kafka-1:9092", "kafka-2:9092", "kafka-3:9092"]
  kafka_cluster_name = "smartvision-prod"
  topics_filter_regex = ".*"
  groups_filter_regex = ".*"
}

prometheus.scrape "kafka_exporter" {
  targets    = prometheus.exporter.kafka.prod.targets
  forward_to = [prometheus.remote_write.central.receiver]
  job_name   = "integrations/kafka_exporter"
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

### 5.2 方案二：Grafana Cloud 集成配置

Grafana 官方 Kafka 集成推荐通过 `discovery.relabel` 补充 `job`、`kafka_cluster`、`instance` 标签，避免多集群混淆：

```alloy
prometheus.exporter.kafka "integrations_kafka_exporter" {
  kafka_uris = ["kafka-node1:9092"]
}

discovery.relabel "integrations_kafka_exporter" {
  targets = prometheus.exporter.kafka.integrations_kafka_exporter.targets

  rule {
    target_label = "job"
    replacement  = "integrations/kafka"
  }

  rule {
    target_label = "kafka_cluster"
    replacement  = "smartvision-prod"
  }

  rule {
    target_label = "instance"
    replacement  = "kafka-node1"
  }
}

prometheus.scrape "integrations_kafka_exporter" {
  targets    = discovery.relabel.integrations_kafka_exporter.output
  forward_to = [prometheus.remote_write.metrics_service.receiver]
  job_name   = "integrations/kafka_exporter"
}
```

### 5.3 方案三：多节点集群配置（避免 instance 冲突）

监控多节点 Kafka 集群时，官方建议为每个节点单独创建 `prometheus.exporter.kafka` 和 `discovery.relabel`，再用 `concat()` 合并 targets：

```alloy
prometheus.exporter.kafka "node1" {
  kafka_uris = ["kafka-node1:9092"]
}

discovery.relabel "node1" {
  targets = prometheus.exporter.kafka.node1.targets

  rule {
    target_label = "kafka_cluster"
    replacement  = "smartvision-prod"
  }

  rule {
    target_label = "instance"
    replacement  = "kafka-node1"
  }
}

prometheus.exporter.kafka "node2" {
  kafka_uris = ["kafka-node2:9092"]
}

discovery.relabel "node2" {
  targets = prometheus.exporter.kafka.node2.targets

  rule {
    target_label = "kafka_cluster"
    replacement  = "smartvision-prod"
  }

  rule {
    target_label = "instance"
    replacement  = "kafka-node2"
  }
}

prometheus.scrape "kafka_cluster" {
  targets = concat(
    discovery.relabel.node1.output,
    discovery.relabel.node2.output,
  )
  forward_to = [prometheus.remote_write.central.receiver]
  job_name   = "integrations/kafka"
}
```

### 5.4 方案四：Kubernetes 自动发现 Kafka Pod

如果 Kafka 运行在 Kubernetes 上，可使用 `discovery.kubernetes` 自动发现 Broker Pod，再通过 `discovery.relabel` 过滤端口和补充标签：

```alloy
discovery.kubernetes "kafka_broker" {
  role = "pod"
  selectors {
    role  = "pod"
    label = "app=kafka"
  }
}

discovery.relabel "kafka_broker" {
  targets = discovery.kubernetes.kafka_broker.targets

  rule {
    source_labels = ["__meta_kubernetes_pod_container_port_number"]
    regex         = "9999"
    action        = "keep"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "instance"
  }

  rule {
    replacement  = "smartvision-prod"
    target_label = "kafka_cluster"
  }
}

prometheus.scrape "kafka_broker" {
  targets      = discovery.relabel.kafka_broker.output
  job_name     = "integrations/kafka"
  honor_labels = true
  forward_to   = [prometheus.remote_write.central.receiver]
}
```

### 5.5 方案五：抓取 JMX Exporter（Broker + JVM 指标）

JMX Exporter 需在 Kafka 启动参数中以 `-javaagent` 嵌入：

```bash
# Kafka 启动参数（二进制或 Docker 环境）
export KAFKA_OPTS="-javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent.jar=9999:/opt/jmx_exporter/kafka-broker.yml"
```

Alloy 抓取 JMX Exporter 暴露的 `/metrics`：

```alloy
discovery.relabel "kafka_jmx" {
  targets = [{ __address__ = "kafka-node1:9999" }]

  rule {
    target_label = "instance"
    replacement  = "kafka-node1"
  }

  rule {
    target_label = "kafka_cluster"
    replacement  = "smartvision-prod"
  }
}

prometheus.scrape "kafka_jmx" {
  targets    = discovery.relabel.kafka_jmx.output
  forward_to = [prometheus.remote_write.central.receiver]
  job_name   = "integrations/kafka"
}
```

### 5.6 方案六：组合方案（生产推荐）

生产环境建议同时启用两条链路：

| 链路 | 采集器 | 负责指标 |
| --- | --- | --- |
| Kafka 业务指标 | `prometheus.exporter.kafka` | Consumer Lag、Topic / Partition Offset |
| Broker / JVM 指标 | JMX Exporter + `prometheus.scrape` | Broker 状态、JVM 内存、GC、线程、请求延迟 |

### 5.7 常用参数

| 参数 | 类型 | 说明 | 默认值 | 必填 |
| --- | --- | --- | --- | --- |
| `kafka_uris` | array(string) | Kafka 节点地址（`host:port`）| — | 是 |
| `kafka_version` | string | Kafka Broker 版本 | `2.0.0` | 否 |
| `instance` | string | 指标的 `instance` 标签 | 第一个 URI 的 `hostname:port` | 否 |
| `kafka_cluster_name` | string | Kafka 集群名称 | — | 否 |
| `use_sasl` | bool | 是否使用 SASL/PLAIN 连接 | `false` | 否 |
| `use_tls` | bool | 是否使用 TLS 连接 | `false` | 否 |
| `topics_filter_regex` | string | 监控的 Topic 过滤正则 | `.*` | 否 |
| `groups_filter_regex` | string | 监控的消费组过滤正则 | `.*` | 否 |
| `allow_concurrency` | bool | 是否并发抓取（大集群可按压测结果调整）| `true` | 否 |

---

## 6. 独立 kafka-exporter 部署（非 Alloy 体系）

适用于未使用 Grafana Alloy 但需要采集 Consumer Lag 的场景：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-exporter
  template:
    metadata:
      labels:
        app: kafka-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9308"
    spec:
      containers:
      - name: kafka-exporter
        image: danielqsj/kafka-exporter:latest
        args:
        - --kafka.server=kafka-1:9092
        - --kafka.server=kafka-2:9092
        - --kafka.server=kafka-3:9092
        ports:
        - containerPort: 9308
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: observability
spec:
  selector:
    app: kafka-exporter
  ports:
  - port: 9308
    targetPort: 9308
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-exporter
  namespace: observability
spec:
  selector:
    matchLabels:
      app: kafka-exporter
  endpoints:
  - port: http
    interval: 30s
```

| 方案 | 优点 | 缺点 |
| --- | --- | --- |
| Alloy 内置 | 无额外容器，统一 Alloy 配置 | 需要已部署 Alloy |
| 独立 kafka-exporter | 无需 Alloy，简单独立 | 多一个容器组件需维护 |

---

## 7. 告警规则

```yaml
groups:
- name: kafka.rules
  rules:
  - alert: KafkaOfflinePartitions
    expr: kafka_controller_kafkacontroller_offlinepartitionscount > 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Kafka 存在离线分区"
      description: "当前离线分区数：{{ $value }}，可能有 Broker 宕机，立即检查集群状态。"

  - alert: KafkaUnderReplicatedPartitions
    expr: kafka_server_replicamanager_underreplicatedpartitions > 0
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Kafka 存在未同步副本"
      description: "{{ $value }} 个副本未同步，请检查 Follower Broker 状态。"

  - alert: KafkaConsumerLagHigh
    expr: kafka_consumergroup_lag > 10000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "消费者组 Lag 过高"
      description: "消费者组 {{ $labels.consumergroup }} Topic {{ $labels.topic }} Lag={{ $value }}，消费速率落后于生产速率。"

  - alert: KafkaConsumerGroupNotConsuming
    expr: kafka_consumergroup_lag > 0 and delta(kafka_consumergroup_current_offset[5m]) == 0
    for: 10m
    labels:
      severity: critical
    annotations:
      summary: "消费者组停止消费"
      description: "消费者组 {{ $labels.consumergroup }} 在过去 10 分钟内没有消费进展，Lag={{ $value }}。"

  - alert: KafkaBrokerJvmHeapHigh
    expr: jvm_memory_bytes_used{area="heap"} / jvm_memory_bytes_max{area="heap"} > 0.85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Kafka Broker JVM 堆内存使用率过高"
      description: "Broker {{ $labels.instance }} 堆内存使用率 {{ $value | humanizePercentage }}，可能触发 Full GC。"
```

---

## 8. Grafana Dashboard

推荐使用 Dashboard ID [7589](https://grafana.com/grafana/dashboards/7589)（Kafka Overview），数据源选 Prometheus，与 kafka-exporter 和 Alloy 内置 exporter 指标兼容。

| Dashboard ID | 名称 | 适用场景 |
| --- | --- | --- |
| [7589](https://grafana.com/grafana/dashboards/7589) | Kafka Overview | Consumer Lag、Topic 偏移（kafka-exporter 指标）|
| [721](https://grafana.com/grafana/dashboards/721) | Kafka Exporter Overview | 详细 Consumer Group 视图 |

---

## 9. KAgent 集成（Kafka 运维 Agent）

官方 MCP 仓库（`modelcontextprotocol/servers`）目前**无官方 Kafka MCP Server**。推荐通过以下两种方式将 Kafka 运维能力引入 KAgent：

1. **绑定 KAgent 内置 PrometheusServer**：直接执行 PromQL 查询 Prometheus 中的 Kafka 指标，无需额外组件。
2. **通过 KAgent Skills 注入 Kafka 运维规范**：将 SOP、Runbook 写成 Markdown，让 Agent 回答时自动遵循团队规范。

### 9.1 使用内置 PrometheusServer 查询 Kafka 指标

KAgent 内置 `PrometheusServer` ToolServer，无需额外部署，可直接执行 PromQL：

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: kafka-ops-agent
  namespace: kagent
spec:
  description: "Kafka 运维助手，可查询消费者 Lag 和 Broker 状态"
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    stream: true
    systemMessage: |
      你是一个 Kafka 运维助手。
      当工程师询问 Kafka 状态时，使用 prometheus_query 工具查询指标。
      常用查询：
      - Consumer Lag: kafka_consumergroup_lag{consumergroup="xxx"}
      - 离线分区: kafka_controller_kafkacontroller_offlinepartitionscount
      - 副本不足: kafka_server_replicamanager_underreplicatedpartitions
      回答用中文，数据以表格展示。
    tools:
    - type: ToolServer
      toolServer:
        apiGroup: kagent.dev
        kind: ToolServer
        name: prometheus
        toolNames: ["prometheus_query", "prometheus_query_range"]
```

### 9.2 KAgent Skills：注入 Kafka 运维规范

KAgent 的 **Git-Based Skills** 机制可将 Markdown 运维 SOP 注入 Agent 上下文，让 Agent 的回答符合团队规范：

**Skill 文档示例（存放在 Git 仓库）：**

```markdown
<!-- skills/kafka-ops.md -->
# Kafka 运维规范

## 告警处理
- Consumer Lag > 10000 时，先确认消费者进程是否存活，再检查 Kafka Broker 状态
- 离线分区 > 0 时，立即检查对应 Broker 日志，不要直接重启集群
- 副本不足时，检查 ISR 列表，等待自动恢复，超过 30min 未恢复升级为 P1

## 日常操作
- 查询 Consumer Lag：kafka-consumer-groups.sh --bootstrap-server kafka:9092 --describe --all-groups
- 查看 Topic 详情：kafka-topics.sh --bootstrap-server kafka:9092 --describe --topic xxx
- 禁止在生产环境直接删除 Topic，需走变更审批流程
```

**在 Agent CRD 中引用 Skill：**

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: kafka-ops-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    modelConfig: bailian-provider-config
    gitSkills:
    - repoURL: "https://gitlab.internal/ops/runbooks.git"
      branch: main
      paths:
      - "skills/kafka-ops.md"
    tools:
    - type: ToolServer
      toolServer:
        kind: ToolServer
        name: prometheus
        toolNames: ["prometheus_query", "prometheus_query_range"]
```

---

## 10. 常见问题

### Alloy 能完全替代 kafka-exporter 吗？

**能替代独立 kafka-exporter 容器，但无法替代 JMX Exporter。** Alloy 内置的 `prometheus.exporter.kafka` 与 kafka-exporter 功能等价（Consumer Lag、Topic 偏移指标），在 Alloy 配置中声明即可，无需额外容器。但 JVM 堆内存、GC、线程等 Broker 内部 JMX 指标必须通过 `-javaagent` 方式获取，Alloy 无法替代这部分。

### 为什么 Consumer Lag 是 Kafka 最关键的告警指标？

Lag 体现了消费者跟不上生产者的速度。Lag 持续增长意味着数据积压，轻则延迟处理，重则消费者崩溃后触发大量重放（replay storm），影响下游系统。注意：Lag=0 不代表消费正常（消费者可能已停止，偏移未提交），需结合 `delta(current_offset[5m])` 检查消费进度是否实际推进。

### Strimzi 部署的 Kafka 如何采集指标？

Strimzi Operator 支持通过 `Kafka` CRD 的 `metricsConfig` 字段直接配置 JMX Exporter 规则，自动在每个 Broker Pod 内嵌入 JMX Exporter 并创建对应的 ServiceMonitor，**无需手动配置 `-javaagent`**。详见 [Strimzi Kafka Metrics 文档](https://strimzi.io/docs/operators/latest/deploying.html#assembly-metrics-setup-str)。

### Grafana Alloy 能采集 Kafka 指标吗？

**可以。** Alloy 内置 `prometheus.exporter.kafka` 组件，无需单独部署 kafka_exporter。它主要采集 Consumer Lag、Topic / Partition Offset 等 Kafka 业务指标。Broker、JVM、GC、线程等内部指标仍需通过 JMX Exporter 暴露后，由 Alloy 使用 `prometheus.scrape` 抓取。

### JMX Exporter 是什么？

JMX Exporter 不是 Kafka 专用采集器，而是通用 Java 应用指标转换工具。Kafka、ZooKeeper、Kafka Connect、Schema Registry、ksqlDB 等 JVM 应用都会通过 JMX 暴露内部指标，但 Prometheus 无法直接读取 JMX 格式，因此需要 JMX Exporter 转成 Prometheus `/metrics`。

```text
Java 应用（JMX 格式） -> JMX Exporter -> Prometheus 格式 -> Alloy 抓取 -> Grafana
```

### JMX Exporter 和 kafka_exporter 有什么区别？

| 维度 | JMX Exporter | kafka_exporter / `prometheus.exporter.kafka` |
| --- | --- | --- |
| 适用范围 | 所有 Java 应用（Kafka、ZooKeeper、Elasticsearch 等）| Kafka 专用 |
| 采集方式 | 以 Java Agent 形式嵌入 JVM 进程 | 独立进程 / Alloy 内置，通过 Kafka API 采集 |
| 指标类型 | Broker、JVM 内存、GC、线程、请求延迟 | Consumer Lag、Topic / Partition Offset |
| Alloy 支持 | 用 `prometheus.scrape` 抓取端点 | 内置 `prometheus.exporter.kafka` |

两者互补：`prometheus.exporter.kafka` 负责消费延迟和 Topic 偏移；JMX Exporter 负责 Broker / JVM 内部状态。生产环境建议同时启用。

### JMX Exporter 和 Alloy 可以集成吗？

**可以。** Alloy 本身不内置 JMX Exporter，但可以通过 `prometheus.scrape` 抓取 JMX Exporter 暴露的 Prometheus 端点。关键注意事项：

| 注意事项 | 说明 |
| --- | --- |
| 每个节点单独打标签 | 避免 `instance` 标签冲突 |
| 配置文件决定指标范围 | Kafka Broker 用 `kafka_broker.yml`，ZooKeeper 用 `zookeeper.yml` |
| 端口可自定义 | Alloy 的 `__address__` 与 JMX Exporter 监听端口一致即可 |

### Kafka 生态组件如何一起采集？

Grafana Cloud Kafka 集成不只覆盖 Kafka Broker，也支持 Kafka 生态组件。JMX Exporter 可用于这些 JVM 组件，Alloy 负责统一抓取和转发。

| 组件 | 采集方式 | 说明 |
| --- | --- | --- |
| Kafka Broker | JMX Exporter + `prometheus.exporter.kafka` | Broker/JVM 指标 + Consumer Lag |
| ZooKeeper | JMX Exporter | ZooKeeper 节点指标 |
| Kafka Connect | JMX Exporter | Connector / Task 状态 |
| Schema Registry | JMX Exporter | Schema Registry JVM 和服务指标 |
| ksqlDB | JMX Exporter | ksqlDB 服务指标 |