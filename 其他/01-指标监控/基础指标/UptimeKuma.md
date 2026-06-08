# Uptime Kuma — 自托管拨测平台

## 概述

Uptime Kuma 是开源的自托管服务 Uptime 监控平台，以美观现代的 UI 和超丰富的通知渠道著称。特别适合做**外部视角**的可用性拨测。

## 核心能力

- **90+ 通知渠道**: 原生支持飞书、钉钉、企业微信、Slack、Telegram 等
- **多种监控类型**: HTTP(s)、TCP、Ping、DNS、Push、Steam、游戏服务器等
- **状态页面**: 内置状态页，可自定义域名、Logo，对外发布
- **证书监控**: 自动检测 SSL 证书过期时间
- **多语言**: 支持中文界面

## 为何推荐

| 特性 | Uptime Kuma | Gatus |
|------|-------------|-------|
| 定位 | 外部拨测 + 状态页 | 内部健康检查 + GitOps |
| 部署方式 | 独立 Docker 实例 | 可部署于 K8s |
| 通知渠道 | 90+（含飞书/钉钉/微信） | Webhook 通用 |
| 配置方式 | Web UI | YAML 文件 |
| 仪表盘 | 内置精美 UI | 简洁状态页 + Prometheus |

两者互补：Gatus 处理 GitOps 健康检查，Uptime Kuma 处理外部拨测和通知。

## 部署方式

```bash
docker run -d --name uptime-kuma \
  -p 3001:3001 \
  -v uptime-kuma-data:/app/data \
  louislam/uptime-kuma:latest
```

## 推荐设置

- 监控部署在生产集群之外（或另一可用区）的独立主机上，防止与业务同时宕机
- 配置飞书 Webhook 作为告警通知
- 设置状态页域名，对外展示服务可用性（SLA 报告）
- 周期性执行断网恢复演练，验证拨测告警有效性
