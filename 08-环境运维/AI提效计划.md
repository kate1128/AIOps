# AI 提效计划 - 环境运维

> 将 AI 引入 K8s 集群的日常运维：智能巡检、配置合规审计、故障排查辅助、变更影响评估。目标：日常巡检从人工 30 分钟自动化为 5 分钟 Review，K8s 配置合规问题发现率提升 3 倍。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| 每日集群巡检 | 20-40 分钟/天 | 运维工程师 | 手动执行 kubectl 命令检查各维度，重复且容易漏项 |
| K8s 配置合规检查 | 靠人工 Code Review | 运维/架构 | 无资源限制/privileged 容器等问题靠运气发现 |
| Pod 异常排查 | 10-60 分钟/次 | 运维工程师 | CrashLoopBackOff/OOMKilled 需要组合命令排查 |
| 变更影响评估 | 1-2 小时/次 | 运维 + 研发 | 变更前难以量化影响范围，依赖经验 |
| 命名空间/资源配额管理 | 季度人工审查 | 运维负责人 | 无实时超配告警，只有快满了才发现 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **kubectl + Claude API** | Pod 异常分析、YAML 审计、故障排查 | 🟡 个人使用 | 低 | ~¥200-400 |
| **Kyverno** | K8s 配置策略执行（合规检查自动化）| ❌ 未使用 | 中 | 开源免费 |
| **Popeye / kube-score** | K8s 集群配置评分和问题扫描 | ❌ 未使用 | 低 | 开源免费 |
| **k9s** | 交互式集群管理（提升运维效率）| 🟡 部分使用 | 低 | 开源免费 |
| **Shell 脚本 + AI 分析** | 自动化巡检报告生成 | ❌ 未使用 | 中 | Claude API 成本 |

---

## 三、高价值机会点详细方案

### 机会1：集群智能日常巡检

**当前状态**：运维每天手动执行十几个 kubectl 命令检查集群状态，耗时 20-40 分钟，且容易遗漏。  
**目标状态**：脚本每天自动巡检，AI 生成摘要报告，运维只需 5 分钟 Review 异常项。

**方案设计**：
```bash
#!/bin/bash
# daily-cluster-check.sh - 每天 9:00 自动执行

echo "=== 集群健康状态 $(date) ===" > /tmp/cluster-report.txt

# 1. Node 状态
kubectl get nodes -o wide >> /tmp/cluster-report.txt
kubectl describe nodes | grep -A3 "Conditions:" >> /tmp/cluster-report.txt

# 2. 异常 Pod 检测
echo "=== 异常 Pod ===" >> /tmp/cluster-report.txt
kubectl get pods -A | grep -v Running | grep -v Completed >> /tmp/cluster-report.txt

# 3. 资源使用率（需要 metrics-server）
kubectl top nodes >> /tmp/cluster-report.txt
kubectl top pods -A --sort-by=memory | head -20 >> /tmp/cluster-report.txt

# 4. 最近的 Event 警告
kubectl get events -A --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -20 >> /tmp/cluster-report.txt

# 5. PVC 使用情况
kubectl get pvc -A >> /tmp/cluster-report.txt

# 发送给 Claude API 生成摘要
REPORT=$(cat /tmp/cluster-report.txt)
SUMMARY=$(curl -s -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: $CLAUDE_API_KEY" \
  -d "{\"model\":\"claude-3-5-haiku\",\"max_tokens\":500,
       \"messages\":[{\"role\":\"user\",\"content\":
       \"分析以下 K8s 集群巡检报告，用中文摘要：哪些需要今天处理（P1），
         哪些需要本周关注（P2），哪些是正常的。\n$REPORT\"}]}")

# 发送到飞书
curl -X POST "$FEISHU_WEBHOOK" -d "{\"text\":\"📋 集群日报\n$SUMMARY\"}"
```

**工具栈**：Shell 脚本 + kubectl + Claude API（claude-3-5-haiku，成本低）+ 飞书  
**前置条件**：无（kubectl 已有权限）  
**实施周期**：2-3 天  
**ROI 估算**：日常巡检时间从 20-40 分钟减少到 5 分钟 Review

---

### 机会2：K8s 配置合规 AI 自动扫描

**当前状态**：K8s 资源配置问题（无 Resource Limit/privileged 容器/镜像使用 latest tag）靠人工 Review，漏检率高。  
**目标状态**：每次 MR 部署变更时自动扫描，合规问题在合并前 100% 被发现。

**方案设计**：
```
方案A（推荐）：Kyverno 策略执行
  关键策略：
  1. 所有容器必须有 CPU/Memory Limits
     rule: require-resource-limits
  2. 禁止 privileged: true
     rule: disallow-privileged-containers
  3. 镜像不得使用 :latest tag
     rule: disallow-latest-tag
  4. 必须有 readinessProbe 和 livenessProbe
     rule: require-probes

  Kyverno 在 audit 模式下先运行，发现问题但不 Block；
  1 个月后切换到 enforce 模式

方案B：kube-score + LLM 解释
  kube-score score deployment.yaml
  # 输出 WARN 和 CRITICAL 问题
  # 用 Claude 将机器输出翻译为中文，附上修复示例
```

