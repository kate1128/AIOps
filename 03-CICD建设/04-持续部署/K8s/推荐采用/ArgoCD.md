# ArgoCD — GitOps 持续部署

> 以 Git 仓库为唯一事实来源，自动将 K8s 集群状态与代码仓库保持同步。
> 当前状态：⏳ 推荐采用（第二阶段目标）

---

## 是什么

ArgoCD 是 CNCF 毕业的 GitOps 持续部署工具，核心理念是：**K8s 集群的期望状态完全由 Git 仓库中的配置文件定义**。ArgoCD 持续监控 Git 变更，自动将集群状态同步到期望状态。与传统 CI/CD（CI 主动推送）相反，是"拉模式"部署。

---

## 与 CI 推模式的核心区别

| 维度 | CI 推模式（kubectl） | ArgoCD 拉模式 |
|------|---------------------|---------------|
| **部署触发** | CI 直接操作 K8s | ArgoCD watch Git 仓库 |
| **K8s 权限** | CI 需要 K8s 凭据 | 只有 ArgoCD 有 K8s 权限 |
| **状态同步** | CI 推送完成后不管 | 持续确保 Git 状态 = 集群状态 |
| **回滚** | 手动执行 kubectl rollout undo | UI 一键回滚到 Git 历史版本 |
| **漂移检测** | ❌ | ✅ 自动检测手动修改，self-heal |
| **多集群** | 每个集群配 CI 连接 | 一个 ArgoCD 管理多个集群 |

---

## 当前方案演进

```
阶段一（当前）：
  CI 构建 → 更新配置仓库 image tag → 人工 kubectl apply
  
阶段二（目标）：
  CI 构建 → 更新配置仓库 image tag
                                     → ArgoCD 自动检测 → 同步 K8s
```

---

## 引入 ArgoCD 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 权限分离 | CI 不需要 K8s 凭据，只有 ArgoCD 有 K8s 权限 |
| ✅ 自动回滚 | 部署失败自动恢复到上一版本 |
| ✅ 自愈 | 有人手动改集群资源，ArgoCD 自动恢复 |
| ✅ 多集群管理 | 一个 ArgoCD 管理 dev/pre/prod 多个集群 |
| ✅ 可视化 | Web UI 展示集群状态与 Git 差异 |

## 引入 ArgoCD 的代价

| 代价 | 说明 |
|------|------|
| ❌ 新增组件 | ArgoCD 需要独立部署和维护 |
| ❌ 配置仓库 | 需要额外维护一套 K8s 配置仓库 |
| ❌ 学习成本 | GitOps 理念和 ArgoCD CRD 需要学习 |
| ❌ 排查链路 | 部署问题排查从 CI → 配置仓库 → ArgoCD → K8s 四个环节 |

---

## 参考

- https://argo-cd.readthedocs.io
- https://github.com/argoproj/argo-cd
