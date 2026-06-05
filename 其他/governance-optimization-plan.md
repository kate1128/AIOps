# 问学 2.0 基础设施治理优化方案

> 基于现有基础（K8s + Docker + GitLab CI + Nginx + 飞书/Jira），通过引入新工具和优化流程，实现从"能跑"到"可控、可观测、可审计"的治理升级。

---

## 一、现状与优化方向

### 现有基础

| 维度 | 现状 | 治理水平 |
|---|---|---|
| 容器化 | K8s + Docker，大部分服务已容器化 | 良好 |
| CI/CD | GitLab CI 已跑通（lint → test → build → deploy） | 基础可用，缺安全门禁 |
| 网关 | Nginx + Ingress-Nginx | 基础可用，缺统一流量治理 |
| 协同 | 飞书 + Jira | 工具已有，流程待标准化 |
| 监控 | 未提及（大概率是"出问题看日志"的被动模式） | 薄弱，最大治理盲区 |
| 安全 | 无 CI 镜像扫描，无准入策略 | 缺失 |
| 二进制服务 | 仍在运行，未纳入 K8s 治理 | 最大不可控因素 |

### 优化目标

1. **安全左移**：发布前拦截高危漏洞，发布后运行时行为可检测
2. **可观测全覆盖**：K8s + Docker + 二进制服务，全部纳入统一监控
3. **变更可控**：GitLab CI 流水线增加安全门禁和多环境部署策略
4. **流程标准化**：On-Call、变更审批、故障复盘，用飞书+Jira 落地
5. **二进制纳管**：不可持续运行的服务逐步迁移，暂时无法迁移的纳入统一监控

---

## 二、核心优化措施

### 模块 1：CI/CD 流程优化（GitLab CI 增强）

#### 1.1 流水线增强：增加安全门禁

在现有流水线（lint → test → build → deploy）基础上，**新增 scan 阶段**，在构建后、部署前执行安全扫描。

```yaml
# 新增 scan 阶段
stages:
  - lint
  - test
  - build
  - scan        # 新增
  - deploy-dev
  - deploy-prod

# ========== 镜像漏洞扫描（新增）==========
scan-image:
  stage: scan
  image: aquasec/trivy:latest
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE_NAME:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_TAG

# ========== 依赖漏洞扫描（新增）==========
scan-deps:
  stage: scan
  image: python:3.11-slim
  script:
    - pip install safety bandit
    - safety check -r requirements.txt          # Python 依赖漏洞
    - bandit -r . -f json -o bandit-report.json  # Python 代码安全
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
    - if: $CI_COMMIT_BRANCH == "main"
```

#### 1.2 流水线增强：多环境部署策略

从"单分支自动部署"升级为"分支对应环境 + 灰度发布"。

```yaml
# 环境映射
# develop 分支 → dev 环境（自动部署）
# release/* 分支 → staging 环境（自动部署）
# main 分支 → prod 环境（手动审批 + 可选灰度）

# 新增 staging 环境部署
deploy-staging:
  stage: deploy-staging
  image: bitnami/kubectl
  script:
    - kubectl set image deployment/$CI_PROJECT_NAME $CI_PROJECT_NAME=$IMAGE_NAME:$CI_COMMIT_SHA -n staging
    - kubectl rollout status deployment/$CI_PROJECT_NAME -n staging --timeout=300s
  environment:
    name: staging
    url: https://staging.wenxue.com
  rules:
    - if: $CI_COMMIT_BRANCH =~ /^release\/.*/

# 生产部署：增加灰度策略（金丝雀）
deploy-prod-canary:
  stage: deploy-prod
  image: bitnami/kubectl
  script:
    # 先更新 10% 流量
    - kubectl set image deployment/$CI_PROJECT_NAME-canary $CI_PROJECT_NAME=$IMAGE_NAME:$CI_COMMIT_SHA -n prod
    - kubectl rollout status deployment/$CI_PROJECT_NAME-canary -n prod --timeout=300s
    # 人工确认后全量
    - echo "Canary deployed. Review metrics, then approve full rollout."
  environment:
    name: production
    url: https://wenxue.com
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  when: manual
```

