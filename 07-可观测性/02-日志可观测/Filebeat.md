# Filebeat — ELK 官方日志采集器

## 概述

Filebeat 是 Elastic 公司开源的轻量日志采集器，属于 Beats 家族（Metricbeat、Packetbeat 等），以 Go 编写，主要用途是将文件日志采集并发送到 Logstash 或 Elasticsearch。

- GitHub: [elastic/beats](https://github.com/elastic/beats) ⭐ ~12k
- CNCF 状态: 非 CNCF 项目（Elastic 主导）
- 默认监听: 无对外端口（纯推送模式）
- 协议: Lumberjack（到 Logstash）/ HTTP Bulk API（到 ES）

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **文件 tail** | 基于文件偏移量持久化，重启不丢日志 |
| **多行合并** | 支持 Java 异常堆栈多行合并（multiline）|
| **内置模块** | Nginx / Apache / MySQL / System 等预置解析模块 |
| **Elasticsearch 原生集成** | 直接推送，自动创建 Index Template |
| **K8s 日志发现** | autodiscover 机制自动发现 Pod 日志 |
| **背压控制** | 内置队列，下游慢时暂停采集 |

---

## 与方案一（Alloy）的对比

| 维度 | Filebeat | Grafana Alloy |
|------|---------|--------------|
| 目标后端 | ES / Logstash（强绑定）| Loki / Prometheus / Tempo（全家桶）|
| 指标采集 | ❌ | ✅（含 node-exporter）|
| OTel 支持 | ❌ | ✅ |
| 内存占用 | ~50 MB | ~100 MB |
| 输出到 Loki | ⚠️ 需 Logstash 中转 | ✅ 原生 |
| 配置复杂度 | 低（YAML）| 中（River）|
| CNCF 标准 | ❌ | ❌ |
| **SmartVision 场景推荐** | 仅 ELK 方案（方案二）使用 | **方案一首选** |

---

## 在本项目中的评估

> **结论：方案一（Grafana Alloy + Loki）不选 Filebeat**，Filebeat 是方案二（ELK）的配套组件。
>
> 如果项目将来需要引入 ELK 做日志全文搜索（如合规审计场景），Filebeat 是标准选择。

### 方案二配置示例（ELK 场景参考）

```yaml
# filebeat.yml（K8s DaemonSet 部署）
filebeat.autodiscover:
  providers:
    - type: kubernetes
      node: ${NODE_NAME}
      templates:
        - condition:
            contains:
              kubernetes.namespace: "prod"
          config:
            - type: container
              paths:
                - /var/log/containers/*${data.kubernetes.container.id}.log
              multiline.type: pattern
              multiline.pattern: '^\d{4}-\d{2}-\d{2}'
              multiline.negate: true
              multiline.match: after
              processors:
                - decode_json_fields:
                    fields: ["message"]
                    target: "json"

output.logstash:
  hosts: ["logstash.logging.svc:5044"]

# 或直接输出到 ES（跳过 Logstash）
output.elasticsearch:
  hosts: ["elasticsearch.logging.svc:9200"]
  index: "smartvision-logs-%{+yyyy.MM.dd}"
```

### 内置模块使用

```yaml
# 启用 Nginx 内置模块（自动解析 access/error log）
filebeat.modules:
  - module: nginx
    access:
      enabled: true
      var.paths: ["/var/log/nginx/access.log"]
    error:
      enabled: true
      var.paths: ["/var/log/nginx/error.log"]
```

---

## 总结

Filebeat 在 ELK 生态中成熟稳定，但在 Grafana/Loki 生态中存在明显短板（无法直接推送 Loki，不采集指标）。SmartVision 当前方案一中不需要 Filebeat；如果未来引入 ELK 做合规审计日志，可使用 Filebeat 作为采集端。
