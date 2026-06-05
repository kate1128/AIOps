# AI 提效计划 - License 授权

> 将 AI 引入 License 全生命周期管理：AI 辅助生成授权配置、异常使用模式检测、到期预警与续费预测、合规审计自动化。目标：License 相关运营工作减少 70% 手动操作。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| 新客户 License 生成 | 15-30 分钟/客户 | License 运营 | 需手动填写 Features/到期日/用户数，ECDSA 签名流程繁琐 |
| License 到期跟进 | 1-2 小时/月（人工扫描）| License 运营/客成 | 没有自动预警，靠人工定期检查 |
| 异常 License 检测 | 基本无主动检测 | 研发/运维 | 转移使用、破解行为靠偶然发现 |
| License 使用量报告 | 1-2 小时/次（月度）| 运营 | 手动汇总 API 调用量/用户数/特性使用 |
| 续费决策支持 | 无数据支撑 | 客成 | 不知道客户实际使用深度，影响续费策略 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **Claude API** | License 配置辅助生成、异常分析、报告生成 | 🟡 个人使用 | 低 | ~¥100-200 |
| **Dify（自托管）** | License 生成工作流（可视化操作台）| ❌ 未部署 | 中 | 可自托管 |
| **Prometheus + Grafana** | License 使用量指标监控 | 🟡 规划中 | 中 | 已有基础设施 |
| **飞书 Bot** | 到期预警、异常告警推送 | 🟡 部分使用 | 低 | 已有 |

---

## 三、高价值机会点详细方案

### 机会1：License 生成流程 AI 辅助

**当前状态**：License 运营人员手动填写 features、user_limit、expire_at、machine_id 等字段，用私钥签名，错误率高且耗时。  
**目标状态**：输入客户信息，AI 自动生成符合规范的 License 配置，运营确认后一键签发。

**方案设计**：
```
Dify 工作流：客户信息输入 → AI 生成配置 → 人工确认 → 自动签名

输入表单（Dify 表单节点）：
  - 客户名称
  - 授权类型（标准版/专业版/企业版）
  - 用户数上限
  - 授权期限（日期）
  - 特殊功能开关（如：GPU 推理 / 多模态 / API 访问）
  - 硬件绑定机器码（可选）

AI 生成 License 配置：

  Prompt：
  "根据以下客户信息，生成 SmartVision License JSON 配置：
   客户：{client_name}，类型：{license_type}，
   用户数：{user_limit}，到期：{expire_date}，
   特性：{features_list}，机器码：{machine_id}
   
   输出规范的 JSON，包含所有必填字段，并检查：
   1. expire_date 格式是否为 ISO8601
   2. features 列表是否与 license_type 匹配（企业版才能开放 API 访问）
   3. 如果 machine_id 为空，注意标注'浮动授权'"

  # 生成 License 并用私钥签名
  cat license_config.json | python3 sign_license.py --key /secure/private.pem

  # 输出到飞书/邮件给运营确认
```

**工具栈**：Dify + Claude API + Python（ECDSA P-256 签名脚本）  
**前置条件**：私钥安全存储（不暴露给 Dify/Claude）；License 字段规范文档  
**实施周期**：1 周  
**ROI 估算**：License 生成时间从 15-30 分钟减少到 3-5 分钟；配置错误减少 80%

---

### 机会2：License 到期自动预警

**当前状态**：没有自动化预警，License 到期全靠运营人员定期手动检查，客户 License 到期后才反应，影响客户体验和续费率。  
**目标状态**：系统自动检查所有客户 License 到期时间，提前 90/30/7 天通过飞书推送提醒，并附上客户使用情况。

**方案设计**：
```
定时任务（每天早上 9:00）：

# check-license-expiry.py
import json
from datetime import datetime, timedelta
import requests

licenses = load_all_licenses()  # 从数据库/文件读取所有License

for lic in licenses:
    days_left = (lic.expire_date - datetime.now()).days
    
    if days_left in [90, 30, 7, 1]:
        # 获取该客户的使用量数据
        usage = get_client_usage(lic.client_id, last_30_days=True)
        
        # AI 生成续费建议摘要
        summary = claude_analyze(f"""
          客户 {lic.client_name} License 还有 {days_left} 天到期
          
          过去 30 天使用情况：
          - 活跃用户：{usage.active_users}/{lic.user_limit}
          - API 调用量：{usage.api_calls}次
          - 主要使用功能：{usage.top_features}
          - 使用增长趋势：{usage.growth_trend}
          
          请生成：
          1. 使用情况总结（2句话）
          2. 续费价值点（基于实际使用，给客成人员参考）
          3. 推荐的续费套餐（基于使用量）
        """)
        
        # 飞书通知
        send_feishu(f"""
          ⏰ License 到期提醒
          客户：{lic.client_name}
          剩余天数：{days_left} 天
          
          {summary}
          
          [续费操作] [查看详情]
        """)
```

