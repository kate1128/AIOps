# AI 提效计划 - 私有化交付

> 将 AI 引入私有化交付全流程：Preflight 环境检查自动化、配置适配 AI 辅助、部署故障 AI 诊断、交付文档自动生成。目标：单次交付周期从平均 2 天缩短到 1 天，交付后技术支持工单减少 40%。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| Preflight 环境检查 | 1-2 小时/客户 | 交付工程师 | 手动检查 CPU/内存/GPU/K8s 版本/网络，依赖经验，漏检多 |
| 配置文件适配 | 0.5-2 小时/客户 | 交付工程师 | 每个客户环境不同（不同 GPU/存储/网络），手动修改 values.yaml 易出错 |
| 部署执行与调试 | 2-8 小时/客户 | 交付工程师 + 研发 | 错误信息不直观，排查靠经验，新人容易卡壳 |
| 交付验收文档 | 1-2 小时/次 | 交付工程师 | 重复填写模板，客户环境信息需手动记录 |
| 交付后技术支持 | 每次 30-120 分钟 | 交付 + 研发 | 客户环境日志无法直接访问，远程诊断效率低 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **Shell + Claude API** | Preflight 报告生成、日志诊断 | ❌ 未接入 | 低 | Claude API 成本 |
| **Helm values 模板 + Claude** | 配置文件适配生成 | ❌ 未接入 | 低 | 已有 |
| **Dify（自托管）** | 交付知识库，FAQ/Runbook 查询 | ❌ 未部署 | 中 | 可自托管 |
| **飞书 Bot** | 交付状态播报、问题分诊 | 🟡 部分使用 | 低 | 已有 |

---

## 三、高价值机会点详细方案

### 机会1：Preflight 环境检查 AI 报告

**当前状态**：交付工程师到达客户现场或远程后，手动检查环境是否满足要求，依赖经验记忆，经常遗漏关键检查项。  
**目标状态**：运行一键 Preflight 脚本，AI 自动汇总检查结果并输出人类可读的差距报告，列出需要客户配合处理的事项。

**方案设计**：
```
#!/bin/bash
# preflight-check.sh

echo "=== SmartVision 私有化部署 Preflight 检查 ==="

# 1. 基础资源检查
echo "[资源检查]"
kubectl get nodes -o json | jq '[.items[] | {
  name: .metadata.name,
  cpu: .status.capacity.cpu,
  memory: .status.capacity.memory,
  gpu: .status.capacity["nvidia.com/gpu"]
}]'

# 2. GPU 驱动版本检查
echo "[GPU 驱动]"
kubectl get pods -n gpu-operator -o wide 2>/dev/null || echo "GPU Operator 未安装"

# 3. 存储类检查
echo "[存储类]"
kubectl get storageclass

# 4. 网络连通性检查（容器能否访问镜像仓库）
echo "[镜像仓库连通]"
kubectl run --rm -it test-connectivity \
  --image=busybox --restart=Never \
  -- wget -q --timeout=5 ${HARBOR_URL}/v2/ -O- 2>&1 | head -3

# 5. 汇总结果发给 Claude 分析
RESULT=$(上述检查结果 JSON 汇总)

REPORT=$(curl https://api.anthropic.com/v1/messages \
  -d "{\"model\":\"claude-3-5-haiku-20241022\",
       \"messages\":[{\"role\":\"user\",\"content\":\"
  作为私有化部署专家，分析以下检查结果，
  判断是否满足 SmartVision 部署要求（4核16G/GPU可选/10GB存储）：
  ${RESULT}
  
  输出格式：
  ✅ 已满足 / ❌ 不满足 / ⚠️ 建议优化，每项一行
  最后列出：需要客户处理的事项（按优先级）\"}]}")

echo "${REPORT}"
```

