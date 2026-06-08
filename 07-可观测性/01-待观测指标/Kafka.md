# Kafka 可观测性

> Kafka 通过 JMX Exporter（内置 / 外挂）暴露海量 broker 和客户端指标。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| JMX Exporter | 读取 Kafka JMX MBeans 转成 Prometheus 格式 | TCP 9999 /metrics |
| kafka-exporter | 轻量独立 exporter，关注 consumer group lag | TCP 9308 /metrics |
| Cruise Control | LinkedIn 开源的 Kafka 集群自动运维，含监控 | Web UI + API |

JMX Exporter 可嵌入 Kafka 进程（`-javaagent`），或使用独立的 kafka-exporter 只采集 lag 指标。

---

## 核心指标

### Broker 层（JMX Exporter）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `kafka_server_brokertopicmetrics_messagesin_total` | 消息写入速率 | — |
| `kafka_server_brokertopicmetrics_bytesin_total` | 写入流量速率 | — |
| `kafka_server_brokertopicmetrics_bytesout_total` | 读出流量速率 | — |
| `kafka_controller_kafkacontroller_offlinepartitionscount` | 离线分区数 | > 0 告警 |
| `kafka_controller_kafkacontroller_underreplicatedpartitionscount` | 副本不足分区数 | > 0 告警 |
| `kafka_server_replicamanager_underreplicatedpartitions` | 未同步副本数 | > 0 告警 |
| `kafka_network_requestmetrics_totaltimems` | 请求处理延迟 | — |

### Consumer 层（kafka-exporter）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `kafka_consumergroup_current_offset` | 当前消费偏移 | — |
| `kafka_consumergroup_lag` | 消费者 Lag | > 10000 告警 |
| `kafka_topic_partition_current_offset` | 分区最新偏移 | — |

---

## 采集集成

```yaml
# JMX Exporter 配置（kafka启动参数）
KAFKA_OPTS="-javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent.jar=9999:/opt/jmx_exporter/kafka-broker.yml"

# Prometheus scrape
- job_name: kafka
  static_configs:
    - targets:
        - "kafka-broker-1:9999"
        - "kafka-broker-2:9999"
        - "kafka-broker-3:9999"
      labels:
        service: kafka
        env: prod

# kafka-exporter 独立部署，专采 consumer lag
- job_name: kafka-consumer
  static_configs:
    - targets:
        - "kafka-exporter:9308"
      labels:
        service: kafka-consumer
```

---

## 告警规则

```yaml
- alert: KafkaOfflinePartitions
  expr: kafka_controller_kafkacontroller_offlinepartitionscount > 0
  for: 1m
  annotations:
    summary: "Kafka 存在 {{ $value }} 个离线分区"

- alert: KafkaConsumerLagHigh
  expr: kafka_consumergroup_lag > 10000
  for: 5m
  annotations:
    summary: "消费者组 {{ $labels.consumergroup }} Lag {{ $value }}"

- alert: KafkaUnderReplicated
  expr: kafka_server_replicamanager_underreplicatedpartitions > 0
  for: 2m
  annotations:
    summary: "Kafka 存在 {{ $value }} 个未同步副本"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 Kafka | Kafka 启动参数加 JMX Exporter javaagent，broker 自带 metrics |
| Docker Kafka | 镜像内置 JMX Exporter 或 sidecar 方式 |
| K8s Kafka (Strimzi) | Strimzi 自动暴露 Prometheus 指标，自带 ServiceMonitor |
| Confluent Operator | 已内置 Prometheus metrics endpoint |

Kafka 是 Java 进程，JMX Exporter 会采集 JVM 指标（GC、内存、线程），这些对排查性能问题非常关键。

---

## 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
|--------|---------|---------|---------|---------|
| JMX Exporter | 嵌入 Kafka 进程 | Broker + JVM 全量 | 无 | 标准方案（需改启动参数） |
| kafka-exporter | 独立容器 | Consumer Lag 专项 | 无 | 只关注消费延迟 |
| JMX + kafka-exporter | 组合 | 全量覆盖 | 无 | 生产推荐 |
| **Grafana Alloy** | **内置 `prometheus.exporter.kafka`** | **Consumer Lag + Topic 级指标** | 内置 loki.source | **无需独立 kafka-exporter** |
| Netdata | 一键安装 | 内置 kafka collector | 内置日志查看 | 快速部署 |

> Alloy 内置 `prometheus.exporter.kafka`（基于 [grafana/kafka_exporter](https://github.com/grafana/kafka_exporter)），可直接连接 Kafka 采集 Consumer Lag、Topic 分区偏移等指标，**无需额外部署 kafka-exporter 容器**。

---

## Alloy 采集配置

### 方案一：Alloy 内置 Kafka Exporter（推荐）

```alloy
// Alloy 内置 prometheus.exporter.kafka，直接连接 Kafka
prometheus.exporter.kafka "example" {
  kafka_uris = ["kafka-1:9092", "kafka-2:9092", "kafka-3:9092"]
}

