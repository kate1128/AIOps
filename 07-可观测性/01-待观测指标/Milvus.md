# Milvus 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Milvus 官方文档：[Milvus Monitoring](https://milvus.io/docs/monitor.md)
2. Milvus GitHub：[milvus-io/milvus](https://github.com/milvus-io/milvus)
3. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)

> Grafana 官方知识来源没有 Milvus 专用 Alloy 集成；Milvus 内置 Prometheus `/metrics`，Alloy 可通过通用 `prometheus.scrape` 抓取。

---

## 1. 结论摘要

Milvus 内置 Prometheus 指标端点，覆盖 Proxy、QueryNode、DataNode、IndexNode、RootCoord 等组件。在 Alloy 体系下，不需要额外 Milvus exporter，直接用 `prometheus.scrape` 抓取各组件 `:9091/metrics` 即可。Milvus 依赖 etcd、对象存储（MinIO/S3）和消息队列（Kafka/Pulsar），完整监控必须覆盖依赖组件。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | Milvus 内置 `/metrics` |
| 默认端口 | TCP `9091` |
| Alloy 集成 | `prometheus.scrape` 抓取组件端点 |
| 关键依赖 | etcd、MinIO/S3、Kafka/Pulsar |
| 推荐 Dashboard | Milvus Dashboard |

---

## 2. 产品概况（Milvus metrics）

| 组件 | 指标内容 |
| --- | --- |
| Proxy | 搜索/查询/插入请求、延迟、QPS |
| QueryNode | 查询执行、加载段、内存 |
| DataNode | Flush、写入、Buffer |
| IndexNode | 索引构建任务和耗时 |
| RootCoord / QueryCoord / DataCoord | 元数据、调度、任务状态 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `milvus_proxy_search_latency_seconds_bucket` | 搜索延迟 | P99 > 500ms 告警 |
| `milvus_proxy_query_latency_seconds_bucket` | 查询延迟 | P99 > 200ms 关注 |
| `milvus_proxy_insert_vectors_count` | 插入向量数 | 写入速率骤降告警 |
| `milvus_proxy_req_count` | 请求总数 | QPS 基线 |
| `milvus_datanode_flush_buffer_size` | Flush Buffer | > 1GB 关注 |
| `milvus_indexnode_build_index_latency` | 索引构建耗时 | 长时间构建告警 |
| `container_memory_usage_bytes{container=~".*node.*"}` | 组件内存 | > 90% limit 告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 适用场景 |
| --- | --- | --- | --- |
| Milvus 内置 metrics | 组件端点 | Milvus 组件指标 | 标准方案 |
| **Grafana Alloy** | `prometheus.scrape` | 抓取 Milvus / 依赖组件 | **本项目首选** |
| kube-prometheus-stack | ServiceMonitor | K8s 标准采集 | Prometheus Operator 体系 |
| Netdata | Agent | 部分系统指标 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 静态目标采集

```alloy
prometheus.scrape "milvus" {
  targets = [
    { __address__ = "milvus-proxy.ai.svc:9091", component = "proxy" },
    { __address__ = "milvus-querynode.ai.svc:9091", component = "querynode" },
    { __address__ = "milvus-datanode.ai.svc:9091", component = "datanode" },
    { __address__ = "milvus-indexnode.ai.svc:9091", component = "indexnode" },
  ]
  scrape_interval = "30s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "milvus"
}
```

### 5.2 Kubernetes 自动发现

```alloy
discovery.kubernetes "milvus" {
  role = "pod"
  selectors { role = "pod" label = "app=milvus" }
}

discovery.relabel "milvus" {
  targets = discovery.kubernetes.milvus.targets
  rule { source_labels = ["__meta_kubernetes_pod_container_port_number"] regex = "9091" action = "keep" }
  rule { source_labels = ["__meta_kubernetes_pod_name"] target_label = "instance" }
}

prometheus.scrape "milvus" {
  targets = discovery.relabel.milvus.output
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "milvus"
}
```

