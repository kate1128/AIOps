# GitHub Actions — CI/CD 工作流引擎

> 与 GitLab CI 的对比参考
> 当前使用：GitLab CI

---

## 是什么

GitHub Actions 是 GitHub 内置的 CI/CD 引擎，通过 `.github/workflows/*.yml` 定义自动化工作流。与 GitLab CI 定位相同，但生态基于 GitHub——代码托管 + Actions 一体化。

---

## 与 GitLab CI 的核心区别

| 维度 | GitLab CI | GitHub Actions |
|------|-----------|---------------|
| **代码平台** | GitLab 专属 | GitHub 专属 |
| **Runner** | 自托管或 GitLab 托管 | GitHub 托管或自托管 |
| **市场** | 无 | Actions Marketplace（丰富社区 Action）|
| **并发** | 取决于 Runner | 免费账户有限制，付费扩容 |
| **Secret 管理** | CI/CD Variables | Repository/Environment Secrets |
| **矩阵构建** | YAML rules + parallel | `strategy.matrix` 原生支持 |
| **自托管** | K8s/Docker Runner | Self-hosted Runner |

---

## 引入 GitHub Actions 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 社区 Action | 官方和市场提供的丰富 Action，开箱即用 |
| ✅ 矩阵构建 | 原生支持多版本/多平台并行测试 |
| ✅ 零运维 Runner | GitHub 托管 Runner，无需自建 |
| ✅ 与 GitHub 深度集成 | Issue/PR/Release 联动 |

## 引入 GitHub Actions 的代价

| 代价 | 说明 |
|------|------|
| ❌ 需迁移到 GitHub | 代码仓库从 GitLab 迁到 GitHub，迁移成本高 |
| ❌ 存储限制 | 制品和日志存储有配额约束 |
| ❌ 自托管复杂 | Self-hosted Runner 的维护不如 GitLab Runner 方便 |
| ❌ 环境管理 | 多环境/多集群的权限模型不如 GitLab 成熟 |

---

## 参考

- https://github.com/features/actions
- https://docs.github.com/actions
