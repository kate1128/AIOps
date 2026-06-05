# Chaos Mesh — 云原生混沌工程平台

> 主动向系统注入故障，验证系统在真实故障场景下的韧性，做到"演习代替救火"。

---

## 是什么

Chaos Mesh 是 CNCF 孵化项目，K8s 原生的混沌工程平台。它通过向运行中的系统注入**网络故障、Pod 崩溃、CPU 压力、磁盘故障、内存压力**等，帮助团队在受控条件下发现系统弱点，而不是等真实故障发生时手忙脚乱。

---

## 核心故障类型

| 故障类型 | 说明 | 典型实验 |
|---|---|---|
| **PodChaos** | Pod 随机终止/暂停/容器杀死 | 验证 Deployment 的 Pod 重建和流量切换 |
| **NetworkChaos** | 网络延迟、丢包、断网 | 验证服务超时和熔断机制 |
| **StressChaos** | CPU/内存压力 | 验证资源限制和 HPA 扩容触发 |
| **IOChaos** | 磁盘 IO 延迟/错误 | 验证数据库和存储在 IO 慢时的表现 |
| **HTTPChaos** | HTTP 响应延迟/错误注入 | 验证上游依赖超时时的降级处理 |
| **TimeChaos** | 时钟偏移 | 验证 JWT Token 过期、分布式时钟敏感逻辑 |
| **DNSChaos** | DNS 解析错误/随机化 | 验证服务发现失败时的重试逻辑 |

---

## 与本项目的关系

```
SRE 混沌实验计划
    │
    ├── 实验 1：AI 推理服务随机 Pod 终止
    │       预期：请求自动路由到其他 Pod，无服务中断
    │
    ├── 实验 2：vLLM 节点网络延迟 500ms
    │       预期：网关超时触发熔断，返回降级响应
    │
    ├── 实验 3：Redis 主节点宕机
    │       预期：Sentinel 30s 内完成主从切换，业务短暂降级后恢复
    │
    └── 实验 4：Kafka 某个 Broker 崩溃
            预期：消费者 Rebalance，消息不丢失，延迟短暂增加
```

---

## 安装

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --set dashboard.create=true \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

---

## 实验配置示例

### 实验 1：随机 Pod 终止（验证高可用）

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: ai-service-pod-kill
  namespace: production
spec:
  action: pod-kill
  mode: one            # 每次随机杀一个
  selector:
    namespaces:
      - production
    labelSelectors:
      app: ai-service
  scheduler:
    cron: "@every 10m" # 每 10 分钟执行一次（仅演练期间）
```

### 实验 2：网络延迟注入（验证熔断）

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: vllm-network-delay
  namespace: production
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - production
    labelSelectors:
      app: vllm
  delay:
    latency: "500ms"
    correlation: "25"
    jitter: "100ms"
  duration: "5m"    # 持续 5 分钟后自动停止
```

### 实验 3：HTTP 错误注入（验证降级）

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: HTTPChaos
metadata:
  name: ai-service-http-error
spec:
  mode: fixed-percent
  value: "30"         # 30% 的请求返回错误
  target: Response
  port: 8000
  path: /api/v1/chat
  code: 503
  duration: "3m"
  selector:
    namespaces:
      - production
    labelSelectors:
      app: ai-service
```

---

## 混沌工程实施流程

```
1. 建立稳态假设
   明确"正常情况下系统的关键指标是什么"
   如：错误率 < 0.1%，P99 延迟 < 500ms

2. 设计最小爆炸半径实验
   从影响最小的 staging 开始，逐步扩展到生产

3. 执行实验 + 实时监控
   Chaos Mesh 注入故障，Grafana 观察指标变化

4. 记录和分析结果
   指标是否超出稳态？系统是否自愈？耗时多久？

5. 修复发现的弱点
   每次实验的结果直接转化为改进任务

6. 定期重复
   每次大版本发布前或基础设施变更前必跑
```

---

## 与 SLO 体系的关系

混沌实验的结果直接验证 SLO 的真实性：
- 单个 Pod 故障 → 服务可用性是否仍满足 99.9% SLO
- 依赖超时 → Error Budget 消耗速率是否可接受
- 自愈时间 → MTTR 是否在 SLO 要求范围内

> **原则**：混沌实验应在 Error Budget 充足时进行，不能在 SLO 紧张时做演练。

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/chaos-mesh/chaos-mesh
- Star：7.7k（统计日期：2026-05-27）

