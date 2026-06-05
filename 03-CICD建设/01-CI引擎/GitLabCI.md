# GitLab CI/CD — 代码托管与流水线一体化平台

> 代码仓库 + CI/CD 流水线的统一平台，当前 CI 引擎核心基础设施。
> 当前状态：✅ 已采用

---

## 是什么

GitLab 是开源的 DevOps 平台，将代码仓库、代码评审（MR）、CI/CD 流水线、制品管理、安全扫描整合在一个平台内。**GitLab CI** 是其内置的流水线引擎，通过 `.gitlab-ci.yml` 定义自动化流程，Runner 执行具体任务。

---

## 核心能力

| 功能模块 | 说明 |
|---|---|
| **代码仓库** | Git 托管，分支管理，代码评审（Merge Request）|
| **GitLab CI** | `.gitlab-ci.yml` 定义流水线，多 Stage 自动化 |
| **GitLab Runner** | 执行 CI Job 的 Agent，支持 Docker / K8s Executor |
| **Container Registry** | 内置 Docker 镜像仓库（当前用 Harbor 替代）|
| **SAST/DAST** | 内置安全扫描（代码漏洞检测）|
| **Environments** | 部署环境追踪 |
| **Release** | 版本发布管理，自动生成 Changelog |

---

## 与替代方案对比

| 维度 | GitLab CI | Jenkins | GitHub Actions | Tekton |
|------|-----------|---------|---------------|--------|
| **代码仓库** | 一体化 | 独立 | GitHub 一体化 | 独立 |
| **配置方式** | YAML | Groovy | YAML | YAML (CRD)|
| **云原生** | Runner on K8s | Agent on K8s | 托管 | K8s 原生 |
| **插件/市场** | 内置功能 | 1800+ 插件 | Actions 市场 | 社区 Catalog |
| **运维成本** | 低 | 高 | 零（托管）| 中 |
| **复杂流水线** | 中 | 强（共享库）| 中 | 强（Task/DAG）|

---

## 流水线架构

```
代码推送 / MR 合并
    │
    └── GitLab CI 触发
            │
            ├── lint（代码风格检查）
            ├── test（单元测试 + 覆盖率）
            ├── build（构建 Docker 镜像）
            ├── scan（Trivy 漏洞扫描）
            ├── deploy-staging（自动部署预发）
            └── deploy-prod（手动审批 + 部署生产）
```

---

## 与其他工具集成

| 集成 | 方式 |
|---|---|
| Harbor | 推送镜像到 Harbor |
| ArgoCD | GitLab CI 更新 Helm values，ArgoCD 检测变更部署 |
| Trivy | CI 中镜像扫描，高危漏洞阻断流水线 |
| Cosign | CI 中签名镜像 |
| Ansible | 触发 Ansible Playbook 部署二进制服务 |
