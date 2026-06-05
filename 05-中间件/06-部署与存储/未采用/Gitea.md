# Gitea - 轻量 Git 服务

> 与GitLab 的对比参考> 当前使用：GitLab

---

## 是什么
Gitea 是 Go 语言编写的轻量自托管 Git 服务，单二进制文件即可运行。相比 GitLab 的全功能 DevOps 平台（代码仓库+ CI/CD + 镜像仓库 + 安全扫描），Gitea 聚焦于 **代码托管 + 轻量 CI**，资源消耗极小。
---

## 与GitLab 的核心区别
| 维度 | GitLab | Gitea |
|------|--------|-------|
| **资源消耗 * | 高（4C8G 起步，推荐 8C16G）| 极低（1C2G 即可流畅运行）|
| **安装** | 多组件（Sidekiq/Gitaly/Redis/PostgreSQL）| 单二进制 / Docker 一容器 |
| **CI/CD** | GitLab CI（功能完整，Runner 丰富）| Gitea Actions（兼容 GitHub Actions）|
| **镜像仓库** | 内置 Container Registry | 无，需外挂 Harbor |
| **安全扫描** | SAST/DAST/Secret Detection | ?无 |
| **代码审查** | MR 功能完善 | PR 功能基础 |
| **升级** | 复杂，需停机 | 替换二进制或重启容器 |

---

## 引入 Gitea 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 极低资源 | 1C2G 机器就能跑，适合边缘节点或灾备 |
| ✅ 极简运维 | 升级替换二进制即可，5 分钟搞定 |
| ✅ 速度极快| 页面和操作响应远快于 GitLab |
| ✅ 兼容 GitHub Actions | CI 配置可复用大量社区 Action |

## 引入 Gitea 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 功能少| 没有内置镜像仓库、安全扫描、环境管理等 |
| ⛔ CI 能力弱| Gitea Actions 不如 GitLab CI 成熟，Runner 生态小 |
| ⛔ 迁移成本 | 现有 GitLab CI 流水线全部需要重写 |
| ⛔ 管理功能 | 用户管理、权限模型不如 GitLab 精细 |

---

## 参考
- https://gitea.io
- https://github.com/go-gitea/gitea
