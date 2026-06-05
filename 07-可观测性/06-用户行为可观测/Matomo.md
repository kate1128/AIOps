# Matomo — 自托管开源网站分析平台

## 概述

Matomo（前身 Piwik）是全球最广泛使用的开源自托管 Web 分析平台，PHP + MySQL 技术栈，是 Google Analytics 的自托管替代方案。支持页面访问统计、来源分析、目标转化漏斗，数据完全自主可控，满足 GDPR 合规要求。

- GitHub: [matomo-org/matomo](https://github.com/matomo-org/matomo) ⭐ ~19k
- 官网: [matomo.org](https://matomo.org)
- 技术栈: PHP + MySQL
- 部署方式: Docker Compose / Kubernetes

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **页面访问分析** | PV/UV、来源渠道、地理位置、设备类型 |
| **目标与转化** | 自定义目标（如注册完成）、转化漏斗 |
| **事件追踪** | 按钮点击、视频播放等自定义事件 |
| **GDPR 合规** | 数据自托管，支持数据删除请求 |
| **API 接口** | Reporting API 可对接 Grafana |
| **插件生态** | 300+ 插件，含热力图、A/B 测试（付费）|

---

## 与同类工具对比

| 维度 | Matomo | PostHog | Plausible |
|------|--------|---------|-----------|
| 技术栈 | PHP + MySQL | Node/Python + ClickHouse | Elixir + PostgreSQL |
| 部署难度 | 中（需 PHP 环境）| 较高（多容器）| **低（单容器）** |
| 内存占用 | ~500 MB | ~4 GB | ~200 MB |
| 会话回放 | ❌（需付费插件）| ✅ | ❌ |
| A/B 测试 | ❌（需付费插件）| ✅ | ❌ |
| 用户级分析 | ✅（User ID 追踪）| ✅ | ❌（隐私优先，无用户级）|
| 功能完整度 | 中 | **高** | 低（刻意精简）|
| Grafana 集成 | ⚠️ 需 API 插件 | ⚠️ 需自定义 | ❌ |
| **SmartVision 推荐** | ❌ 不选 | **✅ 首选** | ❌ 不选 |

---

## 在本项目中的评估

> **结论：不选 Matomo**，原因如下：
>
> 1. **PHP 技术栈与现有 K8s 生态格格不入**：需要维护 PHP-FPM + Nginx + MySQL，增加运维负担
> 2. **核心功能不如 PostHog**：会话回放和 A/B 测试是付费插件，而 PostHog 开源版已包含
> 3. **K8s 部署体验差**：Helm Chart 不够成熟，比 PostHog 的 K8s 部署更繁琐
> 4. **Grafana 集成较弱**：需要额外开发才能对接 Grafana 看板
>
> Matomo 更适合传统 Web 应用（如企业官网、内容平台），在 AI SaaS 产品分析场景中不如 PostHog 灵活。

### 如果必须使用 Matomo（参考配置）

```yaml
# docker-compose.yml（快速试用）
version: '3'
services:
  matomo:
    image: matomo:5
    ports:
      - "8080:80"
    environment:
      MATOMO_DATABASE_HOST: db
      MATOMO_DATABASE_NAME: matomo
      MATOMO_DATABASE_USER: matomo
      MATOMO_DATABASE_PASSWORD: ${MATOMO_DB_PASSWORD}
    volumes:
      - matomo-data:/var/www/html
  db:
    image: mysql:8
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: matomo
      MYSQL_USER: matomo
      MYSQL_PASSWORD: ${MATOMO_DB_PASSWORD}
volumes:
  matomo-data:
```

---

## 结论

SmartVision 用户行为分析首选 PostHog，Matomo 不纳入当前技术方案。
