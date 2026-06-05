# 问学 2.0 基础设施治理全面升级方案

> 基于现有基础（K8s + Docker + GitLab CI + Nginx + 飞书/Jira），从"可用"升级为"全栈可控、可观测、可审计、可商业化"的治理体系。

---

## 一、治理基线评估：现状 vs 目标

### 1.1 现状基线（已有基础）

| 维度 | 现状 | 成熟度 |
|---|---|---|
| **容器编排** | K8s 集群运行中，大部分服务容器化 | 中等 |
| **CI/CD** | GitLab CI 跑通（lint → test → build → deploy），手工部署生产 | 中等 |
| **网关** | Nginx + Ingress-Nginx，基础路由和负载均衡 | 中等 |
| **协同** | 飞书（沟通/审批）+ Jira（缺陷跟踪），工具已有但未标准化 | 中等 |
| **部署形态** | K8s + Docker + 二进制服务（三种形态并行） | 偏低 |
| **监控** | 大概率"出问题看日志"的被动模式 | 薄弱 |
| **安全** | 无 CI 扫描、无准入策略、运行时无检测 | 缺失 |
| **SRE** | 无 SLO/SLI、无 On-Call、无变更分级、无复盘机制 | 缺失 |
| **AI 专项** | 无 Token 计量、无推理延迟监控、无 GPU 硬件监控 | 缺失 |
| **成本** | 无成本归因、无预算告警、无容量预测 | 缺失 |
| **License** | 无商业化授权体系 | 缺失 |

### 1.2 目标基线（治理完成后）

| 维度 | 目标状态 | 成熟度 |
|---|---|---|
| **容器编排** | K8s 为唯一编排平台，二进制服务全部迁移或纳管 | 高 |
| **CI/CD** | GitLab CI + Harbor + ArgoCD，安全门禁 + 多环境 + 灰度发布 + 制品可追溯 | 高 |
| **网关** | APISIX（南北向）+ Istio（东西向），统一流量治理、鉴权、限流 | 高 |
| **协同** | 飞书 + Jira 深度集成，变更审批、缺陷闭环、On-Call 排班全自动化 | 高 |
| **监控** | Prometheus + Grafana + Loki + Tempo + Sentry，指标/日志/追踪/异常全覆盖 | 高 |
| **安全** | Trivy + Kyverno + Falco + Vault，左移+准入+运行时+密钥全链路 | 高 |
| **SRE** | SLO/SLI 体系、On-Call 轮值、变更分级、故障复盘、混沌工程 | 高 |
| **AI 专项** | Token 精确计量、推理延迟拆解、GPU 硬件监控、模型质量追踪 | 高 |
| **成本** | Kubecost + Karpenter，成本归因、预算告警、资源优化、容量预测 | 高 |
| **License** | 自建 License API + KMS/Vault，授权/激活/续期/吊销全链路 | 高 |

### 1.3 核心差距

| 差距 | 影响 | 严重程度 |
|---|---|---|
| 二进制服务未纳入统一治理 | 最大不可控因素，故障难发现、难定位、难恢复 | P0 |
| 无统一可观测性 | "黑盒"运行，排障靠猜，无法量化系统健康度 | P0 |
| 无安全门禁 | 漏洞可能随发布流入生产，无准入策略防误配置 | P0 |
| 无 SRE 流程 | 变更风险不可控，故障无响应机制，无复盘改进 | P0 |
| 无 AI 专项监控 | Token 用量不透明，推理性能不可见，GPU 故障无预警 | P1 |
| 无成本治理 | 资源浪费不可知，预算超支后知后觉 | P1 |
| 无 License 体系 | 商业化缺乏技术支撑 | P1 |

---

## 二、整体架构升级路径

### 2.1 现状架构

```
用户
  ↓
Nginx + Ingress-Nginx（基础路由）
  ↓
K8s 集群（部分服务）
Docker 容器（部分服务）
二进制进程（部分服务）  ← 治理盲区
  ↓
PostgreSQL / Redis / Kafka（中间件）

CI/CD：GitLab CI → 构建镜像 → kubectl set image
监控：无 / 日志文件分散
安全：无
SRE：无
协同：飞书 + Jira（工具已有，流程未标准化）
```

### 2.2 目标架构

```
用户
  ↓
APISIX（南北向网关：鉴权、限流、路由、灰度）
  ↓
Istio Service Mesh（东西向：mTLS、熔断、重试、流量镜像）
  ↓
K8s 集群（全部服务，二进制已迁移或纳管）
  ├── AI Infra：vLLM + Ray + MLflow
  ├── 业务服务：各微服务（统一注入 Sidecar）
  ├── 中间件：Redis + Kafka + PostgreSQL（K8s 内运行）
  └── 可观测性：Prometheus + Grafana + Loki + Tempo + Sentry
  ↓
存储：云厂商 CSI + OSS/S3（模型、日志、备份）

CI/CD：GitLab CI → Harbor（镜像扫描+签名） → ArgoCD（GitOps 部署）
监控：统一可观测性平台（Metrics + Logs + Traces + Exceptions）
安全：Trivy（CI扫描） + Kyverno（准入策略） + Falco（运行时） + Vault（密钥）
SRE：SLO Dashboard + On-Call + 变更管理 + 故障复盘
协同：飞书（IM/审批/日历） + Jira（缺陷/变更/复盘 Action Items）
成本：Kubecost + Karpenter + Cloud Custodian
商业化：自建 License API + KMS/Vault + 审计链路
```

---

## 三、13 个 TODO 的全面升级方案

### TODO 1：私有云 / K8s 运维（升级方案）

#### 现状
- K8s 集群已运行，但命名空间、资源配额、网络策略可能未标准化
- 二进制服务仍在 K8s 外运行

#### 升级措施

**1. 集群标准化治理**

