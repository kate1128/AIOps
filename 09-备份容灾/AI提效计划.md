# AI 提效计划 - 备份容灾

> 将 AI 引入备份监控、恢复验证和演练报告生成，目标：备份异常发现时间从人工周级发现到分钟级告警，恢复演练时间缩短 50%，演练频率从季度提升到月度。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| 备份状态检查 | 手动查看，无自动化 | 运维工程师 | 没有统一监控，靠人工定期确认 |
| 备份有效性验证 | 很少验证（几乎不做）| 运维工程师 | 流程繁琐，需要临时环境，频率极低 |
| 恢复演练 | 从未完整执行过 | 运维 + 研发 | 流程不清晰，所需时间不确定 |
| 演练报告撰写 | 未执行 | - | 没有报告 = 没有沉淀 |
| 备份策略设计 | 凭经验设置 | 运维负责人 | 保留期/频率没有基于数据 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **Shell 脚本 + Prometheus** | 备份任务状态监控和告警 | ❌ 待建立 | 低 | 开源免费 |
| **Claude API** | 备份日志分析、演练报告生成、恢复 SOP 辅助 | 🟡 个人使用 | 低 | ~¥100-200 |
| **pgBackRest / Velero** | PostgreSQL 备份和 K8s 集群备份 | ❌ 待评估 | 中 | 开源免费 |
| **MinIO Console** | MinIO 备份桶监控 | 🟡 已有 MinIO | 低 | 已有 |

---

## 三、高价值机会点详细方案

### 机会1：备份任务自动监控与告警

**当前状态**：备份任务是否成功靠人工偶尔查看，备份失败可能持续数天无人知晓。  
**目标状态**：每次备份任务完成后立即验证状态，失败 5 分钟内告警。

**方案设计**：
```bash
#!/bin/bash
# backup-monitor.sh - 在备份任务完成后执行（CronJob 后置步骤）

BACKUP_TYPE=$1  # postgresql / milvus / minio / k8s
STATUS="SUCCESS"
DETAILS=""

case $BACKUP_TYPE in
  postgresql)
    # 检查最新备份文件时间戳
    LATEST=$(find /backup/postgresql/ -name "*.sql.gz" -mmin -120 | tail -1)
    if [ -z "$LATEST" ]; then
      STATUS="FAILED"
      DETAILS="2小时内无新备份文件"
    else
      SIZE=$(du -sh $LATEST | cut -f1)
      DETAILS="最新备份：$LATEST，大小：$SIZE"
    fi
    ;;
  k8s)
    # 检查 Velero 备份状态
    STATUS=$(velero backup get --output json | jq -r '.items[-1].status.phase')
    DETAILS="最新 K8s 备份状态：$STATUS"
    ;;
esac

# Prometheus Pushgateway 上报指标
curl -X POST "$PUSHGATEWAY/metrics/job/backup_monitor" \
  -d "backup_last_success_timestamp{type=\"$BACKUP_TYPE\"} $(date +%s)"

# 失败告警
if [ "$STATUS" = "FAILED" ]; then
  curl -X POST "$FEISHU_WEBHOOK" \
    -d "{\"text\":\"🚨 备份失败告警：$BACKUP_TYPE\n详情：$DETAILS\"}"
fi
```

**Prometheus 告警规则**：
```yaml
- alert: BackupNotRunning
  expr: time() - backup_last_success_timestamp > 86400  # 超过24小时未备份
  labels:
    severity: critical
  annotations:
    summary: "{{ $labels.type }} 备份超过 24 小时未成功"
```

**工具栈**：Shell + Prometheus Pushgateway + Alertmanager + 飞书  
**前置条件**：自动化备份任务已部署（先完成基础备份建设）  
**实施周期**：2-3 天（监控脚本 + 告警规则）  
**ROI 估算**：备份失败从天级发现到分钟级告警，防止无备份状态的数据风险

---

### 机会2：AI 辅助备份有效性验证

**当前状态**：验证备份是否可用需要在临时环境恢复，流程繁琐，几乎不做。  
**目标状态**：每周自动在沙箱环境做轻量级验证（抽样恢复），验证结果 AI 生成报告。

**方案设计**：
```bash
#!/bin/bash
# weekly-backup-verify.sh - 每周六 02:00 执行

SANDBOX_DB="postgres-verify"
BACKUP_FILE=$(ls -t /backup/postgresql/*.sql.gz | head -1)

echo "=== 备份验证开始：$BACKUP_FILE ==="

# 1. 创建临时验证数据库
kubectl run pg-restore-test --image=postgres:15 --restart=Never \
  -e POSTGRES_PASSWORD=verify123 -n dev
sleep 30

# 2. 恢复备份
kubectl exec pg-restore-test -- sh -c \
  "gunzip -c /backup/dump.sql.gz | psql -U postgres"

# 3. 验证关键数据
ROW_COUNT=$(kubectl exec pg-restore-test -- \
  psql -U postgres -t -c "SELECT COUNT(*) FROM users;")

# 4. 清理
kubectl delete pod pg-restore-test -n dev

# 5. AI 生成验证报告
REPORT="备份文件：$BACKUP_FILE
恢复状态：$([ $? -eq 0 ] && echo "成功" || echo "失败")
users 表行数：$ROW_COUNT
验证时间：$(date)"

SUMMARY=$(echo "$REPORT" | claude-api-call \
  "生成简洁的备份验证报告（中文），包含是否通过、关键数据正常与否、建议")

curl -X POST "$FEISHU_WEBHOOK" -d "{\"text\":\"📋 周度备份验证报告\n$SUMMARY\"}"
```

