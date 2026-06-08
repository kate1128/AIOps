# PostHog — 自托管产品分析平台

## 概述

PostHog 是开源的一站式产品分析平台，集事件追踪、会话录制、功能开关、A/B 测试、热力图于一体。核心优势：支持自托管部署，数据不出境，符合中国数据合规要求。

## 核心能力

- **事件追踪**: 自动捕获页面浏览、按钮点击、API 调用等用户行为事件
- **会话录制**: 录制用户操作回放，用于问题复现和体验优化
- **Feature Flags**: 功能开关，支持渐进式发布和灰度测试
- **A/B 测试**: 内置实验框架，支持多变量测试
- **热力图**: 页面点击热力图，分析用户注意力分布
- **插件系统**: 支持数据导出到 S3、BigQuery、Kafka

## 为何推荐

| 原因 | 说明 |
|------|------|
| All-in-One | 一个产品覆盖产品分析 + Feature Flag + A/B 测试，避免多个工具拼凑 |
| 自托管 | 数据存储在自有服务器，满足中国个人信息保护法要求 |
| 开源核心 | 核心功能 MIT 协议开源，无厂商锁定风险 |
| 社区活跃 | GitHub 20k+ stars，迭代频繁 |

## 部署方式

```bash
# Docker Compose 部署（含 PostgreSQL + Redis + ClickHouse）
git clone https://github.com/PostHog/posthog.git
cd posthog
docker compose -f docker-compose.yml up -d
```

| 组件 | 用途 |
|------|------|
| PostgreSQL | 元数据存储 |
| Redis | 缓存和任务队列 |
| ClickHouse | 事件分析引擎 |
| PostHog App | 主应用 |

## 关键配置

- **默认端口**: 8000
- **部署规模**: 2 核 8GB + 50GB SSD（支持日均百万事件）
- **长期规划**: 日活用户超 10 万后需考虑 ClickHouse 分片
- **集成方式**: PostHog JS SDK（前端）、Python SDK（后端 API）
