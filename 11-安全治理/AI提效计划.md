# AI 提效计划 - 安全治理

> 将 AI 引入漏洞定级、威胁检测、合规检查和事件响应，目标：CVE 误报率从 ~70% 降至 ~20%，安全告警有效率从低提升到 >60%，合规审计时间从季度人工减少 80%。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| CVE 漏洞处理 | 1-4 小时/个（含误报判断）| 研发/运维 | Trivy 误报多，人工逐个判断攻击路径是否可达 |
| K8s 配置安全检查 | 季度人工 Review | 运维/架构 | 靠人工记忆，privileged 容器等问题遗漏多 |
| Secret 泄露检测 | 依赖 gitleaks 有时失效 | 研发/运维 | 扫描规则有时漏检，API Key 格式多样 |
| 安全事件响应 | 1-4 小时/次 | 运维 + 研发 | 响应流程不清晰，依赖经验 |
| 等保/合规审计准备 | 1-2 周/次 | 运维负责人 | 手动收集证据，文档整理耗时 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **Trivy + Claude API** | CVE 上下文分析，去除误报 | 🟡 Trivy 已部分部署 | 中 | Claude API 成本 |
| **gitleaks** | Secret 泄露检测 | 🟡 部分使用 | 低 | 开源免费 |
| **Kyverno** | K8s 配置安全策略执行 | ❌ 未使用 | 中 | 开源免费 |
| **Falco** | 容器运行时异常行为检测 | ❌ 未评估 | 中 | 开源免费 |
| **Claude API** | 威胁分析、响应 SOP 生成、合规报告 | 🟡 个人使用 | 低 | ~¥200-400 |

---

## 三、高价值机会点详细方案

### 机会1：CVE 漏洞智能定级（减少误报）

**当前状态**：Trivy 每次扫描输出大量 CRITICAL CVE，但大多数在当前部署环境中不可利用，研发被误报淹没。  
**目标状态**：每个 CVE 经过 AI 上下文分析后，输出实际可利用性评级，真正需要处理的仅占 20-30%。

**方案设计**：
```
Trivy 扫描 → JSON 输出 → Claude API 逐个分析 → 分级结果

AI 分析每个 CRITICAL/HIGH CVE 的维度：
  1. 攻击路径：本地/网络/物理？
     - 需要本地访问的漏洞在容器内几乎无实际风险
  2. 依赖包是否实际使用了有漏洞的代码路径？
     - 例：log4shell 只在使用 lookup 功能时有风险
  3. 当前部署是否有缓解措施？
     - WAF/网络隔离/AppArmor/seccomp
  4. 是否有 PoC（公开利用代码）？
     - 有 PoC 的漏洞实际风险更高

AI 输出分级：
  🔴 立即修复（1周内）：远程可利用 + 有 PoC + 无缓解
  🟡 计划修复（本月内）：可利用但有缓解 / 本地攻击面
  ⚪ 可接受风险（下次版本升级时）：不可达攻击路径

Prompt 示例：
  "分析以下 CVE 在当前环境的实际风险：
   CVE: {cve_id}，CVSS: {score}，描述: {description}
   攻击向量: {attack_vector}，需要权限: {privileges_required}
   当前部署环境：K8s 容器，不暴露此服务端口，有 NetworkPolicy 限制
   请给出：可利用性（高/中/低）+ 修复优先级 + 原因（2句话）"
```

**工具栈**：Trivy（已有）+ Claude API + GitLab CI  
**前置条件**：Trivy 已接入 CI；部署环境描述文档  
**实施周期**：1 周  
**ROI 估算**：CVE 处理量从全量变为 20-30%，节省研发 ~70% 的 CVE 处理时间

---

### 机会2：K8s 配置安全自动检查

**当前状态**：K8s 安全配置问题（privileged 容器/无 ReadOnly RootFS/ServiceAccount 过度权限）靠人工发现，漏检率极高。  
**目标状态**：每次部署自动检查，违规配置在进入生产前被拦截。

**方案设计**：
```
核心安全规则（Kyverno 策略）：

1. 禁止 privileged: true
   rule: disallow-privileged
   action: enforce（直接拦截）

2. 限制 hostPath 挂载
   rule: restrict-hostpath
   action: enforce（仅允许白名单路径）

3. 容器不得以 root 运行
   rule: require-non-root-user
   action: audit（先监控，1个月后enforce）

4. 禁止使用 default ServiceAccount（有过度权限）
   rule: disallow-default-sa
   action: audit

5. 镜像来源必须是内部 Harbor
   rule: require-internal-registry
   action: enforce

AI 增强：Kyverno 违规时，附上中文解释和修复示例
  "您的 Deployment 配置了 privileged: true，
   这允许容器获得宿主机级别权限，是高危配置。
   修复方法：删除 securityContext.privileged 字段，
   或改为 allowPrivilegeEscalation: false"
```

**工具栈**：Kyverno + Claude API（解释生成）  
**前置条件**：K8s ≥ 1.16；先在 audit 模式运行发现存量问题  
**实施周期**：1 周（Kyverno 部署+策略配置）  
**ROI 估算**：privileged 容器从有到零；K8s 安全基线从依赖人工 Review 到自动执行

---

### 机会3：Secret 泄露检测增强

**当前状态**：gitleaks 规则对某些私有 API Key 格式（如内部服务凭证）识别率低，存在漏检。  
**目标状态**：CI 中 AI 辅助分析代码变更，检测可能的凭证泄露模式，覆盖 gitleaks 的盲区。

