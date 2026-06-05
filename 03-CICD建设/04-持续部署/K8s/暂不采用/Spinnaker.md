# Spinnaker — 持续交付平台

> 与 ArgoCD 的对比参考
> 当前使用：手动 kubectl（计划引入 ArgoCD）

---

## 是什么

Spinnaker 是 Netflix 开源的持续交付平台，主打**多云部署**和**发布策略管理**（灰度、蓝绿、金丝雀）。与 ArgoCD 的 GitOps 不同，Spinnaker 采用"应用编排"模式，通过 Pipeline 定义发布流程。

---

## 与 ArgoCD 的核心区别

| 维度 | ArgoCD | Spinnaker |
|------|--------|-----------|
| **模式** | GitOps（状态同步）| Pipeline（流程编排）|
| **配置来源** | Git 仓库 | 自有存储（GCS/S3/Redis）|
| **发布策略** | 基本（滚动/蓝绿）| 强（灰度/金丝雀/红黑/A/B）|
| **多云** | K8s | K8s + AWS/GCP/Azure + 传统 |
| **CD Pipeline** | PreSync/Sync/PostSync Hook | 完整的阶段式 Pipeline |
| **运维复杂度** | 中 | 极高（6+ 组件，需要 Redis/S3/CloudDriver）|

---

## 引入 Spinnaker 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 精细的发布策略 | 灰度发布、A/B 测试、自动回滚策略开箱即用 |
| ✅ 多云统一 | 一套平台管理 K8s + 云主机 + 函数计算 |
| ✅ 审批网关 | 内置审批、通知、合规检查 |
| ✅ 金丝雀分析 | 基于 Prometheus 的金丝雀自动判定 |

## 引入 Spinnaker 的代价

| 代价 | 说明 |
|------|------|
| ❌ 极重 | 至少 6 个组件（CloudDriver/Orca/Echo/Deck/Gate/Rosco）|
| ❌ 运维复杂 | 部署和维护 Spinnaker 本身就是大工程 |
| ❌ 学习曲线陡峭 | 概念多（Application/Cluster/ServerGroup/Pipeline）|
| ❌ 中小团队不匹配 | Spinnaker 适合大规模发布平台，小团队过度设计 |

---

## 参考

- https://spinnaker.io
- https://github.com/spinnaker/spinnaker