```bash
# 命名空间标准化（强制 ResourceQuota + LimitRange）
# 生产环境命名空间清单：
#   - wenxue-prod（生产业务）
#   - wenxue-staging（预发环境）
#   - wenxue-dev（开发测试）
#   - ai-infra（AI 推理/训练）
#   - middleware（Redis/Kafka/PostgreSQL）
#   - observability（Prometheus/Grafana/Loki）
#   - cicd（ArgoCD/Harbor）
#   - security（Kyverno/Falco/Vault）
```

**2. 二进制服务迁移计划**

| 阶段 | 时间 | 动作 | 输出 |
|---|---|---|---|
| 阶段 1：纳管 | Week 1-2 | 二进制服务接入统一监控（OTel Collector + Blackbox Exporter） | 所有服务在 Grafana 可见 |
| 阶段 2：容器化 | Week 3-6 | 高优先级二进制服务编写 Dockerfile，接入 CI/CD | 核心业务全部容器化 |
| 阶段 3：上 K8s | Week 7-10 | 容器化服务部署到 K8s，配置 HPA、资源限制 | K8s 成为唯一编排平台 |
| 阶段 4：下线 | Week 11-12 | 遗留二进制服务评估后下线或保留纳管 | 消除混合部署 |

**3. 存储治理**

- 块存储：云厂商 CSI（阿里云 NAS CSI / AWS EBS CSI）
- 对象存储：OSS/S3（模型文件、数据集、日志冷存储）
- 共享存储：NAS（ReadWriteMany 场景）
- 备份策略：Velero 集群备份 + etcd 每日备份

**4. 多集群管理（远期）**

- 主集群（生产）+ 灾备集群（异地）
- ArgoCD 多集群管理
- 跨集群网络（Cilium Cluster Mesh）

---

### TODO 2：AI Infra 基建（升级方案）

#### 现状
- AI 服务可能在 K8s 上运行，但无统一管理

#### 升级措施

**1. 推理引擎标准化**

| 场景 | 选型 | 理由 |
|---|---|---|
| 在线推理（高吞吐） | vLLM | PagedAttention 提升 GPU 利用率 |
| 离线推理 / 批处理 | Ray Serve | 分布式任务调度 |
| 模型实验管理 | MLflow | 实验追踪、模型注册、版本管理 |

**2. GPU 资源治理**

```yaml
# GPU 节点专用配置
# Node Labels + Taints 隔离 GPU 节点
# 非 GPU 任务禁止调度到 GPU 节点

# GPU 节点配置：
# - 机型：ecs.gn7i（阿里云）或同类 GPU 实例
# - NVIDIA Device Plugin：Pod 可请求 GPU 资源
# - NVIDIA Container Toolkit：容器内可用 GPU
# - DCGM Exporter：GPU 指标采集
```

**3. 模型生命周期管理**

```
模型训练（Ray） → 模型注册（MLflow） → 模型验证 → 模型部署（ArgoCD）
     ↑                                               ↓
  实验追踪                                     线上监控（延迟/Token/错误率）
     ↑                                               ↓
  数据版本（DVC）                             模型回滚（ArgoCD Rollback）
```

**4. 推理服务部署规范**

```yaml
# 推理服务 Deployment 模板（带 GPU 资源请求）
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-inference-vllm
spec:
  template:
    spec:
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        resources:
          limits:
            nvidia.com/gpu: "1"
            memory: "32Gi"
          requests:
            nvidia.com/gpu: "1"
            memory: "16Gi"
        env:
        - name: MODEL_NAME
          value: "Qwen2-7B-Instruct"
        ports:
        - containerPort: 8000
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
```

---

### TODO 3：可观测性体系（升级方案）

#### 现状
- 大概率无统一监控，或仅有基础监控

#### 升级措施

**1. 三大支柱全覆盖**

| 支柱 | 工具 | 用途 |
|---|---|---|
| Metrics（指标） | Prometheus + VictoriaMetrics（长期存储） | 系统/应用/业务指标 |
| Logs（日志） | Loki + Promtail | 日志聚合和查询 |
| Traces（链路追踪） | Tempo + OpenTelemetry SDK | 跨服务调用链 |
| Exceptions（异常） | Sentry | 代码级异常聚合 |

**2. 部署架构**

```
应用 / K8s / 中间件 / 二进制服务
       │
       ├── Metrics ──→ Prometheus ──→ Grafana
       ├── Logs ────→ Promtail → Loki ──→ Grafana
       ├── Traces ──→ OTel SDK → OTel Collector → Tempo ──→ Grafana
       └── Exceptions ──→ Sentry SDK ──→ Sentry
```

**3. 指标分层体系**

```
L1 业务指标   — 活跃用户数、API 成功率、AI 问答完成率、Token 消耗量
L2 应用指标   — QPS、延迟、错误率（RED 方法）
L3 基础设施   — CPU/内存/磁盘/网络、Pod 状态、节点健康
L4 中间件     — Redis 命中率、Kafka 积压、DB 连接数、慢查询
L5 AI 专项    — GPU 利用率、TTFT、TPOT、模型加载时间
```

**4. 统一 Dashboard 规划**

| Dashboard | 内容 | 优先级 |
|---|---|---|
| 全局健康度 | 核心业务指标 + 系统健康度 + 告警汇总 | P0 |
| K8s 集群 | 节点/Pod/容器资源 + API Server 健康 | P0 |
| 应用性能 | 各服务的 RED 指标（按服务分组） | P0 |
| AI 服务专项 | GPU 利用率、推理延迟、Token 用量 | P1 |
| 中间件 | Redis/Kafka/DB 运行状态 | P1 |
| 成本看板 | Namespace/服务成本归因、预算趋势 | P2 |

**5. 告警体系**

