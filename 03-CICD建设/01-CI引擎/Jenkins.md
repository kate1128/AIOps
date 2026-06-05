# Jenkins — 老牌 CI/CD 自动化服务器

> 与 GitLab CI 的对比参考
> 当前使用：GitLab CI

---

## 是什么

Jenkins 是最成熟的开源 CI/CD 自动化服务器，诞生于 2011 年，拥有 1800+ 插件，几乎可以对接任何工具链。相比 GitLab CI，Jenkins 配置更灵活但也更复杂。

---

## 与 GitLab CI 的核心区别

| 维度 | GitLab CI | Jenkins |
|------|-----------|---------|
| **配置语言** | YAML | Groovy（Jenkinsfile）|
| **插件生态** | 内置功能为主 | 1800+ 插件 |
| **代码仓库** | 一体化（必须 GitLab）| 独立（支持 Git/GitHub/SVN）|
| **共享库** | CI 模板 include | 共享库（Shared Library）|
| **UI** | 现代化 | 传统（Blue Ocean 改善中）|
| **K8s 集成** | Runner on K8s | Agent on K8s |
| **安装运维** | 简单 | 复杂（Master + Agent + 插件管理）|

---

## 引入 Jenkins 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 极灵活的流水线 | Groovy 脚本几乎可以实现任意逻辑 |
| ✅ 丰富的插件 | 1800+ 插件覆盖几乎所有工具和平台 |
| ✅ 共享库 | 跨项目的流水线逻辑复用，成熟度高 |
| ✅ 多 SCM 支持 | 同时管理 GitLab/GitHub/SVN 仓库 |

## 引入 Jenkins 的代价

| 代价 | 说明 |
|------|------|
| ❌ 搭建维护复杂 | Master + Agent + NFS + 插件管理，需要专职运维 |
| ❌ UI 陈旧 | 配置界面传统，排查问题不够直观 |
| ❌ 插件地狱 | 插件兼容性问题时常出现，升级需谨慎 |
| ❌ 与 GitLab 割裂 | 代码在 GitLab，CI 在 Jenkins，上下文切换 |

---

## 参考

- https://www.jenkins.io
- https://github.com/jenkinsci/jenkins
