# SLO 定义文档

> 每个核心服务单独维护一份，修改时更新版本号和日期。

---

## 基本信息

| 字段 | 内容 |
|---|---|
| 服务名称 | [填写服务名，如：vLLM 推理服务 / 问学平台 Web API] |
| 负责人 | |
| 版本 | v1.0 |
| 最后更新 | YYYY-MM-DD |

---

## SLI 定义

| 字段 | 内容 |
|---|---|
| 测量对象 | 成功请求数 / 总请求数（排除客户端错误 4xx）|
| 数据来源 | Prometheus job=vllm / job=nginx |
| 测量窗口 | 滚动 30 天 |
| PromQL | `sum(rate(vllm:request_success_total[30d])) / sum(rate(vllm:request_total[30d]))` |

---

## SLO 目标

| SLI | 目标值 | Error Budget（30天）| 备注 |
|---|---|---|---|
| 请求成功率 | ≥ 99.5% | 3.6 小时 / 月 | |
| TTFT P99 延迟 | ≤ 2s | — | 延迟 SLO 不计 Error Budget |
| 服务可用性 | ≥ 99.9% | 43 分钟 / 月 | |

---

## Error Budget 消耗策略

| Budget 剩余 | 行动 |
|---|---|
| > 50% | 正常迭代，可做实验性变更 |
| 20% ~ 50% | 减少非关键变更，排查潜在风险 |
| < 20% | 冻结功能发布，仅允许 bug fix |
| 耗尽 | 停止一切非紧急发布，开 P0 处置流程 |

---

## Grafana SLO Dashboard PromQL

```promql
# 成功率（滚动 30d）
sum(rate(vllm:request_success_total[30d]))
/
sum(rate(vllm:request_total[30d]))

# Error Budget 消耗速率（相对 SLO=99.5%，值 > 1 表示超速消耗）
(
  1 - sum(rate(vllm:request_success_total[30d])) / sum(rate(vllm:request_total[30d]))
) / (1 - 0.995)
```

---

## 历史 SLO 达标记录

| 月份 | 成功率 | Budget 消耗 | 是否达标 | 备注 |
|---|---|---|---|---|
| 2026-05 | — | — | — | SLO 刚建立，开始统计 |
