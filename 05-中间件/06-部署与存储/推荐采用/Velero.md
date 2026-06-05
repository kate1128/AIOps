# Velero - K8s 集群备份与恢复

> 推荐原因：SmartVision 三套 K8s 集群（prod/pre/dev）的 PVC 数据、ConfigMap、Secret 等资源尚无统一备份机制。Velero 提供 K8s 原生的定时备份（存储到 MinIO）、命名空间级别恢复、跨集群迁移能力。
> 当前状态：❌ 未部署，参见 09-备份容灾 体系建设计划，推荐优先在 prod 集群部署。

---

## 现状与问题

| 项目 | 现状 |
|------|------|
| K8s 资源备份 | ❌ 无（ConfigMap/Secret/Deployment 无备份）|
| PVC 数据备份 | ❌ 部分靠数据库自身备份（pg_dump），K8s 层无统一方案 |
| 集群灾难恢复 | ❌ 无完整方案，K8s 节点故障时 PVC 数据有丢失风险 |
| 命名空间迁移（dev→pre）| 手动导出/导入 YAML，效率低且容易遗漏 |
| 备份验证 | ❌ 无自动化验证（备份了但不知道能否恢复）|

---

## Velero 是什么

Velero 是 VMware 开源的 K8s 备份恢复工具，可以：
- **备份整个命名空间**：所有 K8s 资源对象（YAML）+ PVC 数据
- **定时备份**：Schedule CRD，类似 cron，自动存储到 MinIO/S3
- **命名空间级恢复**：从历史备份恢复到同一或不同集群
- **跨集群迁移**：将 pre 环境数据迁移到 prod（灾备场景）

---

## 与其他备份方案的对比

| 维度 | pg_dump/手动脚本 | Velero |
|------|----------------|--------|
| 覆盖范围 | 数据库数据 | K8s 所有资源 + PVC |
| 自动化 | 需要额外脚本 | 内置 Schedule CRD |
| K8s 感知 | 无 | 完整（含 Labels/Annotations/RBAC）|
| PVC 快照 | 无 | ✅ 支持 CSI 快照 |
| 跨集群恢复 | 困难 | ✅ 原生支持 |
| 验证恢复 | 手动 | 可脚本化验证 |

两者互补，不互斥。

---

## K8s 部署

```bash
# 安装 Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xzf velero-v1.13.0-linux-amd64.tar.gz
mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/

# 创建 MinIO 凭证文件
cat > /tmp/credentials-velero <<EOF
[default]
aws_access_key_id=minio-admin
aws_secret_access_key=minio-secret
EOF

# 安装 Velero（使用 MinIO 作为存储后端）
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups \
  --secret-file /tmp/credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config \
    region=minio,s3ForcePathStyle=true,s3Url=http://minio.prod.svc.cluster.local:9000 \
  --namespace velero
```

---

## 定时备份配置

```yaml
# 每日 2:00 备份 prod 命名空间（保留 30 天）
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: prod-daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
    - prod
    - monitoring
    - argocd
    excludedResources:
    - events          # 排除无需备份的事件
    - events.events.k8s.io
    storageLocation: default
    ttl: 720h0m0s    # 30 天后自动删除
    snapshotVolumes: false  # 使用 restic 替代 CSI 快照
    defaultVolumesToRestic: true  # 备份 PVC 内容
```

---

## 手动备份与恢复

```bash
# 手动备份指定命名空间
velero backup create prod-manual-backup-20240101 \
  --include-namespaces prod \
  --wait

# 查看备份状态
velero backup describe prod-manual-backup-20240101
velero backup logs prod-manual-backup-20240101

# 恢复到原命名空间（灾难恢复）
velero restore create --from-backup prod-manual-backup-20240101

# 恢复到新命名空间（跨集群迁移/测试验证）
velero restore create --from-backup prod-manual-backup-20240101 \
  --namespace-mappings prod:prod-restored

# 验证恢复结果
kubectl get all -n prod-restored
```

---

## 备份有效性自动验证

```bash
#!/bin/bash
# 每周在 dev 集群验证 prod 备份可恢复性（参见 09-备份容灾）

# 1. 从最新备份创建恢复（到临时命名空间）
LATEST_BACKUP=$(velero backup get --output json | \
  jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')

velero restore create verify-${DATE} \
  --from-backup ${LATEST_BACKUP} \
  --namespace-mappings prod:backup-verify

# 2. 检查核心服务是否正常启动
kubectl wait --for=condition=ready pod \
  -l app=smartvision-api \
  -n backup-verify \
  --timeout=300s

# 3. 运行 Smoke Test
curl -f http://smartvision-api.backup-verify.svc/health

# 4. 清理临时命名空间
kubectl delete namespace backup-verify

# 5. 上报结果（Prometheus Pushgateway）
curl -X POST http://pushgateway:9091/metrics/job/velero-backup-verify \
  -d "backup_verify_success{backup=\"${LATEST_BACKUP}\"} 1"
```

---

## 告警规则

```yaml
- alert: VeleroBackupFailed
  expr: velero_backup_last_status{schedule="prod-daily-backup"} != 1
  for: 5m
  labels: { severity: critical }
  annotations:
    summary: "Velero 备份失败，最近一次备份状态异常"

- alert: VeleroBackupOld
  expr: time() - velero_backup_last_successful_timestamp{schedule="prod-daily-backup"} > 86400 * 2
  labels: { severity: warning }
  annotations:
    summary: "Velero 备份已超过 2 天未成功"
```

---

## 引入优先级

| 优先级 | 理由 |
|--------|------|
| 🔴 高优（本季度部署）| prod 集群 PVC 数据无备份是高风险项；参见 09-备份容灾 体系建设 Phase 1 |

---

## 参考

- 官方文档：https://velero.io/docs/
- Restic 集成（PVC 备份）：https://velero.io/docs/main/restic/
- MinIO 后端配置：https://velero.io/docs/main/supported-providers/