---

## 6. 依赖组件监控

| 依赖 | 监控方式 |
| --- | --- |
| etcd | etcd 内置 `/metrics` |
| MinIO / S3 | MinIO metrics 或云厂商指标 |
| Kafka / Pulsar | Kafka/JMX 或 Pulsar metrics |
| Kubernetes | kubelet、KSM、Pod 资源指标 |

---

## 7. 告警规则

```yaml
groups:
- name: milvus.rules
  rules:
  - alert: MilvusSearchLatencyHigh
    expr: histogram_quantile(0.99, rate(milvus_proxy_search_latency_seconds_bucket[5m])) > 0.5
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Milvus 搜索 P99 延迟超过 500ms" }

  - alert: MilvusInsertRateDrop
    expr: rate(milvus_proxy_insert_vectors_count[5m]) < 10
    for: 10m
    labels: { severity: warning }
    annotations: { summary: "Milvus 插入速率过低" }
```

---

## 8. Grafana Dashboard

推荐导入 Milvus Dashboard，并补充依赖组件面板：etcd 延迟、MinIO 容量、Kafka Lag、QueryNode/DataNode Pod 资源。

---

## 9. KAgent 集成（Milvus 运维 Agent）

推荐绑定 PrometheusServer 查询 Milvus 和依赖组件指标，并用 Skills 注入搜索延迟、索引构建慢、DataNode flush 堵塞、MinIO/etcd 异常排查 SOP。

---

## 10. 常见问题

### Grafana Alloy 支持采集 Milvus 指标吗？

**可以，但不是专用集成。** Milvus 内置 Prometheus 指标端点，Alloy 可用 `prometheus.scrape` 抓取；Grafana 官方知识来源没有 Milvus 专用 Alloy 集成。

### 只采集 Milvus 本身够吗？

不够。Milvus 强依赖 etcd、对象存储和消息队列，很多查询慢或写入慢问题来自依赖组件，必须联合监控。
# Milvus 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Milvus 文档：[Milvus Monitoring](https://milvus.io/docs/monitor.md)
2. Milvus GitHub：[milvus-io/milvus](https://github.com/milvus-io/milvus)
3. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)

> Grafana 官方知识来源没有 Milvus 专用集成。Milvus 内置 Prometheus 指标端点，Alloy 可通过通用 `prometheus.scrape` 抓取。

---

## 1. 结论摘要

Milvus 内置 Prometheus 指标端点，覆盖 Proxy、QueryNode、DataNode、IndexNode、RootCoord 等组件。在 Alloy 体系下，无需额外 exporter，使用 `prometheus.scrape` 抓取各组件 `/metrics` 即可。Milvus 强依赖 etcd、消息队列（Kafka/Pulsar）和对象存储（MinIO/S3），完整监控必须同时覆盖这些依赖。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | Milvus 内置 `/metrics` |
| 默认端口 | 常见为 `9091`（以部署配置为准）|
| Alloy 集成 | `prometheus.scrape` 抓取各组件端点 |
| 依赖组件 | etcd、Kafka/Pulsar、MinIO/S3 |
| Dashboard | Milvus Dashboard / 自建向量数据库大盘 |

---

## 2. 产品概况（Milvus Metrics）

