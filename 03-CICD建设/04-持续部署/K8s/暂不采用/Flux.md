# Flux — GitOps 持续部署

> 与 ArgoCD 的对比参考
> 当前使用：手动 kubectl（计划引入 ArgoCD）

---

## 是什么

Flux 是 CNCF 孵化的 GitOps 工具，与 ArgoCD 同样实现 K8s 的 GitOps 部署。最大区别是 Flux 的设计哲学更**轻量、Operator 风格**——它没有独立的 UI，完全通过 K8s CRD 和 CLI 管理。

---

## 与 ArgoCD 的核心区别

| 维度 | ArgoCD | Flux |
|------|--------|------|
| **架构** | Client-Server（gRPC）| 纯 Operator（Controller）|
| **UI** | ✅ Web UI 功能完整 | ❌ 依赖 CLI + VS Code 插件 |
| **通知** | Webhook | Notification Controller |
| **SSO** | ✅ Dex/OIDC | ❌ |
| **多集群** | ✅ 原生支持 | ✅ Cluster API |
| **配置复杂度** | 中 | 低（CRD 更少）|
| **Kustomize** | ✅ | ✅ 原生支持更好 |

---

## 引入 Flux 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 更轻量 | 只需要几个 Deployment，没有 gRPC Server |
| ✅ 严格 Operator 风格 | 全部通过 CRD 管理，GitOps 更纯粹 |
| ✅ Kustomize 支持好 | 对 Kustomize 的原生支持比 ArgoCD 更深 |
| ✅ 资源占用少 | 相比 ArgoCD 省内存 |

## 引入 Flux 的代价

| 代价 | 说明 |
|------|------|
| ❌ 无 UI | 一切操作都通过 CLI 和 Git，不适合需要图形化操作的场景 |
| ❌ 排查困难 | 出问题时没有 ArgoCD 那种直观的差异对比界面 |
| ❌ 团队效率 | 开发和运维跨团队协作时，ArgoCD 的 UI 更友好 |
| ❌ SSO 弱 | 企业集成 LDAP/OIDC 不如 ArgoCD 方便 |

---

## 参考

- https://fluxcd.io
- https://github.com/fluxcd/flux2
