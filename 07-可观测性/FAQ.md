# 可观测性 FAQ

---

## Q1: Zabbix 和 Prometheus 是替代关系吗？Prometheus 能监控网络设备/SNMP/硬件吗？

两者定位不同，不是简单的替代关系：

| 维度 | Zabbix | Prometheus |
|------|--------|------------|
| 采集模型 | Agent 主动推（Push） | 服务端拉取（Pull） |
| 优势领域 | 网络设备 / SNMP / 传统 IT 硬件 | K8s / 应用层 / Exporter 生态 |
| 告警引擎 | 内置，配置复杂 | Alertmanager，灵活路由 |
| 学习成本 | 中高（术语/模板自成体系） | 低（PromQL 统一查询语言） |

Prometheus 生态也有对应方案覆盖传统场景：

| 场景 | Prometheus 方案 |
|------|----------------|
| 网络设备 / SNMP | **snmp_exporter** — 支持 SNMP v1/v2/v3，可监控交换机/路由器/防火墙 |
| 硬件传感器 / BMC | **ipmi_exporter** — 采集温度/风扇/电源状态 |
| 传统 IT 主机 | **node_exporter** — 和 Zabbix agent 覆盖的指标基本一致 |
| 拨测 / 端口探活 | **blackbox_exporter** — ICMP/TCP/HTTP/gRPC |

**核心差异不是能力，而是模型偏好：** Zabbix Agent 主动推数据，适合防火墙严格、服务端不直接可达的网络隔离区；Prometheus 服务端拉取，需要被采集端开放端口，在隔离网络段需要额外架设 Prometheus 代理。

**当前策略：** Zabbix 继续管硬件/网络基线，Prometheus 管应用/AI/K8s；长期看如果 snmp_exporter + blackbox_exporter + node_exporter 能覆盖全部监控项，可逐步下线 Zabbix。

---

## Q2: 日志为什么要用 Loki 而不是 Elasticsearch？

| 维度 | Loki | Elasticsearch |
|------|------|---------------|
| 存储模型 | 只索引标签，不全文索引 | 全文倒排索引 |
| 存储成本 | 低（ES 的 1/5~1/10）| 高（副本 + 索引膨胀）|
| 查询语言 | LogQL（类 PromQL）| DSL（JSON 查询体）|
| Grafana 集成 | 原生，可在同一界面关联 metrics/logs/traces | 需额外插件 |
| 适用场景 | K8s 容器日志、结构化工单日志 | 全文搜索、复杂聚合分析 |

**结论：** 你们以 K8s/Docker 容器日志为主，Loki 标签索引足够；如果需要全文搜索业务日志，可以 Loki + Elasticsearch 并存。

---

## Q3: 为什么要用 Tempo 而不是 Jaeger？

| 维度 | Tempo | Jaeger |
|------|-------|--------|
| 存储后端 | 对象存储（S3/MinIO），低成本 | 需要 ES / Cassandra |
| Grafana 集成 | 原生，traceId 可直接从 Loki 跳转 | 需配置数据源 |
| 部署复杂度 | 单二进制，简单 | 多组件（collector/query/ingester）|
| 社区 | Grafana Labs 维护，快速迭代 | CNCF 毕业项目，成熟但慢 |

**结论：** 已有 Loki + Grafana 技术栈，Tempo 原生集成更好，存储成本更低。

---

## Q4: OpenTelemetry 是什么？和 Prometheus 是什么关系？

**OpenTelemetry（OTel）** 是 CNCF 的遥测数据采集标准，提供一套 SDK/API 来生成 Metrics、Logs、Traces，并统一导出到后端。

```
应用代码 → OTel SDK → OTel Collector → Tempo（链路）
                                       → Prometheus（指标）
                                       → Loki（日志）
```

**关系：** Prometheus 是存储/查询后端（其中一环），OTel 是采集/传输标准。两者互补：OTel 负责从应用产生数据，Prometheus/Tempo/Loki 负责存和查。

---

## Q5: 二进制部署的 Java 服务怎么采集指标和链路？不改代码行吗？

| 观测能力 | 方案 | 是否改代码 |
|---------|------|-----------|
| JVM 指标 | Micrometer + Prometheus Registry | 需加依赖（约 10 行配置）|
| 应用 RED 指标 | Spring Boot Actuator + Micrometer | 框架自带，改配置即可 |
| 链路追踪 | OpenTelemetry Java Agent（`-javaagent`）| **不改代码**，JVM 参数附加 |
| 日志集中 | Promtail 读取本地日志文件 | **不改代码** |
| 慢查询 / 连接池 | JMX Exporter | **不改代码** |

对于 Java 二进制服务，指标采集至少需要加 Micrometer 依赖（10 行配置），链路追踪可以用 OTel Java Agent 零修改接入。

---

## Q6: Loki 查询很慢怎么办？

常见原因和优化：

| 原因 | 优化 |
|------|------|
| 查询时间范围太大 | 缩小时间范围，分批查询 |
| 标签基数太高 | 避免高基数标签（如 requestId），只保留 service/pod/namespace |
| 没有使用标签过滤 | 查询时先加 `{namespace="prod"}` 缩小范围 |
| 数据量过大 | 配置 `query_ingesters_until` 和 `query_store_after` 分离热/冷数据 |
| 没有配置缓存 | 启用 `results_cache` 和 `index_cache` |

Loki 的架构设计优先保证**写入性能**（标签索引，不全文索引），查询大范围非结构化日志确实不如 ES 快——这也是设计取舍。

---

## Q7: 什么时候应该用 Promtail 还是 Fluent Bit？

| 维度 | Promtail | Fluent Bit |
|------|----------|------------|
| 生态 | Grafana 全家桶，Loki 原生 | CNCF 项目，多输出（ES/S3/Kafka）|
| 资源占用 | 低 | 极低（C 语言实现）|
| K8s 集成 | 自动发现 Pod 日志 | 需额外配置 |
| 日志处理 | 简单 relabel + pipeline | 复杂 pipeline（过滤/解析/路由）|

**当前推荐：** Promtail（已有 Loki，原生集成）。Fluent Bit 作为备选，当需要同时输出日志到 Loki + Kafka + S3 时引入。

---

## Q8: 目前有三种部署形态（二进制/Docker/K8s），监控怎么统一？

统一走 Prometheus + node-exporter + Promtail，按部署形态调整采集方式：

| 部署形态 | 指标采集 | 日志采集 | 链路追踪 |
|---------|---------|---------|---------|
| K8s (scheduler) | ServiceMonitor 自动发现 | Promtail DaemonSet | OTel Agent sidecar |
| Docker (ai-backend) | static_configs 指到宿主机 | Promtail 读 /var/lib/docker/containers | OTel Agent sidecar |
| 二进制 (Java) | static_configs 指到 Java 进程 IP:port | Promtail 读本地日志文件 | OTel Java Agent 附加 |

**不变的服务层，变的只是采集器部署方式。** Prometheus 统一作为指标存储，Grafana 统一展示。
