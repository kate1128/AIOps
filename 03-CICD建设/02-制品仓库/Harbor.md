# Harbor — 企业级容器镜像仓库

> 私有 Docker 镜像和 Helm Chart 的统一存储中心，当前制品仓库核心。
> 当前状态：✅ 已采用

---

## 是什么

Harbor 是 CNCF 毕业的开源企业级镜像仓库，是 DockerHub 的私有化替代品。它在标准 Registry API 基础上增加了镜像安全扫描、角色权限管理、镜像复制同步、Helm Chart 存储等企业必备功能。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **镜像安全扫描** | 集成 Trivy，推送镜像时自动扫描漏洞 |
| **多项目隔离** | 按团队/业务创建 Project，权限独立管理 |
| **镜像签名** | Cosign 集成，确保镜像来源可信 |
| **Helm Chart 仓库** | OCI 标准存储 Helm Chart |
| **跨仓库复制** | 生产和灾备仓库自动同步 |
| **垃圾回收** | 定期清理未引用的镜像层 |
| **镜像代理** | 代理 DockerHub / GCR，解决拉取限速 |

---

## 与替代方案对比

| 维度 | Harbor | Docker Registry | Nexus | GitLab Registry |
|------|--------|----------------|-------|----------------|
| **漏洞扫描** | ✅ 内置 Trivy | ❌ | ⚠️ IQ 需付费 | 付费版 |
| **RBAC** | 项目级 | ❌ | 仓库级 | 项目级 |
| **复制** | 跨集群 | ❌ | 付费版 | ❌ |
| **镜像代理** | ✅ | ❌ | ❌ | ❌ |
| **Helm Chart** | ✅ OCI | ❌ | ✅ | ✅ |
| **运维成本** | 中 | 低 | 中 | 与 GitLab 一起 |

---

## 当前用法

- 项目隔离：`smartvision-dev` / `smartvision-pre` / `smartvision-prod`
- 镜像 Tag 规范：`dev-{sha}` / `rc-{semver}` / `{semver}`
- 保留策略：dev 30天 / pre 90天 / 正式版永久
- 集成 Trivy 自动扫描（待开启）

> 详细规范见：`制品管理方案.md`
