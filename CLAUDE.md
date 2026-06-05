# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Nature

This is a **documentation-only knowledge base** for SmartVision (智能视觉平台, internal codename "问学 2.0"), a Kubernetes-based AI SaaS platform. There is no application source code, build system, test suite, or package manager. All content is written in Chinese.

## Product Context

- **Tech stack**: Kubernetes + GitLab CI/CD + Prometheus/Grafana/Loki/Tempo + vLLM
- **Delivery**: SaaS + on-premise (Ansible playbooks)
- **Primary language**: Chinese (Simplified)

## Directory Structure

- `00-产品分析` through `16-知识管理` — 16 domain directories following a consistent template:
  - `体系建设总览.md` — domain index (current state, pain points, roadmap, KPIs, cross-domain dependencies)
  - `AI提效计划.md` — AI/LLM efficiency proposals
  - `FAQ.md` — common questions
  - `01-*/` `02-*/` … — subtopic specification documents
  - `工具分析/` — tool evaluation and comparison documents (often contain PNG screenshots)
- `其他/` — plans, status tracking, utility scripts, and miscellaneous documents

## Non-Documentation Files

These files are executable or configuration, not prose:

| File | Purpose |
|------|---------|
| `03-CICD建设/templates/.gitlab-ci.yml` | Standard GitLab CI pipeline template (~976 lines, supports Python/Java/Go, kubectl/docker/binary deploy modes) |
| `03-CICD建设/templates/artifact-build.gitlab-ci.yml` | Artifact build CI template |
| `13-私有化交付/playbooks/*.yml` | Ansible deployment/rollback/preflight playbooks |
| `其他/fix_encoding.py` | Detects U+FFFD replacement characters in Markdown files |
| `其他/analyze.py` | Encoding analysis script for the middleware docs directory |
| `其他/fix.ps1` | Windows PowerShell script to fix encoding issues (replaces FFFD+? with em-dash) |
| `其他/recover.ps1` | Windows PowerShell script to recover GBK-garbled UTF-8 files |

## Writing Conventions

- Documents are written entirely in Chinese.
- Heavy use of Mermaid diagrams (flowcharts, architecture diagrams).
- Configuration examples use YAML/Bash/Dockerfile code blocks.
- Each document is self-contained; cross-domain references use descriptive Chinese text with relative paths like `../02-架构治理/体系建设总览.md`.
- Image references in `工具分析/` documents point to PNG screenshots stored alongside the Markdown files.

## Constraints

- `.claude/settings.local.json` only allows `WebSearch` permission.
- This is **not a git repository** — do not run `git` commands.
- Do not create new `.md` files unless explicitly requested. The existing document structure is considered complete (see `其他/DOCUMENTS_STATUS.md`).
- When editing documents that contain image references, preserve the image paths.

## CI/CD Architecture (High-Level)

The CICD system is built entirely around an on-premise GitLab instance. The standard pipeline (defined in `03-CICD建设/templates/.gitlab-ci.yml`) progresses through five quality gates:

1. **feature branch** — lint only
2. **dev branch** — lint + SonarQube + gitleaks + oasdiff + build → auto deploy to dev
3. **pre branch** — above + Trivy scan + LLM CVE triaging (via internal vLLM) → auto deploy to pre
4. **main branch** — above + preflight checks + LLM release summary → no auto deploy
5. **Tag (v*.*.*)** — re-tag Harbor image → FTP push → Feishu approval card → manual prod deploy

The template requires GitLab CI Variables for three separate Harbor instances, three kubeconfig files, SSH keys, FTP credentials, Feishu webhook, Sonar token, and GitLab API token. See `03-CICD建设/体系建设总览.md` section 8 for the full variable configuration guide.
