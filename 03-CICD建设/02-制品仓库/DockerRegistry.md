# Docker Registry — 镜像仓库

> 与 Harbor 的对比参考
> 当前使用：Harbor

---

## 是什么

Docker Registry 是 Docker 官方提供的基础镜像仓库，只有最核心的 push/pull 功能，没有任何企业特性。Harbor 就是在 Registry 基础上的企业级封装。

---

## 与 Harbor 的核心区别

| 维度 | Harbor | Docker Registry |
|------|--------|----------------|
| **漏洞扫描** | ✅ Trivy 集成 | ❌ |
| **权限管理** | ✅ 项目级 RBAC | ❌ |
| **Web UI** | ✅ 功能完整 | ❌ 极简 |
| **镜像复制** | ✅ 跨集群自动同步 | ❌ |
| **Helm Chart** | ✅ OCI 存储 | ❌ |
| **垃圾回收** | ✅ UI 操作 | ✅ CLI 手动 |
| **运维复杂度** | 中 | 低 |

---

## 引入 Docker Registry 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 极简 | 一个容器搞定，没有数据库、没有后台任务 |
| ✅ 兼容性 | 最标准的 Registry API，所有工具兼容 |
| ✅ 资源占用少 | 相比 Harbor 省 50%+ 内存 |

## 引入 Docker Registry 的代价

| 代价 | 说明 |
|------|------|
| ❌ 无安全扫描 | 镜像推上去有没有漏洞完全不知道 |
| ❌ 无权限控制 | 谁都能 push/pull，不安全 |
| ❌ 无 Web UI | 管理镜像、查看 Tag 全靠 CLI |
| ❌ 无复制 | 灾备需要自己写脚本同步 |

---

## 参考

- https://hub.docker.com/_/registry
- https://github.com/distribution/distribution
