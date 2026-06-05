# Nexus - 通用制品仓库

> 与Harbor 的对比参考> 当前使用：Harbor

---

## 是什么
Nexus Repository ?Sonatype 出品的通用制品仓库，支?Maven、npm、PyPI、Docker、Helm Chart、Raw 等几乎所有制品类型。Harbor 聚焦容器镜像，Nexus 则是**全品类通用制品仓库**?
---

## 与Harbor 的核心区别
| 维度 | Harbor | Nexus |
|------|--------|-------|
| **定位** | 容器镜像仓库 | 通用制品仓库 |
| **制品类型** | 镜像 + Helm + OCI | Maven/npm/PyPI/Docker/Helm/Raw 20+ 类型 |
| **镜像扫描** | ?内置 Trivy（开源免费）| ⚠️ Nexus IQ（企业收费）|
| **代理缓存** | 镜像代理（DockerHub Proxy）| 制品代理（Maven Central/npm/PyPI）|
| **性能** | 镜像场景优化 | 通用场景均衡 |
| **Helm Chart** | ?OCI 标准 | ?原生 |
| **开源程?* | ?全功能开发| ⚠️ 部分功能需付费 |

---

## 引入 Nexus 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 全制品管理| Maven/npm/PyPI/Docker 统一管理，一套工具全搞定 |
| ✅ 代理中央仓库 | 缓存 Maven Central / npmjs / PyPI，减少公网下无 |
| ✅ 统一权限 | 所有制品类型用同一套权限体系和用户管理 |
| ✅ Raw 仓库 | 存任意二进制文件（JAR/脚本/配置文件）|

## 引入 Nexus 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 容器镜像能力弱| 镜像扫描高级功能需 Nexus IQ（收费）|
| ⛔ 性能 | 纯镜像场景不?Harbor 无 |
| ⛔ 生态| K8s 拉取镜像的集成不?Harbor 原生 |
| ⛔ 迁移 | 现有 Harbor 中的镜像需要迁无 |

---

## 参考
- https://www.sonatype.com/products/sonatype-nexus-repository
- https://github.com/sonatype/nexus-public
