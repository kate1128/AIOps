# Syft — SBOM 物料清单生成

> Anchore 开源的容器镜像 SBOM 生成工具，支持 SPDX/CycloneDX/TJSON 格式输出。
> 当前状态：⏳ 推荐采用

---

## 是什么

Syft 是一个 CLI 工具，可以从 Docker/OCI 镜像、文件系统、tar 归档中自动生成软件物料清单（SBOM）。SBOM 是软件供应链安全的关键环节，记录了镜像中包含的所有包及其版本信息，用于漏洞影响分析和合规审计。

---

## 引入 Syft 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 合规 | 生成 SBOM 满足供应链安全合规要求（如 EO 14028）|
| ✅ 漏洞关联 | 新 CVE 发布时，快速查哪些生产镜像受影响 |
| ✅ 集成方便 | 单 CLI 命令，CI 中一行脚本即完成 |
| ✅ 多格式 | SPDX/CycloneDX/JSON，对接不同审计工具 |

## 引入 Syft 的代价

| 代价 | 说明 |
|------|------|
| ❌ 存储成本 | SBOM 文件需要额外存储空间 |
| ❌ CI 时间 | 生成 SBOM 增加几十秒流水线时间 |
| ❌ 维护 | SBOM 的有效管理和版本关联需要制度化 |

---

## 参考

- https://anchore.com/syft
- https://github.com/anchore/syft
