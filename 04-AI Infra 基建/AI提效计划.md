# AI 提效计划 - AI Infra 基建

> 用 AI 工具提升 AI 基础设施的运维效率：GPU 利用率监控与告警、推理参数自动调优、部署流程自动化、故障预测。目标：GPU 平均利用率从当前 ~30% 提升到 >55%，模型部署时间从 2 小时减少到 30 分钟。

---

## 一、效率基线（现状）

| 环节 | 当前耗时（估算）| 参与人 | 主要痛点 |
|------|--------------|--------|---------|
| GPU 利用率排查 | 1-2 小时/次 | AI Infra 工程师 | 无统一监控，手动 ssh 到节点查 nvidia-smi |
| vLLM 参数调优 | 1-3 天/次 | AI Infra | 依赖经验试参，max_num_batched_tokens 等参数摸索 |
| 模型部署 | 2-4 小时/次 | AI Infra | 手动步骤多：下载→转换→加载→验证→更新路由 |
| 宿主机裸进程识别 | 0.5-1 小时/次 | 运维 | 无自动化工具，手动排查 cgroup 归属 |
| GPU 驱动版本兼容问题排查 | 数小时-天级 | AI Infra + 运维 | 驱动版本分散（535/550/570/580），知识分散 |

---

## 二、AI 工具全景

| 工具/能力 | 适用场景 | 使用状态 | 接入难度 | 月费用参考 |
|----------|---------|---------|---------|----------|
| **DCGM Exporter + Prometheus** | GPU 指标采集（SM利用率/显存/温度/错误）| 🟡 规划中 | 中（helm部署）| 开源免费 |
| **Claude API** | vLLM 配置辅助、故障根因分析 | 🟡 个人使用 | 低 | ~¥200-400 |
| **Locust / k6** | 推理服务压测 + 参数效果验证 | ❌ 未使用 | 中 | 开源免费 |
| **MLflow** | 模型版本管理 + 部署追踪 | ❌ 规划中 | 中 | 开源免费 |
| **Grafana Alerting** | GPU 空跑/OOM风险/驱动异常告警 | 🟡 部分 | 低（已有 Grafana）| 已有 |

---

## 三、高价值机会点详细方案

### 机会1：GPU 全链路可观测 + 智能告警

**当前状态**：GPU 监控靠人工 ssh，没有统一指标，告警覆盖率为零。  
**目标状态**：DCGM Exporter 采集全量 GPU 指标，关键异常 1 分钟内告警。

**方案设计**：
```
部署路径：
  helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
    --namespace monitoring \
    --set serviceMonitor.enabled=true

Grafana Dashboard：
  - GPU 利用率总览（Dashboard ID: 12239）
  - 按 Pod/模型的显存占用归因
  - 宿主机裸进程检测（通过 cgroup 判断）

关键告警规则：
  - GPU SM 利用率 < 5% 持续 2h → 疑似空跑，通知 AI Infra
  - GPU 显存使用率 > 90% 持续 10min → OOM 风险
  - GPU 温度 > 85°C → 散热告警
  - DCGM_FI_DEV_ECC_SBE_VOL_TOTAL 持续增长 → GPU 硬件异常

AI 增强（告警触发时自动生成诊断摘要）：
  "L20 节点 iz2zeh... GPU 0/1 SM 利用率持续 3h < 5%，
   当前运行 Pod：vllm-qwen-7b，建议检查宿主机裸进程是否抢占资源"
```

**工具栈**：DCGM Exporter + Prometheus + Grafana + Claude API  
**前置条件**：Prometheus + Grafana 已部署；NVIDIA 驱动 ≥ 520  
**实施周期**：3-5 天  
**ROI 估算**：GPU 空跑从被动发现变为主动告警，节省每月 4-8 小时排查时间

---

### 机会2：vLLM 推理参数 AI 辅助调优

**当前状态**：vLLM 参数靠工程师经验试验，每次 1-3 天。  
**目标状态**：输入模型特性和硬件配置，AI 给出推荐参数及理由，结合压测迭代。

**方案设计**：
```
步骤1：建立参数调优知识库
  整理已验证的 vLLM 配置记录，包含：
  - 模型名称 + GPU 型号 + 参数组合 + 吞吐量/延迟结果

步骤2：AI 参数推荐 Prompt
  "我有以下硬件和模型配置，请推荐 vLLM 启动参数：
   - 模型：Qwen-72B-Instruct-AWQ
   - GPU：NVIDIA L20 × 8（48GB/卡）
   - 典型请求：平均 512 input tokens + 256 output tokens
   - 并发要求：QPS ≥ 10
   请给出推荐的：tensor_parallel_size, max_num_batched_tokens,
   max_model_len, gpu_memory_utilization，以及选择理由"

步骤3：Locust 压测验证
  from locust import HttpUser, task
  class VLLMUser(HttpUser):
      @task
      def chat(self):
          self.client.post("/v1/chat/completions", json={...})

步骤4：AI 分析压测结果，给出调整建议
  "当前配置下 P99 延迟 3.2s，吞吐量 8 QPS。
   建议将 max_num_batched_tokens 从 4096 提升到 8192，
   预期可将吞吐量提升到 12 QPS，显存占用增加约 15%"
```

**工具栈**：Claude API + Locust + Grafana  
**前置条件**：DCGM 指标已采集；有基础压测脚本  
**实施周期**：1 周（含压测框架搭建）  
**ROI 估算**：参数调优时间从 1-3 天减少到 0.5 天

---

### 机会3：模型部署流程自动化

**当前状态**：部署新模型需人工执行多步骤，平均 2-4 小时，步骤多易出错。  
**目标状态**：提交部署 MR，流水线自动完成从上传到路由更新的全流程。

