# VictoriaLogs — 极致轻量的日志存储后端

## 概述

VictoriaLogs 是 VictoriaMetrics 团队于 2023 年推出的开源日志数据库，采用无索引（Inverted Index Free）流式存储架构，压缩率极高，查询延迟低，单二进制部署无需额外依赖。2024 年起进入生产可用阶段，被认为是 Grafana Loki 的有力替代者。

- GitHub: [VictoriaMetrics/VictoriaMetrics](https://github.com/VictoriaMetrics/VictoriaMetrics)（同仓库）⭐ ~13k
- CNCF 状态: 非 CNCF 项目
- 默认端口: `9428`
- 查询语言: LogsQL（类 Loki 的 LogQL，但更精简）

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **无全文索引** | 不为日志内容建倒排索引，避免 ES 的写放大问题 |
| **极高压缩率** | 实测比 Loki 压缩率高 30-50%，比 ES 低 5-10x 存储成本 |
| **低内存占用** | 同等日志量下内存消耗比 Loki 低约 50% |
| **单二进制** | 无 compactor / ingester / querier 等微服务拆分，运维极简 |
| **兼容 Loki API** | 支持 Loki push 格式，Fluent Bit / Alloy 可无缝切换 |
| **流式查询** | 支持流式大数据量查询，不会 OOM |

---

## 与 Loki 的详细对比

| 维度 | Grafana Loki | VictoriaLogs |
|------|-------------|-------------|
| GitHub Stars | ~23k | ~13k（同 VM 仓库）|
| CNCF 状态 | ✅ Graduated | ❌ |
| 发布时间 | 2018 | 2023 |
| 生产案例 | 大量 | 较少（较新）|
| 存储后端 | 对象存储（S3/MinIO）| 本地磁盘（v0.x），对象存储支持中 |
| 压缩率 | 好 | **更好（高 30-50%）**  |
| 内存消耗 | 中 | **低（约 50%）** |
| 查询延迟 | 中 | **低** |
| Grafana 集成 | ✅ 原生数据源 | ⚠️ 需安装社区插件 |
| LogQL 兼容 | ✅ 原生 | ❌ LogsQL（语法相似但不同）|
| 横向扩展 | Distributed 模式 | 暂不支持（单节点）|
| **SmartVision 推荐** | **✅ 当前首选** | 备选（未来可迁移）|

---

## 在本项目中的评估

### 当前建议

> **结论：当前阶段不选 VictoriaLogs**，原因如下：
>
> 1. **Grafana 集成尚不成熟**：数据源插件需要手动安装，Dashboard 体验不如 Loki
> 2. **对象存储支持尚在开发中**：生产环境大规模日志无法直接对接 MinIO/OSS
> 3. **生产案例少**：2023 年才推出，缺乏大规模生产验证
>
> **未来迁移路径**：当 VictoriaLogs 完善对象存储支持和 Grafana 插件后，可作为 Loki 的升级替换。VictoriaMetrics 整体生态（VM + VLogs）将成为纯 Victoria 方案（方案三）的基础。

### 快速试用对比（实验环境）

```bash
# 单命令启动 VictoriaLogs
docker run -d \
  --name victorialogs \
  -p 9428:9428 \
  -v /data/victorialogs:/victoria-logs-data \
  victoriametrics/victoria-logs:v0.28.0-victorialogs \
  -storageDataPath=/victoria-logs-data \
  -retentionPeriod=30d
```

### 采集端配置（Fluent Bit → VictoriaLogs）

```ini
# fluent-bit.conf
[OUTPUT]
    Name        http
    Match       *
    Host        victorialogs
    Port        9428
    URI         /insert/jsonline?_stream_fields=namespace,pod,container&_msg_field=log&_time_field=time
    Format      json_lines
    Json_date_key time
    Json_date_format epoch
```

### 采集端配置（Alloy → VictoriaLogs，兼容 Loki API）

```river
// VictoriaLogs 兼容 Loki 推送协议
loki.write "victorialogs" {
  endpoint {
    url = "http://victorialogs:9428/insert/loki/api/v1/push?_stream_fields=namespace,pod"
  }
}
```

### LogsQL 查询示例

```
# 查询 prod namespace 中的 ERROR 日志
namespace:prod level:error

# 统计过去 5 分钟的错误率
_time:5m namespace:prod level:error | count() by (service)

# 查询特定 traceId
traceId:abc123
```

---

## 关注点（选型时需确认）

| 问题 | 当前状态（2025 年）|
|------|-----------------|
| MinIO / S3 对象存储支持 | 开发中，预计 2025 Q3 GA |
| Grafana 官方数据源插件 | 社区插件，未进入官方插件市场 |
| 多节点集群 | 路线图中，尚未支持 |
| LogsQL 与 LogQL 转换工具 | 无官方迁移工具 |
