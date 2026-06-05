# HashiCorp Vault — 密钥与凭据管理

> 统一管理数据库密码、API Key、证书等敏感信息，支持动态凭据和审计。

---

## 是什么

Vault 是企业级 Secret 管理平台，提供密钥加密存储、细粒度访问控制、动态凭据签发、审计日志。

---

## 核心能力

- 动态数据库凭据（短期有效，自动过期）
- PKI 证书签发
- Key-Value Secret 存储
- 审计日志完整留痕
- 与 Kubernetes ServiceAccount 集成鉴权

---

## 典型架构

```text
应用 Pod -> Vault Agent 注入临时凭据 -> 应用使用凭据访问 DB
```

---

## 实践建议

- 生产环境开启自动解封和多副本 HA
- 所有静态长效密码逐步迁移为动态凭据
- Secret 访问策略最小权限化（按服务拆分）

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/hashicorp/vault
- Star：35.7k（统计日期：2026-05-27）

