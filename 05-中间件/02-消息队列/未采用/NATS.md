# NATS ?轻量消息系统

> 与RabbitMQ 的对比参考> 当前使用：RabbitMQ

---

## 是什么
NATS 是云原生消息系统，设计哲学是 **简单、高吞吐、低延迟**（微秒级）。相比 RabbitMQ 功能丰富，NATS 追求极简——单二进制、无依赖、毫秒级延迟。通过 NATS JetStream 扩展提供持久化和可靠消费?
---

## 与RabbitMQ 的核心区别
| 维度 | RabbitMQ | NATS |
|------|---------|------|
| **延迟** | 毫秒级 | 微秒级 |
| **吞吐量 * | 万级/s | 百万?s |
| **消息模型** | Exchange + Queue | 发布订阅 + JetStream |
| **持久化 * | 原生存储 | JetStream（内嵌）|
| **路由** | 灵活（Direct/Fanout/Topic/Headers）| 简单（主题匹配）|
| **运维** | 需 Erlang 虚拟机| 单二进制，极简 |

---

## 引入 NATS 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 极低延迟 | 微秒级延迟，适合实时性要求高的场景 |
| ✅ 极高吞吐 | 单节点百?QPS，适合 IoT 和日志流 |
| ✅ 极简运维 | 单二进制文件，无依赖，部署极其简单 |
| ✅ 云原生友好| K8s 部署?StatefulSet 即可 |

## 引入 NATS 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 路由功能有限 | 没有 RabbitMQ 灵活的路由规则（Headers/Dead Letter 等）|
| ?持久化较弱| JetStream 持久化不?RabbitMQ 的镜像队列成无 |
| ⛔ 生态工具| 管理和监控工具不?RabbitMQ 丰富 |
| ⛔ 迁移成本 | 现有基于 RabbitMQ ?consumer 需要改造|

---

## 参考
- https://nats.io
- https://github.com/nats-io/nats-server
