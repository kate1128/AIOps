# OPA Gatekeeper — 策略即代码治理

> 基于 Rego 语言的准入控制，适合复杂合规规则与跨团队统一策略。

---

## 是什么

OPA Gatekeeper 是 Kubernetes 准入控制方案，使用 Rego 规则定义“什么资源允许创建”。

---

## 核心能力

- Admission 控制：不合规资源直接拒绝
- ConstraintTemplate：可复用策略模板
- 违规审计：扫描已存在资源并输出违规报告

---

## 适用场景

- 大型组织统一合规策略
- 需要复杂逻辑判断（比 YAML 规则更灵活）
- 安全审计需要策略可编程

---

## Kyverno vs OPA

- 快速落地、YAML 友好：Kyverno
- 复杂策略、可编程能力：OPA

建议中小团队优先 Kyverno；当规则复杂度上升再引入 OPA。

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/open-policy-agent/gatekeeper
- Star：4.2k（统计日期：2026-05-27）

