# License 字段规范

> 定义 .lic 文件的 JSON 结构、字段语义、枚举值及版本演进规则。

---

## 一、完整字段结构

```json
{
  "license_id": "LIC-20260528-A001",
  "schema_version": "1.0",
  "customer_id": "customer-a",
  "customer_name": "XX 科技有限公司",
  "product": "wenxue",
  "edition": "enterprise",
  "issued_at": "2026-05-28",
  "expires_at": "2027-05-28",
  "grace_period_days": 30,
  "features": [
    "ai-inference",
    "custom-model",
    "sso",
    "audit-log"
  ],
  "limits": {
    "max_users": 200,
    "max_gpu_nodes": 4,
    "max_monthly_tokens": 50000000
  },
  "machine_fingerprint": "",
  "issued_by": "ops@company.com",
  "memo": "年度合同，2026-05-28 签署",
  "signature": "base64-encoded-ecdsa-signature"
}
```

---

## 二、字段说明

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `license_id` | string | ✅ | 唯一标识，格式 `LIC-{日期}-{客户编号}` |
| `schema_version` | string | ✅ | 字段结构版本，用于向后兼容。当前 `1.0` |
| `customer_id` | string | ✅ | 客户内部 ID，与 CRM 系统对应 |
| `customer_name` | string | ✅ | 客户公司全称（显示用）|
| `product` | string | ✅ | 固定值 `wenxue` |
| `edition` | enum | ✅ | 版本：`basic` / `pro` / `enterprise` |
| `issued_at` | date | ✅ | 签发日期，ISO 8601 格式（`YYYY-MM-DD`）|
| `expires_at` | date/null | ✅ | 到期日期；`null` 表示永久授权 |
| `grace_period_days` | int | ✅ | 到期后宽限天数，默认 `30` |
| `features` | string[] | ✅ | 已授权的功能列表（见下方枚举）|
| `limits` | object | ✅ | 用量限制（见下方说明）|
| `machine_fingerprint` | string | ❌ | 硬件指纹，空字符串表示不绑定机器 |
| `issued_by` | string | ✅ | 签发人邮箱，用于审计 |
| `memo` | string | ❌ | 备注，不参与验证 |
| `signature` | string | ✅ | ECDSA P-256 数字签名，Base64 编码 |

---

## 三、features 枚举值

| 值 | 说明 | 可用版本 |
|---|---|---|
| `ai-inference` | AI 推理服务（vLLM）| pro、enterprise |
| `custom-model` | 自定义/私有模型接入 | enterprise |
| `sso` | 单点登录（SAML/OIDC）| pro、enterprise |
| `audit-log` | 操作审计日志 | enterprise |
| `multi-tenant` | 多租户隔离 | enterprise |
| `api-access` | Open API 访问 | pro、enterprise |

各版本默认包含的 features：

| 版本 | 默认 features |
|---|---|
| `basic` | （空，仅核心功能，无需 features 控制）|
| `pro` | `ai-inference`, `sso`, `api-access` |
| `enterprise` | `ai-inference`, `custom-model`, `sso`, `audit-log`, `multi-tenant`, `api-access` |

---

## 四、limits 字段说明

| 字段 | 类型 | 说明 | 无限制 |
|---|---|---|---|
| `max_users` | int | 最大用户账号数 | `-1` |
| `max_gpu_nodes` | int | 最大 GPU 节点数（AI 版）| `-1` |
| `max_monthly_tokens` | int | 每月最大 Token 用量 | `-1` |

---

## 五、schema_version 演进规则

| 版本 | 变更内容 | 向后兼容 |
|---|---|---|
| `1.0` | 初始版本 | — |
| `1.1`（规划）| 新增 `multi_region` 字段 | ✅ 旧客户 License 无此字段时视为 `false` |
| `2.0`（规划）| 签名算法从 ECDSA P-256 升级到 Ed25519 | ❌ 需重新签发所有 License |

**演进原则**：
- 新增可选字段：`schema_version` 小版本递增（`1.0` → `1.1`），产品向后兼容
- 修改字段语义或算法：`schema_version` 大版本递增（`1.x` → `2.0`），需通知所有客户升级