**工具栈**：Python 定时任务 + Claude API + 飞书 Bot  
**前置条件**：License 数据有集中存储（数据库或文件）；有客户使用量统计 API  
**实施周期**：1 周  
**ROI 估算**：续费跟进从被动变主动；续费提前感知率从 20% 提升到 100%

---

### 机会3：License 异常使用检测

**当前状态**：License 被转移给其他机器使用、通过代理服务共享等异常行为基本无法主动发现，靠业务异常才能偶尔察觉。  
**目标状态**：实时分析 License 验证日志，AI 识别异常模式并告警。

**方案设计**：
```
异常检测规则（License 验证日志分析）：

规则 1：机器码漂移（浮动授权绑定后机器码变化）
  - 同一 license_id 在 24 小时内从不同 machine_id 验证
  - 触发告警：可能被转移使用

规则 2：验证请求地理异常
  - 同一 license 在 1 小时内从多个不同 IP 验证
  - 触发告警：可能通过代理共享

规则 3：用户数超过授权上限
  - 单 license concurrent_users > user_limit * 1.1
  - 触发告警：超量使用

规则 4：深夜高频请求（非正常业务时间）
  - 22:00-06:00 请求量 > 日均 50%
  - 触发告警：可能有自动化滥用

AI 分析（每日一次，汇总异常）：
  "分析以下 License 验证日志，识别异常使用模式，
   按严重程度（高/中/低）分类，给出每个异常的证据和可能原因"
```

**工具栈**：License 验证日志 + Loki / ClickHouse + Claude API + 飞书  
**前置条件**：License 验证服务有详细日志；日志包含 license_id、machine_id、IP、时间  
**实施周期**：2 周  
**ROI 估算**：License 异常检测从无到有；潜在收入损失（转移使用）可被发现

---

### 机会4：月度使用量报告 AI 生成

**当前状态**：每月需要手动整理客户使用量，生成报告给客成和销售团队参考，耗时且格式不统一。  
**目标状态**：每月自动生成所有客户的使用量分析报告，并给出续费和扩容建议。

**方案设计**：
```
月度任务（每月 1 号自动执行）：

for each client:
  data = {
    "license_info": get_license_details(client_id),
    "usage_30d": get_usage_stats(client_id, 30),
    "trend": get_usage_trend(client_id, 90)  # 3个月趋势
  }
  
  report = claude_generate(f"""
    生成 {client.name} 的月度使用量分析报告：
    
    数据：{data}
    
    包含：
    1. 本月使用摘要（用户数/API调用量/主要功能）
    2. 与上月对比（增长/下降，给出百分比）
    3. License 容量评估（还剩多少余量或是否超量）
    4. 续费/扩容建议（基于使用趋势）
    5. 重点客户风险提示（使用量下降超30%，可能流失风险）
  """)
  
  # 推送到飞书多维表格（自动更新行）
  update_feishu_bitable(client_id, report)
```

**工具栈**：Python + Claude API + 飞书多维表格 API  
**前置条件**：License 服务有使用量统计 API  
**实施周期**：1 周  
**ROI 估算**：月度报告从 1-2 小时减少到自动化；客成人员有数据支撑进行客户经营

---

## 四、实施路径

### Phase 0（第 1-2 周）：核心预警上线

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| License 到期自动预警 | 部署定时任务，飞书推送 90/30/7/1 天提醒 | 所有到期 License 有预警，不再靠人工扫描 | 运营/研发 |
| License 生成辅助 | Dify 表单 + AI 配置生成，人工确认后签发 | License 生成时间 < 5 分钟 | 运营/研发 |

### Phase 1（第 3-4 周）：数据驱动

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 月度报告自动化 | 定时生成所有客户使用量报告，同步飞书多维表格 | 每月 1 日自动完成，0 手工操作 | 运营/研发 | 使用量统计 API 已就绪 |
| 到期预警附使用分析 | 预警消息中附 AI 生成的续费价值点 | 客成团队反馈有帮助 | 运营 | 使用量数据接通 |

### Phase 2（第 5-8 周）：安全与合规

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| License 异常检测 | 日志分析 + AI 识别异常模式 | 能检测出转移使用等异常行为 | 研发/运维 | License 验证日志集中存储 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（生成+分析+报告）| ~¥100-200/月 | 约 4-6 人天/月 | 极高 |
| Dify 自托管 | 运维 0.5 人天/月 | License 生成错误减少 | 高 |
| **合计** | **~¥150-250/月** | **约 5-8 人天/月** | **约 1:15** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| AI 生成 License 配置字段错误 | 客户无法正常使用产品 | 签发前人工 Review；关键字段（到期日/用户数）有格式校验 |
| 私钥暴露给 AI 服务 | 严重安全风险（可伪造 License）| 严格隔离：AI 只生成明文 JSON，签名操作在隔离脚本中执行，私钥不经过 AI |
| 异常检测误报（正常客户被标记）| 影响客户关系 | 异常检测为"建议调查"，不自动发送给客户；仅内部运营看到 |
| 续费预测不准确 | 误导客成策略 | AI 建议作为参考，客成最终决策；持续收集反馈优化 Prompt |
