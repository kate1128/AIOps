# Grafana OnCall — 开源 On-Call 值班管理

> 和 Grafana 深度集成的开源 On-Call 平台，不需要 PagerDuty，不需要额外账号体系。已有 Grafana 的团队最低成本接入。

---

## 是什么

Grafana OnCall 是 Grafana Labs 出品的开源 On-Call 管理系统，前身是 Amixr。核心能力：**告警路由 → 值班排班 → 升级策略 → 飞书/企微/钉钉通知**，一套流程闭环。

2022 年开源，已集成到 Grafana Cloud 和 Grafana OSS（v9.1+）。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **告警路由** | 按告警标签（severity、service）路由到不同团队/个人 |
| **值班排班** | 可视化排班日历，支持轮换、覆盖、节假日设置 |
| **升级策略** | 一线无响应 → 自动升级二线 → 升级管理层，时间可配 |
| **多渠道通知** | 飞书、企微、钉钉、Slack、Telegram、电话、短信 |
| **告警分组** | 同类告警自动合并，避免告警风暴 |
| **手动触发** | 支持直接触发 Incident，不依赖 Prometheus |
| **Mobile App** | 移动端 App，随时查看值班状态和告警 |

---

## 与当前技术栈的关系

```
Prometheus Alerting Rules
        │ 触发告警
        ▼
Grafana Alerting（已有）
        │ 路由到 OnCall
        ▼
Grafana OnCall
        │ 按排班 + 升级策略
        ▼
飞书 / 企微 通知（已用）
```

**你们已有 Grafana，OnCall 是增量功能**，不需要新建一套账号和权限体系。

---

## 安装方式

### 方式一：Grafana Cloud（推荐起步）

Grafana Cloud Free Tier 包含 OnCall，注册即用，无需部署：

1. 登录 [grafana.com](https://grafana.com) → 创建 Free 账号
2. 左侧菜单 → Alerts & IRM → OnCall
3. 连接你们本地 Grafana（通过 Grafana OnCall Plugin）

### 方式二：自托管（Helm）

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana-oncall grafana/oncall \
  --namespace monitoring \
  --create-namespace \
  -f oncall-values.yaml
```

```yaml
# oncall-values.yaml 最小配置
base_url: https://oncall.your-domain.com

# 依赖（也可用外部已有的）
mariadb:
  enabled: true
rabbitmq:
  enabled: true
redis:
  enabled: true
```

### 方式三：Grafana OSS 插件（推荐，已有 Grafana 直接装）

```bash
# 在已有 Grafana 上安装 OnCall 插件
grafana-cli plugins install grafana-oncall-app

# 重启 Grafana 后在 Plugins 中启用并配置
```

---

## 飞书通知接入

```
Grafana OnCall → Contact Points → 新建 → 选择 Telegram / Webhook

# 飞书 Webhook 配置：
URL: https://open.feishu.cn/open-apis/bot/v2/hook/<YOUR_TOKEN>
Method: POST
Headers: Content-Type: application/json

# 消息体模板（飞书卡片格式）：
{
  "msg_type": "text",
  "content": {
    "text": "🚨 [{{ .GroupLabels.severity }}] {{ .GroupLabels.alertname }}\n节点: {{ .CommonLabels.instance }}\n时间: {{ .StartsAt.Format \"2006-01-02 15:04:05\" }}"
  }
}
```

---

## 值班排班配置示例

```
On-Call Schedule：AI Platform 值班
├── 一线（主）：每人轮值 1 周
│   ├── 张三：2026-05-27 ~ 06-03
│   ├── 李四：2026-06-03 ~ 06-10
│   └── ...
└── 二线（备）：轮值周期错开半周
    ├── 王五：一线升级后响应
    └── 升级等待时间：15 分钟
```

---

## 升级策略配置

```
Escalation Chain：AI Platform P0
Step 1: 立即通知 一线 On-Call（飞书 @）
Step 2: 等待 5 分钟无响应 → 飞书 + 电话
Step 3: 等待 15 分钟无响应 → 通知 二线 On-Call
Step 4: 等待 30 分钟无响应 → 通知 技术负责人
```

---

## 是否引入评估

| 维度 | 评估 |
|---|---|
| 成本 | ✅ 开源免费，Cloud Free Tier 够小团队用 |
| 集成难度 | ✅ 已有 Grafana，装插件即可，1-2 小时接入 |
| 替代方案 | 飞书群机器人（无排班、无升级链，只适合最初期）|
| 引入时机 | 🟡 **建议：On-Call 制度确定后即可接入**，避免靠人工记谁当班 |

---

## 对比 PagerDuty / OpsGenie

| 功能 | Grafana OnCall | PagerDuty | OpsGenie |
|---|---|---|---|
| 开源 | ✅ | ❌ | ❌ |
| 价格 | 免费 | $19/人/月起 | $9/人/月起 |
| Grafana 集成 | ✅ 原生 | 🟡 插件 | 🟡 插件 |
| 排班日历 | ✅ | ✅ | ✅ |
| 移动 App | ✅ | ✅ | ✅ |
| 国内通知渠道 | 🟡 需配置 Webhook | ❌ 不支持飞书 | ❌ 不支持飞书 |
| 适用场景 | 中小团队 + 已用 Grafana | 大团队 / 企业 | 大团队 / 企业 |
