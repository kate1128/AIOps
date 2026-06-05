# AI 提效计划 - 成本管理

> 将 AI 引入 FinOps 工作流：成本归因自动分析、资源浪费 AI 识别、GPU 利用率优化建议、预算预测与告警。目标：GPU 利用率从当前 ~40% 提升到 >70%，每月节省云资源费用 20-30%。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| 月度成本分析 | 2-4 小时/月 | 运维/研发负责人 | 账单数据分散，按服务归因靠手动，无法细化到团队/项目 |
| 资源浪费识别 | 季度偶发性检查 | 运维 | 没有系统化扫描，闲置资源（unused Pod/PVC/LB）靠人工发现 |
| GPU 利用率分析 | 无定期分析 | 运维 | HAMI 的 GPU 分配 vs 实际使用经常有落差，浪费难以量化 |
| 预算超支预警 | 超支后才知道 | 运维/研发负责人 | 无预测能力，无法提前预警 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **Kubecost / OpenCost** | K8s 成本归因（按 Namespace/Pod）| ❌ 未部署 | 中 | 开源版免费 |
| **Prometheus + Claude API** | 资源利用率分析、浪费识别 | 🟡 Prometheus 已有 | 低 | 已有 |
| **阿里云账单 API** | 云资源费用采集 | ❌ 未接入 | 低 | 免费 |
| **Claude API** | 成本分析报告、优化建议生成 | 🟡 个人使用 | 低 | ~¥100-300 |
| **飞书多维表格** | 成本数据可视化、月度报告 | 🟡 部分使用 | 低 | 已有 |

---

## 三、高价值机会点详细方案

### 机会1：GPU 利用率 AI 分析与优化建议

**当前状态**：AI Infra 团队为 vLLM 等推理服务配置了 HAMI vGPU，但实际 GPU SM 利用率经常低于 30%，相当于大量 GPU 资源闲置但计费。  
**目标状态**：AI 定期分析 GPU 利用率分布，识别低利用率服务，给出具体的资源调整建议。

**方案设计**：
```
# GPU 利用率分析脚本（每日执行）

GPU_METRICS=$(curl -s "http://prometheus:9090/api/v1/query_range" \
  --data-urlencode 'query=avg_over_time(DCGM_FI_DEV_GPU_UTIL[24h])' \
  --data-urlencode "start=$(date -d '24 hours ago' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode "step=3600")

ALLOCATION=$(kubectl get pods -A -o json | jq '[.items[] |
  select(.spec.containers[].resources.limits["nvidia.com/gpu"] != null) |
  {
    namespace: .metadata.namespace,
    pod: .metadata.name,
    gpu_requested: .spec.containers[].resources.limits["nvidia.com/gpu"]
  }]')

# AI 分析
claude_analyze """
分析以下 GPU 资源数据，识别优化机会：

GPU 实际利用率（过去24小时）：${GPU_METRICS}
GPU 分配情况（Pod 维度）：${ALLOCATION}

请输出：
1. 高浪费服务列表（分配多/利用率低）
   格式：服务名 | 分配 | 实际利用率 | 建议操作
2. 具体调整建议（含 kubectl 命令）
3. 预计节省成本（按 ¥/GPU/天 估算）
4. 调整优先级（影响最大的先做）
"""
```

**工具栈**：DCGM Exporter + Prometheus + Claude API  
**前置条件**：DCGM Exporter 已部署（04-AI Infra 基建）  
**实施周期**：1 周  
**ROI 估算**：GPU 利用率从 ~40% 提升到 ~70%，等效节省 40% GPU 成本（约数万元/月）

---

### 机会2：云账单异常检测与成本归因

**当前状态**：月底收到阿里云账单时才发现当月费用异常，无法及时排查。成本无法按业务/团队维度归因。  
**目标状态**：每日分析云账单变化，AI 识别成本异常，按 Namespace/业务 归因到团队。

**方案设计**：
```
每日成本异常检测（飞书告警）：

# 1. 采集阿里云账单数据
bill_today = alicloud_billing_api.get_daily_cost(date=today)
bill_yesterday = alicloud_billing_api.get_daily_cost(date=yesterday)
bill_7d_avg = alicloud_billing_api.get_daily_cost(last_n_days=7)

# 2. OpenCost 按 Namespace 成本
k8s_cost = opencost_api.get_namespace_cost(today)

# 3. AI 分析
report = claude_analyze(f"""
今日云费用：{bill_today}元
昨日云费用：{bill_yesterday}元
近7天日均：{bill_7d_avg}元

K8s各Namespace成本：{k8s_cost}

请分析：
1. 是否有异常（超过日均30%以上视为异常）
2. 成本最高的 TOP 5 资源，说明是否合理
3. 与昨日相比显著变化的资源（增/减超过10%）
4. 建议关注的节省机会
""")

# 如有异常，飞书告警
if has_anomaly(report):
    feishu_alert(f"⚠️ 今日云费用异常\n{report}")
```

**工具栈**：阿里云账单 API + OpenCost + Claude API + 飞书  
**前置条件**：阿里云 RAM 账号（只读账单权限）；OpenCost 部署  
**实施周期**：2 周  
**ROI 估算**：成本异常从月度发现提前到当日发现；历史案例：漏删的 LB 月费约 2000-5000 元

---

### 机会3：K8s 资源浪费 AI 扫描

**当前状态**：集群中存在 Request 过大（超过实际使用）、空闲 PVC、长期 Pending 的 Pod 等浪费，没有定期清理机制。  
**目标状态**：每周 AI 扫描资源浪费，生成清单，Owner 确认后清理或调整。

