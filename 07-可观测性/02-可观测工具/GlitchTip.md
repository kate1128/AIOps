# GlitchTip — 轻量级错误追踪（未采用）

## 概述

GlitchTip 是 Sentry API 兼容的轻量级错误追踪平台，仅需 4 个容器（前端、后端、Worker、PostgreSQL）。部署简单，资源需求远低于 Sentry。

## 核心能力

- **Sentry SDK 兼容**: 使用 sentry-python、sentry-javascript 等官方 SDK 即可上报
- **错误分组**: 按堆栈指纹自动聚合同一类错误
- **版本追踪**: 标记每个错误的版本号，跟踪版本间错误率变化
- **通知**: 支持 Email、Slack、Webhook 通知

## 为何未采用

| 原因 | 说明 |
|------|------|
| 功能局限 | GlitchTip 功能远少于 Sentry，缺少性能追踪、SourceMap、Span 分析等高级功能 |
| 社区规模 | 社区活跃度低，更新频率慢 |
| 产品分析缺失 | 只能做错误追踪，无法替代 PostHog 的产品分析能力 |
| 投入产出比 | 在 PostHog 上线后，其内置错误追踪功能已能覆盖大部分需求 |

## 部署方式

```bash
docker run -d \
  -e DATABASE_URL=postgres://user:pass@host/glitchtip \
  -e SECRET_KEY=change-me \
  -p 8000:8000 \
  glitchtip/glitchtip
```

## 何时可以考虑

- 尚未部署 PostHog，且临时需要一个轻量错误追踪方案
- 仅需要错误聚合和通知，不需要产品分析和 A/B 测试
- 资源受限环境下（如边缘节点、小型设备）
