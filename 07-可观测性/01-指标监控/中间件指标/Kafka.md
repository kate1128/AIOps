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
