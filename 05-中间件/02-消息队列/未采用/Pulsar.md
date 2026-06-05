# Pulsar - 消息流平台
> 与Kafka 的对比参考> 当前使用：Kafka

---

## 是什么
Apache Pulsar 是云原生消息流平台，相比 Kafka 的最大区别是**存算分离**——Broker 不存储数据，数据存储在 Apache BookKeeper 集群中。这使得 Broker 和存储可以独立扩缩容?
---

## 与Kafka 的核心区别
| 维度 | Kafka | Pulsar |
|------|-------|--------|
| **架构** | 存算一体（Broker 即存储）| 存算分离（Broker + BookKeeper）|
| **扩缩容 * | 需 rebalance，影响在线流量 | 独立扩缩，无感 |
| **多租户 * | Topic 命名约定隔离 | 原生多租户（命名空间级隔离）|
| **消息保留** | Topic 级别配置 | 命名空间级别统一配置 |
| **延迟消息** | 需插件或自实现 | 原生支持 |
| **协议** | 自定义 TCP 协议 | 兼容 Kafka 协议 + Pulsar 协议 |

---

## 引入 Pulsar 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 弹性扩缩| 流量增加只需加 Broker，存储不够只加 BookKeeper |
| ✅ 多租户隔离 | 不同业务/团队命名空间隔离，配额独立 |
| ✅ 无感 rebalance | 扩容不影响生产和消费 |
| ✅ 更灵活的消息模型 | 支持延迟消息、死信 Topic、函数计算 |

## 引入 Pulsar 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 组件多| 多一个 BookKeeper 集群需要运维（至少 3 节点）|
| ⛔ 生态| Kafka Connect / Kafka Streams / KSQL 无直接替代 |
| ⛔ 成熟度| Kafka 更广泛验证，Pulsar 一些边缘特性不够稳定 |
| ⛔ 团队经验 | 有Kafka 经验的工程师容易，Pulsar 经验难找 |

---

## 参考
- https://pulsar.apache.org
- https://github.com/apache/pulsar
