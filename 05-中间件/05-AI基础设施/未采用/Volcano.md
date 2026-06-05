# Volcano ?K8s 批处理调度器

> 与HAMI 的对比参考> 当前使用：HAMI

---

## 是什么
Volcano ?CNCF 孵化?K8s 批量计算?AI 调度引擎。核心能力包?**Gang-Scheduling**（一?Pod 要么全部调度成功要么都不调度，适合分布式训练）?*队列管理**（多团队资源共享和隔离）?*公平调度**（DRF 算法）?
---

## 与HAMI 的核心区别
| 维度 | HAMI | Volcano |
|------|------|---------|
| **定位** | GPU 显存/算力调度 | 通用批处?+ AI 调度 + 大数据|
| **GPU 共享** | ?显存动态分无 | ⛔ GPU 共享 + MPS |
| **Gang 调度** | 无 | ?分布式训练必无 |
| **队列** | 简单优先级 | ?多级队列 + 配额管理 |
| **调度策略** | 优先级| FIFO / 优先级/ DRF（公平调度）|
| **适用场景** | GPU 推理任务 | AI 训练 + 推理 + Spark/Flink |

---

## 引入 Volcano 你能得到什么
| 收益 | 说明 |
|------|------|
| ?Gang-Scheduling | 分布式训练任务确保所?Worker 同时调度，避免死信|
| ✅ 队列配额 | 按团?项目分配资源配额，互不抢无 |
| ?公平调度 | DRF 算法让多个训练任务公平竞争资无 |
| ?多框架支无 | 原生支持 PyTorch/TensorFlow/MPI/Spark |
| ?任务依赖 | DAG 编排：数据预处理 ?训练 ?评估 |

## 引入 Volcano 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 配置复杂性| 需要定?VCJob/PodGroup ?CRD，比普?Pod 复杂 |
| ?训练 vs 推理 | 如果你的场景主要是推理（在线服务），Volcano 优势不大 |
| ?门槛 | 需要理?Volcano 的调度概念和 CRD API |
| ??HAMI 共存 | 如果同时?HAMI 管理 GPU 分片，两者可能冲无 |

---

## 参考
- https://volcano.sh
- https://github.com/volcano-sh/volcano
