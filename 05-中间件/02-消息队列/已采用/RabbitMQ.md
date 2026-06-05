# RabbitMQ - 任务队列

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 任务调度、事件分发、延迟任务 |
| 部署方式 | 待确认 |
| 版本 | - |
| 节点数 | 无 |

---

## 核心配置

```conf
vm_memory_high_watermark.relative = 0.8
disk_free_limit.absolute = 5GB
heartbeat = 60
cluster_partition_handling = pause_minority
```

---

## Queue 设计

| Queue | 类型 | TTL | 死信 | 说明 |
|-------|------|-----|------|------|
| `task.inference` | Quorum | 1h | 无 | AI 推理任务 |
| `task.scheduled` | Classic | 持久 | 无 | 定时任务 |
| `event.notification` | Quorum | 5min | 无 | 通知 |
| `event.audit` | Stream | 24h | 无 | 审计日志 |

---

## K8s 部署

```bash
helm install rabbitmq bitnami/rabbitmq \
  --namespace rabbitmq --create-namespace \
  --set auth.username=admin \
  --set metrics.enabled=true \
  --set replicaCount=3 \
  --set persistence.size=50Gi
```

---

## 监控

```promql
rabbitmq_queue_messages_ready{queue=~"task.*"}
rabbitmq_queue_consumers{queue=~"task.*"} == 0
rabbitmq_queue_messages_unacked
rabbitmq_alarms_running{type="disk"}
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 消费者积压监控告警 |
| P0 | 死信队列配置 |
| P1 | Quorum vs Classic 队列选型 |
| P1 | 延迟任务（delayed-message 插件）|
| P2 | 3 节点集群高可用|