// 配合 prometheus.scrape 采集
prometheus.scrape "kafka" {
  targets    = prometheus.exporter.kafka.example.targets
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

### 方案二：Alloy 抓取 JMX Exporter（JVM 指标）

```alloy
// Kafka JMX Exporter 仍需独立部署（嵌入 -javaagent）
// Alloy 抓取其暴露的 /metrics 端口
prometheus.scrape "kafka_jmx" {
  targets = [
    { __address__ = "kafka-1:9999", service = "kafka-jmx" },
    { __address__ = "kafka-2:9999", service = "kafka-jmx" },
    { __address__ = "kafka-3:9999", service = "kafka-jmx" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

### 方案三：Alloy 内置 Kafka + JMX 组合（生产推荐）

```alloy
// Alloy 内置 Kafka Exporter（Consumer Lag + Topic 指标）
prometheus.exporter.kafka "example" {
  kafka_uris = ["kafka-1:9092", "kafka-2:9092", "kafka-3:9092"]
}

prometheus.scrape "kafka_exporter" {
  targets    = prometheus.exporter.kafka.example.targets
  forward_to = [prometheus.remote_write.central.receiver]
}

// JMX Exporter（JVM 指标：GC/内存/线程）
prometheus.scrape "kafka_jmx" {
  targets = [
    { __address__ = "kafka-1:9999", service = "kafka-jmx" },
    { __address__ = "kafka-2:9999", service = "kafka-jmx" },
    { __address__ = "kafka-3:9999", service = "kafka-jmx" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

---

## Netdata 方案

Netdata 内置 kafka collector，但需要 JMX 端口可达：

```bash
docker run -d --name=netdata \
  -p 19999:19999 \
  --cap-add SYS_PTRACE \
  netdata/netdata
```

> 注意：Kafka 的 JMX Agent 必须嵌入进程（`-javaagent`），这是所有方案的共同前提，Netdata 也不例外。

---

## 方案对比

| 维度 | JMX Exporter + Prometheus | Alloy（内置 Kafka Exporter） | Netdata |
|------|--------------------------|----------------------------|---------|
| 部署复杂度 | 高（需改 Kafka 启动参数） | 中（Alloy 内置 Kafka Exporter + JMX 仍需 agent） | 中 |
| Kafka 侧改动 | 必须加 `-javaagent` | Kafka Exporter 无需改动；JVM 指标仍需 `-javaagent` | 必须加 `-javaagent` |
| Consumer Lag | 需额外 kafka-exporter | ✅ Alloy 内置 `prometheus.exporter.kafka` | 内置 |
| JVM 指标 | ✅ | ✅（需 JMX Exporter 配合） | ✅ |
| Topic/Partition 指标 | 需 kafka-exporter | ✅ Alloy 内置 | ✅ |
| 推荐场景 | 标准方案 | **Grafana 全栈（减少一个组件）** | 快速验证 |