**前置条件**：PostgreSQL 自动备份已部署；Dev 环境有 K8s 临时 Pod 权限  
**实施周期**：1 周  
**ROI 估算**：备份可用性从"从未验证"到每周自动验证，实际可用率从未知变为可量化

---

### 机会3：恢复演练 AI 辅助与报告生成

**当前状态**：恢复演练流程不清晰，没有人知道完整步骤需要多长时间，季度演练目标基本未执行。  
**目标状态**：AI 生成分步演练 SOP，演练后自动生成复盘报告。

**方案设计**：
```
演练前：AI 生成演练 SOP
  输入：演练场景（如"PostgreSQL 主库数据损坏，需从备份恢复"）
  输出：
    Step 1: 确认备份文件完整性（校验 SHA256）
    Step 2: 停止所有写入连接（应用 read-only 模式）
    Step 3: 执行 pg_restore 命令（附具体命令）
    Step 4: 验证数据完整性（关键表行数校验）
    Step 5: 切换应用连接
    Step 6: 监控 30 分钟确认稳定
  附：每步预期耗时和风险点

演练中：记录实际耗时和问题
  - 手机计时每步实际耗时
  - 记录遇到的问题和临时处理方式

演练后：AI 生成复盘报告
  输入：演练记录（时间/步骤/问题）
  输出：
    - RTO 实测值 vs 目标值对比
    - 执行顺畅 vs 卡壳的步骤
    - 改进建议（SOP 哪些步骤需要更新）
    - 下次演练建议
```

**工具栈**：Claude API（SOP生成+报告生成）  
**前置条件**：至少有一份完整的备份和恢复文档（手动演练过一次）  
**实施周期**：Phase 0 先人工演练一次并记录，Phase 1 再自动化  
**ROI 估算**：演练频率从近零提升到月度；RTO 目标可量化并持续改进

---

## 四、实施路径

> ⚠️ **注意**：当前备份体系从零开始，AI 增强能力需在完成[体系建设总览](./体系建设总览.md) Phase 1 基础备份后才有意义。先建备份，再做 AI 监控。

### Phase 0（第 1-4 周）：基础备份先行（必须完成后才能执行下一步）

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| PostgreSQL 自动备份 | 部署 pg_dump CronJob，备份到 MinIO | 每天自动备份，文件存在 | 运维 |
| K8s etcd 备份 | etcd snapshot 定时任务 | 每天自动 etcd 快照 | 运维 |
| 第一次手动恢复演练 | 人工执行一次 PostgreSQL 恢复，记录步骤和耗时 | 完成演练记录，有 RTO 实测数据 | 运维 |

### Phase 1（第 5-6 周）：监控与验证自动化

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 备份监控告警 | 部署 backup-monitor.sh + Prometheus 告警规则 | 备份失败 5 分钟内飞书告警 | 运维 | 自动备份任务已部署 |
| 周度备份验证 | 部署 weekly-backup-verify.sh，周报推送 | 每周自动推送备份验证报告 | 运维 | 备份文件已在 MinIO |

### Phase 2（第 7-8 周）：演练 AI 化

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| AI 演练 SOP 生成 | 为每类场景生成 AI 辅助 SOP，纳入知识库 | 覆盖 PostgreSQL/MinIO/K8s 三类场景 | 运维 + SRE | 手动演练记录 |
| 演练 AI 报告 | 演练后用 Claude 自动生成复盘报告 | 演练后 1 小时内完成报告 | 运维 | Phase 1 完成 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（监控分析+报告生成）| ~¥100-200 | 约 2-4 人天/月 | 高 |
| 运维脚本开发（一次性）| 2-3 人天 | 长期持续受益 | 高 |
| **合计** | **~¥100-200/月** | **约 3-5 人天/月** | **约 1:12** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| 备份验证沙箱环境污染生产数据 | 数据安全风险 | 验证环境完全隔离在 dev 命名空间；使用只读的备份副本 |
| AI 生成的恢复 SOP 有步骤遗漏 | 演练时出问题 | SOP 必须由人工 Review 后才能作为正式流程使用 |
| 验证脚本误删生产备份文件 | 数据丢失 | 脚本中所有删除操作需要二次确认；MinIO 桶开启版本控制 |
