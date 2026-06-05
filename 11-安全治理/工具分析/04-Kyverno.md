# Kyverno — Kubernetes 策略引擎

> 用声明式策略约束 K8s 资源，防止不安全配置进入集群。

---

## 是什么

Kyverno 是 K8s 原生策略引擎，策略本身使用 YAML 定义，学习成本低，适合平台团队快速落地治理。

---

## 核心能力

- Validate：校验资源配置（例如禁止 privileged）
- Mutate：自动补齐字段（例如统一加 label）
- Generate：自动生成资源（例如默认 NetworkPolicy）
- Policy Report：策略命中和违规统计

---

## 常见策略

- 禁止 root 用户容器
- 强制 imagePullPolicy
- 强制 request/limit
- 限定镜像仓库白名单

---

## 实践建议

- 先 audit 模式观察，不立即阻断
- 稳定后切换 enforce 模式
- 策略版本化管理，按环境灰度发布

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/kyverno/kyverno
- Star：7.8k（统计日期：2026-05-27）

