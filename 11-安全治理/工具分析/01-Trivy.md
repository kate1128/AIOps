# Trivy — 漏洞与配置安全扫描

> 在 CI 阶段扫描镜像、依赖和 IaC 配置，尽早发现并阻断高风险漏洞。

---

## 是什么

Trivy 是开源安全扫描工具，支持容器镜像、文件系统、依赖包、K8s 配置、Terraform 等扫描。

---

## 核心能力

- 镜像漏洞扫描（OS 包 + 语言依赖）
- 依赖扫描（Python/Node/Go/Java）
- IaC 扫描（K8s YAML/Terraform）
- Secret 扫描（误提交密钥）
- SBOM 生成（软件物料清单）

---
0000000000
## CI 集成示例（GitLab）

```yaml
security-scan:
  stage: scan
  image: aquasec/trivy:latest
  script:
    - trivy image --severity HIGH,CRITICAL --exit-code 1 $IMAGE_NAME
```

---

## 实践建议

- 起步策略：仅阻断 Critical，再逐步收紧到 High
- 扫描报告归档，纳入发布审批证据
- 与 Harbor 镜像仓库联动做二次保障

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/aquasecurity/trivy
- Star：35.2k（统计日期：2026-05-27）

