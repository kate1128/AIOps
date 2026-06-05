# Dragonfly - 内存数据库
> 与Redis 的对比参考> 当前使用：Redis

---

## 是什么
Dragonfly 是现代化的内存数据库，完全兼容 Redis 和 Memcached 协议，但采用多线程架构，单实例吞吐量可达数百万 QPS（Redis 的 5-10 倍），且内存效率更高（无碎片）?
---

## 与Redis 的核心区别
| 维度 | Redis | Dragonfly |
|------|-------|-----------|
| **架构** | 单线程事件循环 | 多线程（共享无内存）|
| **吞吐量 * | ~10万 QPS | ~数百万 QPS |
| **内存效率** | 可能有碎片 | 共享无内存，碎片极少 |
| **协议兼容** | 原生 | 兼容 Redis + Memcached |
| **持久化 * | RDB + AOF（fork 开销）| 快照 + AOF（无 fork，不阻塞）|
| **集群** | Sentinel / Cluster | 内置多线程多主 |

---

## 引入 Dragonfly 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 性能飞跃 | 单实例替代多 Redis 分片，同样硬件 5x+ 吞吐 |
| ✅ 内存省 | 无内存碎片，同样数据更省内存 |
| ✅ 兼容零迁移| 应用代码完全不用改，Redis 协议全兼容 ||
| ✅ 简化架构| 单实例顶多个 Redis 分片，运维简单 |

## 引入 Dragonfly 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 生产案例少| 2022 年才开源，大规模生产验证不如 Redis |
| ⛔ 生态工具| redis-cli / RedisInsight 等工具可能不完全兼容 |
| ⛔ 社区支持 | Redis 社区极其成熟，Dragonfly 遇到问题难搜到答案 |
| ✅ 极端稳定性| Redis 经过十余年检验，Dragonfly 偶有边缘 case |

---

## 参考
- https://dragonflydb.io
- https://github.com/dragonflydb/dragonfly
