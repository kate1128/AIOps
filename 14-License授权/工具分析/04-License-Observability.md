# License 审计链路（可观测性）

> License 不仅要能签发，更要可追踪：谁签发、谁激活、谁失败、哪里异常。

---

## 建议链路

```text
License 服务日志 -> Loki/ELK
License 指标 -> Prometheus
License 关键事件 -> ClickHouse/PostgreSQL 审计表
告警 -> 飞书/钉钉
```

---

## 关键指标

- 每日签发数量
- 激活成功率
- 验证失败率（按原因分组：过期/签名失败/指纹不匹配）
- 吊销后仍请求次数（疑似盗版）

---

## 建议告警

- 10 分钟内签名失败率 > 5%
- 单客户激活失败连续超过阈值
- 同一 License 在多地区短时激活（异常共享）

---

## 事件模型（建议）

- issue
- activate
- verify
- renew
- revoke
- grace_enter
- grace_exit

每个事件应记录：license_id、customer_id、device_id、operator、timestamp、result。

---

## GitHub 信息

- 开源状态：混合（含开源与商业组件）
- 相关仓库：
  - https://github.com/grafana/loki （Star：28.3k，2026-05-27）
  - https://github.com/prometheus/prometheus （Star：64.2k，2026-05-27）
  - https://github.com/grafana/tempo （Star：5.3k，2026-05-27）