**工具栈**：Kyverno（推荐）或 kube-score + Claude API  
**前置条件**：K8s >= 1.16（Kyverno 要求）  
**实施周期**：1 周（Kyverno 部署 + 初始策略配置）  
**ROI 估算**：配置合规问题发现率从随机发现到 100% 覆盖；privileged 容器从有到零

---

### 机会3：Pod 异常 AI 辅助排查

**当前状态**：Pod CrashLoopBackOff/OOMKilled 时，运维需要组合 kubectl describe/logs/events 命令逐步排查。  
**目标状态**：检测到异常 Pod 时，自动采集诊断信息，AI 给出根因分析和修复建议。

**方案设计**：
```bash
#!/bin/bash
# pod-troubleshoot.sh <namespace> <pod-name>
NS=$1; POD=$2

echo "=== 诊断信息采集：$NS/$POD ==="

# 采集诊断数据
DESCRIBE=$(kubectl describe pod $POD -n $NS)
LOGS=$(kubectl logs $POD -n $NS --previous --tail=100 2>/dev/null || \
       kubectl logs $POD -n $NS --tail=100)
EVENTS=$(kubectl get events -n $NS --field-selector \
         involvedObject.name=$POD --sort-by='.lastTimestamp')

# Claude 分析
ANALYSIS=$(echo "Pod: $NS/$POD
Describe: $DESCRIBE
Logs: $LOGS
Events: $EVENTS" | claude-api-call "请分析该 Pod 的故障原因并给出修复步骤")

echo "$ANALYSIS"
```

**自动触发**：Alertmanager 收到 KubePodCrashLooping 告警时自动调用此脚本  
**工具栈**：kubectl + Claude API  
**前置条件**：无  
**实施周期**：2-3 天  
**ROI 估算**：Pod 异常排查时间从 10-60 分钟减少到 10-15 分钟

---

### 机会4：变更 AI 影响评估

**当前状态**：每次 K8s 变更（Deployment 更新/ConfigMap 修改/资源调整）前，依赖工程师经验评估影响，容易遗漏。  
**目标状态**：提交变更 YAML 时，AI 自动分析与当前生产配置的差异，标注变更影响和风险点。

**方案设计**：
```
输入：变更前的 YAML vs 变更后的 YAML（diff）

AI 分析输出：
  "变更摘要：
   - 修改了 vllm-qwen Deployment 的 replicas：1 → 2
   - 修改了 GPU resource request：nvidia.com/gpu: 4 → 8

   影响评估：
   ⚠️ GPU 资源需求增加：需要确认节点有足够的空闲 GPU（当前 L20 节点还有 X 卡可用）
   ℹ️ 滚动更新策略：新 Pod 启动前旧 Pod 不会被删除，需要节点有额外容量
   ✅ 无 ConfigMap/Secret 变更，无需应用重载
   ✅ 回滚方式：kubectl rollout undo deployment/vllm-qwen -n prod"
```

**工具栈**：kubectl diff + Claude API  
**前置条件**：变更通过 GitLab MR 提交，CI 中有 kubectl diff 步骤  
**实施周期**：1 周  
**ROI 估算**：变更引发的意外故障减少，变更评审时间减少 50%

---

## 四、实施路径

### Phase 0（第 1 周）：立即可用

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| 集群日常巡检脚本 | 部署 daily-cluster-check.sh，设置 cron 9:00 执行 | 每天自动推送集群日报到飞书 | 运维 |
| Pod 排查脚本 | 编写 pod-troubleshoot.sh，测试 3 个真实故障场景 | 输出根因分析准确率 > 80% | 运维 |

### Phase 1（第 2-3 周）：配置合规自动化

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| Kyverno 部署（audit 模式）| helm install kyverno，部署关键策略 | 扫描出所有 prod 命名空间的不合规资源 | 运维 | K8s ≥ 1.16 |
| 变更 AI 影响评估 CI | CI 中添加 kubectl diff + Claude 分析步骤 | 每次部署 MR 有变更影响摘要 | DevOps | GitLab CI 配置 |

### Phase 2（第 4-6 周）：策略收紧与自动化深化

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| Kyverno enforce 模式 | 存量不合规资源修复后，切换 enforce 模式 | privileged 容器数 = 0，所有 Pod 有 Resource Limits | 运维 | 存量问题已修复 |
| 告警联动排障 | Pod 异常告警自动触发 pod-troubleshoot.sh | 异常 Pod 告警 3 分钟内附上 AI 分析结果 | 运维 | Alertmanager 告警已配置 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（巡检+排障+评估）| ~¥150-300（使用 Haiku 模型）| 约 4-6 人天/月 | 高 |
| Kyverno（开源）| 运维 0.5 人天/月 | 配置合规长期节省排查成本 | 极高 |
| **合计** | **~¥200-400/月** | **约 5-8 人天/月** | **约 1:12** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| Kyverno enforce 模式误 Block 合法资源 | 部署中断 | 先在 pre 环境运行 1 个月再切 prod；保留 break-glass 排除策略 |
| 巡检脚本执行错误 kubectl 命令 | 误操作集群 | 脚本只读操作，不执行任何修改命令；运行前 dry-run 验证 |
| AI 分析结果让运维过度依赖，减少思考 | 遇到新型故障无法分析 | AI 分析标注为"参考"，重大故障必须有人工分析过程 |