| 组件 | 指标内容 |
| --- | --- |
| Proxy | 搜索/查询/插入请求、延迟、QPS |
| QueryNode | 查询执行、Segment 加载、内存 |
| DataNode | Flush、写入缓冲、DataCoord 通信 |
| IndexNode | 索引构建耗时、任务状态 |
| RootCoord / QueryCoord | 元数据、调度、任务状态 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `milvus_proxy_search_latency_seconds_bucket` | 搜索延迟 | P99 > 500ms 告警 |
| `milvus_proxy_query_latency_seconds_bucket` | 查询延迟 | P99 > 200ms 关注 |
| `milvus_proxy_insert_vectors_count` | 插入向量数 | 突降排查写入链路 |
| `milvus_proxy_req_count` | 请求总数 | 错误率分母 |
| `milvus_datanode_flush_buffer_size` | Flush 缓冲大小 | > 1GB 关注 |
| `milvus_indexnode_build_index_latency` | 索引构建耗时 | 长时间增长排查资源 |
| `container_memory_usage_bytes{container=~"querynode|datanode"}` | 组件内存 | > 90% limit 告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| Milvus 内置 metrics | 原生端点 | 各组件指标 | 无 | 标准方案 |
| **Grafana Alloy** | `prometheus.scrape` | 抓取内置端点 | Loki 采集日志 | **本项目首选** |
| Prometheus Operator | ServiceMonitor | 各组件指标 | 无 | K8s 标准方案 |
| Netdata | Agent | 有限支持 | 内置 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 静态 targets

```alloy
prometheus.scrape "milvus" {
  targets = [
    { __address__ = "milvus-proxy.ai.svc:9091", component = "proxy" },
    { __address__ = "milvus-querynode.ai.svc:9091", component = "querynode" },
    { __address__ = "milvus-datanode.ai.svc:9091", component = "datanode" },
    { __address__ = "milvus-indexnode.ai.svc:9091", component = "indexnode" },
  ]
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "milvus"
}
```

### 5.2 Kubernetes 自动发现

```alloy
discovery.kubernetes "milvus" {
  role = "pod"
  selectors { role = "pod" label = "app=milvus" }
}

discovery.relabel "milvus" {
  targets = discovery.kubernetes.milvus.targets
  rule {
    source_labels = ["__meta_kubernetes_pod_container_port_number"]
    regex = "9091"
    action = "keep"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label = "instance"
  }
}

prometheus.scrape "milvus_k8s" {
  targets = discovery.relabel.milvus.output
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "milvus"
}
```

---

## 6. 部署方式对比

| 部署方式 | 采集方式 |
| --- | --- |
| Standalone | 抓取单实例 metrics 端点 |
| Docker Compose | 同 network 抓取各容器 metrics |
| K8s Cluster | ServiceMonitor 或 Alloy Kubernetes discovery |
| 托管依赖 | etcd/Kafka/MinIO 需单独接入对应监控 |

---

## 7. 告警规则

```yaml
groups:
- name: milvus.rules
  rules:
  - alert: MilvusSearchLatencyHigh
    expr: histogram_quantile(0.99, rate(milvus_proxy_search_latency_seconds_bucket[5m])) > 0.5
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Milvus P99 搜索延迟超过 500ms" }

  - alert: MilvusInsertRateDrop
    expr: rate(milvus_proxy_insert_vectors_count[5m]) < 10
    for: 10m
    labels: { severity: warning }
    annotations: { summary: "Milvus 插入速率异常降低" }

  - alert: MilvusDataNodeMemoryHigh
    expr: container_memory_usage_bytes{container=~"datanode|querynode"} / container_spec_memory_limit_bytes > 0.9
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Milvus 组件内存使用率过高" }
```

---

## 8. Grafana Dashboard

推荐使用 Milvus Dashboard，并额外联动 etcd、Kafka/Pulsar、MinIO/S3 Dashboard，构成完整向量数据库链路视图。

---

## 9. KAgent 集成（Milvus 运维 Agent）

推荐绑定 PrometheusServer 查询 Milvus 搜索延迟、写入速率、Index 构建、依赖组件状态，并用 Skills 注入向量检索性能排障 SOP。

---

## 10. 常见问题

### Grafana Alloy 支持采集 Milvus 指标吗？

**可以。** Grafana 官方知识来源没有 Milvus 专用集成，但 Milvus 内置 Prometheus `/metrics`，Alloy 可用 `prometheus.scrape` 直接抓取。

### Milvus 只监控自身够吗？

不够。Milvus 强依赖 etcd、消息队列和对象存储。搜索慢、插入阻塞、索引构建慢经常来自依赖组件瓶颈，需要联动分析。
