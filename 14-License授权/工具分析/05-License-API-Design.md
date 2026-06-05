# License 授权服务 API 设计要点

> License 能否稳定运营，关键在授权服务 API 的一致性和幂等性。

---

## 最小 API 集

- POST /licenses：创建 License
- POST /licenses/{id}/activate：激活
- POST /licenses/{id}/verify：校验
- POST /licenses/{id}/renew：续期
- POST /licenses/{id}/revoke：吊销

---

## 关键设计原则

- 幂等：同一请求重复提交结果一致
- 可追踪：每次调用都有 request_id 和审计事件
- 可回放：失败请求可重试，不产生脏状态
- 可扩展：features/limits 使用结构化字段

---

## 安全要求

- API 鉴权：服务间使用短期 token 或 mTLS
- 签名校验：响应可选附带签名，防篡改
- 速率限制：防止暴力请求与撞库

---

## 与工单/CRM联动

- 续费工单完成后自动调用 renew API
- 吊销操作需工单审批，避免误操作
- 每次状态变更回写客户系统，形成闭环

---

## GitHub 信息

- 开源状态：非开源/不对应单一开源仓库
- 说明：该文档为架构设计方法，不对应单一官方开源工具
- Star：不适用

