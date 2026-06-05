# Elasticsearch — 日志全文搜索引擎

## 概述

Elasticsearch（简称 ES）是 Elastic 公司的分布式全文搜索引擎，基于 Apache Lucene，是 ELK Stack（Elasticsearch + Logstash + Kibana）的核心存储层。通过对每个单词建立倒排索引，支持毫秒级全文检索，是日志搜索能力最强的方案之一。

- GitHub: [elastic/elasticsearch](https://github.com/elastic/elasticsearch) ⭐ ~68k
- CNCF 状态: 非 CNCF 项目（Elastic 主导，2021 年改为 SSPL 非 Apache 协议）
- 默认端口: `9200`（HTTP）、`9300`（集群通信）

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **全文倒排索引** | 每个单词都可以被秒搜，搜索能力无可匹敌 |
| **ELK 生态** | Logstash 处理管道 + Kibana 可视化，三者高度整合 |
| **Schema 灵活** | 动态 Mapping，无需预定义字段 |
| **聚合分析** | 支持类 SQL 的聚合查询（Bucket / Metric / Pipeline）|
| **多种搜索** | 全文检索、精确匹配、模糊匹配、地理空间查询 |
| **水平扩展** | 分片 + 副本机制，TB 级数据水平扩展 |

---

## 与 Loki 的详细对比

| 维度 | Elasticsearch | Grafana Loki |
|------|--------------|-------------|
| 索引方式 | **全文倒排索引**（每词索引）| 仅标签索引（不索引内容）|
| 全文搜索 | ✅ 毫秒级 | ❌ 需要全量扫描（慢）|
| 存储成本 | ❌ 是 Loki 的 5-10x | ✅ 极低 |
| 内存占用 | ❌ JVM Heap 8-32 GB | ✅ ~500 MB |
| K8s 标签查询 | ⚠️ 需配置字段映射 | ✅ 原生对齐 |
| Grafana 集成 | ⚠️ 需 Elasticsearch 数据源 | ✅ 原生集成 |
| 运维复杂度 | ❌ 高（JVM 调优、碎片管理）| ✅ 低 |
| 合规审计查询 | ✅ 强 | ❌ 弱 |
| 日增量场景 | > 10 TB/天 | < 1 TB/天 |

---

## 在本项目中的评估

> **结论：方案一不选 Elasticsearch**。
>
> - SmartVision 日志以 K8s 容器日志为主，日增量预估 < 50 GB/天，标签查询（namespace/pod/level）已足够，无需全文倒排索引
> - ES 的存储成本是 Loki 的 5-10 倍，JVM 调优和碎片管理增加运维负担
> - Grafana 全家桶下 Loki 原生集成，三支柱（指标/日志/链路）联动体验更好
>
> **保留场景**：如果未来需要**合规审计日志**（操作记录、API 审计）且需要按任意字段秒速搜索，可引入 ES 单独承接审计日志场景。

### OpenSearch 替代方案

> AWS 维护的 ES 开源替代品（Apache 2.0 协议），功能与 ES 7.x 对齐，不受 Elastic 改变 License 影响。如果必须引入全文搜索后端，优先考虑 OpenSearch。

```bash
# OpenSearch 快速启动（试用）
docker run -d \
  --name opensearch \
  -p 9200:9200 \
  -e "discovery.type=single-node" \
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=Admin@12345" \
  opensearchproject/opensearch:2.13.0
```

---

## 选型决策矩阵

| 场景 | 推荐选择 |
|------|---------|
| K8s 容器日志，按 namespace/pod 查询 | **Loki** |
| 应用错误日志，按 traceId / userId 精确查询 | **Loki**（标签查询）|
| 合规审计日志，任意字段全文搜索 | **Elasticsearch / OpenSearch** |
| 安全日志分析（SIEM）| **Elasticsearch** |
| 日增量 > 10 TB | Elasticsearch（列式 ClickHouse 也可）|
