# AI 提效计划 - 中间件

> 将 AI 引入中间件的运维与排障：异常根因快速定位、配置参数智能推荐、容量预测、跨环境配置一致性检查。目标：中间件故障 MTTR 减少 50%，性能调优时间减少 70%。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| Kafka 消息堆积排查 | 2-6 小时/次 | 运维工程师 | 需逐一检查 Consumer Group 状态，关联业务代码逻辑 |
| PostgreSQL 慢查询分析 | 1-4 小时/次 | 运维 + DBA | 执行计划分析需专业知识，优化建议依赖经验 |
| 中间件参数调优 | 1-3 人天/次 | 运维工程师 | 参数多，各中间件参数相互影响，依赖专家经验 |
| 容量规划 | 季度手动估算 | 运维负责人 | 无趋势预测，扩容往往被动响应 |
| 跨环境配置差异排查 | 1-3 小时/次 | 运维工程师 | 手动 diff 三套环境配置，易漏项 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **Claude API** | 慢查询分析、Kafka堆积根因、参数推荐 | 🟡 个人使用 | 低 | ~¥200-400 |
| **Prometheus + predict_linear** | 容量趋势预测 | 🟡 Prometheus已有 | 低（内置函数）| 已有 |
| **Grafana Loki** | 中间件日志 AI 分析 | 🟡 规划中 | 中 | 已有 Grafana |
| **pg_stat_statements** | PostgreSQL 慢查询采集 | 🟡 部分启用 | 低 | 内置扩展免费 |
| **Kafka UI + LLM** | Kafka 状态可视化 + AI 分析 | ❌ 未使用 | 中 | 开源免费 |

---

## 三、高价值机会点详细方案

### 机会1：PostgreSQL 慢查询 AI 自动分析

**当前状态**：慢查询告警触发后，DBA 手动执行 EXPLAIN ANALYZE，需要 1-4 小时。  
**目标状态**：慢查询自动捕获，AI 在 2 分钟内输出执行计划分析和优化建议。

**方案设计**：
```sql
-- 采集慢查询（pg_stat_statements）
SELECT query, mean_exec_time, calls, total_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 1000  -- 超过 1 秒
ORDER BY total_exec_time DESC LIMIT 20;

-- 获取执行计划
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {slow_query};
```

**AI 分析 Prompt**：
```
"请分析以下 PostgreSQL 慢查询：
 查询 SQL：{sql}
 执行计划：{explain_json}
 平均耗时：{mean_time}ms，调用次数：{calls}/天

 请给出：
 1. 性能瓶颈（顺序扫描/索引失效/内存不足/锁等待）
 2. 具体优化建议（索引创建 SQL / 查询改写 / 参数调整）
 3. 预期优化效果"
```

**自动化触发**：Prometheus 告警 pg_slow_query_count > 10/min 触发；每日定时推送 TOP 5 慢查询日报  
**前置条件**：pg_stat_statements 扩展已启用  
**实施周期**：3-5 天  
**ROI 估算**：慢查询分析时间从 1-4 小时减少到 15 分钟

---

### 机会2：Kafka 消息堆积智能诊断

**当前状态**：Kafka Consumer Group 堆积时，需手动排查消费者状态→消费速率→业务代码，耗时 2-6 小时。  
**目标状态**：堆积告警触发后，AI 自动给出根因分类和处置建议。

**方案设计**：
```bash
# 自动采集 Consumer Group 状态
kafka-consumer-groups.sh --describe --group {group} \
  --bootstrap-server {broker}
```

**AI 根因分类**：
- **消费者宕机/重平衡**：检查 Pod 状态，建议查看 Rebalance 日志
- **消费速率下降**：分析是否有数据库慢查询或外部接口超时
- **生产突增**：正常业务高峰 or 异常消息风暴，建议限流措施
- **分区分配不均**：建议触发 Rebalance 或增加 Consumer 实例

**工具栈**：Kafka CLI + Prometheus + Claude API + 飞书 Webhook  
**前置条件**：Kafka lag/offset/consumer 健康指标已接入 Prometheus  
**实施周期**：1 周  
**ROI 估算**：Kafka 堆积排查从 2-6 小时减少到 20-30 分钟

---

### 机会3：中间件参数 AI 推荐