```
告警触发 → Alertmanager
         ├── P0: 电话 + 短信 + 飞书 → 5分钟无响应升级
         ├── P1: 短信 + 飞书 → 30分钟无响应升级
         ├── P2: 飞书 → 工作时间处理
         └── P3: 邮件/工单 → 下次迭代处理
```

**核心告警规则（初始集）：**

| 告警 | 条件 | 级别 |
|---|---|---|
| 服务不可达 | up == 0 for 1m | P0 |
| 高错误率 | 5xx rate > 5% for 2m | P0 |
| 高延迟 | P99 latency > 2s for 3m | P1 |
| 节点磁盘满 | disk usage > 85% | P1 |
| Pod 频繁重启 | restart count > 3 in 10m | P1 |
| GPU 温度过高 | temperature > 85°C | P1 |
| 推理队列积压 | queue length > 100 | P1 |

---

### TODO 4：AI 服务专项监控（升级方案）

#### 现状
- 无 Token 计量、无推理延迟监控、无 GPU 硬件监控

#### 升级措施

**1. Token 用量统计与计费**

```python
# 推理服务中记录 Token 用量（中间件方式）
# 方式 A：API Gateway 层拦截记录（推荐，对推理服务无侵入）
# 方式 B：推理服务暴露 /metrics 端点，Prometheus 采集

# 数据模型（ClickHouse / PostgreSQL）
class TokenUsage:
    request_id: str
    user_id: str
    app_id: str
    model: str
    input_tokens: int
    output_tokens: int
    latency_ms: int
    timestamp: datetime
    status: str  # success / failure / timeout
```

**计费模型：**

| 模式 | 适用 | 实现方式 |
|---|---|---|
| 按量计费 | SaaS 多租户 | Token 数 × 单价，实时扣费 |
| 套餐包 | 企业客户 | 月度固定额度 + 超量计费 |
| 内部核算 | 内部团队 | 按部门统计成本，不出账 |

**2. 推理延迟全链路监控**

| 指标 | 含义 | 目标 | 告警 |
|---|---|---|---|
| TTFT (Time to First Token) | 首 Token 返回时间 | < 500ms | P99 > 2s → P1 |
| TPOT (Time Per Output Token) | 每 Token 生成时间 | < 50ms | P99 > 100ms → P1 |
| E2E Latency | 端到端总延迟 | 根据场景 | P99 > 5s → P1 |
| Queue Wait Time | 请求排队时间 | < 100ms | > 500ms → P2 |

**3. GPU 硬件监控（新增进程级可选方案）**

```bash
# 基础方案：部署 DCGM Exporter（卡级指标）
helm install dcgm-exporter nvidia/dcgm-exporter --namespace observability

# 关键指标：
# - GPU Utilization（利用率）
# - GPU Memory Used（显存使用）
# - GPU Temperature（温度）
# - GPU Power Usage（功耗）
# - ECC Errors（显存纠错错误）
# - XID Errors（驱动错误）
```

**GPU 进程级监控可选方案：**

| 方案 | 监控粒度 | 适用场景 | 部署复杂度 | 推荐度 |
|---|---|---|---|---|
| **A. DCGM Exporter（默认）** | 卡级 + Pod 级（K8s） | K8s 上跑 AI 任务，需要 Pod 级别 GPU 监控 | 低 | ⭐⭐⭐⭐⭐ |
| **B. 自定义 GPU Process Exporter** | PID 级 + 用户级 + 命令级 | 需要精确到"谁跑了多少 GPU"，做成本归因 | 中 | ⭐⭐⭐⭐ |
| **C. nvidia-smi 脚本** | PID 级（临时查看） | 快速验证、排障、不接入 Prometheus | 极低 | ⭐⭐⭐ |

**方案 A：DCGM Exporter（推荐，K8s 场景）**

```bash
# 安装 GPU Operator（含 DCGM Exporter）
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --set dcgmExporter.enabled=true

# 关键指标：
# DCGM_FI_DEV_GPU_UTIL              -- GPU 利用率
# DCGM_FI_DEV_FB_USED               -- 显存使用
# DCGM_FI_DEV_GPU_TEMP              -- GPU 温度
# DCGM_FI_DEV_POWER_USAGE           -- GPU 功耗

# K8s Pod 级别（需要 GPU Operator）：
# DCGM_FI_DEV_GPU_UTIL{pod="llm-inference-abc123", namespace="ai-infra"}
```

**方案 B：自定义 GPU Process Exporter（进程级精确监控）**

```bash
# 原理：通过 nvidia-smi 获取 PID/用户/命令/显存占用，暴露为 Prometheus 指标
# 部署方式：DaemonSet 运行在每个 GPU 节点上

# 关键指标：
# gpu_process_memory_mib{gpu="0", pid="12345", user="alice", command="python"}
# gpu_process_utilization_percent{gpu="0", pid="12345", user="alice"}
# gpu_process_count{gpu="0"}

# PromQL 查询示例：
# sum by (user) (gpu_process_memory_mib)          -- 每个用户占用多少 GPU 显存
# topk(10, gpu_process_memory_mib)                -- Top 10 GPU 进程
# gpu_process_count                                -- 每个 GPU 的进程数
```

**方案 C：nvidia-smi 脚本（快速验证）**

```bash
# 查看 GPU 上的进程（临时命令）
nvidia-smi

# 持续监控每个进程的 GPU 使用
nvidia-smi pmon -s um -d 1

# 查看进程详细信息
nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv
```

**GPU 生命周期管理：**

```
健康 → 降频/降温预警 → 故障（自动摘除 + 迁移负载）→ 维修/替换 → 重新上线
```

---

### TODO 5：CI/CD 基座（升级方案）

#### 现状
- GitLab CI 已跑通（lint → test → build → deploy）
- 生产部署手工触发
- 无镜像扫描、无多环境、无灰度

#### 升级措施

**1. 流水线增强：新增 Scan 阶段**

