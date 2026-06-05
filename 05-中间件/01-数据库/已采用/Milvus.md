# Milvus - 向量数据库
> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| AI 向量相似度搜索|
| 部署方式 | 待确认（单机 / 集群）|
| 版本 | - |
| 索引类型 | - |

---

## 部署模式

| 模式 | 场景 | 说明 |
|------|------|------|
| Standalone | 开发测试 | 单容器，全组件打包 |
| Cluster | 生产 | Proxy + QueryNode + DataNode + IndexNode 分离 |

### 集群架构

```
请求 → Proxy → RootCoord
                              ├── QueryNode（搜索）
               ├── DataNode（持久化）
               └── IndexNode（索引构建）
          └── MinIO/S3（存储）
          └── etcd（元数据）          └── Pulsar/Kafka（消息）
```

```bash
helm repo add milvus https://milvus-io.github.io/milvus-helm/
helm install milvus milvus/milvus \
  --namespace milvus --create-namespace \
  --set cluster.enabled=true \
  --set persistence.pvc.storageClass=nfs-client
```

---

## 索引选型

| 索引 | 场景 | 召回率| 构建速度 |
|------|------|--------|---------|
| IVF_FLAT | 通用 | 高 | 快 |
| IVF_SQ8 | 内存敏感 | 中高 | 快 |
| HNSW | 高精度高并发 | 最高 | 慢 |
| AutoIndex | 自动调优 | 自动 | 自动 |

```python
collection.create_index(
    field_name="embedding",
    index_params={"metric_type": "IP", "index_type": "IVF_FLAT", "params": {"nlist": 1024}}
)
```

---

## 监控

```promql
histogram_quantile(0.99, rate(milvus_proxy_search_latency_seconds_bucket[5m]))
rate(milvus_proxy_insert_vectors_count[1m])
container_memory_usage_bytes{container="datanode"}
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 确认部署模式（生产必须集群）|
| P0 | 内存规划：向量量 × 维度 × 4B × 1.5 |
| P1 | 索引类型调优 |
| P1 | 备份策略 |
| P2 | 数据生命周期管理 |
