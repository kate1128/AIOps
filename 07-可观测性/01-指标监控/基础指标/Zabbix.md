# Zabbix — 企业级基础监控（已采用）

## 概述

Zabbix 是企业级开源主机和网络监控系统，采用 Server-Proxy-Agent 三层架构，支持 SNMP、IPMI、JMX、Agent 等多种采集方式。目前在本项目中作为基础设施监控主力，覆盖主机和网络设备。

## 核心能力

- **Agent 推送模型**: 被监控主机主动上报数据，适合防火墙后场景
- **SNMP 采集**: 支持 SNMP v1/v2c/v3，覆盖交换机、路由器、防火墙
- **自动发现**: 自动发现网络设备、磁盘、网卡、CPU 核心等
- **模板系统**: 预置数百个监控模板，覆盖常见 OS、中间件、数据库
- **触发器与动作**: 灵活的条件触发和通知动作编排

## 在本项目中的角色

| 监控目标 | 方式 | 目前状态 |
|----------|------|----------|
| 物理服务器 | Zabbix Agent | ✅ 在运行 |
| 网络设备（交换机/路由器） | SNMP | ✅ 在运行 |
| 防火墙/负载均衡 | SNMP | ✅ 在运行 |
| K8s 集群 | - | ❌ Prometheus 接管 |
| 中间件 (PG/Redis) | - | ❌ Prometheus 接管 |

## 迁移路径

随着 Prometheus 生态逐步完善，Zabbix 将逐步缩减职责范围：

| 阶段 | Zabbix 职责 | Prometheus 职责 |
|------|-------------|-----------------|
| 当前 | 主机 + 网络设备 + 部分中间件 | K8s + vLLM + Java |
| 短期目标 | 主机 + 网络设备 | 所有服务 + 中间件 + K8s |
| 长期目标 | 仅网络设备 (SNMP) | 全量指标监控 |

### 迁移方案

```yaml
# 逐步用 Prometheus Exporter 替代
- Zabbix Agent → node-exporter (9100)
- SNMP poller → snmp_exporter (9116)
- IPMI → ipmi_exporter (9290)
- DB 监控 → postgres_exporter / mysqld_exporter
```

## Zabbix 与 Prometheus 对比

| 特性 | Zabbix | Prometheus |
|------|--------|------------|
| 数据模型 | 指标树 + Item | 标签化时间序列 |
| 采集模型 | Push（Agent） | Pull（Server） |
| 查询语法 | Zabbix API + 预处理 | PromQL |
| 可视化 | 内置面板（有限） | Grafana |
| 告警引擎 | 触发器 + 动作 | Alertmanager |
| 动态扩展 | 自动发现 | 服务发现 (K8s/Consul) |
| 网络设备 | 原生 SNMP 支持 | 需 snmp_exporter |
