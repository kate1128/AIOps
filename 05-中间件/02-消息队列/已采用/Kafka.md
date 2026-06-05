# Kafka - 高吞吐消息流

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| AI 推理任务队列、事件流、日志收集 |
| 部署方式 | 待确认 |
| 版本 | - |
| Broker 无 | 无 |

---

## 核心配置

```properties
num.partitions=3
default.replication.factor=3
min.insync.replicas=2
log.retention.hours=168
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
```

---

## Topic 规范

| Topic | 分区 | 保留 | 说明 |
|-------|------|------|------|
| `ai.inference.requests` | 12 | 7d | 推理请求 |
| `ai.inference.results` | 12 | 3d | 推理结果 |
| `audit.user-actions` | 6 | 30d | 审计 |
| `monitoring.alerts` | 3 | 3d | 告警 |
| `events.system` | 3 | 7d | 系统事件 |

---

## K8s 部署（Strimzi）
```bash
kubectl create namespace kafka
kubectl apply -f https://strimzi.io/install/latest?namespace=kafka -n kafka

# 创建集群
cat <<EOF | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: smartvision-kafka
  namespace: kafka
spec:
  kafka:
    replicas: 3
    config:
      offsets.topic.replication.factor: 3
      default.replication.factor: 3
      min.insync.replicas: 2
    storage:
      type: persistent-claim
      size: 500Gi
  zookeeper:
    replicas: 3
    storage:
      type: persistent-claim
      size: 20Gi
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF
```

---

## 监控

```promql
kafka_consumer_group_lag{group="ai-inference-workers"}
rate(kafka_server_brokertopicmetrics_messagesinpersec[5m])
count(kafka_cluster_partition_undereplicated) > 0
kafka_log_log_size / kafka_log_log_maxsize * 100
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 消费者 Lag 监控告警 |
| P0 | Topic 声明式管理（KafkaTopic CRD）|
| P1 | 消息大小限制适配（AI 场景）|
| P1 | 分区数按消费并发度调整 |
| P2 | 审计 Topic 启用日志压缩 |