**工具栈**：Shell + kubectl + Claude API（haiku 模型，低成本）  
**前置条件**：有标准化 Preflight 检查项清单；Claude API Key  
**实施周期**：3-5 天  
**ROI 估算**：环境检查从 1-2 小时减少到 15 分钟，且覆盖更全

---

### 机会2：配置适配 AI 辅助生成

**当前状态**：每个客户环境不同（GPU 型号/存储类/CPU 架构/网络域名），需要修改大量 Helm values 字段，手动修改容易出错，且依赖资深工程师经验。  
**目标状态**：输入客户环境信息，AI 自动生成对应的 values.yaml，并高亮与默认配置的差异。

**方案设计**：
```
Prompt 模板（交付工程师填写客户信息后执行）：

"你是 SmartVision 私有化部署专家，根据以下客户环境信息，
生成适配的 Helm values.yaml 配置。

客户环境：
- K8s 版本：{k8s_version}
- GPU：{gpu_type} × {gpu_count}（如 A100 × 4 / RTX4090 × 8）
- 存储类：{storage_class}（如 local-path / ceph-rbd）
- 内网镜像仓库：{registry_url}
- 模型存储路径：{model_storage}（NFS 或 MinIO 地址）
- 是否离线环境：{offline: true/false}

基础 values.yaml：{template_content}

请生成：
1. 完整的 values.yaml（仅修改需要适配的字段）
2. 与默认配置差异说明（2-3 句话）
3. 注意事项（如该 GPU 型号的驱动版本要求）"

输出后，交付工程师 Review 差异说明（5分钟）后执行部署
```

**工具栈**：Claude API + Dify（可视化表单界面，更友好）  
**前置条件**：有标准化 values.yaml 模板；常见客户环境类型有案例库  
**实施周期**：1 周（含 Dify 表单搭建）  
**ROI 估算**：配置适配从 0.5-2 小时减少到 10 分钟；配置错误导致的返工减少 70%

---

### 机会3：部署失败 AI 诊断

**当前状态**：部署过程中出现 Pod 异常/服务启动失败时，工程师需要逐条分析错误日志，新人经常找不到根因，需要升级给资深工程师，效率低。  
**目标状态**：部署失败时，一键 AI 诊断，输出根因和下一步操作命令。

**方案设计**：
```
#!/bin/bash
# deploy-diagnose.sh <namespace>

NS=${1:-smartvision}

echo "正在采集诊断信息..."

# 获取所有异常 Pod 状态
ABNORMAL_PODS=$(kubectl get pods -n ${NS} \
  --field-selector='status.phase!=Running' -o json 2>&1)

# 获取异常 Pod 的最近日志和事件
for POD in $(kubectl get pods -n ${NS} \
  --no-headers | grep -v "Running\|Completed" | awk '{print $1}'); do
  echo "--- ${POD} Events ---"
  kubectl describe pod ${POD} -n ${NS} | tail -20
  echo "--- ${POD} Logs (last 50 lines) ---"  
  kubectl logs ${POD} -n ${NS} --tail=50 2>&1 || echo "无法获取日志"
done

# 发送给 Claude 诊断
DIAGNOSIS=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: ${CLAUDE_API_KEY}" \
  -d "{\"model\":\"claude-3-5-sonnet-20241022\",
       \"max_tokens\": 1024,
       \"messages\":[{\"role\":\"user\",\"content\":\"
  作为 K8s 部署专家，分析以下 Pod 异常信息：
  ${ABNORMAL_PODS}
  
  请输出：
  1. 根因判断（1-2 句话）
  2. 下一步操作命令（直接可执行）
  3. 如果是已知的私有化交付常见问题，给出完整解决方案\"}]}")

echo "${DIAGNOSIS}"
```

**工具栈**：Shell + kubectl + Claude API  
**前置条件**：交付环境能访问 Claude API（或使用离线 LLM 如本地 Ollama）  
**实施周期**：2-3 天  
**ROI 估算**：部署排错从 1-4 小时减少到 15-30 分钟；新人自主解决率从 30% 提升到 70%

