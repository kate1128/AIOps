# MinIO 数据复制

## 定位

MinIO 内置的数据复制能力，用于实现对象存储的高可用和容灾备份。

## 两种复制模式

### 1. 站点复制（Site Replication）

多个独立 MinIO 集群之间的双向实时同步：

```bash
# 将 backup 站点加入复制组
mc admin replicate add primary backup

# 查看复制状态
mc admin replicate info primary
```

- 适用于多数据中心高可用
- 双向同步，任一站点可独立提供服务
- 延迟通常小于 1 分钟

### 2. Bucket 复制（Bucket Replication）

指定 bucket 的单向/双向异步复制：

```bash
# 配置单向复制规则
mc replicate add primary/prod-bucket \
  --remote-bucket backup/prod-bucket-replica \
  --replicate "delete,delete-marker,existing-objects" \
  --priority 1

# 查看复制状态
mc replicate status primary/prod-bucket
```

- 适用于跨环境备份
- 可配置仅复制特定前缀的对象

## 版本控制 + 复制（推荐组合）

```bash
# 开启版本控制（防止误删/覆写）
mc version enable primary/prod-bucket

# 配置 lifecycle：旧版本 30 天后删除
mc ilm add primary/prod-bucket --noncurrent-days 30
```

## 监控复制延迟

```bash
# 查看待复制队列深度
mc admin replicate status primary --json | jq '.replication'
```

建议在 Grafana 中接入 MinIO metrics 监控复制队列：

```text
minio_bucket_replication_pending_bytes
minio_bucket_replication_failed_bytes
```

## 局限性

- 站点复制要求 MinIO 版本一致
- 大量小文件复制延迟会增加
- 不支持跨 MinIO 版本的协议差异

## 官方文档

<https://min.io/docs/minio/linux/operations/data-recovery/recover-after-unexpected-loss.html>

## 本项目使用参考

[03-存储与对象存储/存储备份规范.md](../03-存储与对象存储/存储备份规范.md)
