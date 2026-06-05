# AI 提效计划 - 可观测性

> 将 AI 引入可观测性的核心场景：智能告警降噪、日志异常快速定位、根因关联分析、自然语言查询。目标：有效告警占比从当前 <30% 提升到 >70%，排障时间减少 60%。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| 告警研判（真实 vs 误报）| 5-20 分钟/个 | 运维/SRE | 告警多且重复，有效告警被淹没 |
| 日志排障 | 30-120 分钟/次 | 运维工程师 | 海量日志手动翻查，grep 命令门槛高 |
| 跨系统根因关联 | 1-4 小时/次 | 运维 + 研发 | 需同时看 metrics/logs，难以关联 |
| PromQL/LogQL 编写 | 10-30 分钟/次 | 运维工程师 | 语法复杂，产品/研发无法自助查询 |
| 监控看板创建 | 2-4 小时/个 | 运维工程师 | 每次手动配置，Panel 复用率低 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **Claude API** | 日志分析、根因解释、PromQL 生成 | 🟡 个人使用 | 低 | ~¥200-400 |
| **Grafana ML Plugin** | 异常检测（基于 MAD/Prophet）| ❌ 未使用 | 中 | Grafana Enterprise 或自建 |
| **Loki + LogQL AI** | 日志自然语言查询 | ❌ 未使用 | 高 | 需开发 |
| **Alertmanager + AI 路由** | 告警聚合降噪 | 🟡 Alertmanager部分配置 | 中 | Claude API 成本 |
| **Perplexity / Claude** | PromQL/LogQL 辅助生成（直接对话）| 🟡 个人使用 | 低 | 已有 |

---

## 三、高价值机会点详细方案

### 机会1：告警智能降噪与研判

**当前状态**：告警量大，有效告警占比低，OnCall 工程师需逐条研判，产生告警疲劳。  
**目标状态**：AI 对告警进行聚合、去重、优先级排序，每次 OnCall 收到的是已研判过的精简告警。

**方案设计**：
```
告警降噪流程：
  Prometheus → Alertmanager → AI 研判层 → 飞书/PagerDuty

AI 研判规则（Claude API）：
  1. 告警聚合：同一根因的多个告警合并为 1 条（如内存不足同时触发多个 Pod 告警）
  2. 优先级重新评估：
     - 结合当前时间（业务高峰 vs 低谷）
     - 结合影响范围（生产核心服务 vs 测试服务）
     - 结合历史（该告警过去 7 天是否多次触发且是误报）
  3. 自动响应建议（每条告警附上初步排查步骤）

Alertmanager webhook 处理：
  POST /ai-alert-handler
  body: {alert_name, labels, annotations, starts_at}

  AI 输出：
  {
    "severity_revised": "critical",  // 可能降级/升级
    "is_likely_noise": false,
    "suggested_actions": ["检查 Node iz2ze... 的内存使用 kubectl describe node"],
    "related_alerts": ["kube-oomkill-2025-01-15-14:30"]
  }
```

**工具栈**：Alertmanager Webhook + Claude API + 飞书 Bot  
**前置条件**：Alertmanager 已配置并有真实告警数据 ≥ 2 周  
**实施周期**：1-2 周  
**ROI 估算**：有效告警比例从 <30% 提升到 >70%，OnCall 研判时间减少 50%

---

### 机会2：AI 日志异常分析助手

**当前状态**：排障时需要手写复杂 LogQL，只有熟悉语法的运维工程师可以查询，且需要知道日志在哪个 Label。  
**目标状态**：用自然语言描述问题，AI 自动查询相关日志，提炼关键异常信息。

**方案设计**：
```
用户输入（飞书/Slack Bot 或内部 Chat 界面）：
  "查一下今天上午 10点 vllm-qwen 服务有没有 OOM 相关的错误"

AI 处理流程：
  1. 语义理解 → 生成 LogQL：
     {namespace="prod", pod=~"vllm-qwen.*"} |= "OOM" or "out of memory"
     | json | line_format "{{.time}} {{.level}} {{.message}}"

  2. 执行查询（Loki API）

  3. 分析结果（Claude API）：
     "今天 10:03-10:15 期间，vllm-qwen-0 出现 3 次 OOM Killed 事件，
      显存使用在崩溃前达到 48.2GB（接近 L20 显存上限 48GB）。
      建议：降低 gpu_memory_utilization 参数（当前0.95，建议0.85）
      或检查是否有宿主机进程占用显存"

实现方式（两种）：
  方案A：飞书自定义机器人接收问题 → 后端 API 处理
  方案B：Dify 工作流（内置 Loki API Tool）
```

**工具栈**：Loki API + Claude API + 飞书 Bot（or Dify）  
**前置条件**：Loki 日志集中化完成，核心服务日志已接入  
**实施周期**：2-3 周  
**ROI 估算**：日志排障时间从 30-120 分钟减少到 10-20 分钟；非运维人员也可自助查询

---

### 机会3：自然语言生成 PromQL/LogQL

**当前状态**：PromQL 和 LogQL 语法学习成本高，团队只有 2-3 人能熟练使用，查询需求排队。  
**目标状态**：产品/研发用中文描述需求，AI 自动生成对应查询语句。