**方案设计**：
```
gitleaks 扫描 + AI 补充分析

AI 补充检查场景（gitleaks 规则覆盖不好的）：
  1. 代码中的硬编码 IP + 端口 + 路径（可能是内部服务地址）
  2. 注释中的旧密码/临时凭证
  3. 配置文件中 password/secret/token 字段有非占位符值
  4. 环境变量赋值中的明显凭证（REDIS_PASSWORD=xxxx123）

Prompt：
  "检查以下代码变更 diff，识别可能的凭证泄露：
   {git_diff}
   重点关注：硬编码密码/API Key/连接字符串/内网地址
   输出：[是否有风险] [风险描述] [建议操作]
   注意：误报比漏报代价小，宁可多报"

CI 集成：
  1. gitleaks 正常运行（现有）
  2. 对 gitleaks 未发现问题的 MR，Claude 做补充扫描
  3. 发现可疑内容时：阻止合并 + 飞书通知安全负责人
```

**工具栈**：gitleaks（已有）+ Claude API + GitLab CI  
**前置条件**：gitleaks 已接入 CI  
**实施周期**：3-5 天  
**ROI 估算**：Secret 泄露事件减少 50%；CI 阶段发现，修复成本最低

---

### 机会4：安全事件响应 AI 辅助

**当前状态**：安全事件（API Key 泄露/入侵检测/异常访问）发生时，响应流程不清晰，依赖工程师经验，响应时间长。  
**目标状态**：安全告警触发时，AI 自动提供分级处置 SOP 和紧急措施清单。

**方案设计**：
```
安全告警 → AI 分析 → 飞书推送处置 SOP

告警类型 + AI 输出示例：

[API Key 泄露]
  "检测到 API Key 在公开 GitHub Repo 中出现
   
   立即操作（5分钟内）：
   1. 吊销该 API Key（链接：阿里云控制台 > 访问控制 > API Key）
   2. 生成新 Key，更新 K8s Secret：
      kubectl create secret generic api-key \
        --from-literal=key=NEW_KEY --dry-run=client -o yaml | \
        kubectl apply -f -
   
   排查操作（1小时内）：
   3. 检查该 Key 的使用日志（阿里云操作审计）
   4. 确认是否有异常 API 调用
   5. gitleaks 全仓库扫描：git log --all | gitleaks detect
   
   后续措施：
   6. 追查 Key 是如何进入代码库的（git blame）
   7. 添加 pre-commit hook 防止再次发生"

[Falco 异常容器行为]
  "容器 vllm-qwen-0 出现异常 shell 执行
   可能的入侵迹象，立即隔离处理..."
```

**工具栈**：Falco / Alertmanager + Claude API + 飞书 Bot  
**前置条件**：安全告警已接入 Alertmanager；有安全事件类型定义  
**实施周期**：1-2 周（SOP 库建立 + AI 对接）  
**ROI 估算**：安全事件响应时间从 1-4 小时减少到 < 1 小时；新人也能有效响应

---

## 四、实施路径

### Phase 0（第 1 周）：立即可以降低风险

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| CVE 误报过滤试跑 | 将最近一次 Trivy 报告（CRITICAL/HIGH）全部用 Claude 分析 | 识别出 ≥ 50% 为不可利用的误报 | 运维/安全 |
| Secret 扫描 AI 补充 | 对最近 20 个 MR 的 diff 用 Claude 做安全检查 | 发现 gitleaks 漏检的问题（验证价值）| 运维 |

### Phase 1（第 2-3 周）：自动化安全检查接入

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| CVE 定级 CI 自动化 | Trivy + Claude 定级 → MR 评论附分级报告 | 每次 MR 有 CVE 分级结果，真正需处理的占比 < 30% | DevOps + 运维 | Trivy 已在 CI |
| Kyverno 部署（audit）| 部署 Kyverno + 核心安全策略，audit 模式 | 扫描出所有 prod 违规配置 | 运维 | K8s ≥ 1.16 |
| Secret 扫描增强 | CI 中在 gitleaks 后增加 Claude 补充扫描 | Secret 泄露检测覆盖 gitleaks 盲区 | DevOps | gitleaks 已在 CI |

### Phase 2（第 4-6 周）：合规与事件响应

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| Kyverno enforce 模式 | 存量违规修复后，privileged 等高危策略切 enforce | privileged 容器数 = 0 | 运维 | 存量违规已修复 |
| 安全事件 SOP 库 | 整理 TOP 5 安全事件类型的处置 SOP，Dify 知识库化 | 告警触发时 AI 可推荐对应 SOP | 运维/SRE | Dify 已部署 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（CVE分析+代码扫描+事件响应）| ~¥300-500 | 约 6-10 人天/月 | 极高 |
| Kyverno（开源）| 运维 0.5 人天/月 | 配置安全长期节省响应成本 | 极高 |
| Falco（开源）| 运维 1 人天/月（规则调优）| 入侵检测能力从无到有 | 极高 |
| **合计** | **~¥400-600/月** | **约 8-12 人天/月** | **约 1:12** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| AI 将高危 CVE 判定为误报 | 真实漏洞未修复，安全事件 | AI 只做降级（降低误报），CVSS ≥ 9.0 的漏洞不允许降级 |
| Kyverno enforce 模式阻塞紧急发布 | 紧急变更无法上线 | 保留 break-glass 旁路；紧急情况运维 Leader 审批后可临时排除 |
| Secret 扫描误报影响开发效率 | 开发忽略安全告警（狼来了效应）| 严格控制误报率 < 10%；误报多时先调为 warning 而非 block |
| 代码 diff 发送给 Claude API 泄露代码 | 知识产权风险 | 评估是否使用 Claude 企业版（数据不用于训练）或自托管 LLM |