**方案设计**：
```
每周资源浪费扫描报告：

检查项 1：CPU/内存 Request 远超实际使用
  over_requested=$(kubectl top pods -A --no-headers | \
    awk 'NR>0 {print $1, $2, $3}' | \
    # 对比 requests 配置，找出 request/实际 > 3 的 Pod
  )

检查项 2：长期低利用率 Deployment
  # CPU 使用率 < 5% 的 Deployment（基于Prometheus 过去7天）
  underused=$(promql "avg_over_time(
    rate(container_cpu_usage_seconds_total[5m])[7d:]) < 0.05")

检查项 3：未使用的 PVC
  unused_pvc=$(kubectl get pvc -A --no-headers | \
    grep -v Bound | awk '{print $1, $2, $4}')

检查项 4：闲置的 LoadBalancer Service
  idle_lb=$(kubectl get svc -A --no-headers | \
    grep LoadBalancer | \
    # 检查7天内无流量
  )

AI 生成优化建议清单：
  "发现以下资源浪费（本周）：
   
   🔴 CPU 超配（建议立即调整）：
   - vllm-qwen Deployment: request 8核/实际平均 2核，建议改为 3核
   - 预计节省：¥xxx/月
   
   🟡 空闲 PVC（建议确认后删除）：
   - pvc-test-data（50Gi，已90天未挂载）
   ..."
```

**工具栈**：kubectl + Prometheus + Claude API  
**前置条件**：Prometheus 已采集 Pod 资源使用指标  
**实施周期**：1 周  
**ROI 估算**：CPU 超配调整通常可减少 20-30% 计算成本；空闲存储清理减少存储费

---

### 机会4：月度成本 AI 分析报告

**当前状态**：没有月度成本报告，管理层和研发负责人对实际成本情况缺乏了解。  
**目标状态**：每月自动生成成本分析报告，包含趋势、归因、优化成果、下月预测。

**方案设计**：
```
月度成本报告（每月 1 日自动生成）：

报告内容（AI 生成 Markdown）：
  # SmartVision 基础设施成本月报 - YYYY年MM月
  
  ## 成本总览
  | 类别 | 本月费用 | 环比变化 | 占比 |
  |------|---------|---------|------|
  | GPU 服务器 | ¥xxx | +5% | 65% |
  | 存储（MinIO+PVC）| ¥xxx | -10% | 15% |
  | 网络（LB+带宽）| ¥xxx | 持平 | 10% |
  | 其他 | ¥xxx | +2% | 10% |
  
  ## 成本变化原因（AI 分析）
  - 本月 GPU 成本上升 5% 的原因：...
  
  ## TOP 5 资源（按成本）
  ...
  
  ## 已完成的优化（与上月对比）
  - 清理空闲 PVC 节省：¥xxx
  
  ## 下月成本预测
  - 预测值：¥xxx（置信区间 ±10%）
  - 主要变量：新项目 XX 计划上线，预计增加 GPU 消耗
```

**工具栈**：阿里云账单 API + OpenCost + Claude API + 飞书多维表格  
**前置条件**：有 3 个月历史账单数据；成本归因体系建立  
**实施周期**：1-2 周  
**ROI 估算**：月报从 2-4 小时减少到自动化；管理层决策有数据支撑

---

## 四、实施路径

### Phase 0（第 1-2 周）：数据采集与基础分析

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| 阿里云账单 API 接入 | RAM 账号 + 账单 API 自动采集 | 每日成本数据自动入库 | 运维 |
| GPU 利用率分析试跑 | 手动执行一次分析，验证数据准确性 | 识别出 TOP 3 GPU 浪费服务 | 运维/AI Infra |

### Phase 1（第 3-4 周）：自动化告警与扫描

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 成本异常日告警 | 每日自动检测 + 飞书推送异常 | 有效告警率 > 80%（不误报）| 运维 | 账单 API 接入 |
| 资源浪费周扫描 | 每周自动扫描 + 生成优化清单 | 每周产出可执行的优化清单 | 运维 | Prometheus + kubectl |

### Phase 2（第 5-8 周）：FinOps 体系化

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| OpenCost 部署 | 按 Namespace 成本归因 | prod 环境成本按 Namespace 可见 | 运维 | K8s 集群访问权限 |
| 月度成本报告 | 自动生成并推送飞书 | 每月 1 日零手动干预完成报告 | 运维 | 账单数据 + OpenCost 就绪 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（成本分析+报告）| ~¥100-200/月 | 约 4-6 人天/月 | 极高 |
| OpenCost（开源）| 运维 0.5 人天/月 | - | - |
| **GPU 利用率优化（节省）** | **节省 ¥1-5 万/月** | - | **极高** |
| **合计** | **~¥200-400/月投入** | **+节省数万** | **约 1:50+** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| AI 优化建议导致服务 OOM（调低内存 Request 后）| 服务不稳定 | 调整 Request 前必须先观察 2 周实际使用数据；生产改动走变更审批 |
| 账单 API 权限过大 | 数据安全风险 | RAM 账号只开启账单只读权限（AliyunBSSReadOnlyAccess）|
| GPU 分析误判（DCGM 数据延迟）| 错误指导优化方向 | 分析基于 7 天平均值，而非单点数据；突发负载场景单独标注 |
| 成本归因不准确（OpenCost 配置）| 团队看到错误的成本数据 | 先在测试环境验证 OpenCost 数据准确性后再推广 |
