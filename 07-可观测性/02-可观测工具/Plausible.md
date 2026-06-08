# Plausible — 轻量级隐私优先网站统计

## 概述

Plausible 是一款极简的隐私优先 Web 分析工具，采集脚本仅 < 1 KB，不使用 Cookie，天然满足 GDPR 合规要求，无需弹出 Cookie 同意横幅。主打"够用就好"的理念，仅提供页面浏览量、来源、设备等基础数据，不做用户级追踪。

- GitHub: [plausible/analytics](https://github.com/plausible/analytics) ⭐ ~20k
- 官网: [plausible.io](https://plausible.io)
- 技术栈: Elixir + PostgreSQL + ClickHouse
- 默认端口: `8000`

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **极轻量采集脚本** | < 1 KB，不影响页面性能 |
| **无 Cookie 追踪** | 基于 IP+UA 哈希的匿名统计，不识别个人 |
| **GDPR/CCPA 合规** | 数据完全自托管，无第三方传输 |
| **实时看板** | 实时显示当前在线人数、实时来源 |
| **自定义事件** | 可追踪按钮点击等自定义事件（但无漏斗）|
| **邮件周报** | 自动发送每周统计摘要 |

---

## 与同类工具对比

| 维度 | Plausible | PostHog | Matomo |
|------|-----------|---------|--------|
| 采集脚本大小 | **< 1 KB** | ~100 KB | ~30 KB |
| Cookie | ❌ 无 | ⚠️ 可选 | ✅ 默认有 |
| 用户级分析 | ❌（刻意不支持）| ✅ | ✅ |
| 会话回放 | ❌ | ✅ | 付费插件 |
| A/B 测试 | ❌ | ✅ | 付费插件 |
| 漏斗分析 | ❌ | ✅ | ✅ |
| 部署难度 | **低** | 高 | 中 |
| 内存占用 | ~200 MB | ~4 GB | ~500 MB |
| 适用场景 | 内容/营销网站 | **AI SaaS 产品分析** | 传统 Web |
| **SmartVision 推荐** | ❌ 不选 | **✅ 首选** | ❌ 不选 |

---

## 在本项目中的评估

> **结论：不选 Plausible**，原因如下：
>
> 1. **功能过于精简**：刻意不提供用户级分析（无 User ID 追踪）、无漏斗、无会话回放、无 A/B 测试
> 2. **不适合 AI SaaS 产品分析**：SmartVision 需要了解特定用户的 AI 功能使用路径，Plausible 的匿名统计无法满足
> 3. **无法回答关键业务问题**：比如"付费用户和免费用户的功能使用差异"、"哪些用户最近 7 天没有使用 AI 问答"
>
> Plausible 适合**内容型网站、博客、企业官网**（只需知道有多少人来、从哪里来），不适合需要深度用户行为分析的 SaaS 产品。

### Plausible 适合的场景

- 企业官网流量统计（不需要用户级分析）
- 替代 Google Analytics（合规敏感、不想被 Google 追踪）
- 产品 Landing Page 效果监测

### 快速试用配置（参考）

```yaml
# docker-compose.yml
version: '3'
services:
  plausible_db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: ${PG_PASSWORD}
    volumes:
      - pg-data:/var/lib/postgresql/data

  plausible_events_db:
    image: clickhouse/clickhouse-server:23
    volumes:
      - clickhouse-data:/var/lib/clickhouse

  plausible:
    image: ghcr.io/plausible/community-edition:v2.1
    ports:
      - "8000:8000"
    environment:
      BASE_URL: https://analytics.smartvision.internal
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}  # 通过 K8s Secret 注入
      DATABASE_URL: postgres://postgres:${PG_PASSWORD}@plausible_db:5432/plausible
      CLICKHOUSE_DATABASE_URL: http://plausible_events_db:8123/plausible_events
    depends_on:
      - plausible_db
      - plausible_events_db
volumes:
  pg-data:
  clickhouse-data:
```

---

## 结论

SmartVision 用户行为分析首选 PostHog（开源自托管，功能完整），Plausible 因功能过于精简不纳入当前方案。如果将来仅需要统计匿名流量数据（如官网访问量），可单独引入 Plausible 作为补充。