#### 1.3 流水线增强：制品可追溯

```yaml
# Build 阶段增加镜像签名
build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t $IMAGE_NAME:$CI_COMMIT_SHA .
    # 使用 cosign 签名（新增）
    - cosign sign --key env://COSIGN_PRIVATE_KEY $IMAGE_NAME:$CI_COMMIT_SHA
    - docker push $IMAGE_NAME:$CI_COMMIT_SHA
```

#### 1.4 GitLab CI 优化后流水线

```
lint → test → build → scan → deploy-dev → deploy-staging → deploy-prod
                                        （自动）    （自动）      （手动审批）
```

**新增价值：**
- 高危漏洞在发布前被拦截
- 多环境部署降低"测试通过生产翻车"风险
- 镜像签名防止"部署了被篡改的镜像"

---

### 模块 2：可观测性体系建设（重点引入新工具）

你现在的最大治理盲区是**"看不见"**。引入 Prometheus + Grafana + Loki 三件套，覆盖 Metrics + Logs。

#### 2.1 部署方案

```yaml
# 使用 kube-prometheus-stack（Helm 一键部署）
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.retention=30d

# 部署 Loki（日志聚合）
helm install loki grafana/loki \
  --namespace observability \
  --set grafana.enabled=false  # 共用上面部署的 Grafana
```

#### 2.2 接入策略

| 服务类型 | 接入方式 | 说明 |
|---|---|---|
| K8s 服务 | 自动采集 | kube-prometheus-stack 自带 ServiceMonitor，自动发现 Pod 的 `/metrics` |
| Docker 服务（非 K8s） | Prometheus Node Exporter + 自定义端口暴露 | 在每个 Docker 节点部署 node-exporter，服务暴露 `/metrics` |
| 二进制服务 | 两种方式选其一 | **推荐方式 A**：用 OpenTelemetry Collector 做 Agent，二进制服务通过 OTLP 协议推送指标<br>**备选方式 B**：二进制服务直接暴露 `/metrics`（用 Prometheus client 库），Prometheus 通过 static_configs 抓取 |
| Nginx/Ingress | nginx-prometheus-exporter | 暴露 QPS、延迟、错误率等指标 |

#### 2.3 二进制服务快速接入方案（最小改动）

如果你的二进制服务不方便修改代码，用 **OpenTelemetry Collector** 做"无侵入"纳管：

```yaml
# 在每个运行二进制服务的节点部署 OTel Collector
# 二进制服务输出结构化日志到文件 → OTel Collector tail 日志 → 解析成指标推送到 Prometheus

# 1. 二进制服务日志格式（已有日志即可，不需要改代码）
# 2024-01-15T10:30:00Z ERROR api/login failed user=1234 latency=450ms

# 2. OTel Collector 配置：解析日志，提取指标
receivers:
  filelog:
    include: ["/var/log/wenxue/*.log"]
    operators:
      - type: regex_parser
        regex: 'latency=(?P<latency>\d+)ms'
        timestamp:
          parse_from: attributes.timestamp
          layout: '%Y-%m-%dT%H:%M:%SZ'

processors:
  - type: metricstransform
    transforms:
      - include: wenxue.request.latency
        action: update
        operations:
          - action: aggregate_histogram
            aggregation_type: histogram

exporters:
  prometheus:
    endpoint: "prometheus:9090"
```

**核心价值**：不改一行代码，二进制服务的延迟、错误率、QPS 就能在 Grafana 里看见。

#### 2.4 关键 Dashboard 和告警

