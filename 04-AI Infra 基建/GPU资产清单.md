# GPU 资产清单

> 最后更新：2026-05-28，基于 nvidia-smi 实测数据整理。

---

## 一、各环境 GPU 汇总

| 环境 | 节点名 | GPU 型号 | 卡数 | 单卡显存 | 驱动版本 | CUDA |
|---|---|---|---|---|---|---|
| 生产 | iz2zehh4uj8wuh64pe836tz | NVIDIA L20 | 8 | 46 GB | 570.133.20 | 12.8 |
| 生产 | llm-l20-20250909 | NVIDIA L20 | 8 | 46 GB | 570.133.20 | 12.8 |
| 生产 | root（A100节点1）| A100-SXM4-80GB | 1 | 80 GB | 535.54.03 | 12.2 |
| 生产 | iz2ze8fusva2xt3sjsi0ywz | A100-SXM4-80GB | 1 | 80 GB | 535.129.03 | 12.2 |
| pre | worker3 | NVIDIA L20 | 4 | 46 GB | 580.82.07 | 13.0 |
| pre | worker2 | NVIDIA L20 | 4 | 46 GB | 570.124.06 | 12.8 |
| dev | cluster（node1）| RTX 4090 | 4 | 24 GB | 580.159.03 | 13.0 |
| dev | localhost（node2）| RTX 4090 | 1 | 24 GB | 550.78 | 12.4 |

**生产总显存：** L20×16（736 GB）+ A100×2（160 GB）= **896 GB**

---

## 二、生产显存使用快照（2026-05-28）

### 节点 iz2zehh4uj8wuh64pe836tz（L20×8）

| GPU | 已用 / 总量 | 占用率 | 进程数 | 风险 |
|---|---|---|---|---|
| GPU 0 | 21169 / 46068 MiB | 46% | 7 个（含宿主机进程）| 🟡 混用 |
| GPU 1 | 45422 / 46068 MiB | **98.6%** | 1 个 | 🔴 濒临 OOM |
| GPU 2 | 2041 / 46068 MiB | 4% | 1 个 | ✅ |
| GPU 3 | 819 / 46068 MiB | 2% | 1 个 | ✅ |
| GPU 4 | 42727 / 46068 MiB | 92.8% | 1 个（TP0）| 🟡 高占用 |
| GPU 5 | 42727 / 46068 MiB | 92.8% | 1 个（TP1）| 🟡 高占用 |
| GPU 6 | 2279 / 46068 MiB | 5% | 1 个 | ✅ |
| GPU 7 | 3 / 46068 MiB | 0% | 0 | ✅ |

> GPU 1 已达 98.6%，无缓冲空间，OOM 风险极高，需立即建立告警。

### 节点 iz2ze8fusva2xt3sjsi0ywz（A100×1）

| GPU | 已用 / 总量 | 占用率 | 说明 |
|---|---|---|---|
| GPU 0 | 67479 / 81920 MiB | 82.4% | vLLM EngineCore 单进程独占 |

---

## 三、驱动版本不统一问题

| 驱动版本 | 节点 | 风险 |
|---|---|---|
| 535.x | A100 两台 | 旧版，不支持 CUDA 12.6+ 特性 |
| 550.x | dev localhost | dev 环境可接受 |
| 570.x | 生产 L20 × 2、pre worker2 | 当前主流，稳定 |
| 580.x | pre worker3、dev cluster | 最新，兼容性需验证 |

**目标：** 统一生产节点为 570.x 或 575.x，A100 节点升级到 550+ 系列。

---

## 四、宿主机裸进程清单（需迁移至 K8s）

以下进程直接跑在宿主机，不经过 K8s 调度，HAMI 无法管理：

| 节点 | GPU | 进程 | 显存占用 | 状态 |
|---|---|---|---|---|
| iz2zehh4uj8wuh64pe836tz | 0 | python3（多个）| ~18 GiB | 🔴 待迁移 |
| root（A100-1）| 0 | python3（多个）| ~53 GiB | 🔴 待迁移 |
| cluster（dev）| 1,3 | python / python3（多个）| ~18 GiB | 🟡 dev 可接受 |

识别命令：

```bash
# 找出不在任何 K8s 容器中的 GPU 进程
nvidia-smi --query-compute-apps=pid,used_memory,name --format=csv,noheader | while read pid mem name; do
  if ! cat /proc/$pid/cgroup 2>/dev/null | grep -q kubepods; then
    echo "宿主机进程: PID=$pid MEM=${mem}MiB CMD=$name"
  fi
done
```
