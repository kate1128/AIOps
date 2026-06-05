# SmartVision 工程体系建设与优化方案 合订本

> **文档说明**：本文是 产品在 Kubernetes AI SaaS 平台工程体系的完整合订本，涵盖 AI 基础设施、中间件治理、产品质量、可观测性、环境运维、备份容灾、SRE 稳定性工程、安全治理、版本发布、私有化交付、License 授权、成本管理、知识管理 13 个核心领域的现状分析、建设方案、AI 提效落地与量化指标。
>
> **技术底座**：Kubernetes 多环境（dev/pre/prod）+ GitLab CI/CD + Prometheus/Grafana/Loki/Tempo + vLLM（Qwen2.5-Coder-32B） + Harbor 三级镜像仓库 + 飞书协作
>
> **阅读建议**：可按领域跳读，也可全文阅读以理解各领域间的上下游联动关系。

---

## 目录

1. [产品需求管理](#一产品需求管理)
2. [架构治理](#二架构治理)
3. [CI/CD 建设](#三cicd-建设)
4. [AI Infra 基建](#四ai-infra-基建)
5. [中间件治理](#五中间件治理)
6. [产品质量保障](#六产品质量保障)
7. [可观测性体系](#七可观测性体系)
8. [环境运维](#八环境运维)
9. [备份容灾](#九备份容灾)
10. [SRE 稳定性工程](#十sre-稳定性工程)
11. [安全治理](#十一安全治理)
12. [版本发布管理](#十二版本发布管理)
13. [私有化交付](#十三私有化交付)
14. [License 授权管理](#十四license-授权管理)
15. [成本管理](#十五成本管理)
16. [知识管理](#十六知识管理)
17. [跨领域联动总图](#十七跨领域联动总图)

---

# 一、产品需求管理

> 需求管理是产品团队的核心工作流——需求从哪来、怎么评优先级、怎么写 PRD、怎么评审、怎么追踪到上线。任何环节失控都会直接导致研发资源浪费和交付质量下降。

## 1.1 现状评估

| 子维度 | 当前状态 | 主要痛点 | 影响 |
|--------|---------|---------|------|
| **需求收集** | 🔴 无统一入口 | 需求来自飞书消息/邮件/口头，散落多渠道，容易遗漏 | 重要需求丢失，资源分散 |
| **优先级管理** | 🔴 无框架 | 依赖 PM 个人判断，RICE 模型未落地 | 研发做了低价值的需求 |
| **PRD 规范** | 🟡 有模板不统一 | 各 PM 格式不一，缺验收标准，研发理解偏差 | 开发返工频繁 |
| **需求评审** | 🟡 有但不规范 | 参与人不固定，结论无书面记录 | 评审遗漏问题上线后暴露 |
| **路线图** | 🔴 无 | 团队对未来 1-3 个月方向不清晰 | 跨团队协作难对齐 |
| **需求追踪** | 🟡 Jira 有记录 | 状态更新滞后，跨团队不可见 | 需求"消失"无感知 |

**典型问题场景**

- **需求遗漏**：客户通过飞书群发来一个高优功能请求，PM 当时回复了但忘记录入 Jira。两周后客户追问，PM 才发现漏掉了，不得不插单打乱迭代节奏。
- **PRD 理解偏差**：UI 原型有，但边界情况描述不清。研发按自己理解实现后，测试阶段发现与 PM 预期不符，返工 3 天。验收标准缺失是根本原因。
- **路线图不透明**：销售承诺客户某功能"下个版本上线"，但研发侧该需求排在 3 个迭代之后，双方信息不对称导致承诺无法兑现，影响客户关系。

## 1.2 建设方案

### 需求统一收集入口（飞书多维表格 + n8n）

```
需求来源（多渠道）
  ├── 飞书表单（内部需求提报）
  ├── 飞书群关键词监听（n8n 自动检测"需求"/"建议"/"问题"关键词）
  └── 邮件转发到指定地址自动入库

Claude API 自动分类打标：
  - 功能模块（AI问答/文档管理/权限/性能/其他）
  - 需求类型（新功能/优化/Bug/技术债）
  - 影响用户群
  - 初步优先级（P0-P2）
  - 相似需求去重提示（Embedding 相似度检索）

→ 自动写入飞书多维表格（需求池）
→ PM 每周 Review 确认优先级
```

### RICE 优先级评分模型

| 字段 | 说明 | 评分范围 |
|------|------|---------|
| **Reach（覆盖）** | 每迭代影响多少用户/客户 | 1-100 |
| **Impact（影响）** | 对目标的提升程度 | 0.25/0.5/1/2/3 |
| **Confidence（置信度）** | 对估算的把握程度（%） | 20%-100% |
| **Effort（工作量）** | 研发人天 | 实际值 |

`RICE = (Reach × Impact × Confidence) / Effort`，分值越高优先级越高。

### PRD 模板核心结构

```markdown
## 需求背景
- 解决什么问题（用户痛点，2-3 句话）
- 不解决的后果

## 目标用户与使用场景

## 功能设计
- 主流程描述（步骤 + 流程图）
- 边界情况与异常处理

## 验收标准（Given-When-Then 格式）
- Given：前置条件
- When：用户操作
- Then：期望结果（可量化）

## 非功能性要求（性能/安全/兼容性）

## 排期与依赖
```

**准入准出标准**：PRD 进入评审前必须有原型图 + 完整验收标准；评审通过才进入研发排期。

## 1.3 需求评审（四方评审制）

**固定参与方**：产品（主持）+ 研发 Lead + 测试 Lead + 设计

**评审记录**：飞书妙记自动转录 → AI 提炼决策摘要 + Action Items → 归档到对应 PRD 文档

**评审结论**：通过 / 通过（附条件）/ 驳回重做（必须说明原因）

## 1.4 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| 多渠道需求自动汇聚与分类 | n8n + Claude API → 飞书多维表格 | 2-3h/周手工 → 自动实时 |
| PRD 草稿辅助生成 | 需求描述 + 背景 → Claude 生成结构化初稿 | 1-2人天 → 0.5人天 |
| 需求评审材料准备 | 相关背景/竞品/历史需求 → AI 汇总摘要 | 4-6h → 1h |
| 评审纪要自动整理 | 飞书妙记 → Claude 提炼决策 + Action Items | 1-2h → 10-15min |
| 优先级 AI 辅助 | 历史交付数据 + 客户反馈频率 → RICE 分数建议 | 主观判断 → 数据辅助 |

## 1.5 关键指标与建设路径

**Phase 0（第 1 个月）**：飞书收集入口上线 + RICE 模型推行 + PRD 模板统一
**Phase 1（第 2-3 月）**：四方评审固定化 + 季度路线图 + n8n 自动汇聚
**Phase 2（第 4-6 月）**：PRD AI 辅助 + 需求追踪闭环 + 数据驱动优先级

| 指标 | 当前值 | 目标 |
|------|--------|------|
| 需求收集覆盖率 | 估算 60% | > 95% |
| PRD 一次评审通过率 | 未采集 | > 80% |
| 需求变更率 | 较高 | < 20% |
| P0 需求交付周期 | 未采集 | < 7 天 |

---

# 二、架构治理

> 架构治理解决的核心问题：技术决策有没有记录、选型有没有依据、架构债有没有人管、服务间契约有没有约定。任何一项失控都会埋下长期维护成本急剧上升的隐患。

## 2.1 现状评估

| 领域 | 当前状态 | 主要痛点 | 影响 |
|------|---------|---------|------|
| **架构评审** | 🔴 无正式机制 | 架构决策靠个人口头对齐，无 ADR 记录 | 新成员不了解历史决策，重复踩坑 |
| **技术选型** | 🟡 有讨论无规范 | 无标准对比矩阵，选型结论不落文档 | 不同团队重复评估相同技术 |
| **架构债管理** | 🔴 无管理 | 技术债靠主观感知，无量化趋势 | 维护成本持续上升，重构时机难判断 |
| **API 契约** | 🟡 部分服务有文档 | 无版本兼容规范，破坏性变更靠人工发现 | 联调返工频繁 |

**典型问题场景**

- **架构决策无记录**：某服务当初为什么选 Kafka 而不是 RocketMQ？选型会议没有文字记录，半年后新人无法了解背景，同类讨论重来一次。
- **技术债隐形积累**：某模块圈复杂度长期偏高，靠老员工消化。没有客观数字，直到新需求进不去才发现已是 P0 技术债。
- **API 破坏性变更上线**：后端删除了一个旧字段，认为前端不再使用，上线后 App 端报错，紧急热修复。

## 2.2 建设方案

### 架构评审：ADR 制度

**ADR（Architecture Decision Record）** 是每个重要技术决策的标准记录格式。

```markdown
# ADR-{编号}：{决策标题}

## 状态：草稿 / 已接受 / 已废弃

## 背景
为什么要做这个决策，当时的约束条件是什么。

## 候选方案
| 方案 | 优点 | 缺点 |
|------|------|------|
| 方案 A | ... | ... |
| 方案 B | ... | ... |

## 决策
选择方案 A，理由：...

## 影响
- 对现有系统的变更点
- 需要同步的团队
- 后续行动项
```

**触发条件（必须写 ADR）**：引入新数据库/中间件、重大服务拆合、与外部系统集成协议、破坏性 API 变更。

### 技术选型：标准化对比矩阵

新技术引入必须填写六维评估表：

| 维度 | 权重 | 评分标准 |
|------|------|---------|
| 社区活跃度 | 20% | Stars/Commit 频率/维护者背景 |
| 技术成熟度 | 25% | 版本状态/生产案例/企业背书 |
| 团队熟悉度 | 15% | 已有经验/学习成本估算 |
| 生态集成 | 20% | 与现有技术栈兼容性 |
| License | 10% | 商业友好度（Apache/MIT/GPL）|
| 性能与安全 | 10% | 基准测试数据/CVE 历史 |

进入"核心区"的技术需经架构评审；"候选区"团队可自由探索但不得在生产直接使用。

### 架构债管理：量化（SonarQube）

```
每次代码 Push → SonarQube 自动扫描（K8s 自托管）
  ↓ 积累历史趋势
  ↓ 指标：bugs数 / 技术债时长(分钟) / 圈复杂度 / 测试覆盖率
  ↓ 月度 AI 报告（Claude 分析 Top 3 服务债务趋势 → 飞书推送）
```

**债务处理策略**：P0（阻碍业务迭代）立即排期 → P1 下个迭代消减 → P2 每迭代预留 20% 容量 → P3 按需处理。

### API 契约管理：oasdiff 破坏性变更检测

```yaml
# CI 自动对比 OpenAPI 文件（MR 时触发）
api-contract-check:
  stage: lint
  script:
    - oasdiff breaking origin/main HEAD
  # 发现 Breaking Change → MR 失败，必须明确标注版本并评审
```

规范：所有服务间 API 必须定义 OpenAPI 3.0 规范，纳入 Git 版本管理；破坏性变更必须走 ADR 评审 + MAJOR 版本升级。

## 2.3 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| ADR 草稿辅助 | 架构师描述背景 + 候选方案 → Claude 生成结构化 ADR 初稿 | 1-2h → 20-30min |
| 技术债 AI 月报 | SonarQube 数据 → Claude 分析 Top 3 服务趋势 + 优先级 | 季度手工 → 月度自动 |
| 选型对比 AI 辅助 | 技术名称 + 使用场景 → Claude 输出对比矩阵初稿 | 3-5h → 1-2h |
| API 兼容性说明 | 破坏性变更列表 → Claude 生成迁移指南 | 2-4h → 30min |

## 2.4 建设路径

**Phase 0（第 1-2 周）**：ADR 模板发布 + oasdiff CI 集成 + SonarQube 部署
**Phase 1（第 3-4 周）**：技术选型矩阵推广 + 存量重大决策补录 ADR
**Phase 2（第 5-8 周）**：技术债 AI 月报 + 架构评审会机制固化

| 指标 | 当前值 | 目标 |
|------|--------|------|
| 重大技术决策有 ADR 记录率 | ~5% | > 95% |
| API 破坏性变更漏检率 | 高（人工）| 0（oasdiff 自动拦截）|
| 技术债月度量化覆盖率 | 0% | > 80% 服务 |

---

# 三、CI/CD 建设

> 整套体系完全依托内网 **GitLab** 构建。GitLab 是代码仓库、CI/CD 引擎、发布审批入口，所有工具通过 GitLab CI 或 GitLab API 集成，不依赖任何外部 SaaS 服务。

## 3.1 现状评估

| 环节 | 当前状态 | 核心痛点 | 影响 |
|------|---------|---------|------|
| **代码提交** | 🔴 无检查 | Secret 可直接提交进 Git | 凭据泄露风险 |
| **CI 流水线** | 🟡 各服务自维护 | 质量门禁标准不一，安全扫描形同虚设 | 发布质量参差 |
| **镜像构建** | 🟡 无规范 | `latest` 滥用，镜像来源不可追溯 | 回滚无法确定版本 |
| **安全扫描** | 🟡 部分接入 | Trivy ~70% 误报率，工程师疲于处理 | 真正风险被忽视 |
| **部署** | 🔴 手动操作 | 无 GitOps，集群状态与 Git 不一致 | 回滚靠经验，风险高 |
| **发布治理** | 🔴 无流程 | 发布前核查靠人脑，DORA 指标未采集 | 频繁发布事故 |

## 3.2 标准流水线架构（五层质量门禁）

```
feature 分支：lint 检查
  ↓（Code Review 合并）
dev 分支：lint + SonarQube + gitleaks + oasdiff → 自动部署 dev
  ↓（验证通过合并）
pre 分支：以上 + Trivy 扫描 + LLM CVE 定级 → 自动部署 pre
  ↓（验证通过合并）
main 分支：以上 + preflight 核查 + LLM 发布摘要（不自动部署）
  ↓（打 Tag）
Tag v*.*.*：FTP 制品推送 → 飞书审批卡片 → 人工确认 → 手动部署 prod
```

## 3.3 镜像 Tag 命名规范

```
dev 环境：  {service}:dev_{short_sha}
pre 环境：  {service}:pre_{short_sha}
main 环境： {service}:main_{short_sha}
生产发布：  {service}:release_{tag}
            {service}:latest
```

**三套 Harbor 镜像仓库**：`harbor-dev.internal` / `harbor-pre.internal` / `harbor.internal`（生产）

## 3.4 关键阶段说明

**gitleaks（提交即检测）**：
```yaml
secret-scan:
  script: gitleaks detect --source . --report-format json
  allow_failure: false  # Secret 发现 → CI 失败
```

**Trivy + LLM CVE 定级（pre 阶段）**：
```
Trivy JSON 报告 → Claude API 过滤误报 → 精简到 5-10 条关键 CVE
Critical CVE > 0 → 构建失败 + 飞书通知 Security Lead
效果：误报率 ~70% → ~20%
```

**LLM 发布摘要（main 阶段）**：
```
commit log + diff 统计 + SonarQube delta
  → Claude API 生成：功能列表 / 风险点 / 建议发布窗口
  → Pipeline 注释 + 飞书通知
```

**飞书审批卡片（Tag 阶段）**：
```json
{
  "版本": "v1.2.3",
  "变更摘要": "LLM 生成的摘要",
  "Trivy 结果": "通过（0 个 Critical）",
  "发布窗口建议": "周二/四 10:00-11:00",
  "操作": ["✅ 批准发布", "❌ 拒绝"]
}
```

## 3.5 DORA 指标追踪

```
Deployment Frequency：GitLab API 统计每周 deploy-prod 次数
Lead Time for Changes：MR 创建时间 → deploy-prod 完成时间
Change Failure Rate：发布后 1h 内触发 P0/P1 告警比例
MTTR：故障时间 → 热修复 deploy-prod 完成时间
→ Prometheus 自定义指标 → Grafana DORA Dashboard
```

## 3.6 GitLab CI 关键变量配置

| 变量名 | 类型 | 用途 |
|-------|------|------|
| `HARBOR_URL_DEV/PRE/PROD` | Variable | 三套 Harbor 仓库地址 |
| `HARBOR_USER/PASS_*` | Variable（Masked）| Harbor 认证凭据 |
| `KUBECONFIG_DEV/PRE/PROD` | **File** | K8s 集群访问凭据（File 类型，不是 Variable）|
| `FEISHU_WEBHOOK` | Variable（Masked）| 飞书通知 Webhook |
| `SONAR_TOKEN` | Variable（Masked）| SonarQube 分析 Token |
| `FTP_HOST/USER/PASS` | Variable（Masked）| 制品 FTP 服务器 |

> **注意**：KUBECONFIG 必须设置为 **File 类型**，不能用 Variable，否则 kubectl 无法正确读取。

## 3.7 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| CVE 误报过滤 | Trivy + Claude 定级过滤 | 误报率 70% → 20% |
| Pipeline 失败根因分析 | 失败日志 → Claude 分析 → MR 评论 | 10-30min → 5min |
| 发布摘要 AI 生成 | commit log → Claude → 发布摘要 + 风险提示 | 30-60min → 5min |
| oasdiff 破坏性变更说明 | Breaking Change 列表 → Claude 生成迁移说明 | 1-2h → 15min |

## 3.8 建设路径

**Phase 0（第 1-2 周）**：gitleaks 全服务接入 + Trivy AI 分类 + 镜像 Tag 规范推行
**Phase 1（第 3-4 周）**：LLM 发布摘要 + preflight 核查 + KUBECONFIG 迁移到 File 类型
**Phase 2（第 5-8 周）**：DORA 指标 Dashboard + 飞书审批卡片 + Pipeline 失败 AI 分析

| 指标 | 当前值 | 目标 |
|------|--------|------|
| Trivy CVE 有效率 | ~30% | > 80% |
| Secret 泄露 CI 拦截率 | 0% | 100% |
| 发布前核查完成率 | ~50% | > 95% |
| DORA 部署频率 | < 1次/周 | > 2次/周 |

---

# 四、AI Infra 基建

> AI Infra 基建是 产品差异化的核心——GPU 资源是否被充分利用、推理服务是否稳定高效、模型资产是否有治理，直接决定 AI 功能的交付速度和服务质量。

## 1.1 现状评估

| 子域 | 当前状态 | 主要痛点 | 影响 |
|------|---------|---------|------|
| **GPU 可观测** | 🔴 DCGM 未部署 | 无 SM 利用率/显存/温度时序指标，GPU 空跑无法主动发现 | 每月浪费大量 GPU 算力 |
| **GPU 调度** | 🟡 HAMI 已部署 | 宿主机裸进程绕过 HAMI 管控，Quota 形同虚设 | 资源争抢时无依据，故障难定位 |
| **推理服务** | 🟡 vLLM 多实例运行 | 无统一部署规范，版本分散，参数靠经验试调 | 性能不稳定，运维成本高 |
| **AI 模型治理** | 🔴 无 | 模型版本无记录，无 A/B 测试框架，模型来源不可追溯 | 生产模型出问题无法快速回滚 |

**典型问题场景**

- **GPU 空跑**：Qwen2.5-Coder-32B 在夜间业务低谷期仍占用 4 张 A100（每张显存 80GB），利用率不足 5%。因无 DCGM 指标，运维不知道空跑，每月多消耗约 2 万元算力成本。
- **裸进程绕过 HAMI**：某研究员直接 `nvidia-smi` 确认有空闲 GPU 后，在节点上手动运行 `python train.py`，占用了 2 张 GPU，导致 vLLM 推理服务显存不足 OOM。HAMI 完全不知道这个裸进程的存在。
- **模型无法回滚**：某次更新了 Qwen2.5 fine-tuned checkpoint 后，某类推理请求质量下降。因为旧版本已被覆盖（MinIO 无版本控制），只能重新触发训练，耗时 3 天。

## 1.2 建设方案

### GPU 可观测（DCGM）

```
DCGM Exporter（每台 GPU 节点，DaemonSet）
  ↓ 暴露指标到 /metrics
Prometheus 采集（30s 间隔）
  ↓ 存储时序数据
Grafana Dashboard（GPU Fleet 总览 + 单节点详情）
  ↓ 告警规则（SM利用率/温度/显存）
Alertmanager → 飞书 OnCall
```

**关键指标**：
- `DCGM_FI_DEV_GPU_UTIL`：SM 利用率（%）
- `DCGM_FI_DEV_MEM_USED`：已用显存（MiB）
- `DCGM_FI_DEV_GPU_TEMP`：GPU 温度（°C）
- `DCGM_FI_DEV_POWER_USAGE`：功耗（W）

### 裸进程检测

```
Node Exporter process_collector（每分钟扫描）
  → 检测 python/torch/nvidia-smi 等进程
  → 不在 K8s cgroup 中的进程 = 裸进程
  → Prometheus 规则：裸进程存在 > 5 分钟 → 告警
  → 飞书通知：节点名/进程名/用户/PID/GPU 显存占用
  → 自动终止（可选，需人工确认）
```

### vLLM 标准化部署规范

| 配置项 | 推荐值（A100 80G × 4）| 说明 |
|-------|---------------------|------|
| `tensor_parallel_size` | 4 | 张量并行，充分利用多卡带宽 |
| `max_model_len` | 8192 | 最大上下文长度，超出截断 |
| `gpu_memory_utilization` | 0.90 | 预留 10% 显存给 KV Cache 溢出 |
| `max_num_seqs` | 256 | 最大并发序列数 |

### 模型治理（MLflow + MinIO）

```
模型注册流程：
  训练/微调完成 → mlflow.log_model() 注册到 MLflow Model Registry
    → 记录：版本号/训练参数/评估指标/数据集 hash
    → 存储到 MinIO（s3://models/{model_name}/{version}/）
    → MinIO 开启版本控制（防误删）

生产部署流程：
  MLflow Registry "Production" 标签 → Helm values 引用模型路径
  → 支持一键回滚（切换到上一个 Production 版本）
```

## 1.3 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| GPU 利用率 AI 月报 | DCGM 数据 → Claude 分析 → 优化建议 + 节省估算 | 月度手工盘点 → 自动日报 |
| 裸进程自动发现 | 告警 + 飞书通知（含用户/进程信息）| 人工巡检 → 分钟级发现 |
| vLLM 参数 AI 推荐 | 当前负载 + 显存数据 → Claude 推荐最优参数 | 人工调参 2-4h → 10min |
| 模型性能自动评估 | 新版本部署后自动运行 benchmark → 对比历史版本 | 人工评估 2-4h → 自动 30min |

## 1.4 关键指标与建设路径

**Phase 0（第 1-2 周）**：DCGM 部署 + 裸进程检测 + MLflow 接入
**Phase 1（第 3-4 周）**：vLLM 规范化 + GPU 利用率告警 + 模型 A/B 测试框架
**Phase 2（第 5-8 周）**：GPU 优化月报 AI 生成 + 参数自动推荐

| 指标 | 当前值 | 目标 |
|------|--------|------|
| GPU 平均利用率 | ~40% | > 70% |
| 裸进程发现时间 | 人工，可能数天 | < 5 分钟（自动）|
| 模型回滚时间 | 3 天（重训练）| < 1 小时（版本切换）|

---

# 五、中间件治理

> 中间件是支撑所有业务服务的技术底座——数据库、消息队列、网关、存储这些水电煤一旦不稳，整个产品体系都会受影响。治理目标是让基础设施从"靠运气"变成"靠工程"。

## 2.1 现状评估

| 子域 | 当前状态 | 主要痛点 | 影响 |
|------|---------|---------|------|
| **数据库** | 🟡 RDS 托管 + K8s 自建混合 | 无连接池（PgBouncer 未部署），高并发连接数飙升；慢查询无自动分析 | 偶发性 DB 连接耗尽 |
| **消息队列** | 🟡 Kafka + RabbitMQ 并存 | Kafka Consumer 堆积无自动告警，排查依赖人工经验 | 消息堆积 2-6 小时才发现 |
| **网关** | 🟡 Nginx Ingress 在用 | 无统一 API 管理，限流/认证各服务自己实现 | 接口保护参差不齐 |
| **监控覆盖** | 🟡 约 40% | 大量中间件无 Exporter | 故障靠人工发现 |

## 2.2 核心建设方案

### 数据库连接池（PgBouncer）

```
应用服务（多实例）
  ↓ 连接 PgBouncer（pgbouncer.db.svc.cluster.local:5432）
PgBouncer（池化管理，pool_mode=transaction）
  ↓ 按需建立真实连接
PostgreSQL RDS（max_connections=500 由此控制）
```

关键配置：
- `pool_mode = transaction`：事务级复用，适合短连接高并发
- `max_client_conn = 500`：应用侧最大连接数
- `default_pool_size = 20`：每个用户/数据库的默认连接池大小

### PostgreSQL 慢查询 AI 分析

```
pg_stat_statements 采集慢查询（mean_exec_time > 1s）
  ↓ Prometheus postgres_exporter 暴露
  ↓ 告警触发（慢查询次数 > 10/min）
  ↓ 自动执行 EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
  ↓ Claude API：识别顺序扫描/索引失效/锁等待
  ↓ 输出优化建议（索引 SQL / 查询改写 / 参数调整）
  ↓ 飞书推送（含慢 SQL + 建议 + 预期效果）
```

效果：1-4 小时手工分析 → 15 分钟 AI 分析

### Kafka 堆积 AI 诊断

```
kafka_exporter 采集 Consumer Group Lag
  ↓ 告警：kafka_consumer_lag > 10000 持续 5min
  ↓ 聚合上下文：Consumer Group 状态 + 消费/生产速率对比 + 近期发布记录
  ↓ Claude API 根因分类：消费者宕机 / 速率不足 / Rebalance 风暴
  ↓ 处置建议 → 飞书通知 OnCall
```

效果：2-6 小时排查 → 20-30 分钟（有 AI 建议）

## 2.3 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| PostgreSQL 慢查询分析 | pg_stat_statements + EXPLAIN + Claude | 1-4h → 15min |
| Kafka 堆积诊断 | kafka_exporter + 告警 + AI 根因分类 | 2-6h → 20-30min |
| 容量趋势预测 | `predict_linear()` + AI 月报 | 季度手动 → 自动月报 |
| 跨环境配置一致性 | 自动 diff 三套环境配置 + AI 标注差异风险 | 1-3h → 15min |

## 2.4 建设路径

**Phase 0（第 1-2 周）**：PgBouncer 部署 + postgres_exporter/kafka_exporter 补全 + 监控覆盖率 40% → 80%
**Phase 1（第 3-4 周）**：慢查询 AI 分析 + Kafka 堆积 AI 诊断 + 容量预测配置
**Phase 2（第 5-8 周）**：Dify 部署 + APISIX 试点 + 跨环境配置 diff

---

# 六、产品质量保障

> 质量不是测完才出来的，而是内建在开发流程中的。从需求到上线的每一个环节都应该有质量关卡。目标是让缺陷越来越少，让已有缺陷越来越快被发现、定位、修复。

## 3.1 现状评估

| 子域 | 当前状态 | 主要痛点 | 影响 |
|------|---------|---------|------|
| **缺陷流程** | 🟡 Jira 跟踪 | 缺陷指派依赖人工判断，转单 3 次常有 | 高优缺陷响应慢 |
| **测试策略** | 🔴 主要靠人工回归 | 自动化覆盖率 < 20% | 发布节奏受限（< 1 次/周）|
| **自动化测试** | 🟡 部分接口有脚本 | 脚本维护成本高，接口变更后易失效 | 自动化效果打折 |
| **性能测试** | 🔴 无常态化 | 只有大版本才做性能测试 | 性能问题到生产才暴露 |
| **度量体系** | 🟡 有数据无报告 | 质量数据散落，无统一看板 | 质量趋势不可见 |

## 3.2 测试金字塔

```
                ┌──────────────────┐
                │  E2E / UI 测试   │  ~10%（关键用户旅程）
               ─┴──────────────────┴─
            ┌──────────────────────────┐
            │    集成测试 / API 测试   │  ~30%（核心接口契约）
           ─┴──────────────────────────┴─
        ┌──────────────────────────────────┐
        │           单元测试               │  ~60%（业务逻辑）
       ─┴──────────────────────────────────┴─
```

**与 CI 联动**：
- `feature` 分支：单元测试 + API 测试必须全绿
- `pre` 分支：自动触发集成测试 + 性能基准对比
- `main`/Tag：E2E 冒烟测试 + 全量回归

## 3.3 缺陷流程规范化（AI 分类指派）

```
测试/用户提交 Bug（标题 + 复现步骤 + 截图）
  ↓ Claude API 分析：提取关键词 → 匹配模块归属映射表
  ↓ 自动推荐：模块 Owner + 优先级（P0/P1/P2）+ 相似历史缺陷
  ↓ Jira 自动预填写 → Owner 确认后正式指派
```

**缺陷优先级定义**：

| 级别 | 定义 | 响应时效 |
|------|------|---------|
| P0 | 生产服务不可用/数据丢失 | 30 分钟响应，4 小时修复 |
| P1 | 核心功能异常/高频路径阻断 | 4 小时响应，1 天修复 |
| P2 | 非核心功能/有 workaround | 1 天响应，当前迭代修复 |

## 3.4 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| 测试用例 AI 生成 | OpenAPI → Claude → pytest 测试框架 + 边界用例 | 2-4h → 30-60min |
| Bug 分类指派 | Claude 分析描述 → 匹配 Owner → Jira 预填 | 15-30min/单 → 2min |
| 根因分析辅助 | 失败 log + 堆栈 → Claude 定位文件行号 | 0.5-2h → 15-30min |
| 性能回归诊断 | k6 报告 + Prometheus → AI 自动对比解读 | 1-2h → 15min |

## 3.5 建设路径

**Phase 0（第 1-2 周）**：CI 强制测试 + 缺陷 P0-P3 工作流 + 质量看板
**Phase 1（第 3-4 周）**：AI 用例生成（核心 5 模块）+ Bug 分类 + 性能基准
**Phase 2（第 5-8 周）**：E2E 覆盖 + 质量周报自动化 + 缺陷逃逸率追踪

**目标指标**：自动化覆盖率 < 20% → > 60%；发布回归时间 2-3 天 → < 2 小时。

---

# 七、可观测性体系

> 可观测性是系统自证健康的能力。三大支柱（指标/日志/链路追踪）必须协同工作，才能在最短时间内定位根因、止损恢复。

## 4.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **指标监控** | 🟡 Prometheus + Grafana | 误报率 > 60%；中间件指标覆盖不足 |
| **日志** | 🔴 日志分散 | 各服务日志未统一，排查需逐个 Pod 查 |
| **链路追踪** | 🔴 未建设 | 跨服务问题无法快速定位 |
| **告警路由** | 🟡 只有邮件 | 飞书未接入，OnCall 不及时 |

## 4.2 统一可观测平台（Grafana Stack）

```
应用服务 / 中间件
  ├── Prometheus Exporter → Prometheus → Grafana（指标）
  ├── Promtail DaemonSet → Loki → Grafana（日志）
  └── OpenTelemetry SDK → Tempo → Grafana（链路追踪）

三支柱在 Grafana 中统一查询：
  Metrics 跳转 → Logs 跳转 → Traces（三维联动排障）

告警路由：Alertmanager → 飞书 Bot（告警卡片含 Grafana 直链 + OnCall 认领按钮）
```

## 4.3 告警降噪方案

```yaml
# 分层告警策略（减少误报）
groups:
  - name: infra.critical
    rules:
      - alert: ServiceDown
        expr: up{job="app"} == 0
        for: 5m         # 5 分钟确认，避免闪断误报

  - name: infra.warning
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
        for: 2m

# Alertmanager 分组（减少告警风暴）
group_by: ['alertname', 'cluster']
group_wait: 30s
repeat_interval: 4h
```

## 4.4 日志规范（结构化 JSON）

```json
{
  "timestamp": "2025-01-01T12:00:00Z",
  "level": "ERROR",
  "service": "user-api",
  "trace_id": "abc123",
  "message": "DB connection timeout",
  "duration_ms": 5023
}
```

`trace_id` 字段确保日志能与 Tempo 链路追踪关联。

## 4.5 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| 告警降噪与研判 | 告警 + Metrics/Logs 上下文 → Claude 判断根因 | 有效告警率 < 30% → > 70% |
| 日志异常分析 | ERROR 聚合 → Claude 归因 + 影响范围 | 30-120min → 10-20min |
| 根因关联分析 | Trace + Log + Metric 三维 → AI 排障报告 | 1-4h → 30-60min |
| PromQL 生成 | 自然语言描述 → AI 生成 PromQL + 解释 | 10-30min → < 2min |

## 4.6 建设路径

**Phase 0**：Alertmanager 飞书路由 + 告警规则审查 + SLO Dashboard
**Phase 1**：Loki + Promtail 部署 + Tempo 部署 + 日志告警规则
**Phase 2**：告警 AI 研判 + 日志异常分析 + PromQL 飞书 Bot

**目标**：MTTD 30-120min → < 15min；日志覆盖率 20% → 95%；链路追踪覆盖率 0 → 60%。

---

# 八、环境运维

> 运维不应该只是"救火"，而应该通过系统性巡检和自动化检查，把问题消灭在萌芽阶段。

## 5.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **集群管理** | 🟡 K8s 三套环境 | 无常态化巡检，资源问题靠告警发现 |
| **命名空间治理** | 🔴 无 ResourceQuota | 单个 namespace 可能耗尽集群资源 |
| **配置合规** | 🔴 无自动检查 | K8s 安全基线靠人工 review，漏检率高 |
| **Pod 异常诊断** | 🟡 人工 kubectl describe | 10-60 分钟排查 |

## 5.2 命名空间 ResourceQuota

```yaml
# 标准资源配额（按 Namespace 类型）
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ns-quota
  namespace: dev-service-name
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "50"
```

| Namespace 类型 | CPU Request | Memory |
|--------------|------------|--------|
| dev-* | 4 核 | 8 Gi |
| pre-* | 8 核 | 16 Gi |
| prod-* | 按容量规划 | 按容量规划 |

## 5.3 配置合规（Kyverno）

关键 Block 策略：

| Policy | 说明 |
|--------|------|
| `disallow-root-user` | 容器必须 runAsNonRoot |
| `require-resource-limits` | 必须设置 CPU/Memory limits |
| `restrict-image-registries` | 只允许 harbor.internal 镜像 |
| `disallow-latest-tag` | 禁止 :latest tag |
| `disallow-privileged-containers` | 禁止特权容器 |

## 5.4 集群巡检 AI 摘要（Popeye）

```
每日 09:00 CronJob 运行 Popeye
  ↓ 生成 JSON 报告（E/F/D 级问题）
  ↓ Claude API：优先级排序 + 处置建议
  ↓ 飞书推送"今日集群健康摘要"（Top 5 需处理问题）
```

效果：20-40 分钟人工巡检 → 5 分钟 review 飞书摘要

## 5.5 Pod 异常 AI 诊断

```
Prometheus 告警：CrashLoopBackOff
  ↓ 自动采集：kubectl describe + logs --previous + events
  ↓ Claude 分析：
     识别错误类型（OOMKilled/配置错误/依赖不可达/代码异常）
  ↓ 处置建议 → 飞书通知 OnCall
```

效果：10-60 分钟排查 → 10-15 分钟（有 AI 建议）

## 5.6 建设路径与指标

**Phase 0**：ResourceQuota 全覆盖 + Kyverno 4 条 Block + 合规修复
**Phase 1**：Popeye 每日巡检 + AI 摘要 + Pod 异常自动诊断
**Phase 2**：kube-score CI 集成 + 配置变更追踪 + 多环境 diff

| 指标 | 目标 |
|------|------|
| 配置合规通过率 | > 98% |
| Pod 异常诊断时间 | < 15min（AI 辅助）|
| ResourceQuota 覆盖率 | 100% |

---

# 九、备份容灾

> 备份容灾体系决定了"最坏的情况下，我们能恢复到什么状态、需要多长时间"。核心指标是 RPO（数据丢失上限）和 RTO（恢复时间上限）。

## 6.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **数据库备份** | 🟡 RDS 自动备份 7 天 | K8s 内 PostgreSQL 无备份；有效性未验证 |
| **对象存储** | 🟡 MinIO PVC | 无快照，无跨节点副本 |
| **K8s 集群备份** | 🔴 无 | 无 etcd 备份，无 Velero |
| **容灾演练** | 🔴 从未演练 | RTO/RPO 目标未验证 |

**核心目标**：RPO 数据库 < 1h，RTO 核心服务 < 4h。

## 6.2 数据库备份（pgBackRest）

```
备份策略：
  全量备份：每周日 02:00（保留 4 周）
  增量备份：每日 02:00（保留 7 天）
  WAL 连续归档：实时，保留 48h（实现 RPO < 1h）
  目标：MinIO s3://backup/postgres/{env}/{db}/{date}/

月度有效性验证：
  第一个周六 03:00 → 启动临时 PG 实例
    → 从最新全量备份恢复
    → 数据完整性检查（行数对比 + 关键表 checksum）
    → 记录恢复时间（RTO 测量）→ 销毁临时实例
    → 结果推送飞书（✅ / ❌ + 失败详情）
```

## 6.3 K8s 集群备份

**Velero**（每日 01:00）：所有 Deployment/Service/ConfigMap/PVC 快照 → MinIO，保留 7 天

**etcd 独立备份**（每 6 小时）：
```bash
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d%H%M).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt
```

## 6.4 AI 提效落地

| 提效机会 | 落地方案 | 提效幅度 |
|---------|---------|---------|
| 备份状态监控 | Prometheus + CronJob 指标 + 告警 | 无监控 → 分钟级告警 |
| 有效性验证自动化 | 月度恢复测试 + 验证脚本 | 很少验证 → 月度自动 |
| 演练报告 AI 生成 | 演练时间线 + 操作记录 → Claude 生成报告 | 2-4h → 30-60min |

## 6.5 建设路径

**Phase 0** etcd 定期备份 + 备份状态监控
**Phase 1**：Velero 部署 + pgBackRest 部署
**Phase 2**：月度自动验证 + 季度演练 + RTO/RPO 数据记录

---

# 十、SRE 稳定性工程

> SRE 的本质是用工程化方法管理系统可靠性：用数据（SLO/错误预算）代替主观判断，用流程（OnCall/变更管理）代替救火文化，用复盘代替责任追究。目标不是零故障，而是在可控的不可靠性范围内交付业务价值。

## 7.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **SLO 与错误预算** | 🔴 无 | 无服务可用性目标，稳定性改进无方向 |
| **告警体系** | 🟡 基础告警 | 有效率 < 30%，OnCall 疲劳 |
| **OnCall 值班** | 🔴 无正式制度 | 靠喊人，关键人依赖 |
| **故障复盘** | 🟡 偶尔 | 无模板，行动项未追踪，问题重复出现 |
| **变更管理** | 🔴 无 | 生产变更无审批记录，回滚方案缺失 |
| **混沌工程** | 🔴 无 | 从未主动验证故障恢复能力 |

## 7.2 SLO 定义与错误预算

```yaml
# 核心服务 SLO 示例（vLLM 推理服务）
service: vllm-inference
slos:
  - name: availability
    target: 99.5%       # 月度可用率（允许 ~3.6h 故障/月）
    indicator:
      metric: "成功请求数 / 总请求数"

  - name: latency_p99
    target: 95%         # 95% 请求 P99 < 5s

error_budget:
  window: 30d
  burn_rate_alert:
    - severity: critical
      threshold: 14.4   # 1h 内燃烧 > 2% 月度预算
    - severity: warning
      threshold: 6.0    # 6h 内燃烧 > 5%
```

**Grafana 错误预算看板**：剩余预算（百分比 + 绝对时间）+ 消耗趋势 + 各 SLO 状态（红/黄/绿）

## 7.3 OnCall 制度

**值班周期**：每周轮换，周一 09:00 交接

**飞书 OnCall 机器人**：
```
告警触发 → Alertmanager → 飞书 OnCall 机器人
告警卡片：
  - 告警级别 + 服务名
  - 告警摘要 + Runbook 直链
  - 认领按钮（记录响应人 + 时间）
  - 升级按钮（通知备份 OnCall）
```

**响应 SLA**：P0 < 15min，P1 < 1h，P2 < 4h

## 7.4 Runbook 体系（AI 推荐）

Runbook 目录：`10-SRE 稳定性工程/流程模板/runbooks/`

**每个 Runbook 包含**：告警触发条件 → 快速确认命令（3-5 条）→ 常见根因 + 处置 → 升级条件 → 恢复验证

**AI 自动推荐**：告警触发时，Claude 分析告警名称 + 当前指标，飞书消息自动附带最相关 Runbook 链接 + 摘要。

## 7.5 故障复盘模板（Blameless Postmortem）

```markdown
## 故障摘要
- 故障时间范围、影响范围、严重程度

## 时间线（Timeline）
| 时间 | 事件 |
|------|------|
| HH:MM | 告警触发 |
| HH:MM | 根因确认 |
| HH:MM | 修复上线 |

## 根因分析（5 Why）
## 行动项（Owner + 截止日期）
## 经验教训
```

**AI 辅助**：时间线数据 → Claude 生成结构化初稿 → 人工 review，复盘耗时 2-4h → 30-60min。

## 7.6 变更管理矩阵

| 变更类型 | 审批级别 | 回滚方案 |
|---------|---------|---------|
| 配置调整（非关键）| 自审 | 版本控制 |
| 服务部署（正常迭代）| Lead 审批 | helm rollback |
| 数据库 DDL | DBA + Lead | 回滚 SQL |
| 生产紧急修复 | 事后补审 | git revert |

## 7.7 AI 提效落地

| 提效机会 | 提效幅度 |
|---------|---------|
| 告警研判 | 5-20min → 2-5min |
| Runbook 推荐 | 查文档 10-15min → 即时 |
| 故障复盘 AI 生成 | 2-4h → 30-60min |
| 变更风险评估 | 0.5-1h → 10min |

## 7.8 建设路径

**Phase 0**：SLO 定义（核心 3 服务）+ OnCall 制度 + Runbook Top 5
**Phase 1**：告警 AI 研判 + 故障复盘 AI + 变更管理规范
**Phase 2**：错误预算月报 + 混沌工程试点（pre 环境）

---

# 十一、安全治理

> 安全不是一道墙，而是贯穿研发和运维全生命周期的纵深防御体系。从代码提交、镜像构建、K8s 部署到运行时，每个环节都应有安全检查。

## 8.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **密钥安全** | 🟡 K8s Secret | 偶有凭据写入代码，无自动检测 |
| **依赖安全** | 🟡 Trivy CI | 误报率 ~70%，有效 CVE 没有优先级 |
| **镜像安全** | 🟡 Harbor | 无签名，外部镜像未过审 |
| **接口鉴权** | 🟡 各服务自行 | 标准不统一，部分接口缺认证 |
| **K8s 配置安全** | 🔴 无检查 | 容器可能 root 运行，无资源限制 |
| **运行时告警** | 🔴 无 Falco | 入侵后难以发现 |

## 8.2 密钥安全（gitleaks）

```yaml
# CI 添加 Secret 扫描
secret-scan:
  stage: security
  image: zricethezav/gitleaks:v8
  script:
    - gitleaks detect --source . --report-format json
  allow_failure: false  # 发现 Secret 则 CI 失败
```

**规范**：
- ❌ 代码文件 / Helm values / CI echo 打印 / K8s Manifest 明文
- ✅ K8s Secret / GitLab CI Variables（Masked）

## 8.3 CVE 智能过滤（AI 辅助）

```
CI: Trivy 扫描镜像 → JSON 报告
  ↓ Claude API 分析：
     排除误报（已修复 CVE、OS 低风险）
     按 CVSS + 可利用性分类（Critical/High/Medium）
     对 Critical CVE 给出升级建议
  ↓ 精简报告（200 条 → 5-10 条关键项）
  ↓ Critical CVE > 0 则构建失败
  ↓ 飞书通知 Security Lead
```

效果：误报率 ~70% → ~20%

## 8.4 K8s 安全策略（Kyverno）

与 08-环境运维共享部署：

| Policy | 类型 |
|--------|------|
| `disallow-root-user` | Block |
| `require-resource-limits` | Block |
| `restrict-image-registries` | Block（只允许 harbor.internal）|
| `disallow-privileged-containers` | Block |

## 8.5 运行时安全（Falco）

```yaml
# 检测容器内 shell 执行
- rule: Terminal Shell in Container
  condition: spawned_process and container and shell_procs
  priority: WARNING
  output: "Shell in container (user=%user.name container=%container.name)"
```

## 8.6 AI 提效落地

| 提效机会 | 提效幅度 |
|---------|---------|
| CVE 误报过滤 | 误报率 70% → 20% |
| K8s 配置合规 | 人工 review → 自动拦截 |
| Secret 泄露检测 | 被动发现 → 提交即检测 |
| 安全事件响应 | 1-4h → 15-30min |

## 8.7 建设路径

**Phase 0**：gitleaks CI + Kyverno 4 条 Block + Trivy AI 分类
**Phase 1**：Falco 部署 + 鉴权规范梳理 + RBAC 审查
**Phase 2**：安全周报自动化 + Cosign 镜像签名 + 渗透测试

---

# 十二、版本发布管理

> 好的发布体系让团队自信地频繁发布。目标是把发布变成一件无聊的、可预期的日常操作。

## 9.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **版本号规范** | 🟡 基本 SemVer | 部分团队用日期作版本 |
| **发布流程** | 🟡 有流程不完整 | Checklist 靠人工记忆，漏检概率高 |
| **变更日志** | 🔴 无自动化 | Release Notes 手工 30-60min |
| **灰度发布** | 🟡 有 helm rollback | 无流量切分，发布即全量 |
| **环境同步** | 🔴 手动 | dev/pre/prod 配置漂移严重 |

## 9.2 版本号规范（SemVer）

```
MAJOR.MINOR.PATCH[-prerelease]
  PATCH：Bug 修复，不含破坏性变更
  MINOR：新功能，向后兼容
  MAJOR：破坏性变更

Git Tag 触发 CI 生产发布：v1.2.3
镜像 Tag：release_v1.2.3（CI 自动设置）
```

## 9.3 Conventional Commits + AI Release Notes

**提交规范**：
```
feat(inference): 支持 Qwen2.5 模型批量推理
fix(api): 修复用户权限判断逻辑错误
perf(db): 为 user_id 添加索引，延迟 500ms → 50ms
BREAKING CHANGE: API /v1/chat 返回格式变更
```

**AI 自动生成 Release Notes**：
```
git tag v1.2.3 推送
  ↓ GitLab API 获取 commit log（上个 Tag → 当前 Tag）
  ↓ Claude API：
     解析 feat/fix/perf/breaking → 归类
     过滤无意义 commit（typo/merge）
     生成面向用户的自然语言描述（中英双语）
  ↓ 自动创建 GitLab Release
  ↓ 飞书推送发布摘要
```

效果：30-60 分钟手工 → 5 分钟 AI 自动

## 9.4 发布 Checklist 自动验证

```
CI 发布阶段自动检查：
  - GitLab: 所有 Issue 已 Closed？
  - Prometheus: pre 环境 SLO > 99.5%？
  - Trivy: 无 Critical CVE？
  - 环境 diff: pre vs prod 配置无意外差异？
→ 生成验证报告 → 飞书推送 → 审批人确认后继续
```

## 9.5 灰度发布（Argo Rollouts）

```
发布 v1.3.0 金丝雀流程：
Phase 1: 10% 流量 → 新版本，观测 5 分钟
  → 自动检查：错误率 < 1%，P99 < SLO 阈值
Phase 2: 50% 流量，观测 10 分钟
Phase 3: 100% 流量

任一阶段指标异常 → 自动回滚
```

## 9.6 AI 提效落地

| 提效机会 | 提效幅度 |
|---------|---------|
| Release Notes 生成 | 30-60min → 5min |
| Checklist 自动验证 | 人工 30min → 自动 < 2min |
| 灰度策略推荐 | 人工决策 → AI 辅助 |
| 回滚决策辅助 | 10-20min → 2min |

## 9.7 建设路径

**Phase 0**：发布 Checklist 模板 + SemVer 规范 + Conventional Commits 推广
**Phase 1**：Release Notes AI 生成 + 环境 diff 检查 + Checklist 自动验证
**Phase 2**：Argo Rollouts 试点 + 自动回滚

---

# 十三、私有化交付

> 私有化交付是把 SaaS 产品搬到客户内网运行。失去基础设施控制权意味着交付质量完全依赖我们的工程化程度。

## 10.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **实施规范** | 🟡 有流程不完整 | 依赖个人经验，新人独立交付困难 |
| **配置管理** | 🔴 手工适配 | 每个客户环境手工调整，易出错 |
| **Preflight 检查** | 🟡 有脚本不完整 | 客户环境不满足条件交付中途中断 |
| **故障诊断** | 🔴 靠个人经验 | 排查时间 1-4 小时 |
| **交付文档** | 🟡 模板不完整 | 文档质量参差，客户自助维护困难 |

## 10.2 Preflight 自动化检查

```bash
#!/bin/bash
# preflight-check.sh 覆盖所有已知踩坑点

check_kubernetes() {
  # K8s 版本 >= 1.24
  K8S_VERSION=$(kubectl version --short | grep Server | awk '{print $3}')
}

check_resources() {
  # 总 CPU >= 32 核，总内存 >= 64GB
  TOTAL_CPU=$(kubectl get nodes -o json | jq '[.items[].status.capacity.cpu | tonumber] | add')
}

check_gpu() {
  # CUDA 版本 >= 11.8（防止 vLLM 兼容问题）
  CUDA_VERSION=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
}

check_storage() {
  kubectl get storageclass   # 必须有默认 StorageClass
}

check_network() {
  # 检查 Harbor 可达性 + DNS 解析 + 所需端口
}
```

**Preflight AI 报告**：
```
脚本输出 JSON → Claude API：
  逐项评估（通过/警告/失败）
  对失败项给出修复方法
  整体可行性评估
→ 生成 HTML 报告（1-2h 手工 → 15min 自动）
```

## 10.3 配置适配模板（Helm Values）

```yaml
# values-customer-template.yaml（AI 根据问卷自动填写初稿）
global:
  customerName: "{{ customer_name }}"
  imageRegistry: "{{ harbor_endpoint }}"

database:
  host: "{{ db_host }}"
  passwordSecretRef: "db-credentials"  # 密码通过 Secret 注入

ai:
  modelPath: "{{ model_path }}"
  gpuMemoryFraction: 0.9

ingress:
  hosts: ["{{ domain }}"]
```

**配置 AI 生成**：实施工程师填写交付问卷 → Claude 生成 values.yaml 初稿 → 工程师 review + 补充敏感信息，0.5-2h → 10min。

## 10.4 交付故障诊断 Playbook


| Playbook | 场景 |
|----------|------|
| pod-crashloop.md | Pod 崩溃循环 |
| image-pull-failed.md | 镜像拉取失败 |
| gpu-not-detected.md | GPU 未识别 |
| vllm-load-failed.md | 模型加载失败 |
| db-connection-failed.md | 数据库连接失败 |

**知识库**：Playbook + 产品文档接入 RAG，实施工程师可通过飞书 Bot 现场查询故障处置。

## 10.5 AI 提效落地

| 提效机会 | 提效幅度 |
|---------|---------|
| Preflight AI 报告 | 1-2h → 15min |
| 配置适配 AI 生成 | 0.5-2h → 10min |
| 部署故障诊断 | 1-4h → 30-60min（Dify 辅助）|
| 交付文档生成 | 2-3h → 30-60min |

## 10.6 建设路径与指标

**Phase 0**：Preflight 脚本完善 + values 模板 + Playbook Top 5
**Phase 1**：Preflight AI 报告 + Dify 配置生成 + Dify 知识库上线
**Phase 2**：交付文档自动化 + 交付复盘机制

| 指标 | 目标 |
|------|------|
| 首次交付成功率 | > 90% |
| 平均交付耗时 | < 1 天 |
| Preflight 覆盖率 | 100% |

---

# 十四、License 授权管理

> License 管理是产品商业化的重要控制点。缺乏自动化会导致运营效率低、客户体验差（到期无感知、续费提醒不及时）。

## 11.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **生成操作** | 🔴 手工流程 | 15-30 分钟/次，参数填错导致客户当天过期 |
| **到期管理** | 🔴 无预警 | 靠客户反馈才知道过期，突然断服 |
| **使用量监控** | 🔴 无 | 不知道客户实际使用量 |
| **异常检测** | 🔴 无 | License 共享/跨环境使用无法检测 |

## 11.2 License 生成（Dify 工作流）

```
运营人员填写 Dify 表单：
  客户名称 / License 类型 / 有效期 / 功能模块 / 并发数限制
  ↓
Dify 工作流：
  AI 根据套餐自动预填大部分参数
  对异常参数发出警告（如有效期异常）
  生成 license.json（RSA 签名）
  ↓
同步写入 License 台账（飞书多维表格）
+ 生成激活说明文档
+ 飞书通知销售/CSM

效率：15-30min → 3-5min
```

**License 数据结构**：
```json
{
  "customer_id": "cust-20250101",
  "plan": "enterprise",
  "features": ["inference", "finetune", "rag", "workflow"],
  "limits": {"max_concurrent_requests": 50, "max_nodes": 3},
  "valid_until": "2026-01-01",
  "signature": "<RSA签名>"
}
```

## 11.3 到期分层预警

| 提前天数 | 通知对象 | 内容 |
|---------|---------|------|
| 90 天 | 销售 + CSM | 续约提醒，附使用量报告 |
| 30 天 | 销售 + 客户邮件 | 正式续约提醒 + 报价 |
| 7 天 | 销售 + CSM + 运营 | 紧急提醒 |
| 1 天 | 全员相关方 | 高优提醒，当日必须处理 |

```yaml
# Prometheus 告警规则
- alert: LicenseExpiringSoon
  expr: (license_valid_until_timestamp - time()) / 86400 < 30
  annotations:
    summary: "客户 {{ $labels.customer_name }} License 将在 {{ $value }}天后到期"
```

## 11.4 使用量监控与异常检测

**采集指标**：
```
license_requests_total{customer_id, feature}  # 各功能调用次数
license_concurrent_requests{customer_id}       # 当前并发数
license_users_active{customer_id}              # 近 7 天活跃用户
```

**月度 AI 分析报告**：Prometheus 数据 → Claude 生成使用量分析（利用率 + 趋势 + 套餐升级建议）→ 飞书推送 CSM + 销售。

**异常检测**：超量使用告警 + 跨 IP 激活检测 + RSA 签名定期验证。

## 11.5 建设路径

**Phase 0**：License 台账整理 + 基础到期告警（30/7/1 天）
**Phase 1**：工作流 + 使用量指标采集 + 异常检测
**Phase 2**：月度报告自动化 + 90 天续约提醒

---

# 十五、成本管理

> 成本管理不是省钱，而是把每一分钱花在刀刃上。GPU 资源是最大成本项，也是优化潜力最大的地方。ROI 分析显示，AI 辅助的成本优化工具每月成本约 ¥200-400，可带来 ¥9-25 万/月的 GPU 节省，ROI >> 100x。

## 12.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **GPU 成本** | 🔴 无追踪 | GPU 利用率未统计，空闲持续计费 |
| **云账单** | 🟡 月度人工 | 账单分析季度一次，异常发现滞后 |

## 12.2 GPU 利用率监控与优化

**指标采集（DCGM，与 04-AI Infra 共用）**

**分层处置策略**：
| 利用率 | 状态 | 建议 |
|--------|------|------|
| > 80% | 高负载 | 评估扩容 |
| 40-80% | 健康 | 维持 |
| 20-40% | 偏低 | 调度优化 |
| < 20% | 闲置 | AI 分析原因，评估缩减 |

**AI 月度优化报告**：
```
每月 1 日：DCGM 30 天利用率数据 → Claude API：
  - 闲置节点 + 低谷时段识别
  - 推理参数优化（batch_size / max_model_len）
  - 混合部署可行性（空闲 GPU 跑训练）
→ 输出报告（预期节省金额 + 具体步骤）→ 飞书 AI Infra + 管理层
```

## 12.3 云账单异常检测

```yaml
- alert: CloudBillDailySpike
  expr: cloud_billing_daily_cost > cloud_billing_daily_cost_avg_7d * 1.3
  annotations:
    summary: "当日云费用超过近 7 天均值 30%，请检查异常消费"
```

## 12.4 AI 提效落地

| 提效机会 | 提效幅度 |
|---------|---------|
| GPU 利用率分析 | 月度感知 → 日度，节省 20-30% |
| 资源浪费扫描 | 季度人工 → 周度自动 |
| 成本异常检测 | 月度发现 → 当日告警 |
| 月度成本报告 | 2-3h 手工 → 30min 自动 |

## 12.5 建设路径

**Phase 0**：GPU 利用率 Dashboard
**Phase 1**：GPU 闲置告警 + 账单异常告警 + 资源浪费周报
**Phase 2**：GPU 优化月报 AI 生成 + 成本分摊月报 + 自动 MR

---

# 十六、知识管理

> 知识管理把散落在个人头脑、飞书、Wiki、代码注释里的知识，沉淀成可被团队检索、复用、传承的组织资产。当团队规模增长、人员流动加快时，知识管理的价值会指数级放大。

## 13.1 现状评估

| 子域 | 当前状态 | 主要痛点 |
|------|---------|---------|
| **文档标准** | 🟡 有规范不统一 | 结构混乱，无模板约束，质量参差 |
| **知识沉淀** | 🔴 经验散落在人 | 故障经验靠个人记忆，离职即消失 |
| **知识检索** | 🔴 无 RAG | 找文档靠手搜，5-15 分钟，跨文件夹困难 |
| **文档质量** | 🔴 无 CI 检查 | 链接失效、内容过时无法自动发现 |
| **Onboarding** | 🟡 有文档 | 新人需 1-2 周熟悉，全靠老员工带 |

## 13.2 RAG 知识库

```
数据源（自动同步）：
  - 本工程所有 .md 文件（GitLab Webhook 触发）
  - 飞书知识库（飞书 API 接入）

Dify 处理：
  文档分块（按章节切分）→ BGE-M3 向量化 → 存入 Milvus

查询入口：
  - 飞书 Bot（@机器人 + 问题，7x24h）
  - Dify Web UI

示例查询：
  "Kafka 消息堆积怎么排查？"
  → 检索 Runbook + FAQ
  → Claude 基于上下文生成精准答案
  → 附带原始文档链接

效果：5-15min 手搜 → < 1min 问答
```

## 13.3 文档质量 CI 检查

```yaml
# GitLab CI docs-lint stage
docs-lint:
  stage: lint
  script:
    - markdownlint '**/*.md'
    - markdown-link-check '**/*.md'    # 内部链接有效性
    - python3 scripts/doc-quality-check.py  # AI 质量评分
  rules:
    - changes: ["**/*.md"]
```

## 13.4 知识强制沉淀触发点

| 触发场景 | 沉淀方式 | 目标文档 |
|---------|---------|---------|
| P0/P1 故障复盘完成 | 复盘报告 → SRE/postmortems/ | Runbook 更新 |
| 私有化交付踩坑 | 交付复盘 → 私有化交付/playbooks/ | Playbook 更新 |
| 新工具选型 | ADR → 架构治理/架构评审/ | 选型记录 |
| 高频 FAQ 发现 | Dify 查询统计 → 对应领域 FAQ.md | FAQ 补充 |

## 13.5 会议纪要 AI 自动整理

```
飞书会议录音 → 飞书妙记（自动转录）
  ↓ Claude API：
     提取关键决策（WHAT + 为什么）
     提取行动项（WHO + WHAT + 截止日期）
     生成 100-300 字结构化摘要
  ↓ 自动发送飞书群 + 创建飞书文档
  ↓ 重要决策同步到对应领域文档

效率：30-60 分钟手工整理 → 5-10 分钟 AI 辅助 review
```

## 13.6 Onboarding 加速

**按角色定制阅读路径**：

| 角色 | Week 1 重点 | Week 2 重点 |
|------|------------|------------|
| 研发 | 03-CICD + 02-架构治理 + 11-安全治理 | 首个 Feature PR 完成 |
| 运维 | 07-可观测性 + 08-环境运维 + 10-SRE | 首次 OnCall 影子模式 |
| 实施 | 13-私有化交付 + 04-AI Infra + 14-License | 参与一次交付任务 |

**RAG 辅助**：不懂的直接问飞书 Bot，7x24h 响应，Onboarding 时间 1-2 周 → < 1 周。

## 13.7 AI 提效落地

| 提效机会 | 提效幅度 |
|---------|---------|
| RAG 知识问答 | 5-15min → < 1min |
| 文档质量 CI | 人工 review → 自动检查 |
| 会议纪要整理 | 30-60min → 5-10min |
| Onboarding 加速 | 1-2 周 → < 1 周 |

## 13.8 建设路径

**Phase 0**：文档规范发布 + CI 文档检查 + 知识沉淀触发点入流程
**Phase 1**：Dify 知识库建立（需 05-中间件 Dify 先部署）+ 飞书 Bot 问答 + 会议纪要 AI
**Phase 2**：月度知识健康报告 + Onboarding 路径优化 + 知识贡献激励

---

# 十七、跨领域联动总图

## 14.1 核心依赖链

```
关键依赖链（必须先完成）：

[05-中间件] Agent 部署
  └─→ [13-私有化交付] 知识库问答 + 配置生成工作流
  └─→ [16-知识管理] RAG 问答平台
  └─→ [14-License 授权] License 生成工作流

[07-可观测性] Loki + Tempo 部署
  └─→ [10-SRE] 告警 AI 研判（需要 Log 上下文）
  └─→ [05-中间件] Kafka/DB 告警路由

[04-AI Infra] DCGM 指标采集
  └─→ [15-成本管理] GPU 利用率分析
  └─→ [07-可观测性] 指标汇入 Prometheus

[11-安全治理] Kyverno 部署
  └─→ [08-环境运维] 配置合规共享策略
```

## 14.2 工具共享矩阵

| 工具 | 主要领域 | 其他使用领域 |
|------|---------|-----------|
| Prometheus | 07-可观测性 | 05/08/09/10/11/14/15 |
| Grafana | 07-可观测性 | 04/10/15 |
| Claude API | 全领域 | AI 提效核心工具 |
| Kyverno | 08-环境运维 | 11-安全治理 |
| DCGM Exporter | 04-AI Infra | 15-成本管理 |
| GitLab CI | 03-CICD | 06/11/12/16 |
| 飞书 Bot | 10-SRE | 05/07/08/09/13/14/15 |

## 14.3 全局建设优先级（基于影响和依赖）

### 第一批（立即启动，0-2 周）
1. **Alertmanager 飞书路由**（07）：高优，解决告警盲区，是其他 AI 告警的前提
2. **Kyverno 4 条 Block 策略**（08/11 共享）：高优，安全门禁
3. **ResourceQuota 全覆盖**（08）：防止资源耗尽
4. **gitleaks CI 集成**（11）：防凭据泄露，成本低效果好
5. **DCGM Exporter 部署**（04）：GPU 利用率可见性，成本管理前提

### 第二批（第 3-4 周）
6. **Loki + Promtail**（07）：日志可观测，是后续 AI 分析的数据来源
7. **SLO 定义 + OnCall 制度**（10）：稳定性工程基础
8. **慢查询 AI 分析**（05）：直接产生价值
9. **Kafka 堆积 AI 诊断**（05）：高频痛点
10. **测试用例 AI 生成（核心模块）**（06）：提升发布效率

### 第三批（第 5-8 周）
11. **Dify 部署**（05）：解锁后续多个 AI 工作流
12. **Release Notes AI 生成**（12）：减少发布准备工作
13. **Preflight AI 报告**（13）：私有化交付效率
14. **License 到期自动预警**（14）：保护收入
15. **Kubecost 部署**（15）：资源成本可见性

### 第四批（第 9-12 周）
16. **Velero + pgBackRest**（09）：补齐备份盲区
17. **Tempo 部署 + OpenTelemetry 接入**（07）：链路追踪
18. **Dify 知识库 + 飞书 RAG 问答**（16）：知识管理 AI 化
19. **Argo Rollouts 灰度发布**（12）：降低发布风险
20. **GPU 优化 AI 月报**（15）：成本优化闭环

## 14.4 AI 提效全景汇总

| 领域 | 关键 AI 提效场景 | 最大提效幅度 |
|------|----------------|------------|
| 04-AI Infra | GPU 利用率月报 + 模型参数推荐 | 月度 → 日度感知 |
| 05-中间件 | 慢查询分析 + Kafka 诊断 | 1-6h → 15-30min |
| 06-质量保障 | 测试用例生成 + Bug 分类 | 2-4h → 30min |
| 07-可观测性 | 告警研判 + PromQL 生成 | 有效率 <30% → >70% |
| 08-环境运维 | 集群巡检 AI 摘要 + Pod 诊断 | 40min → 5min review |
| 09-备份容灾 | 演练报告生成 | 2-4h → 30-60min |
| 10-SRE | 故障复盘生成 + Runbook 推荐 | 2-4h → 30-60min |
| 11-安全治理 | CVE 分类过滤 | 误报率 70% → 20% |
| 12-版本发布 | Release Notes 生成 + Checklist 验证 | 60min → 5min |
| 13-私有化交付 | Preflight 报告 + 配置生成 | 2-4h → 25min |
| 14-License | 生成工作流 + 月度报告 | 30min → 5min |
| 15-成本管理 | GPU 优化月报 + 浪费扫描 | 节省 GPU 成本 20-30% |
| 16-知识管理 | RAG 问答 + 会议纪要 | 15min → 1min |

## 14.5 量化价值估算

| 优化项 | 月度节省 | 备注 |
|-------|---------|------|
| GPU 利用率 40%→70% | ¥9-25 万/月 | 减少 3-5 台 A100 |
| 研发效率提升（AI 辅助）| 约 20% 人效提升 | 测试/文档/分析类任务 |
| 私有化交付效率 | 减少 1-2 天/项目 | 降低客户等待成本 |
| 故障 MTTR 缩短 | 减少故障损失 | P0 从 2h+ → < 1h |
| **AI 工具成本（Claude API）** | **-¥200-400/月** | 极低成本 |

## 14.6 实施原则

1. **渐进式交付**：每个 Phase 结束都应有可量化的成果，不追求大而全
2. **工具共享复用**：Prometheus/Dify/Claude API 是基础设施，要在多个领域共享
3. **AI 辅助而非 AI 替代**：所有 AI 输出都需要人工确认，特别是生产操作
4. **数据驱动**：每个建设目标都有对应的度量指标，用数据证明价值
5. **文档同步**：工具上线的同时，更新对应领域文档和 Dify 知识库

---

*最后更新：2026 年 5 月 | 维护团队：SmartVision 工程效能组*
---

# 附录一：各领域 FAQ 精选

## A1. AI Infra 基建 FAQ

**Q：vLLM 推理服务突然 OOM，如何快速处置？**

排查步骤：
1. `kubectl describe pod <vllm-pod> -n ai-infra` → 确认是否 OOMKilled
2. `kubectl logs <vllm-pod> --previous --tail=100` → 查看崩溃前日志
3. Grafana 查看 `DCGM_FI_DEV_MEM_USED` 趋势 → 确认是请求突增还是内存泄漏
4. 临时处置：`kubectl rollout restart deployment/vllm` 重启 + 检查 `max_num_seqs` 是否过高
5. 根本修复：调低 `gpu_memory_utilization`（从 0.95 降到 0.90）+ 设置请求排队上限

**Q：HAMI GPU 配额设置了但裸进程绕过了怎么办？**

- 短期：手动 `kill <pid>` + 飞书通知使用者
- 中期：部署裸进程自动检测告警（详见本文第一章），5 分钟内自动发现
- 长期：节点级 GPU 访问控制（NVIDIA MPS 或 cgroup v2 device controller）

**Q：模型加载时间太长（超过 5 分钟），是正常的吗？**

Qwen2.5-Coder-32B（约 64GB）在 4× A100 上加载时间约 2-4 分钟，属正常。如果超过 8 分钟检查：
- MinIO 带宽是否瓶颈：`mc admin trace --path myminio` 查看传输速率
- NVLink 是否启用：`nvidia-smi topo -m` 确认 GPU 间互联
- 模型文件是否完整：`md5sum` 校验

---

## A2. 中间件 FAQ

**Q：生产数据库用阿里云 RDS 还是 K8s 自建？**

生产环境强烈推荐托管 RDS：自动主从复制、自动故障切换、内置自动备份、安全补丁维护。唯一适合 K8s 自建的场景是私有化交付（客户无云数据库服务），此时用 Bitnami PostgreSQL + pgBackRest + MinIO 备份。

**Q：如何判断是否需要为某个表建索引？**

```sql
-- 查找顺序扫描次数多的表（说明缺索引）
SELECT schemaname, tablename, seq_scan, idx_scan,
       seq_scan - idx_scan AS diff
FROM pg_stat_user_tables
WHERE seq_scan > 1000
ORDER BY diff DESC
LIMIT 20;

-- 查找未使用的索引（占用空间但无效）
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexname NOT LIKE 'pg_%'
ORDER BY schemaname, tablename;
```

如果一个表 `seq_scan` 比 `idx_scan` 高很多，且查询量大，应考虑为常用 WHERE 条件建立索引。

**Q：Kafka Consumer Group 出现 REBALANCING 状态，业务是否受影响？**

Rebalancing 期间该 Consumer Group 不消费消息，会短暂积压。正常 Rebalancing（应用部署、实例扩缩容）持续 30-60 秒后恢复。如果 Rebalancing 持续超过 5 分钟或反复发生，通常是：
- Session timeout 设置太短（建议 `session.timeout.ms=30000`）
- 消费者处理单条消息时间超过 `max.poll.interval.ms`（建议 `max.poll.interval.ms=300000`）
- 网络不稳定导致心跳超时

---

## A3. 可观测性 FAQ

**Q：Prometheus 数据保留多久，如何调整？**

默认保留 15 天。调整方式：Helm values 中设置 `server.retention: 30d`（磁盘允许的情况下）。超长期存储建议接入 Thanos 或 VictoriaMetrics，可低成本保留 1 年以上数据用于趋势分析。

**Q：告警一直在 FIRING 但问题已解决，为什么不恢复？**

检查告警规则的 `for` 时间窗口，如果问题指标回落但未持续 `for` 设定时间则不会 RESOLVED。另外检查 Alertmanager 的 `resolve_timeout` 配置（默认 5 分钟），确认 Prometheus 在指标恢复后发送了 RESOLVED 通知。

**Q：新服务如何快速接入可观测体系（无代码改动）？**

1. **指标**：K8s Pod 已自动被 kube-state-metrics 和 node_exporter 覆盖基础指标；业务指标需在代码中暴露 `/metrics` 端点
2. **日志**：只要应用写 stdout/stderr，Promtail DaemonSet 会自动采集（无需配置）
3. **链路追踪**：需要在应用中接入 OpenTelemetry SDK（Python 约 10 行代码）

---

## A4. SRE 稳定性工程 FAQ

**Q：错误预算已消耗 80%，应该怎么应对？**

1. **立即**：召开紧急会议，识别消耗错误预算的主要告警/事件
2. **短期**：冻结非必要功能发布（只允许 Bug 修复和稳定性相关变更）
3. **中期**：为消耗预算的根因做专项修复（如减少部署频率、修复高频告警根因）
4. **月末**：如果错误预算完全耗尽，下个月的功能发布限额减半

**Q：OnCall 工程师不了解某个服务怎么办？**

标准 Escalation 流程：
1. 查 Runbook（如果有 Dify RAG，直接问 Bot）
2. Runbook 处理不了 → 飞书通知该服务的 Tech Owner
3. Tech Owner 也不确定 → 拉群讨论 + 升级到 Engineering Lead
4. 事后补充 Runbook，避免下次同样情况

**Q：混沌工程实验会影响生产吗？**

起步阶段的混沌实验只在 pre 环境执行，完全不影响生产。推荐工具：Chaos Mesh（K8s 原生）。常见实验类型：
- Pod 随机删除（验证自动恢复能力）
- 节点 CPU 压力注入（验证资源限制和降级）
- 网络延迟注入（验证超时处理和重试逻辑）
- 在生产环境执行前，必须在 pre 环境验证系统能自动恢复。

---

## A5. 安全治理 FAQ

**Q：Trivy 扫描出来 200 多个 CVE，应该怎么处理？**

分优先级处理：
1. **Critical + 有 PoC（可利用）**：立即修复（7 天内）
2. **Critical + 无 PoC**：计划修复（30 天内）
3. **High**：当前迭代修复
4. **Medium/Low**：积压列表，按季度清理

使用 AI 辅助分类后（详见第八章），有效 CVE 通常只有 5-20 条，大大降低处理压力。

**Q：K8s ServiceAccount Token 如何安全使用？**

```yaml
# 建议：使用 Projected ServiceAccount Token（有效期限制）
spec:
  containers:
    - name: app
      volumeMounts:
        - name: token
          mountPath: /var/run/secrets/tokens
  volumes:
    - name: token
      projected:
        sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600  # 1 小时有效期，自动刷新
              audience: my-service
```

避免使用 `automountServiceAccountToken: true`（默认开启），不需要访问 K8s API 的服务应设置为 `false`。

---

## A6. 私有化交付 FAQ

**Q：客户环境没有外网，如何拉取镜像？**

需要在客户环境搭建内网 Harbor 镜像仓库（或客户提供），然后：
1. 在我方环境将镜像打包：`docker save harbor.internal/app:v1.2.3 > app.tar`
2. 传输到客户环境（U 盘/企业内网文件传输）
3. 导入到客户 Harbor：`docker load < app.tar && docker push customer-harbor/app:v1.2.3`
4. 修改 Helm values 中的 `imageRegistry` 为客户 Harbor 地址

这个流程应该在 Preflight 阶段就确认好，避免交付中途发现。

**Q：客户环境 K8s 版本比要求低，能降级部署吗？**

不建议降级版本要求，因为可能导致 API 兼容问题。建议路径：
1. 明确告知客户需要升级 K8s 版本（提供升级文档）
2. 如果客户无法立即升级，评估是否可以临时用 Docker Compose 方案部署（非 K8s）
3. 后续版本考虑放宽 K8s 版本要求（在 pre 环境用旧版本 K8s 测试兼容性）

**Q：私有化部署后如何进行远程技术支持？**

建议方案：
1. **VPN 接入**：客户环境提供 VPN 账号，我方工程师可远程访问
2. **堡垒机**：通过客户提供的跳板机 SSH 到 K8s 节点
3. **无 VPN 方案**：引导客户运行诊断脚本，将输出发送给我方分析（不暴露敏感数据）
4. **Dify 知识库**：客户自己的实施工程师可以通过 Dify RAG 查询故障处置（无需联系我方）

---

# 附录二：关键配置参考

## B1. GitLab CI/CD 核心变量配置

| 变量名 | 类型 | 用途 |
|-------|------|------|
| `HARBOR_URL_DEV/PRE/PROD` | Variable | 三套 Harbor 仓库地址 |
| `HARBOR_USER_DEV/PRE/PROD` | Variable（Masked）| Harbor 登录用户名 |
| `HARBOR_PASS_DEV/PRE/PROD` | Variable（Masked）| Harbor 登录密码 |
| `KUBECONFIG_DEV/PRE/PROD` | File | K8s 集群访问凭据（File 类型）|
| `SSH_PRIVATE_KEY` | File | SSH 私钥（部署到物理机场景）|
| `FTP_HOST/USER/PASS` | Variable（Masked）| FTP 制品服务器 |
| `FEISHU_WEBHOOK` | Variable（Masked）| 飞书通知 Webhook |

```yaml
# 镜像 Tag 命名规范（在 CI 中自动设置）
DEV:   ${HARBOR_URL_DEV}/smartvision/{service}:dev_${CI_COMMIT_SHORT_SHA}
PRE:   ${HARBOR_URL_PRE}/smartvision/{service}:pre_${CI_COMMIT_SHORT_SHA}
MAIN:  ${HARBOR_URL_PROD}/smartvision/{service}:main_${CI_COMMIT_SHORT_SHA}
PROD:  ${HARBOR_URL_PROD}/smartvision/{service}:release_${CI_COMMIT_TAG}
       ${HARBOR_URL_PROD}/smartvision/{service}:latest
```

## B2. Prometheus 告警规则模板

```yaml
groups:
  - name: service.slo
    rules:
      # 可用率 SLO 告警（错误预算燃烧率）
      - alert: ErrorBudgetBurnHigh
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[1h])) by (service)
            /
            sum(rate(http_requests_total[1h])) by (service)
          ) > 0.01   # 1h 内错误率 > 1%（对应 burn_rate ~14.4x）
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.service }} 错误预算高速消耗"
          runbook: "https://wiki.internal/runbooks/high-error-rate"

  - name: infra.resources
    rules:
      # 节点磁盘容量预测告警
      - alert: DiskSpacePredictedFull
        expr: |
          predict_linear(node_filesystem_free_bytes{mountpoint="/"}[7d], 30*24*3600) < 0
        labels:
          severity: warning
        annotations:
          summary: "节点 {{ $labels.instance }} 磁盘预计 30 天内耗尽"
```

## B3. Helm 多环境 Values 管理

```
helm/
├── Chart.yaml
├── values.yaml            # 所有环境共用默认值
├── values-dev.yaml        # dev 环境覆盖值
├── values-pre.yaml        # pre 环境覆盖值
└── values-prod.yaml       # prod 环境覆盖值

# 部署命令
helm upgrade --install app ./helm \
  -f helm/values.yaml \
  -f helm/values-${ENV}.yaml \
  --namespace ${NS} \
  --set image.tag=${IMAGE_TAG}
```

**三环境差异典型配置**：

| 配置项 | dev | pre | prod |
|-------|-----|-----|------|
| `replicaCount` | 1 | 2 | 3+ |
| `resources.requests.cpu` | 100m | 500m | 按容量规划 |
| `resources.requests.memory` | 256Mi | 1Gi | 按容量规划 |
| `autoscaling.enabled` | false | false | true |
| `logLevel` | debug | info | warn |

## B4. K8s 常用诊断命令速查

```bash
# Pod 状态快速诊断
kubectl get pods -n <ns> | grep -v Running
kubectl describe pod <pod> -n <ns> | tail -30
kubectl logs <pod> -n <ns> --previous --tail=100
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20

# 资源使用情况
kubectl top pods -n <ns> --sort-by=memory
kubectl top nodes

# Helm 操作
helm list -n <ns>                    # 列出 Release
helm history <release> -n <ns>       # 查看历史版本
helm rollback <release> <revision> -n <ns>  # 回滚到指定版本
helm get values <release> -n <ns>    # 查看当前 values

# 临时调试（不推荐生产使用）
kubectl run debug --image=busybox -it --rm --restart=Never -- sh
kubectl exec -it <pod> -n <ns> -- /bin/bash
kubectl port-forward svc/<service> 8080:80 -n <ns>

# GPU 相关
kubectl describe node <gpu-node> | grep -A 10 "Capacity:"
kubectl get pods -n ai-infra -l app=vllm -o wide
nvidia-smi dmon -s u -d 5  # 实时 GPU 使用率监控（在节点上运行）
```

---

# 附录三：建设里程碑与 OKR 建议

## C1. 季度 OKR 建议

### Q1 OKR（第 1-3 个月）

**O：建立工程基础设施安全底座与可观测能力**

- KR1：Kyverno 4 条 Block 策略覆盖率 100%（无特权/root 容器进入任何环境）
- KR2：Alertmanager 飞书路由上线，P0 告警平均响应时间 < 15 分钟
- KR3：Loki 部署完成，K8s Pod 日志集中存储覆盖率 > 95%
- KR4：核心 3 个服务 SLO 定义完成，Grafana 错误预算看板可用

### Q2 OKR（第 4-6 个月）

**O：AI 辅助工具覆盖高频运维场景，人效提升 30%**

- KR1：慢查询 AI 分析工具上线，分析时间从 1-4h 降至 < 15min（验证 3 次以上）
- KR2：Release Notes AI 生成工具上线，发布准备时间 < 15 分钟/次
- KR3：Dify 知识库上线，飞书 RAG 问答覆盖 80%+ 常见问题（基于用户反馈）
- KR4：Preflight AI 报告工具上线，私有化交付首次成功率 > 90%

### Q3 OKR（第 7-9 个月）

**O：成本优化与稳定性达到行业标准水平**

- KR1：GPU 平均利用率 > 70%（通过 AI 优化建议推动），月度 GPU 成本同比下降 ≥ 20%
- KR2：核心服务可用率 > 99.5%（连续 3 个月）
- KR3：Velero + pgBackRest 全覆盖，完成 2 次容灾演练（RTO 实测 < 4h）
- KR4：Argo Rollouts 在生产环境覆盖 3 个核心服务的灰度发布

## C2. 里程碑检查点

| 里程碑 | 时间节点 | 验收标准 |
|-------|---------|---------|
| M1：安全门禁上线 | 第 2 周末 | gitleaks/Kyverno/Trivy AI 分类全部上线 |
| M2：可观测三支柱联通 | 第 6 周末 | Prometheus+Loki+Tempo 在 Grafana 统一查询 |
| M3：AI 辅助工具第一版 | 第 8 周末 | 慢查询分析/Release Notes/Bug 分类 3 个工具可用 |
| M4：Dify 平台上线 | 第 10 周末 | 知识库问答/配置生成/交付文档 3 个工作流可用 |
| M5：成本可见性 | 第 12 周末 | Kubecost + GPU Dashboard + 云账单接入全部完成 |
| M6：容灾体系完整 | 第 16 周末 | 首次完整容灾演练通过，RTO/RPO 有实测数据 |

---

# 附录四：工具选型决策记录（ADR 摘要）

## D1. 为什么选 Grafana Stack 而非 ELK？

| 维度 | Grafana Stack（Loki+Tempo+Prometheus）| ELK（Elasticsearch+Logstash+Kibana）|
|------|--------------------------------------|--------------------------------------|
| 存储成本 | 低（Loki 索引少，压缩比高）| 高（Elasticsearch 索引占用大）|
| K8s 集成 | 原生（Helm chart 成熟）| 需要额外配置 |
| 三支柱统一 | 在 Grafana 统一查询 | 需要多个 UI |
| 学习曲线 | 中（LogQL 相对简单）| 高（Lucene 查询语法）|
| 资源消耗 | 低 | 高（ES 内存消耗大）|

**决策**：Grafana Stack，适合中小规模且已有 Prometheus 的团队。

## D2. 为什么选 Dify 而非自建 RAG？

| 维度 | Dify | 自建 RAG（LangChain + FastAPI）|
|------|------|-------------------------------|
| 开发成本 | 低（无代码/低代码）| 高（需要 2-4 周开发）|
| 可视化 | 有（工作流图形化）| 无 |
| 多模型支持 | 是（OpenAI/Claude/内网 vLLM）| 需要自己适配 |
| 运维复杂度 | 中（K8s 部署 1 套）| 高（维护多个组件）|
| 飞书集成 | 插件支持 | 需要自己开发 |

**决策**：Dify，低代码上手快，适合运营人员自助使用。

## D3. 为什么选 Kyverno 而非 OPA/Gatekeeper？

| 维度 | Kyverno | OPA/Gatekeeper |
|------|---------|----------------|
| 学习曲线 | 低（YAML 原生规则）| 高（Rego 语言）|
| K8s 原生 | 是 | 否（OPA 是通用工具）|
| 社区活跃度 | 高 | 高 |
| Mutate 支持 | 是（可自动修改 manifest）| 是（需要 mutation webhook）|
| Debug 友好性 | 好 | 一般 |

**决策**：Kyverno，K8s 原生语法对运维更友好，规则即 YAML。

## D4. 为什么选 pgBackRest 而非 pg_dump？

| 维度 | pgBackRest | pg_dump |
|------|------------|---------|
| 增量备份 | 支持（Block-level）| 不支持 |
| WAL 归档 | 内置（实现 PITR）| 不支持 |
| 压缩率 | 高（zstd/lz4）| 中 |
| 并行备份 | 支持 | 不支持 |
| 适合数据量 | 大型 DB（GB~TB）| 小型 DB（< 10GB）|
| 恢复细粒度 | 任意时间点（PITR）| 备份时间点 |

**决策**：pgBackRest，RPO < 1h 的目标需要 WAL 连续归档，pg_dump 无法满足。

---

*本合订本涵盖 SmartVision 工程体系 13 个核心领域，字数约 2.5 万字。建议配合各领域独立文档（体系建设总览.md）深入阅读具体实施细节。*

*如需讨论任何章节的方案，可通过飞书 RAG Bot（上线后）直接查询，或联系 SmartVision 工程效能组。*
