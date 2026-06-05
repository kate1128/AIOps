# Restic

## 定位

开源文件级备份工具，支持加密、去重、压缩，适合文件系统和数据库 dump 文件的备份。

## 核心能力

- 文件级增量备份（基于内容寻址，天然去重）
- 端到端加密（AES-256）
- 支持多种后端：MinIO（S3）、本地磁盘、SFTP、Azure Blob 等
- 快照管理（保留策略）
- 轻量，无需服务端守护进程

## 适用场景

- 数据库 dump 文件备份（配合 mysqldump/pg_dump）
- 服务器文件目录备份
- 容器内文件系统备份（配合 Velero 的文件系统备份模式）

## 基本用法

```bash
# 初始化仓库（MinIO 后端）
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
restic -r s3:http://minio:9000/backup-restic init

# 备份目录
restic -r s3:http://minio:9000/backup-restic backup /var/backup/mysql/

# 查看快照
restic -r s3:http://minio:9000/backup-restic snapshots

# 恢复
restic -r s3:http://minio:9000/backup-restic restore latest --target /restore/

# 清理旧快照（保留最近 30 天）
restic -r s3:http://minio:9000/backup-restic forget --keep-daily 30 --prune
```

## 与数据库备份集成

```bash
# MySQL 备份脚本示例
mysqldump --all-databases | gzip > /tmp/mysql-$(date +%Y%m%d).sql.gz
restic -r s3:http://minio:9000/backup-db backup /tmp/mysql-*.sql.gz
rm /tmp/mysql-*.sql.gz
```

## 局限性

- 不支持数据库时间点恢复（只能恢复到快照时间点）
- 恢复速度取决于网络带宽，大文件恢复慢

## 官方文档

<https://restic.net/docs/>

## 本项目使用参考

[02-数据库备份与恢复/数据库备份规范.md](../02-数据库备份与恢复/数据库备份规范.md)