```yaml
# Grafana Dashboard 清单（按优先级）
Priority 1 - 全局健康度:
  - 所有服务的可用性（HTTP 200 比例）
  - 所有服务的 P99 延迟
  - 告警汇总（按级别分组）

Priority 2 - K8s 集群:
  - 节点 CPU / 内存 / 磁盘使用率
  - Pod 重启率 / OOM 事件
  - 网络流量（Ingress 入口）

Priority 3 - AI 专项（如果你的二进制服务包含 AI 推理）:
  - GPU 利用率 / 温度 / 显存
  - 推理 QPS / 延迟（TTFT / TPOT）
  - Token 消耗速率
```

```yaml
# 核心告警规则（Prometheus Alertmanager）
groups:
  - name: critical
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: P0
        annotations:
          summary: "服务 {{ $labels.instance }} 不可达"

      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 2m
        labels:
          severity: P1
        annotations:
          summary: "服务 {{ $labels.instance }} 错误率超过 5%"

      - alert: HighLatency
        expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 3m
        labels:
          severity: P1
        annotations:
          summary: "服务 {{ $labels.instance }} P99 延迟超过 2s"
```

**告警通道接入飞书：**

```yaml
# Alertmanager 配置：告警推送到飞书群
global:
  smtp_smarthost: 'localhost:25'

receivers:
  - name: 'feishu'
    webhook_configs:
      - url: 'https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_WEBHOOK_TOKEN'
        send_resolved: true
        http_config:
          headers:
            Content-Type: application/json
```

---

### 模块 3：安全合规增强（引入 Trivy + Kyverno）

#### 3.1 CI 安全门禁（已在模块 1 中实现）

- Trivy 镜像漏洞扫描：阻断 HIGH/CRITICAL 漏洞
- Safety/Bandit：Python 依赖和代码安全扫描

#### 3.2 K8s 准入策略（Kyverno）

```bash
# 部署 Kyverno
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace

# 应用核心策略
kubectl apply -f - <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resources
spec:
  validationFailureAction: Enforce  # 或 Audit（先审计后阻断）
  rules:
    - name: check-requests
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Pod 必须设置 resources.requests 和 resources.limits"
        pattern:
          spec:
            containers:
              - resources:
                  requests:
                    memory: "?*"
                    cpu: "?*"
                  limits:
                    memory: "?*"
                    cpu: "?*"
EOF
```

**核心策略清单：**

| 策略 | 作用 | 级别 |
|---|---|---|
| 禁止特权容器 | 防止容器逃逸 | 强制 |
| 禁止 root 用户运行 | 最小权限原则 | 强制 |
| 强制 resources.requests/limits | 防止资源失控 | 强制 |
| 镜像仓库白名单 | 只允许部署来自 Harbor/ACR 的镜像 | 强制 |
| 禁止 hostPath | 防止宿主机文件泄露 | 强制 |

#### 3.3 运行时安全（Falco，可选，后期引入）

```bash
# 部署 Falco（检测容器内的异常行为）
helm install falco falcosecurity/falco --namespace falco --create-namespace

# 核心告警规则
# - 容器内执行 shell
# - 可疑的网络连接
# - 敏感文件访问（/etc/shadow 等）
```

---

### 模块 4：SRE 流程建设（不引入新工具，用飞书+Jira 落地）

#### 4.1 On-Call 制度

- **排班工具**：飞书日历（免费，够用）
- **响应分级**：
  - P0（服务不可用）：5 分钟内响应，15 分钟内定位，30 分钟内恢复
  - P1（核心功能异常）：30 分钟内响应，2 小时内恢复
  - P2（非核心功能异常）：工作时间内处理
- **升级路径**：主 On-Call（5min）→ 备 On-Call（15min）→ 技术负责人（30min）

#### 4.2 变更管理（接入 GitLab CI + Jira）

