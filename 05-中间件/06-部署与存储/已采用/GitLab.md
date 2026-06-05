# GitLab - 代码仓库 + CI/CD

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 代码托管、GitLab CI 流水线 |
| 版本 | gitlab.com / 私有部署 |
| 分支策略 | dev ?pre ?main |

---

## 存在问题

- CI 流水线到镜像推送为止，部署阶段未自动化
- 缺少制品扫描（Trivy）和归档环节
- Runner 资源配置待确?
---

## 优化建议

- CI 集成 Trivy 镜像扫描 + 自动归档
- 引入 ArgoCD 实现 GitOps，CI 只更新配置仓?- Runner 迁移?K8s 动态 executor

> 参考：`05-cicd/`、`工具分析/01-GitLab CI.md`
