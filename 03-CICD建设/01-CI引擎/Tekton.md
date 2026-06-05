# Tekton — K8s 原生 CI/CD 框架

> 与 GitLab CI 的对比参考
> 当前使用：GitLab CI

---

## 是什么

Tekton 是 CNCF 孵化的 K8s 原生 CI/CD 框架，以 CRD（Custom Resource Definition）方式定义流水线。每个构建步骤都是一个 Pod 中的容器，适合**对 K8s 控制力要求高**的团队。

---

## 与 GitLab CI 的核心区别

| 维度 | GitLab CI | Tekton |
|------|-----------|--------|
| **架构** | Runner + Job | K8s CRD（Task/Pipeline/Run）|
| **配置方式** | `.gitlab-ci.yml` | YAML CRD apply |
| **K8s 集成** | Runner on K8s | 原生 CRD，完全 K8s 原生 |
| **编排能力** | Stage/Job 线性 | DAG 任务编排 |
| **可复用** | Template include | Task/Pipeline 可跨项目共享 |
| **触发器** | Push/MR/Tag | EventListener + Trigger |
| **UI** | GitLab 内置 | Tekton Dashboard / CLI |

---

## 引入 Tekton 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 完全 K8s 原生 | 流水线即 K8s 资源，kubectl apply 即触发 |
| ✅ DAG 编排 | 复杂依赖关系的任务编排能力 |
| ✅ 强可复用 | Task 和 Pipeline 像容器镜像一样跨项目共享 |
| ✅ 可观测性好 | 每个步骤都是 Pod，kubectl logs 直接看 |

## 引入 Tekton 的代价

| 代价 | 说明 |
|------|------|
| ❌ 配置冗长 | 一个简单流水线可能需要上百行 YAML |
| ❌ 无代码仓库 | 需要额外配套代码仓库（GitLab/GitHub）|
| ❌ 学习曲线 | CRD 概念多（Task/Pipeline/Run/Trigger），上手门槛高 |
| ❌ 调试困难 | 出错排查不如 GitLab CI 方便 |

---

## 参考

- https://tekton.dev
- https://github.com/tektoncd/pipeline
