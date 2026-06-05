# VictoriaMetrics ?时间序列数据?
> 与Prometheus 的对比参考> 当前使用：Prometheus

---

## 是什么
VictoriaMetrics 是高性能 Prometheus 兼容的时间序列数据库。可以作?Prometheus ?*远程存储**?*直接替代**。在大量指标数据场景下，它的存储压缩率（1:10+）、查询性能和资源效率均显著优于原生 Prometheus?
---

## 与Prometheus 的核心区别
| 维度 | Prometheus | VictoriaMetrics |
|------|-----------|----------------|
| **架构** | 单节点（?Thanos 集群）| 单节点 / vmcluster 多组件|
| **存储压缩** | ?1:4 | 1:10+（同样磁盘存 2x+ 数据）|
| **查询** | PromQL | PromQL + MetricsQL（扩展函数）|
| **高可用 * | 双写 + Thanos | vmcluster 内置 |
| **长期存储** | 需 Thanos / Cortex | 内置，不需要额外组无 |
| **数据摄入** | Pull 模型 | Pull + Push 双模无 |

---

## 引入 VictoriaMetrics 你能得到什么
| 收益 | 说明 |
|------|------|
| ?省存储| 同样 100GB 磁盘，VictoriaMetrics 能存 Prometheus 2-3 倍时长的数据 |
| ✅ 查询更快 | 大数据聚合查询显著快?Prometheus（秒?vs 超时）|
| ✅ 长期存储内置 | 无需额外部署 Thanos，自带长期存储能无 |
| ✅ 兼容 PromQL | 现有 Grafana Dashboard 和告警规则可直接复用 |
| ✅ Push 模式 | 支持 Prometheus 没有✅ Push 模式，适合短生命周期任无 |

## 引入 VictoriaMetrics 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 组件增多 | 集群模式需?vmselect/vminsert/vmstorage 多个组件 |
| ⛔ 排障经验少| 出问题时社区解决方案不如 Prometheus 无 |
| ?小规模无优势 | 指标量不大（< 100?s）时，优势不明显 |
| ⛔ 告警和记录规则| 需单独配置 vmalert，不如原?Prometheus 方便 |

---

## 参考
- https://victoriametrics.com
- https://github.com/VictoriaMetrics/VictoriaMetrics
