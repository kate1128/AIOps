# SmartVision 知识库 — AGENTS.md

## 仓库性质

纯文档仓库，无应用源码、无测试、无构建系统。内容是为 SmartVision（又名问学 2.0）Kubernetes AI SaaS 平台准备的工程与运维知识体系。

## 目录结构

- `00-产品分析` ~ `16-知识管理` — 16 个标准领域目录
- `其他/` — 计划、状态追踪、工具脚本、零散文档
- 每个领域目录遵循统一模板：
  - `体系建设总览.md` — 领域索引/总览（现状、痛点、路线图、KPI、跨域依赖）
  - `AI提效计划.md` — AI/LLM 提效方案
  - `FAQ.md` — 常见问题
  - `01-*/` `02-*/` … — 子主题规范文档
  - `工具分析/` — 工具选型对比（含截图）

## 可执行文件（非纯文档）

| 文件 | 用途 |
|------|------|
| `03-CICD建设/templates/.gitlab-ci.yml` | GitLab CI 流水线模板（~976 行） |
| `03-CICD建设/templates/artifact-build.gitlab-ci.yml` | 制品构建 CI 模板 |
| `13-私有化交付/playbooks/*.yml` | Ansible 部署/回滚/预检 playbook |
| `其他/fix_encoding.py` | MD 文件编码检测工具 |
| `其他/analyze.py` | 分析工具 |
| `其他/fix.ps1` / `recover.ps1` | Windows 维护脚本 |

## 项目背景

- 产品名：SmartVision (智能视觉平台)，内部也称"问学 2.0"
- 技术栈：Kubernetes + GitLab CI/CD + Prometheus/Grafana/Loki/Tempo + vLLM
- 交付方式：SaaS + 私有化部署（Ansible playbooks）
- 文档状态：`其他/DOCUMENTS_STATUS.md` 声明全部 13 个待办领域 100% 完成

## 写作惯例

- 文档用中文编写
- 大量使用 Mermaid 图表（流程图、架构图）
- 配置示例用 YAML/Bash/Dockerfile 代码块
- 每个文档独立成篇，跨域引用用中文描述关联

## 对 Agent 的约束

- `.claude/settings.local.json` 仅允许 `WebSearch` 权限
- 本仓库不是 git 仓库，不要尝试 `git` 命令
- 不要创建新的 `.md` 文件除非明确要求（现有文件已覆盖完整）
- 图片多为工具分析的截图（PNG），修改文档时注意保留图片引用