**方案设计（示例 Prompt 模板）**：
```
PostgreSQL 调优：
  "当前配置：shared_buffers: 4GB（总内存 64GB），work_mem: 64MB
   问题：读多写少场景下查询偶发慢，cache hit rate 仅 85%
   数据量：500GB，日活连接：200
   请推荐参数调整方案并说明原因"

Redis 调优：
  "当前配置：maxmemory: 8GB，eviction: allkeys-lru
   问题：高峰期有大量 key 被驱逐，命中率下降到 75%
   请分析并给出优化建议"

Kafka 调优：
  "目标：高吞吐量场景（日消息量 5000万条）
   当前 batch.size: 16KB，linger.ms: 0
   请推荐 producer 端参数优化"
```

**工具栈**：Claude（直接对话，无需额外集成）  
**前置条件**：整理各中间件当前配置文档  
**实施周期**：立即可用（建立 Prompt 模板即可）  
**ROI 估算**：调优时间从 1-3 人天减少到 0.5 天

---

### 机会4：容量趋势预测

**方案设计**：
```promql
# PostgreSQL 存储增长趋势（预测 30 天后大小）
predict_linear(pg_database_size_bytes[30d], 30*24*3600)

# Redis 内存使用趋势
predict_linear(redis_memory_used_bytes[7d], 7*24*3600)

# Kafka Topic 磁盘使用
predict_linear(kafka_log_log_size[30d], 30*24*3600)
```

**AI 月度容量报告示例**：
```
"当前 PostgreSQL 存储 480GB（总容量 600GB），
 过去 30 天增长率 15GB/月，预计 8 周后达到 90% 告警阈值。
 建议：第 6 周前扩容至 1TB，或审查历史数据归档策略"
```

**工具栈**：Prometheus（predict_linear）+ Claude API  
**前置条件**：Prometheus 各中间件指标保留 ≥ 30 天历史数据  
**实施周期**：1 周  
**ROI 估算**：从被动扩容变为主动规划，避免因容量问题导致的紧急处置

---

## 四、实施路径

### Phase 0（第 1-2 周）：高频痛点优先解决

| 任务 | 具体行动 | 验收标准 | Owner |
|------|---------|---------|-------|
| PostgreSQL 慢查询分析试跑 | 取最近 10 条慢查询，Claude 分析，人工验证建议质量 | 分析准确率 > 80%，建议可执行 | 运维/DBA |
| 参数调优 Prompt 模板 | 为 PostgreSQL/Redis/Kafka 各建 1 份标准调优提问模板 | 下次调优直接使用模板，节省 50% 时间 | 运维 |

### Phase 1（第 3-4 周）：自动化诊断接入

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 慢查询自动分析 | pg_stat_statements 定时采集 → Claude 分析 → 飞书日报 | 每天自动推送 TOP 5 慢查询分析 | 运维 | pg_stat_statements 已启用 |
| Kafka 堆积诊断 | 告警触发 → 状态采集 → Claude 诊断 → 飞书告警 | Lag 告警后 5 分钟内收到诊断结果 | 运维 | Kafka 指标已入 Prometheus |

### Phase 2（第 5-8 周）：容量预测与一致性检查

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 容量趋势月报 | predict_linear + Claude 生成月度容量预测报告 | 月报自动生成，提前识别 ≥ 1 个容量风险 | 运维 | Prometheus 历史数据 ≥ 30 天 |
| 跨环境配置 Diff | 脚本自动 diff prod/pre/dev 中间件配置，LLM 标注差异影响 | 每周自动生成配置差异报告 | 运维 | 三环境配置版本化存储 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| Claude API（慢查询+堆积+容量报告）| ~¥200-400 | 约 5-8 人天/月 | 极高 |
| 运维脚本开发 | 一次性 2-3 人天 | 长期持续受益 | 高 |
| **合计** | **~¥200-400/月** | **约 6-10 人天/月** | **约 1:15** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| AI 参数建议不适合具体业务场景 | 参数调整后性能下降 | 调优建议必须在 pre 环境验证后才执行 prod 变更 |
| 慢查询分析 SQL 泄露敏感字段名 | 数据安全风险 | SQL 中替换实际值为占位符后再发送给 AI |
| Kafka 诊断脚本执行权限过高 | 误操作 Kafka | 脚本只读权限，禁止执行任何修改操作 |
| predict_linear 预测不准（数据不够）| 容量预警误报 | 数据 < 30 天时标注为"数据不足，仅供参考" |