```
变更发起（GitLab MR）
    ↓
变更审批（Jira 工单：填写变更内容、影响范围、回滚方案）
    ↓
技术 Lead 审批（N 级）/ 技术负责人审批（H 级）
    ↓
GitLab MR 合并（自动化测试 + 镜像扫描通过）
    ↓
部署到 Staging（自动）
    ↓
QA 验证签字（Jira 工单状态更新）
    ↓
生产部署（GitLab 手动 Gate）
    ↓
线上验证（Jira 工单关闭）
```

#### 4.3 故障复盘（Postmortem）

- **模板**：用飞书文档或 Jira Confluence
- **触发条件**：P1 及以上故障，或任何 P0 级别事件
- **时限**：故障恢复后 48 小时内完成复盘文档
- **输出**：根因分析 + Action Items（录入 Jira 跟踪）

---

### 模块 5：二进制服务纳管方案

这是你最需要解决的问题。建议分两步走：

#### 短期（1-2 周）：纳入统一可观测性

目标：让二进制服务"看得见"，不需要迁移。

| 纳管项 | 方案 | 工具 |
|---|---|---|
| 指标 | 二进制服务暴露 `/metrics`（Prometheus client），或用 OTel Collector 解析日志 | Prometheus |
| 日志 | 统一输出 JSON 格式到标准路径，Filebeat/Promtail 采集 | Loki |
| 告警 | 服务不可用时告警（TCP 探测或 HTTP 健康检查） | Blackbox Exporter |
| 进程守护 | systemd 管理，崩溃自动重启 | systemd |

**最小改动方案**：

```bash
# 1. 二进制服务增加一个简单的 /health 接口（如果已有 HTTP 服务）
# 2. 用 Blackbox Exporter 做健康探测
cat <<EOF > blackbox-config.yml
modules:
  http_2xx:
    prober: http
    http:
      valid_status_codes: [200]
EOF

# 3. Prometheus 配置
- job_name: 'binary-services'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - http://binary-service-1:8080/health
      - http://binary-service-2:8080/health
EOF
```

#### 长期（按优先级）：逐步迁移到 K8s

| 优先级 | 迁移对象 | 理由 |
|---|---|---|
| P0 | 核心业务服务 | 稳定性要求最高，K8s 自愈能力最强 |
| P1 | 频繁变更的服务 | K8s 滚动更新降低变更风险 |
| P2 | 有状态服务 | 需要 StatefulSet + PVC，复杂度较高 |
| P3 | 低频访问服务 | 收益低，可以最后迁移或保持现状 |

---

## 三、工具引入清单

### 新增工具（按优先级排序）

| 优先级 | 工具 | 用途 | 部署复杂度 | 是否引入 |
|---|---|---|---|---|
| P0 | **Trivy** | CI 镜像漏洞扫描 | 低（GitLab CI 中直接调用） | 必引入 |
| P0 | **Prometheus + Grafana** | 统一指标监控和可视化 | 中（Helm 一键部署） | 必引入 |
| P0 | **Loki** | 日志聚合 | 低（Helm 一键部署） | 必引入 |
| P1 | **Kyverno** | K8s 准入策略 | 低（Helm 一键部署） | 必引入 |
| P1 | **OpenTelemetry Collector** | 二进制服务指标/日志纳管 | 中（配置较复杂） | 推荐引入 |
| P1 | **Blackbox Exporter** | 外部服务健康探测 | 低 | 推荐引入 |
| P2 | **Falco** | 运行时安全检测 | 中 | 后期引入 |
| P2 | **Alertmanager** | 告警路由和去重 | 低（Prometheus 自带） | 必引入 |

### 现有工具优化

| 工具 | 优化方向 |
|---|---|
| GitLab CI | 新增 scan 阶段、多环境部署、镜像签名 |
| Nginx + Ingress | 接入 nginx-prometheus-exporter，暴露流量指标 |
| 飞书 | 接入 Alertmanager 告警、On-Call 排班 |
| Jira | 变更审批流程、故障复盘 Action Items 跟踪 |