---

### 机会4：交付验收报告自动生成

**当前状态**：部署完成后，需要手动填写交付报告（客户环境信息/服务状态/性能指标），这类重复劳动耗时且枯燥，容易出错。  
**目标状态**：部署完成后，脚本自动采集环境和服务状态，AI 生成专业的交付验收报告。

**方案设计**：
```
部署成功后自动触发报告生成：

采集信息：
  - 客户名称/项目名（参数传入）
  - 集群节点信息（CPU/内存/GPU 规格）
  - 所有服务 Pod 状态（Running/实例数）
  - 关键服务健康检查（API /health 响应时间）
  - 部署的镜像版本（每个服务）
  - 实际资源使用情况（kubectl top）

AI 生成报告（Markdown）：
  # SmartVision 私有化部署交付验收报告
  
  **客户**：{client_name}
  **交付日期**：{date}
  **版本**：v{version}
  **交付工程师**：{engineer}
  
  ## 部署环境
  | 节点 | CPU | 内存 | GPU | 状态 |
  |------|-----|------|-----|------|
  | ...  | ... | ...  | ... | ...  |
  
  ## 服务状态
  | 服务 | 实例数 | 状态 | 版本 |
  |------|--------|------|------|
  | ...  | ...    | ✅   | ...  |
  
  ## 验收测试结果
  ...
  
  ## 注意事项与后续支持
  ...
```

**工具栈**：Shell + kubectl + Claude API + Markdown  
**前置条件**：标准交付报告模板定义好  
**实施周期**：1 周  
**ROI 估算**：交付文档从 1-2 小时减少到 10 分钟；文档专业度提升

---

## 四、实施路径

### Phase 0（第 1-2 周）：立即可用工具

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| Preflight 脚本 + AI 报告 | 编写 preflight-check.sh，接入 Claude | 下次交付使用并验证 | 交付工程师 |
| 部署失败诊断脚本 | 编写 deploy-diagnose.sh | 能正确诊断 TOP 5 常见部署失败原因 | 交付工程师 |

### Phase 1（第 3-4 周）：配置适配能力

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 标准化 values.yaml 模板 | 整理各 GPU/存储类型的 values 模板 | 覆盖 90% 客户场景 | 研发 + 交付 | 历史交付案例整理 |
| 配置适配 Dify 表单 | Dify 搭建配置生成工作流 | 10 分钟内生成适配配置 | 交付工程师 | Dify 已部署 |

### Phase 2（第 5-8 周）：知识库与支持能力

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 交付知识库建设 | 历史问题解决方案录入 Dify 知识库 | 覆盖 50+ 常见问题 | 交付工程师 | Dify 部署完成 |
| 验收报告自动生成 | 部署完成后自动生成报告 | 减少手动填写时间 90% | 交付工程师 | 报告模板标准化 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（Preflight + 诊断 + 配置 + 报告）| ~¥100-200/月 | 约 6-10 人天/月（按每月 4 次交付估算）| 极高 |
| Dify 自托管 | 运维 0.5 人天/月 | 配置错误返工减少 | 极高 |
| **合计** | **~¥200-300/月** | **约 8-12 人天/月** | **约 1:20** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| 客户环境无外网（AI API 不可用）| Preflight/诊断工具无法使用 AI 能力 | 离线场景使用 Ollama + qwen2.5:7b 本地模型；或提前在有网环境生成模板 |
| 配置 AI 生成错误（如存储类名称写错）| 部署失败 | AI 配置必须经工程师 Review 后才能使用；关键字段有注释说明 |
| 诊断脚本采集到客户敏感信息 | 数据合规风险 | 脚本明确排除 Secret 内容；不上传完整日志，只发送关键 error 片段 |
| 新工程师过度依赖 AI 诊断 | 工程师自身能力不提升 | AI 诊断结果附上解释（为什么这样判断），促进学习而非依赖 |
