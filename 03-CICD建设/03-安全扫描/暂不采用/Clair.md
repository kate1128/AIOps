# Clair — 容器镜像漏洞扫描

> 与 Trivy 的对比参考
> 当前使用：无（计划引入 Trivy）

---

## 是什么

Clair 是 Red Hat 开源（Quay 团队）的容器镜像漏洞扫描工具。与 Trivy 的单二进制设计不同，Clair 是**C/S 架构**——使用 PostgreSQL 存储漏洞库，API Server 接收扫描请求。

---

## 与 Trivy 的核心区别

| 维度 | Trivy | Clair |
|------|-------|-------|
| **架构** | CLI 单二进制 | C/S（API + PostgreSQL）|
| **部署** | 一行命令 | 需要部署 API + 数据库 + 更新器 |
| **扫描速度** | 秒级 | 分钟级（需要先 `clairctl analyze`）|
| **数据库** | 内置 | PostgreSQL |
| **Harbor 集成** | ✅ 内置 | ✅ 内置 |
| **增量更新** | 自动 | 需配置 updater |

---

## 引入 Clair 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ Harbor 原生集成 | Harbor 默认支持 Clair 作为扫描引擎 |
| ✅ 成熟稳定 | Red Hat 产品，大规模生产验证 |
| ✅ 数据本地 | 漏洞库完全自托管，不依赖外部 |

## 引入 Clair 的代价

| 代价 | 说明 |
|------|------|
| ❌ 架构重 | 需要运行 API Server + PostgreSQL + 更新器 |
| ❌ 扫描慢 | 相比 Trivy 慢得多 |
| ❌ 运维成本 | 需要维护漏洞库的更新和 PostgreSQL |

---

## 参考

- https://clairproject.org
- https://github.com/quay/clair
