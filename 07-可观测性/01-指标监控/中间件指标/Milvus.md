# Milvus 可观测性

> Milvus 内置 Prometheus 指标端点，无需额外 Exporter。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| Milvus 内置 metrics | 各组件（Proxy/QueryNode/DataNode/IndexNode）内置 /metrics | TCP 9091（默认）|
| Milvus Dashboard | Milvus Insight GUI，可查看集合/索引/查询状态 | Web UI |

Milvus 使用 etcd（元数据）和 Pulsar/Kafka（消息）作为依赖组件，它们的可观测性也需要覆盖。

---

## 核心指标

### Proxy 层

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `milvus_proxy_search_latency_seconds_bucket` | 搜索延迟分布 | P99 > 500ms 告警 |
| `milvus_proxy_query_latency_seconds_bucket` | 查询延迟分布 | P99 > 200ms 关注 |
| `milvus_proxy_insert_vectors_count` | 每秒插入向量数 | 骤降说明写入瓶颈 |
| `milvus_proxy_req_count` | 请求总数 | — |

### QueryNode / DataNode

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `milvus_querynode_sq_count` | 执行查询数 | — |
| `milvus_datanode_flush_buffer_size` | Flush 缓冲区大小 | > 1GB 关注 |
| `container_memory_usage_bytes{container="datanode"}` | DataNode 内存 | OOM 前预警 |

### IndexNode

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `milvus_indexnode_build_index_latency` | 索引构建延迟 | 长时间构建说明资源不足 |

---

## 采集集成

```yaml
# Prometheus static_configs（二进制部署）
- job_name: milvus
  static_configs:
    - targets:
        - "milvus-proxy-host:9091"
        - "milvus-querynode-host:9091"
        - "milvus-datanode-host:9091"
      labels:
        service: milvus
        env: prod

# K8s ServiceMonitor（Cluster 模式）
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: milvus
  namespace: observability
spec:
  selector:
    matchLabels:
      app: milvus
  endpoints:
    - port: metrics
      interval: 15s
```

---

## 告警规则

```yaml
- alert: MilvusSearchLatencyHigh
  expr: histogram_quantile(0.99, rate(milvus_proxy_search_latency_seconds_bucket[5m])) > 0.5
  for: 3m
  annotations:
    summary: "Milvus P99 搜索延迟 > 500ms"

- alert: MilvusInsertRateDrop
  expr: rate(milvus_proxy_insert_vectors_count[5m]) < 10
  for: 5m
  annotations:
    summary: "Milvus 插入速率极低，可能写入阻塞"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 Standalone | 单一进程，直接抓取 9091/metrics |
| Docker Standalone | 容器化同 network，抓取容器 IP:9091 |
| K8s Cluster | 多组件多 ServiceMonitor，每个 Pod 都有 /metrics |

Milvus 依赖 etcd 和消息队列，需同步监控 etcd/mem 和 Pulsar/Kafka 指标。