**方案设计**：
```
中文输入 → AI 生成查询语句 → 用户确认后执行

PromQL 示例：
  用户：查最近 1 小时各服务的 P95 响应时间
  AI 生成：
    histogram_quantile(0.95,
      sum by (le, service) (
        rate(http_request_duration_seconds_bucket[1h])
      )
    )
  附注：此查询需要 http_request_duration_seconds_bucket 指标存在

LogQL 示例：
  用户：找出今天所有接口错误率超过 5% 的服务
  AI 生成：
    sum by (service) (rate({job="app"} |= "error" [5m]))
    /
    sum by (service) (rate({job="app"} [5m])) > 0.05

工具选型：
  - 直接在 Claude 中对话生成（最简单，立即可用）
  - 接入 Grafana 的 "Query Assist"（Grafana Cloud 功能）
  - 自建：Grafana Plugin 调用 Claude API
```

**前置条件**：无（直接使用 Claude 对话即可）  
**实施周期**：立即可用（建立标准 Prompt 模板并推广）  
**ROI 估算**：查询门槛降低，自助查询覆盖人数从 2-3 人扩展到全团队

---

### 机会4：监控看板 AI 辅助生成

**当前状态**：每次新服务上线或需要新视角监控时，运维手动配置 Grafana Panel，耗时 2-4 小时。  
**目标状态**：输入服务信息，AI 生成 Grafana Dashboard JSON，直接导入。

**方案设计**：
```
输入：
  - 服务名称和功能描述
  - 已有的 Prometheus 指标列表（kubectl 查询或 /metrics 端点）
  - 监控重点（延迟/错误率/资源/业务）

AI 输出：
  - Grafana Dashboard JSON（可直接导入）
  - 告警规则建议（YAML 格式）
  - 每个 Panel 的用途说明

Prompt 示例：
  "请为以下服务生成 Grafana Dashboard JSON：
   服务：vLLM 推理服务
   可用指标：{metric_list}（从 /metrics 端点采集）
   监控重点：推理延迟（P50/P99）、GPU 显存使用、请求成功率、并发量
   请输出标准 Grafana Dashboard JSON 格式"
```

**前置条件**：服务已暴露 Prometheus metrics 端点  
**实施周期**：立即可用（对话式生成）  
**ROI 估算**：Dashboard 创建时间从 2-4 小时减少到 30 分钟（生成+调整）

---

## 四、实施路径

### Phase 0（第 1 周）：立即可用的提效

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| PromQL 生成 Prompt 推广 | 建立标准化 Prompt 模板，分享给全团队 | 团队成员 ≥ 3 人使用，自助解决 1+ 查询需求 | 运维 |
| Dashboard 模板生成 | 用 Claude 生成 2-3 个常用服务的 Dashboard | Dashboard 可导入 Grafana，基本可用 | 运维 |

### Phase 1（第 2-4 周）：智能告警接入

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 告警 AI 研判 Webhook | 开发 Alertmanager Webhook + Claude API 处理器 | 每条告警附带 AI 研判结果和建议操作 | SRE + 运维 | Alertmanager 已配置，有 ≥ 2 周告警数据 |
| 告警降噪规则 | 配置同类告警聚合，历史误报自动降级 | 有效告警占比提升 ≥ 20% | SRE | 告警 AI 研判上线 |

### Phase 2（第 5-8 周）：日志 AI 助手

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| Loki 日志 AI 查询助手 | 飞书 Bot 接收自然语言 → Loki API + Claude 分析 | 运维可用自然语言完成 80% 日常日志查询 | SRE + 运维 | Loki 日志集中化完成 |
| AI 助手与告警联动 | 告警触发时自动查询相关日志，附在告警消息中 | P0/P1 告警消息中包含相关日志摘要 | SRE | Loki AI 助手 + 告警 Webhook 已上线 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（告警研判+日志分析）| ~¥300-600 | 约 8-12 人天/月 | 极高 |
| 开发成本（Webhook + Bot）| 一次性 3-5 人天 | 长期持续受益 | 高 |
| **合计（持续）** | **~¥300-600/月** | **约 10-15 人天/月** | **约 1:15** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| AI 研判误将真实告警降级为噪音 | 遗漏真实故障 | AI 只降级低置信度告警；P0 类型的告警不允许被 AI 降级 |
| 日志中含有敏感用户数据 | 数据泄露给 Claude API | 日志发送前过滤 PII 字段（用户ID/手机号等）；使用自托管 LLM 替代 |
| Loki 查询量增加导致性能问题 | Loki 响应慢，影响排障效率 | 限制 AI 查询时间范围（最多 24h）；设置查询超时 30s |
| AI 生成的 PromQL 语义正确但逻辑错误 | 看板数据误导决策 | 生成后展示语句供用户确认；关键看板人工 Review |

> ⚠️ **注意**：当前 Loki 未完整配置、Alertmanager 未完全接管告警，Phase 1/2 需先完成[体系建设总览](./体系建设总览.md)中的基础建设，再推进 AI 叠加能力。
