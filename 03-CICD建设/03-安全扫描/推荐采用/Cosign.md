# Cosign — 镜像签名与供应链安全

> Sigstore 项目提供的镜像签名工具，确保只有经过签名的制品才能部署到生产环境。
> 当前状态：⏳ 推荐采用

---

## 是什么

Cosign 是 CNCF 孵化项目 Sigstore 的核心组件，为容器镜像和其他制品提供加密签名验证。它支持密钥对签名（静态密钥或 KMS）、一次性密码签名（OIDC/Fulcio），是构建软件供应链安全的基础设施。

---

## 与替代方案对比

| 维度 | Cosign | Notary v2 |
|------|--------|-----------|
| **标准** | OCI Sigstore | OCI Notary |
| **密钥管理** | 本地/KMS/OIDC | TUF（The Update Framework）|
| **集成** | GitHub Actions / GitLab CI / Harbor | Harbor / Docker Desktop |
| **验证** | CLI `cosign verify` | Notation CLI |
| **复杂度** | 低 | 中 |
| **社区** | 活跃（Sigstore）| 较冷 |

---

## 引入 Cosign 你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 供应链安全 | 确保生产部署的镜像来自受信任的构建流水线 |
| ✅ 防篡改 | 签名验证失败 → 阻断部署，防止镜像被中间人替换 |
| ✅ 生态好 | Harbor / GitHub / GitLab 都支持集成 |
| ✅ 免费 | Sigstore 项目完全开源 |

## 引入 Cosign 的代价

| 代价 | 说明 |
|------|------|
| ❌ 密钥管理 | 签名密钥的存储和轮换需要额外管理 |
| ❌ 流程增加 | CI 中增加签名步骤，流水线略微变长 |
| ❌ 兼容性 | 老旧工具可能不支持签名验证 |

---

## 参考

- https://sigstore.dev
- https://github.com/sigstore/cosign