```yaml
stages:
  - lint
  - test
  - build
  - scan          # 新增
  - deploy-staging
  - deploy-prod

# 镜像漏洞扫描
scan-image:
  stage: scan
  image: aquasec/trivy:latest
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE_NAME:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
    - if: $CI_COMMIT_BRANCH == "main"

# 依赖漏洞扫描
scan-deps:
  stage: scan
  image: python:3.11-slim
  script:
    - pip install safety bandit
    - safety check -r requirements.txt
    - bandit -r . -f json -o bandit-report.json
```

**2. 引入 Harbor 作为统一制品仓库**

```bash
# 部署 Harbor（Helm）
helm install harbor harbor/harbor --namespace cicd --create-namespace

# Harbor 能力：
# - 镜像存储和版本管理
# - 镜像漏洞扫描（集成 Trivy）
# - 镜像签名（Cosign/Notary）
# - 镜像复制（多环境同步）
# - 审计日志
```

**3. 引入 ArgoCD 实现 GitOps 部署**

**引入 ArgoCD 的 7 个核心好处：**

| 好处 | 说明 |
|---|---|
| **1. 消除配置漂移** | Git 仓库是"唯一真相"，ArgoCD 持续比对 Git 与线上状态，不一致自动告警或同步，避免"仓库里是 v1.0.0、线上是 v1.0.5"的问题 |
| **2. 一键回滚** | 部署异常时，在 UI 点一下"Rollback"即可回退到上一个版本，无需记忆镜像 Tag |
| **3. 多环境统一管理** | 一个 Git 仓库管理 dev/staging/prod 所有环境配置，避免配置分散在不同地方 |
| **4. 健康度检查 + 自动回滚** | ArgoCD 持续检查 Pod 是否 Ready，部署后 5 分钟不健康可自动回滚 |
| **5. 审计追踪** | 每次同步都有记录（谁点的同步、同步了什么、结果如何），配合 Git 仓库可精确回溯任意时间点的部署状态 |
| **6. 安全隔离** | 开发同学不需要 kubectl 权限，只需要 Git 权限，ArgoCD 用 ServiceAccount 操作 K8s，权限可控 |
| **7. 可视化 + 告警** | UI 实时显示所有应用的部署状态（绿=健康、红=失败），部署失败自动告警（Webhook → 飞书） |

**引入前后对比：**

| 维度 | 引入前（手动 kubectl） | 引入后（ArgoCD） |
|---|---|---|
| **部署操作** | 手动 `kubectl set image` | 自动或点一下按钮 |
| **配置一致性** | 仓库和线上可能不一致 | Git 是"唯一真相" |
| **回滚** | 手动记 Tag，容易搞错 | UI 点一下或 `git revert` |
| **多环境管理** | 分散在不同地方 | 一个 Git 仓库统一管理 |
| **部署状态** | `kubectl get pods` 看 | UI 实时显示健康度 |
| **审计** | CI 日志（易过期） | Git 仓库永久记录 + ArgoCD 审计日志 |
| **权限隔离** | 需要 kubectl 权限 | 只需要 Git 权限 |
| **回滚速度** | 手动执行，几分钟 | 秒级自动回滚 |
| **失败感知** | 需要手动检查 | 自动检测 + 告警 + 可选自动回滚 |

```bash
# 部署 ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD 能力：
# - GitOps 拉模式部署（消除"集群漂移"）
# - 多环境管理（dev/staging/prod）
# - 自动同步 + 手动同步
# - 回滚（Rollback）
# - 应用健康度 Dashboard
```

**部署流程升级：**

```
代码提交 → GitLab CI（lint → test → build → scan）
         → 推送镜像到 Harbor（带签名）
         → ArgoCD 检测到 Git 仓库变更
         → 自动同步到 Dev/Staging
         → 生产部署：人工审批 → ArgoCD 同步到 Prod
```

**4. 引入 AI 代码审查机器人（可选但推荐）**

在 CI 流水线中增加 AI 自动代码审查阶段，提升代码质量，减少人工 Review 负担。

**可选方案对比：**

| 方案 | 费用 | 核心能力 | 推荐度 |
|---|---|---|---|
| **PR-Agent**（推荐） | 免费 + API 费 | 自动 Review + MR 描述 + 问答 | ⭐⭐⭐⭐⭐ |
| **GitLab Duo** | $99/人/月 | 与 GitLab 原生集成 | ⭐⭐⭐ |
| **CodeRabbit** | $15/月 | SaaS，5 分钟接入 | ⭐⭐⭐⭐ |
| **Danger** | 免费 | 规则驱动（非 AI） | ⭐⭐ |

**推荐方案：PR-Agent（开源免费）**

```yaml
# .gitlab-ci.yml 中增加 AI Review 阶段
stages:
  - lint
  - ai-review     # 新增 AI 代码审查
  - test
  - build
  - scan
  - deploy

# AI 代码审查 Job
ai-code-review:
  stage: ai-review
  image: codiumai/pr-agent:latest
  variables:
    # GitLab 配置
    GITLAB_TOKEN: $CI_JOB_TOKEN
    GITLAB_URL: $CI_SERVER_URL
    
    # AI 提供商（可选 OpenAI / Anthropic / Azure）
    OPENAI_KEY: $OPENAI_API_KEY
    
    # PR-Agent 配置
    PR_REVIEWER.EXTRA_INSTRUCTIONS: "请重点关注安全性和性能问题"
    PR_DESCRIPTION.EXTRA_INSTRUCTIONS: "请用中文生成描述"
  script:
    - |
      python -m pr_agent.cli \
        --url "$CI_MERGE_REQUEST_IID" \
        --pr_url "$CI_MERGE_REQUEST_SOURCE_BRANCH_SHA" \
        review
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  allow_failure: true   # AI 审核失败不阻塞流水线
```

**审查效果示例：**

