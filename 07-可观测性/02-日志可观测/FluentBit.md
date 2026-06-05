# Fluent Bit — 轻量级日志处理器

## 概述

Fluent Bit 是 CNCF 毕业项目，用 C 编写的轻量级日志处理器和转发器。相比 Promtail，Fluent Bit 资源占用更低（约 5MB 内存），且支持更丰富输出端和复杂数据处理管道。

## 核心能力

- **低资源**: C 语言实现，内存 5-10MB，CPU 极低
- **多输出**: 同时输出到 Loki + Elasticsearch + S3 + Kafka + 文件
- **丰富输入**: tail、systemd、tcp、syslog、K8s 等
- **数据处理管道**: Parsers (正则/json/ltsv)、Filters (grep/modify/record/geoip/throttle)
- **插件生态**: 100+ 官方插件

## 引入时机

当前 Promtail 满足基本日志采集需求。当出现以下情况时引入 Fluent Bit：

1. **多输出需求**: 日志同时发往 Loki（展示）+ Kafka（流处理）+ S3（归档）
2. **复杂日志解析**: 需要对日志内容做结构化转换、字段提取
3. **统一 Agent**: 替代 Promtail + Vector 等角色，一个 Agent 完成采集 + 处理 + 转发

## 配置示例

`ini
[SERVICE]
    parsers_file    /etc/fluent-bit/parsers.conf

[INPUT]
    name            tail
    path            /var/log/*.log
    tag             ai-backend.*
    parser          json

[OUTPUT]
    name            loki
    match           *
    host            loki.monitoring.svc
    port            3100
    labels          job=fluentbit, host=

[OUTPUT]
    name            s3
    match           *
    bucket          observability-logs
    region          us-east-1
    total_file_size 50M
`

## 与 Promtail 对比

| 特性 | Promtail | Fluent Bit |
|------|----------|------------|
| 语言 | Go | C |
| 内存占用 | 20-50MB | 5-10MB |
| 多输出 | 有限 | 原生支持 |
| 日志解析 | pipeline_stages | parsers + filters |
| K8s 集成 | 原生 | 需额外配置 |
| 运维复杂度 | 低 | 中 |
