# RabbitMQ 可观测性

> RabbitMQ 管理插件内置 Prometheus 指标端点，无需额外 Exporter。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| rabbitmq_prometheus | 内置 Prometheus 指标端点（管理插件） | TCP 15692 /metrics |
| Management API | RESTful API 查看队列/交换机/连接状态 | TCP 15672 |
| rabbitmq-export | HTTP API 抓取器，格式兼容 Prometheus | TCP 9419 /metrics |

3.8+ 版本推荐使用内置 `rabbitmq_prometheus`，无需额外部署。

---

## 核心指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `rabbitmq_queue_messages_ready` | 待消费消息数（队列积压）| > 10000 告警 |
| `rabbitmq_queue_messages_unacknowledged` | 未确认消息数 | > 100 关注 |
| `rabbitmq_connections` | 当前连接数 | 骤降说明消费者断开 |
| `rabbitmq_consumers` | 当前消费者数 | 骤降说明消费端挂掉 |
| `rabbitmq_node_mem_used` | 节点内存使用 | > 80% 告警 |
| `rabbitmq_node_disk_free` | 节点磁盘剩余 | < 5GB 告警 |
| `rabbitmq_queue_messages_ready_ram` | 内存中的待消费消息 | 偏高说明未持久化 |
| `rabbitmq_channel_messages_unroutable_returned` | 无法路由被退回消息 | > 0 说明 routing key 配错 |

---

## 采集集成

```yaml
# 启动 RabbitMQ Prometheus 端点（默认已启用）
# rabbitmq.conf
prometheus.tcp.port = 15692
prometheus.return_per_object_metrics = false

# Prometheus scrape
- job_name: rabbitmq
  static_configs:
    - targets:
        - "rabbitmq-host:15692"
      labels:
        service: rabbitmq
        env: prod

# K8s ServiceMonitor
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
      interval: 15s
```

---

## 告警规则

```yaml
- alert: RabbitMQQueueBacklog
  expr: rabbitmq_queue_messages_ready > 10000
  for: 5m
  annotations:
    summary: "RabbitMQ 队列 {{ $labels.queue }} 积压 {{ $value }} 条"

- alert: RabbitMQMemoryHigh
  expr: rabbitmq_node_mem_used / rabbitmq_node_mem_limit * 100 > 80
  for: 3m
  annotations:
    summary: "RabbitMQ 节点 {{ $labels.node }} 内存使用率 {{ $value | humanizePercentage }}"

- alert: RabbitMQNoConsumers
  expr: rabbitmq_consumers == 0
  for: 2m
  annotations:
    summary: "RabbitMQ 队列 {{ $labels.queue }} 无消费者"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 RabbitMQ | 管理插件默认启用，直接抓取 15692/metrics |
| Docker RabbitMQ | 需手动启用 `rabbitmq_prometheus` 插件 |
| K8s RabbitMQ (Cluster Operator) | RabbitMQ Operator 默认暴露 15692 |

需确保管理插件已启用：`rabbitmq-plugins enable rabbitmq_prometheus`
