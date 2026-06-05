# API 契约管理规范

> API 是服务间的"合同"——规范化的 API 契约管理确保服务间互操作性和兼容性。

---

## 一、API 规范标准

| 规范 | 要求 |
|------|------|
| **HTTP API** | OpenAPI 3.0 |
| **gRPC API** | Proto3 |
| **消息契约** | AsyncAPI / Avro Schema |
| **GraphQL** | Schema Definition Language(SDL) |

---

## 二、版本管理

### 版本策略

- API 版本与产品版本**解耦**，独立版本号
- URL 路径版本：`/api/v1/users`
- 版本号遵循 SemVer

### 版本兼容规则

| 变更类型 | 版本变更 | 说明 |
|----------|----------|------|
| 新增字段/接口 | MINOR +1 | 向后兼容 |
| 修改字段类型 | MAJOR +1 | 不兼容 |
| 删除接口 | MAJOR +1 | 需提前一个版本废弃 |
| 修复 Bug | PATCH +1 | 不影响契约 |

---

## 三、废弃(Deprecation)策略

1. 废弃前通过 API 响应头标记 `Deprecation: true`
2. 废弃版本至少提供 6 个月过渡期
3. 废弃版本在文档中明确标注
4. 调用方收到废弃通知后需在过渡期内迁移

---

## 四、CI 检查

- CI 中集成 OpenAPI diff 检查
- 自动检测不兼容变更
- 检测到不兼容变更时，检查是否符合 MAJOR 版本变更规则
- API 规范文件纳入代码评审范围
