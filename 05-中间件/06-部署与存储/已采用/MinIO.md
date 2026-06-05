# MinIO - 对象存储

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 对象存储（备份归档、制品存储） |
| 部署方式 | 待确认 |
| 版本 | - |
| API | S3 兼容 |

---

## 部署

```bash
# K8s Helm 部署
helm repo add minio https://charts.min.io/
helm install minio minio/minio \
  --namespace minio --create-namespace \
  --set replicas=4 \
  --set persistence.size=500Gi \
  --set rootUser=admin \
  --set rootPassword=<secure-password> \
  --set buckets[0].name=smartvision-archive \
  --set buckets[0].policy=private
```

---

## 当前用?
| 用途| 说明 | 状态|
|------|------|------|
| 制品归档 | CI 产物的历史版本存储| ??`05-cicd/制品管理方案.md` |
| 备份存储 | 数据?中间件备无 | ?待接无 |
| 模型文件 | AI 模型文件存储 | ?待确认 |
| Milvus 底层存储 | 向量数据持久化| ?待确认 |

---

## 运维要点

```bash
# 客户?mc 使用
mc alias set smartvision http://minio.minio:9000 admin <password>
mc ls smartvision/smartvision-archive

# 生命周期管理（过期自动清理）
mc ilm rule add smartvision/smartvision-archive \
  --expire-days 365 \
  --filter-prefix "temp/"

# 事件通知（文件上传触发）
mc event add smartvision/smartvision-archive arn:minio:sqs::primary:kafka \
  --event put
```

---

## 监控

```promql
# 存储桶大小minio_bucket_usage_object_total

# 请求速率
rate(minio_s3_requests_total[5m])

# 磁盘使用?minio_disk_used_bytes / minio_disk_total_bytes * 100

# 节点在线?minio_cluster_nodes_online_total
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 确认部署模式（单?vs 分布式）|
| P0 | 备份策略（跨集群复制 / 定期同步到远端）|
| P1 | 接入 Prometheus 监控 + 告警 |
| P1 | 生命周期管理策略（过期清理）|
| P2 | 事件通知集成（对象创建触发 CI/CD）|
