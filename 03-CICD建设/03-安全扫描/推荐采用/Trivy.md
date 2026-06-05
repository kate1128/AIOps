# Trivy — 容器镜像漏洞扫描

> Aqua Security 开源的 SCA + CVE 扫描器，CI/CD 流水线标准安全门禁。
> 当前状态：⏳ 待集成

---

## 是什么

Trivy 是 Aqua Security 开源的轻量级、全方位的安全扫描器，支持容器镜像、文件系统、Git 仓库、Kubernetes 资源的 CVE 检测。它无需安装依赖数据库即可运行（内置 vulnerability DB），是目前最流行的镜像扫描工具之一。

---

## 与替代方案对比

| 维度 | Trivy | Snyk | Clair |
|------|-------|------|-------|
| **部署方式** | CLI + CI 集成 | SaaS / CLI | Container |
| **数据库** | 内置自动更新 | 云端 | Postgres |
| **速度** | 快（秒级） | 中 | 慢（分钟级）|
| **扫描范围** | 镜像/FS/Git/K8s | 镜像/代码/依赖库 | 镜像 |
| **免费额度** | 完全免费 | 有限免费 | 免费 |
| **K8s 集成** | ✅ | ✅ | ✅ |

---

## 引入 Trivy 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 零依赖 | 单二进制，下载即用，不需要数据库 |
| ✅ 扫描速度快 | 秒级扫描一个镜像，不拖慢流水线 |
| ✅ 覆盖面广 | OS 包 + 语言依赖（Python/Java/Node/Go）|
| ✅ 集成方便 | GitLab CI / Harbor / ArgoCD 均有集成 |

## 引入 Trivy 的代价

| 代价 | 说明 |
|------|------|
| ❌ 误报率 | 偶尔有误报，需要人工审核和配置 `.trivyignore` |
| ❌ 漏洞库更新 | 新 CVE 的更新速度略慢于商业产品 |
| ❌ 无策略引擎 | 不能自定义合规策略（对比 Snyk）|

---

## 参考

- https://trivy.dev
- https://github.com/aquasecurity/trivy