---

## 四、实施路线图

### 第一阶段：安全 + 可观测（Week 1-2）

**目标**：发布有安全门禁，系统"看得见"。

- [ ] GitLab CI 新增 Trivy 镜像扫描
- [ ] 部署 Prometheus + Grafana + Loki
- [ ] K8s 服务自动接入监控
- [ ] Docker/二进制服务接入 node-exporter 和日志采集
- [ ] 配置核心告警规则（服务Down、高错误率、高延迟）
- [ ] 告警接入飞书

**产出**：
- 每次发布前自动扫描漏洞
- Grafana 能看到所有服务的健康状态
- 核心故障能在 5 分钟内通过飞书告警通知到人

### 第二阶段：策略 + 流程（Week 3-4）

**目标**：K8s 安全基线落地，变更和故障流程标准化。

- [ ] 部署 Kyverno，启用核心安全策略（禁止特权、强制 resources）
- [ ] GitLab CI 新增多环境部署（dev/staging/prod）
- [ ] Jira 建立变更审批工作流
- [ ] 建立 On-Call 排班表（飞书日历）
- [ ] 制定故障复盘模板，完成第一次演练

**产出**：
- 生产命名空间启用安全策略
- 变更必须经过审批才能部署到生产
- On-Call 排班运转，故障有复盘模板

### 第三阶段：精细化 + 长期优化（Week 5-8）

**目标**：AI 专项监控、二进制迁移、运行时安全。

- [ ] AI 推理服务接入 GPU 监控（DCGM Exporter）
- [ ] Token 用量统计 Dashboard
- [ ] 二进制服务逐步迁移到 K8s（按优先级）
- [ ] 部署 Falco，运行时安全告警
- [ ] DORA 指标采集和研发效能回顾

**产出**：
- AI 服务有专门的监控 Dashboard
- 二进制服务大部分迁移到 K8s
- 运行时异常行为可检测

---

## 五、预期收益

| 维度 | 优化前 | 优化后 |
|---|---|---|
| 安全 | 发布无扫描，漏洞可能流入生产 | 发布前自动拦截 HIGH/CRITICAL 漏洞 |
| 可观测性 | "出问题看日志"，定位慢 | 指标+日志统一入口，5 分钟内定位根因 |
| 变更 | 手动部署，风险不可控 | 流水线自动化，多环境验证，可回滚 |
| 故障 | 被动响应，无复盘 | On-Call 制度，48h 内复盘，Action Items 跟踪 |
| 二进制服务 | 黑盒运行，不可控 | 纳入统一监控，逐步迁移到 K8s |
| 合规 | 无审计能力 | 变更可追溯，安全策略可审计 |

---

## 六、风险控制

| 风险 | 应对 |
|---|---|
| 引入工具过多，团队学习成本高 | 分阶段引入，每阶段只引入 2-3 个工具 |
| 二进制服务迁移成本高 | 短期先纳管监控，长期按优先级迁移，不强制一次性迁移 |
| 告警风暴 | 告警规则从简到繁，先配核心规则，再逐步细化 |
| 安全策略误杀 | Kyverno 先开 Audit 模式，观察 1 周后再切 Enforce |
| CI 流水线变慢 | Trivy 扫描可并行执行，不阻塞其他 stage |

---

## 七、下一步行动

**本周内可以做起来的 3 件事：**

1. **GitLab CI 加 Trivy**：在 `.gitlab-ci.yml` 中加一个 `scan-image` 的 job，测试一下镜像扫描效果。
2. **部署 Prometheus + Grafana**：用 Helm 在 K8s 上跑起来，接入 1-2 个现有服务看看效果。
3. **选一个二进制服务做监控纳管**：用 Blackbox Exporter 或 OTel Collector，把这个服务的健康状态接入 Grafana。

做完这 3 件事，你就能看到治理优化的实际效果，然后再决定下一步怎么推进。
