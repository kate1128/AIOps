# GPU 成本核算规范

> GPU 节点占总成本约 75%，本规范定义 GPU 成本的归因方法、利用率监控和成本优化策略。

---

## 一、GPU 资产与成本概览

### 当前 GPU 节点成本结构

| 节点 | GPU 型号 | 数量 | 用途 | 月均费用（估算）|
|------|---------|------|------|---------------|
| iz2zehh4uj8wuh64pe836tz | L20 | 8 卡 | 推理（主力）| 待填写 |
| llm-l20-20250909 | L20 | 8 卡 | 推理（扩容）| 待填写 |
| iz2ze8fusva2xt3sjsi0ywz | A100 | 2 卡 | 推理（特定模型）| 待填写 |

> GPU 节点费用从阿里云账单 → 实例费用明细 中获取，按节点 ID 过滤。

---

## 二、GPU 成本归因方法

### 目标：将 GPU 费用归因到具体模型/服务

**前提**：DCGM Exporter 已部署，K8s Pod 打了 `model` 标签。

### 成本计算公式

```
模型 X 的 GPU 成本 = 
  GPU 节点日费用 × (模型 X 显存占用 / 节点总显存) × 使用天数
```

### 在 Grafana 中配置 GPU 成本看板

```promql
# 各 Pod 的 GPU 显存占用（GB）
sum by (namespace, pod, model) (
  DCGM_FI_DEV_FB_USED{} / 1024
)

# 按模型标签聚合显存占用比例
sum by (model) (DCGM_FI_DEV_FB_USED) 
  / 
sum(DCGM_FI_DEV_FB_TOTAL)
```

### GPU 成本归因表（月度填写）

| 模型/服务 | 平均显存占用(GB) | 占比 | 分摊成本 | 调用量 | 单次调用成本 |
|---------|---------------|------|---------|--------|------------|
| qwen-72b | | | | | |
| qwen-7b | | | | | |
| embedding 服务 | | | | | |
| 宿主机裸进程 | | | | 不可追踪 | N/A |

---

## 三、GPU 利用率监控

### 关键指标

| 指标 | Prometheus 查询 | 告警阈值 |
|------|---------------|---------|
| GPU SM 利用率 | `DCGM_FI_DEV_GPU_UTIL` | < 20% 持续 2h → 疑似空跑 |
| GPU 显存利用率 | `DCGM_FI_DEV_MEM_COPY_UTIL` | > 90% → OOM 风险 |
| GPU 温度 | `DCGM_FI_DEV_GPU_TEMP` | > 85°C → 需关注散热 |
| 节点空闲时长 | 自定义，SM_util < 5% 的持续时间 | > 4h → 考虑释放 |

### 日常巡检脚本

```bash
#!/bin/bash
# gpu-cost-check.sh - 每日检查 GPU 利用率，发现浪费

echo "=== GPU 节点利用率快照 ==="
for node in iz2zehh4uj8wuh64pe836tz iz2ze8fusva2xt3sjsi0ywz; do
  echo "--- Node: $node ---"
  ssh $node "nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits"
done

echo ""
echo "=== 宿主机直跑进程（不受 K8s 管控）==="
for node in iz2zehh4uj8wuh64pe836tz iz2ze8fusva2xt3sjsi0ywz; do
  echo "--- Node: $node ---"
  ssh $node "nvidia-smi --query-compute-apps=pid,used_memory,process_name \
    --format=csv,noheader | while read line; do
      pid=\$(echo \$line | cut -d, -f1)
      if ! cat /proc/\$pid/cgroup 2>/dev/null | grep -q kubepods; then
        echo \"[宿主机进程] \$line\"
      fi
    done"
done
```

---

## 四、GPU 成本优化策略

### 4.1 消除宿主机裸进程（立即行动）

宿主机直跑进程不受调度约束，是成本浪费和安全风险的双重来源：

```bash
# 识别宿主机进程
ssh GPU节点 "ps aux | grep python"
# 逐一确认是否有对应 K8s Pod
# 如无：联系相关负责人，迁移到 K8s 或记录合法原因
```

### 4.2 Dev GPU 节点下班自动关机

Dev 环境 GPU 节点（如 RTX4090 工作站）在工作时间外关机，节省约 60% 费用：

```bash
# 添加 crontab（在 dev GPU 节点上）
# 工作日 23:00 自动关机
0 23 * * 1-5 /sbin/shutdown -h now

# 工作日 8:30 自动开机（需在阿里云控制台配置定时任务，或 BIOS 设置 Wake-on-LAN）
```

### 4.3 模型按需加载（业务低峰期）

非核心模型（低频使用）在业务低峰期卸载，释放显存给其他服务：

| 场景 | 策略 |
|------|------|
| 工作日白天 | 全模型加载 |
| 工作日夜间（22:00-8:00）| 仅保留核心模型 |
| 周末 | 仅保留核心模型 |

用 K8s CronJob 实现 vLLM Deployment 的 replicas 缩容。

### 4.4 GPU 按使用量计费（中期目标）

当多个业务共用 GPU 时，按照实际调用量进行内部分摊：

```
内部分摊价格 = GPU 节点总成本 / 月总 Token 处理量
每次调用成本 = Token 数量 × 内部分摊价格
```

---

## 五、月度 GPU 成本报告

```markdown
## GPU 成本月报 {YYYY-MM}

### 总 GPU 费用
- 本月：元
- 上月：元，环比：%

### 利用率统计
| 节点 | 平均 SM 利用率 | 平均显存利用率 | 空跑时长（SM<5%）|
|------|------------|------------|---------------|

### 成本归因（按模型）
| 模型 | 显存占比 | 分摊成本 | 调用量 | 单次成本（元/千Token）|
|------|---------|---------|--------|---------------------|

### 发现的浪费
- 宿主机裸进程：个，占用显存 GB
- 空闲节点（SM 利用率持续 < 10%）：小时

### 本月优化动作
- 

### 下月节省预估
- 
```
