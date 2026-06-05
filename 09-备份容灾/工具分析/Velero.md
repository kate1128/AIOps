# Velero

## 定位

Kubernetes 工作负载和 PVC 数据备份与恢复工具。

## 核心能力

- K8s 资源（Deployment、ConfigMap、Secret 等）备份恢复
- PVC 持久卷数据快照恢复
- 跨集群迁移（蓝绿迁移、集群升级）
- 定时备份 + 保留策略

## 适用场景

- K8s 命名空间级别定时备份
- 误删资源快速恢复
- 集群迁移时数据搬运
- 配合 MinIO 作为 S3 兼容后端存储

## 与 MinIO 集成

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backup \
  --backup-location-config \
    region=minio,s3ForcePathStyle=true,s3Url=http://minio.backup:9000 \
  --secret-file ./minio-credentials
```

## 局限性

- 不适合数据库级别的时间点恢复（数据库用专用备份方案）
- PVC 快照依赖 CSI Driver 支持，裸机环境需额外配置
- 大 PVC（TB 级）备份耗时较长

## 官方文档

<https://velero.io/docs/>

## 本项目使用参考

[03-存储与对象存储/存储备份规范.md](../03-存储与对象存储/存储备份规范.md)
[04-K8s集群与配置/集群备份规范.md](../04-K8s集群与配置/集群备份规范.md)