**方案设计**：
```
GitLab CI 模型部署流水线：

  阶段1 - 上传与校验：
    - 计算模型文件 SHA256 校验
    - 上传到 MinIO model-registry/${model_name}/${version}/
    - 记录到 MLflow Model Registry（版本化管理）

  阶段2 - 部署：
    - 更新 K8s Deployment 模型路径环境变量
    - 滚动更新，监控 Pod Ready 状态
    - 等待 vLLM 健康检查通过（/health endpoint）

  阶段3 - 自动验证：
    curl -X POST http://vllm-service/v1/chat/completions \
      -d '{"model": "${MODEL_NAME}", "messages": [{"role": "user",
           "content": "你好，请用一句话介绍自己"}]}'
    # 断言：响应时间 < 5s，content 非空

  阶段4 - 路由更新：
    - 更新 Nginx/Ingress 路由规则
    - 旧版本保留 24h 作为回滚备份

  失败处理：
    - 任一阶段失败 → 自动回滚到上一版本
    - 飞书通知部署结果（成功/失败 + 耗时）
```

**工具栈**：GitLab CI + Python + K8s API + MLflow + MinIO  
**前置条件**：MLflow 已部署；MinIO 模型仓库目录规范已定义  
**实施周期**：2-3 周  
**ROI 估算**：部署时间从 2-4 小时减少到 20-30 分钟（流水线自动执行）

---

### 机会4：GPU 宿主机裸进程自动检测

**目标状态**：每小时自动扫描并告警，发现宿主机裸进程立即通知负责人。

```bash
#!/bin/bash
# 每小时 cron 执行

for node in iz2zehh4uj8wuh64pe836tz iz2ze8fusva2xt3sjsi0ywz; do
  BARE_PROCS=$(ssh $node "
    nvidia-smi --query-compute-apps=pid,used_memory,process_name \
      --format=csv,noheader | while IFS=, read pid mem name; do
        pid=\$(echo \$pid | tr -d ' ')
        if ! cat /proc/\$pid/cgroup 2>/dev/null | grep -q kubepods; then
          echo \"[宿主机进程] PID:\$pid MEM:\$mem NAME:\$name\"
        fi
      done
  ")
  if [ -n "$BARE_PROCS" ]; then
    curl -X POST "$FEISHU_WEBHOOK" \
      -d "{\"text\":\"⚠️ GPU节点 $node 发现宿主机裸进程：\n$BARE_PROCS\"}"
  fi
done
```

**前置条件**：无  
**实施周期**：1-2 天  
**ROI 估算**：宿主机裸进程从周级发现变为小时级告警，消除 GPU 资源黑洞

---

## 四、实施路径

### Phase 0（第 1-2 周）：监控与告警建立

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| DCGM Exporter 部署 | helm install 到 monitoring 命名空间，接入 Prometheus | Grafana 可查看 GPU SM/显存/温度指标 | AI Infra | Prometheus + Grafana 就绪 |
| 宿主机裸进程检测 | 部署检测脚本 + 飞书告警 | 发现裸进程 1h 内告警 | AI Infra | - |
| GPU 关键告警规则 | 空跑/OOM风险/温度 3 类告警 | 告警规则生效，测试触发正确 | AI Infra | DCGM 指标采集 |

### Phase 1（第 3-4 周）：调优与部署效率

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| vLLM 压测框架 | Locust 脚本覆盖核心接口 | 可输出 QPS/P50/P99 指标 | AI Infra | - |
| AI 调优 Prompt 模板 | 建立标准化 vLLM 调参提问模板 | 下次调参使用模板，时间 < 1 天 | AI Infra | - |
| 部署脚本化 | 将现有手动步骤写成 Shell/Python 脚本 | 部署时间 < 1 小时 | AI Infra | MinIO 已有模型存储 |

### Phase 2（第 5-8 周）：流水线与自动化

| 任务 | 具体行动 | 验收标准 | Owner | 前置条件 |
|------|---------|---------|-------|---------|
| 模型部署 CI 化 | GitLab CI 实现自动部署+验证+告警 | 部署时间 < 30 分钟，失败自动回滚 | AI Infra + DevOps | GitLab CI + MLflow 部署 |
| GPU 利用率优化回顾 | 基于 1 个月 DCGM 数据，分析利用率提升空间 | GPU 平均 SM 利用率对比基线提升 ≥ 10% | AI Infra | DCGM 运行 ≥ 1 个月 |

---

## 五、成本与收益

| 项目 | 月度成本 | 节省人力（估算）| ROI |
|------|---------|--------------|-----|
| DCGM Exporter（开源）| 运维 0.5 人天/月 | 排查时间节省 4-8h/月 | 中 |
| Claude API（辅助调优+故障分析）| ~¥200-400 | 约 3-5 人天/月 | 高 |
| 模型部署自动化（开发成本）| 一次性 3-5 人天 | 每次部署节省 2h | 高（长期）|
| **合计（持续）** | **~¥300-500/月** | **约 5-8 人天/月** | **约 1:10** |

---

## 六、风险与回退

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| DCGM Exporter 与驱动版本不兼容 | 指标采集失败 | 参考驱动版本兼容矩阵；不同驱动节点用不同版本 DCGM |
| 模型部署自动化回滚失败 | 服务中断 | 保留旧版 Deployment YAML；紧急时手动 kubectl apply 回滚 |
| AI 调优建议与实际环境不符 | 性能下降 | 调参变更必须先在 pre 环境验证，压测通过才上 prod |
| 宿主机裸进程告警风暴 | 警觉疲劳 | 相同进程 1h 内不重复发送；发现后 24h 内跟进处置 |
