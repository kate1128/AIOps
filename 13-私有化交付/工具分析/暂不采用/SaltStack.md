# SaltStack — 暂不采用

> 当前状态：❌ 暂不采用（功能与 Ansible 高度重叠，Ansible 已在用）

---

## 是什么

SaltStack（Salt）是开源的 IT 自动化和配置管理平台，使用 Agent（Minion）+ Master 架构，通过消息总线（ZeroMQ）下发指令，执行速度比 Ansible SSH 方式更快。

---

## 与 Ansible 对比

| 维度 | SaltStack | Ansible |
|---|---|---|
| 架构 | Agent（Minion）+ Master | 无 Agent，纯 SSH |
| 执行速度 | ✅ 更快（消息总线）| 🟡 SSH 有开销 |
| 安装复杂度 | ❌ 需在每台机器装 Minion | ✅ 目标机只需 Python |
| 学习曲线 | 陡峭 | 平缓 |
| 社区生态 | 较小 | ✅ 更大 |
| 国内文档 | 少 | ✅ 丰富 |

---

## 不采用原因

1. Ansible 已在用，功能完全覆盖当前需求
2. SaltStack Agent 架构需要在所有目标机器安装 Minion，客户环境改造成本高
3. 团队对 Ansible 更熟悉，迁移收益不明显