```markdown
## 🤖 AI 代码审查报告

### [严重] utils/db.py:45 - SQL 注入风险
**问题**：`cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")` 使用 f-string 拼接 SQL
**修复建议**：使用参数化查询

### [警告] services/order.py:78 - N+1 查询
**问题**：循环内查询数据库
**修复建议**：使用 `select_related` 批量查询

### [建议] models/user.py:23 - 缺少类型提示
**问题**：函数参数和返回值缺少类型注解
**修复建议**：添加类型提示
```

**AI 审查的价值：**

| 维度 | 人工 Review | AI Review | 结合使用 |
|---|---|---|---|
| 安全性检查 | 容易遗漏 | 能发现常见漏洞 | AI 初筛 + 人工复核 |
| 代码规范 | 主观 | 客观一致 | AI 自动检查 |
| 性能问题 | 需经验 | 能识别常见模式 | AI 提示 + 人工判断 |
| 架构设计 | 强 | 弱 | 人工负责 |
| 业务逻辑 | 强 | 弱 | 人工负责 |

**注意事项：**
- AI 审查是**辅助工具**，不能替代人工 Review
- `allow_failure: true`，AI 审查失败不阻塞流水线
- 审查结果发布到 MR 评论区，供人工 Reviewer 参考
- 定期 Review AI 审查的有效性，调整审查指令

**5. 多环境 + 灰度发布**

```yaml
# GitLab CI 环境映射
develop 分支 → Dev 环境（自动部署）
release/* 分支 → Staging 环境（自动部署）
main 分支 → Prod 环境（手动审批 + 可选金丝雀）

# 金丝雀发布（ArgoCD + Istio）
# 1. 更新 10% 流量到新版本
# 2. 观察指标（错误率、延迟）
# 3. 指标正常 → 全量发布
# 4. 指标异常 → 自动回滚
```

**5. 制品管理规范**

- **镜像 Tag 策略**：`commit-sha`（唯一）+ `branch-name`（最新）+ `semver`（发布）
- **禁止使用 `latest` Tag 部署生产**
- **镜像签名**：关键镜像用 Cosign 签名，部署时验证
- **清理策略**：保留最近 30 天构建，标记 `keep` 的永久保留

---

### TODO 6：中间件运维（升级方案）

#### 现状
- 中间件可能在 K8s 外运行，或未标准化运维

#### 升级措施

**1. 中间件清单与部署**

| 中间件 | 用途 | 部署建议 |
|---|---|---|
| PostgreSQL | 业务主库 | K8s 内 StatefulSet + PVC + Patroni（高可用） |
| Redis | 缓存 + 会话 | K8s 内 StatefulSet + Redis Sentinel |
| Kafka | 消息队列 | K8s 内 StatefulSet + 3 Broker |
| Elasticsearch | 日志/搜索 | K8s 内 StatefulSet + 3 节点集群 |
| MinIO | 对象存储 | K8s 内 StatefulSet + PVC（S3 兼容） |

**2. 密钥与配置管理（ConfigMap + Secret + Vault）**

**问题背景：**

```
ConfigMap：存非敏感配置（数据库地址、端口、超时时间）
    ↓
Secret：存敏感信息（密码、密钥、Token）
    ↓
Vault：专门管理密钥的外部工具（真正加密 + 动态生成 + 自动轮换）
```

**为什么 K8s Secret 不够安全？**

```bash
# K8s Secret 只是 Base64 编码，任何人都能解码
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d
# → 直接看到明文密码

# Secret 默认以明文形式存到 etcd
# etcd 备份泄露 → 所有 Secret 暴露
```

**三种方案对比：**

| 方案 | 安全性 | 复杂度 | 适用场景 |
|---|---|---|---|
| **ConfigMap + Secret** | 低（Base64 编码） | 低 | 测试环境、非敏感数据 |
| **Secret + etcd 加密** | 中 | 低 | 过渡方案、小团队 |
| **Vault** | 高（真正加密 + 动态 Secret） | 中 | 生产环境、敏感数据 |

**推荐方案：HashiCorp Vault**

Vault 的核心能力：
1. **真正加密存储** — 数据加密后存在 Vault 中
2. **动态 Secret** — 自动给应用生成临时的数据库密码（用完即废）
3. **自动轮换** — 密码到期自动更新
4. **审计** — 谁看了什么 Secret，都有记录
5. **不存 K8s Secret** — 密码只在 Vault 里，K8s 里只有 Vault 的访问地址

**Vault 在 K8s 中的两种用法：**

**用法 A：应用直连 Vault（推荐，最安全）**

```
应用启动时
   ↓
调用 Vault API 获取密码
   ↓
连接数据库
```

**用法 B：Vault Agent Injector（对应用无侵入）**

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    metadata:
      annotations:
        # Vault Agent 自动将 Secret 注入到 Pod
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "my-app"
        vault.hashicorp.com/agent-inject-secret-db-creds: "database/creds/mydb"
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        # 应用从文件 /vault/secrets/db-creds 读取密码
```

**部署 Vault：**

```bash
# Helm 部署 Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault --namespace security --create-namespace

# 启用 K8s 认证
vault auth enable kubernetes
vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert="$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)"
```

**过渡方案：K8s Secret + etcd 加密**

如果暂时不想引入 Vault，可以先启用 etcd 加密：

```bash
# 创建加密配置文件
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: <base64-encoded-32-byte-key>
    - identity: {}
```

**结论：**

| 环境 | 推荐方案 |
|---|---|
| 测试环境 | ConfigMap + Secret（够用） |
| 预发环境 | Secret + etcd 加密（过渡） |
| **生产环境** | **Vault（必须）** |

**3. 备份策略**
  - PostgreSQL：全量每日 + WAL 持续
  - Redis：RDB 每小时 + AOF 持续
  - Kafka：依赖副本策略
- 监控：每个中间件接入 Prometheus Exporter
- 告警：可用性、延迟、积压、磁盘

---

### TODO 7：SRE 稳定性工程（升级方案）

#### 现状
- 无 SLO/SLI、无 On-Call、无变更分级、无复盘机制

#### 升级措施

**1. SLO/SLI 体系**

| 服务 | SLI | SLO |
|---|---|---|
| Web API | 成功率 | ≥ 99.9% |
| Web API | P99 延迟 | ≤ 500ms |
| AI 推理 | 成功率 | ≥ 99.5% |
| AI 推理 | TTFT P99 | ≤ 2s |
| 平台可用性 | 用户可正常访问比例 | ≥ 99.95% |

**Error Budget 策略：**
- 充足 → 可以大胆发布
- 紧张 → 冻结非关键变更
- 耗尽 → 停止发布，直到恢复

**2. On-Call 制度**

```
主 On-Call（5 分钟响应）
    ↑ 升级
备 On-Call（15 分钟响应）
    ↑ 升级
技术负责人（重大故障介入）
```

- **工具**：PagerDuty / Grafana OnCall / 飞书日历（小团队起步）
- **响应 SLA**：P0（5min）/ P1（30min）
- **补偿机制**：夜班/节假日值班给予调休或补贴

**3. 变更管理**

| 级别 | 影响 | 审批 | 例子 |
|---|---|---|---|
| S（标准） | 低风险 | 无需审批 | 配置微调、日志级别修改 |
| N（普通） | 中等风险 | 团队 Lead | 功能发布、中间件升级 |
| H（高危） | 高风险 | 技术负责人 | DB Schema 变更、核心链路改造 |
| E（紧急） | 紧急修复 | 事后补审 | 线上 Hotfix |

**变更规范：**
- 变更窗口：工作日 10:00-16:00
- 冻结期：大促/重要活动期间
- 三板斧：可灰度、可监控、可回滚

**4. 故障复盘（Postmortem）**

- **原则**：Blameless（无指责）
- **时限**：故障恢复后 48 小时内完成
- **输出**：根因分析 + Action Items（录入 Jira 跟踪）
- **模板**：见 `07-sre/README.md`

**5. 混沌工程（进阶）**

- **工具**：Chaos Mesh（K8s 原生）
- **实验场景**：
  - 随机杀死 Pod → 验证自愈能力
  - 模拟网络延迟 → 验证超时处理
  - 模拟 GPU 故障 → 验证自动摘除

---

### TODO 8：研发运营管理支撑（升级方案）

#### 升级措施

**1. 版本管理**

- **语义化版本**：`MAJOR.MINOR.PATCH`
- **分支策略**：GitFlow（main / develop / feature/* / release/* / hotfix/*）
- **Release Notes**：新功能、修复、改进、已知问题、升级注意事项

**2. 介质管理**

```
artifacts/
├── docker/       # Docker 镜像（Harbor）
├── helm/         # Helm Charts（ChartMuseum）
├── scripts/      # 部署/升级脚本
├── docs/         # 版本文档
└── checksum/     # SHA256 校验文件
```

**3. 发布审批工作流（飞书 + Jira）**

```
开发完成 → 代码 Review → 自动化测试通过
         → 填写变更单（Jira）
         → 技术 Lead 审批
         → QA 验证签字
         → 运维确认部署窗口
         → 执行部署（ArgoCD）
         → 线上验证
         → 关闭变更单
```

**4. DORA 指标**

| 指标 | 目标 |
|---|---|
| 部署频率 | 按需，每日多次 |
| 变更前置时间 | < 1 小时 |
| 变更失败率 | < 5% |
| 故障恢复时间 | < 1 小时 |

---

### TODO 9：产品缺陷管理（升级方案）

#### 升级措施

**1. 缺陷分级**

| 等级 | 响应时间 | 修复时间 |
|---|---|---|
| P0 - 致命 | 15 分钟 | 4 小时 |
| P1 - 严重 | 1 小时 | 24 小时 |
| P2 - 一般 | 4 小时 | 当前迭代 |
| P3 - 轻微 | 下个迭代 | 按排期 |

**2. 缺陷生命周期**

```
新建 → 确认 → 分配 → 修复中 → 已修复 → 验证中 → 已关闭
                                          ↓
                                        重新打开
```

**3. 工具选型**

- **主选**：Jira（研发执行）+ 飞书服务台（客户沟通）
- **集成**：Jira 工单 ↔ 飞书通知（Webhook）

---

### TODO 10：License 管理系统（升级方案）

#### 升级措施

**1. 授权模式**

| 模式 | 适用 | 说明 |
|---|---|---|
| 订阅制 | SaaS | 按月/年付费，到期自动失效 |
| 永久授权 | 私有化部署 | 一次性购买，永久使用 |
| 混合模式 | 大型企业 | 基础功能永久 + 高级功能订阅 |

**2. 技术架构**

```
客户端请求 → License API（K8s 内运行）
               ↓
            校验签名（RSA）
               ↓
            查询数据库（PostgreSQL）
               ↓
            返回：有效/无效/已过期
               ↓
            记录审计日志（ClickHouse）
```

**3. 核心功能**

- **License 生成**：基于用户 + 套餐 + 有效期生成签名 License
- **客户端验证**：应用启动时校验 License（本地 + 联网双校验）
- **管理后台**：创建/续期/吊销 License
- **到期提醒**：到期前 30 天自动邮件提醒
- **防共享**：设备指纹绑定

**4. 密钥安全**

- 私钥存储在 Vault/KMS
- 禁止明文密钥进入代码仓库
- 定期轮换签名密钥

---

### TODO 11：工具参考与选型对比

#### 升级措施

**统一口径选型表（最终定版）**

| 领域 | 主选 | 备选 | 同类工具 |
|---|---|---|---|
| CI/CD | GitLab CI + Harbor + ArgoCD | Jenkins | GitHub Actions, Tekton |
| 观测 | Prometheus + Grafana + Loki + Tempo + Sentry | Zabbix, Jaeger | ELK, Datadog |
| 流量 | APISIX + Istio | Kong + Linkerd | Nginx, Traefik |
| 运维入口 | JumpServer | Teleport | 云堡垒机 |
| 安全 | Trivy + Kyverno + Falco + Vault | OPA Gatekeeper | Snyk, Sysdig |
| AI | vLLM + Ray + MLflow | TGI, Triton | KubeFlow, W&B |
| 协同 | 飞书 + Jira | Linear, GitLab Issues | TAPD, Zendesk |
| 成本 | Kubecost + Karpenter | OpenCost | CloudHealth |
| 商业化 | Vault + 自建 License API | Keygen, Cryptolens | SLM 商业平台 |

---

### TODO 12：安全与合规（升级方案）

#### 升级措施

**1. 供应链安全**

- CI 阶段：Trivy 镜像漏洞扫描（阻断 HIGH/CRITICAL）
- 依赖扫描：Safety（Python）、Snyk（多语言）
- 镜像签名：Cosign（部署时验证签名）

**2. 密钥治理**

- Secret 统一由 Vault/KMS 管理
- 禁止明文密钥进入代码仓库
- 关键凭据定期轮换

**3. K8s 准入策略（Kyverno）**

- 禁止特权容器
- 禁止 root 用户运行
- 强制 resources.request/limit
- 镜像仓库白名单

**4. 运行时安全（Falco）**

- 异常系统调用检测
- 可疑进程行为告警
- 高风险操作审计

**5. 合规审计**

- 资产清单（CMDB）
- 日志留存（操作日志、审计日志）
- 权限审计（定期 review RBAC）
- 变更审计（所有变更可追溯）

---

### TODO 13：成本与容量管理（升级方案）

#### 升级措施

**1. 成本可视化（Kubecost + OpenCost）**

- 按 Namespace / Service / Pod 维度归因成本
- 实时成本看板
- 月度成本报告

**2. 资源优化（Goldilocks）**

- 自动推荐 resources.requests/limits
- 识别过度分配和分配不足
- 定期 Right-Sizing

**3. 节点弹性（Karpenter）**

- 按需自动扩缩容节点
- 减少节点空置
- 支持 GPU 节点自动调度

**4. 预算告警**

- 月度预算阈值：50% / 80% / 100%
- 超预算自动告警（飞书）
- 预算偏差分析

**5. 容量预测**

- 基于历史趋势预测未来 3 个月容量需求
- 提前规划节点扩容
- 避免临时紧急采购

---

## 四、统一技术架构图

### 4.1 基础设施层

```
┌─────────────────────────────────────────────────────────────┐
│                     云厂商（阿里云/AWS）                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  K8s (ACK)  │  │  OSS/S3     │  │  RDS/Redis/Kafka    │  │
│  │  托管集群    │  │  对象存储    │  │  托管中间件         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      K8s 集群内部                              │
│  ┌───────────────────────────────────────────────────────┐   │
│  │  APISIX（Ingress Gateway）                              │   │
│  │  - 鉴权、限流、路由、灰度                              │   │
│  └───────────────────────────────────────────────────────┘   │
│                              ↓
│  ┌───────────────────────────────────────────────────────┐   │
│  │  Istio Service Mesh（Sidecar）                          │   │
│  │  - mTLS、熔断、重试、流量镜像                            │   │
│  └───────────────────────────────────────────────────────┘   │
│                              ↓
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │
│  │ 业务微服务  │  │ AI 推理服务 │  │ 中间件               │   │
│  │ (Deployment)│  │ (vLLM/Ray)  │  │ (Redis/Kafka/PostgreSQL)│ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘   │
│                              ↓
│  ┌───────────────────────────────────────────────────────┐   │
│  │ 可观测性（Prometheus + Grafana + Loki + Tempo + Sentry）│   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 CI/CD 流水线

```
代码提交（GitLab）
    ↓
GitLab CI Pipeline
    ├── lint（代码风格）
    ├── test（单元测试 + 集成测试）
    ├── build（构建镜像）
    └── scan（Trivy 漏洞扫描 + 依赖扫描）
        ↓
Harbor（镜像仓库：存储 + 扫描 + 签名）
        ↓
ArgoCD（GitOps 部署）
    ├── Dev（自动部署）
    ├── Staging（自动部署）
    └── Prod（人工审批 + 金丝雀）
```

### 4.3 安全体系

```
左移（CI 阶段）          准入（部署阶段）         运行时（运行阶段）
    │                        │                       │
    ▼                        ▼                       ▼
┌─────────┐            ┌─────────────┐           ┌──────────┐
│ Trivy   │            │ Kyverno     │           │ Falco    │
│ 镜像扫描 │            │ 准入策略     │           │ 行为检测 │
│ 依赖扫描 │            │ - 禁止特权   │           │ - 异常进程│
└─────────┘            │ - 强制资源   │           │ - 可疑网络│
                       │ - 镜像白名单 │           │ - 敏感文件│
                       └─────────────┘           └──────────┘
                              │
                              ▼
                       ┌─────────────┐
                       │ Vault/KMS   │
                       │ 密钥管理     │
                       └─────────────┘
```

---

## 五、实施路线图（6 个月）

### Phase 1：底座强化（Week 1-4）

**目标**：安全左移 + 可观测性全覆盖 + 二进制纳管

- [ ] GitLab CI 新增 Trivy 镜像扫描
- [ ] 部署 Harbor 作为统一制品仓库
- [ ] 部署 Prometheus + Grafana + Loki
- [ ] K8s/Docker/二进制服务全部接入监控
- [ ] 配置核心告警规则（服务Down、高错误率、高延迟）
- [ ] 告警接入飞书
- [ ] 二进制服务纳管（OTel Collector + Blackbox Exporter）
- [ ] 制定二进制服务迁移计划

**产出**：
- 发布前自动拦截高危漏洞
- 所有服务在 Grafana 可见
- 核心故障 5 分钟内通过飞书告警通知

### Phase 2：AI 基建 + 流量治理（Week 5-8）

**目标**：AI 推理标准化 + 流量统一治理

- [ ] GPU 节点接入 K8s（NVIDIA Device Plugin）
- [ ] 部署 vLLM + Ray + MLflow
- [ ] AI 推理服务接入 GPU 监控（DCGM Exporter）
- [ ] Token 用量统计和计费系统上线
- [ ] 推理延迟 Dashboard（TTFT/TPOT）
- [ ] 部署 APISIX（南北向网关）
- [ ] 部署 Istio（东西向 Service Mesh）
- [ ] 统一入口鉴权、限流、路由

**产出**：
- GPU 资源可调度，推理服务在线运行
- AI 专项监控 Dashboard 上线
- 流量统一收口，不再每个服务各搞一套鉴权

### Phase 3：SRE + 流程标准化（Week 9-12）

**目标**：稳定性可控 + 变更可控 + 故障可复盘

- [ ] 定义核心服务 SLO/SLI
- [ ] 建立 On-Call 排班表（飞书日历）
- [ ] 制定变更分级制度（S/N/H/E）
- [ ] Jira 变更审批工作流上线
- [ ] 写故障复盘模板，完成第一次演练
- [ ] DORA 指标采集
- [ ] 建立研发效能回顾机制

**产出**：
- SLO Dashboard 可见
- On-Call 排班运转
- 变更必须经过审批才能部署生产
- 至少完成一次故障复盘

### Phase 4：安全 + 成本（Week 13-16）

**目标**：安全基线落地 + 成本可控

- [ ] 部署 Kyverno，启用核心安全策略
- [ ] Secret 迁移到 Vault/KMS
- [ ] 部署 Falco，运行时安全告警
- [ ] 部署 Kubecost + OpenCost
- [ ] 成本看板上线（按 Namespace/Service 归因）
- [ ] 预算阈值告警（50%/80%/100%）
- [ ] 首次 Right-Sizing（至少 1 个关键服务）

**产出**：
- 生产命名空间安全策略生效
- 运行时异常行为可检测
- 成本可视化，预算超支可预警

### Phase 5：商业化 + 精细化（Week 17-24）

**目标**：License 系统上线 + 精细化运营

- [ ] 设计 License 数据结构和授权模式
- [ ] 实现 License 生成服务
- [ ] 实现客户端验证逻辑
- [ ] 实现管理后台（创建/续期/吊销）
- [ ] 部署 Chaos Mesh，第一次混沌演练
- [ ] 链路追踪全量上线（Tempo + OpenTelemetry）
- [ ] Sentry 异常监控接入
- [ ] 成本容量预测模型

**产出**：
- License 全链路跑通
- 系统韧性经过混沌工程验证
- 全链路可追踪、可观测、可审计

---

## 六、关键指标（治理度量）

### 稳定性指标

| 指标 | 当前 | 目标（6 个月） |
|---|---|---|
| 可用性 | 未知 | ≥ 99.9% |
| P99 延迟 | 未知 | ≤ 500ms（Web）/ ≤ 2s（AI） |
| MTTR | 未知 | ≤ 30 分钟（P0） |
| 变更引发的故障占比 | 未知 | < 10% |

### 安全指标

| 指标 | 当前 | 目标（6 个月） |
|---|---|---|
| 高危漏洞存量 | 未知 | = 0（发布前阻断） |
| 准入策略拦截数 | 0 | > 0（策略生效） |
| 运行时高危事件数 | 未知 | 可检测、可告警 |
| Secret 明文出现在仓库 | 可能 | = 0 |

### 成本指标

| 指标 | 当前 | 目标（6 个月） |
|---|---|---|
| 资源利用率 | 未知 | CPU > 50%，内存 > 60% |
| 预算偏差率 | 未知 | < 10% |
| 闲置成本占比 | 未知 | < 20% |

### 商业化指标

| 指标 | 当前 | 目标（6 个月） |
|---|---|---|
| 激活成功率 | N/A | ≥ 99% |
| 续费率 | N/A | ≥ 80% |
| 校验失败率 | N/A | < 1% |

---

## 七、风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| 团队人力不足 | 无法按计划推进 | 优先做 P0（安全+可观测），其余延后 |
| 二进制服务迁移成本高 | 进度延迟 | 短期纳管监控，长期按优先级迁移，不强制一次性完成 |
| 新工具学习成本高 | 团队抵触 | 每阶段只引入 2-3 个工具，提供培训文档 |
| 告警风暴 | 告警无效 | 从核心规则开始，逐步细化，定期 review 告警有效性 |
| 安全策略误杀 | 影响业务 | Kyverno 先开 Audit 模式，观察 1 周后再切 Enforce |
| License 被破解 | 商业损失 | 接受"提高门槛"而非"绝对防破"，设备指纹 + 联网校验 |

---

## 八、下一步行动

**本周内建议做的 3 件事：**

1. **GitLab CI 加 Trivy**：在 `.gitlab-ci.yml` 中增加 `scan-image` 阶段，测试镜像扫描效果（30 分钟）
2. **部署 Prometheus + Grafana**：用 Helm 在 K8s 上跑起来，接入 1-2 个现有服务（1-2 小时）
3. **二进制服务纳管试点**：选一个最重要的二进制服务，用 Blackbox Exporter 做健康探测（1-2 小时）

做完这 3 件事，你就能看到治理升级的实际效果，然后再决定下一步怎么推进。
