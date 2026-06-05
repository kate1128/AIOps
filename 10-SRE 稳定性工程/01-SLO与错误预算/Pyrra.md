# Pyrra — 基于 Prometheus 的 SLO 管理平台

> 不需要引入新的数据源，直接在 Prometheus 之上生成 SLO 看板和告警规则。

---

## 是什么

Pyrra 是一个轻量级 SLO 管理工具，它读取你定义的 `SLO` 资源（YAML 或 CRD），自动生成：
- **Prometheus Recording Rules**（预计算 Error Rate）
- **Prometheus Alerting Rules**（Error Budget 耗尽告警）
- **Grafana Dashboard**（SLO 看板，含 Error Budget 燃烧率）

你只需定义"这个服务的成功率目标是 99.5%"，剩下的规则和图表全自动生成。

---

## 核心概念：Error Budget 燃烧率告警

SLO 的精髓不是"当前是否达标"，而是**预测 Error Budget 会不会在月底前耗尽**。

Pyrra 基于 Google SRE Book 的多窗口告警策略：

| 告警窗口 | 燃烧率倍数 | 含义 | 告警级别 |
|---|---|---|---|
| 1h + 5min | > 14.4x | 1 小时内耗完 2h Budget | P1 |
| 6h + 30min | > 6x | 6 小时内耗完 5h Budget | P1 |
| 1d + 2h | > 3x | 1 天内耗完 10h Budget | P2 |
| 3d + 6h | > 1x | 3 天内耗完 1d Budget | P3 |

> 燃烧率 = 当前错误率 / (1 - SLO)。燃烧率 = 1 表示刚好在 30 天内耗完 Budget。

---

## 安装

### Helm 安装

```bash
helm repo add pyrra https://pyrra-dev.github.io/pyrra/helm-charts
helm repo update

helm install pyrra pyrra/pyrra \
  --namespace monitoring \
  --set config.prometheusUrl=http://prometheus-server:9090 \
  --set config.prometheusExternalUrl=http://your-prometheus-domain
```

### docker-compose（非 K8s 环境）

```yaml
version: "3"
services:
  pyrra:
    image: ghcr.io/pyrra-dev/pyrra:latest
    ports:
      - "9099:9099"
    volumes:
      - ./slo-definitions:/etc/pyrra  # SLO 定义目录
    command:
      - filesystem                     # 使用文件模式（非 K8s CRD 模式）
      - --prometheus-url=http://prometheus:9090
```

---

## SLO 定义文件（文件模式）

在 `/etc/pyrra/` 目录下放置 YAML 文件，Pyrra 自动读取：

```yaml
# /etc/pyrra/vllm-availability.yaml
apiVersion: pyrra.dev/v1alpha1
kind: ServiceLevelObjective
metadata:
  name: vllm-availability
  namespace: monitoring
spec:
  description: "vLLM 推理服务可用性"
  target: "99.5"              # SLO 目标 99.5%
  window: 30d                 # Error Budget 计算窗口

  serviceLevel:
    objectives:
      - latency: null
        ratio:
          errors:
            metric: vllm:request_failure_total{}
          total:
            metric: vllm:request_total{}
```

```yaml
# /etc/pyrra/api-availability.yaml
apiVersion: pyrra.dev/v1alpha1
kind: ServiceLevelObjective
metadata:
  name: api-availability
  namespace: monitoring
spec:
  description: "问学平台 Web API 可用性"
  target: "99.9"
  window: 30d

  serviceLevel:
    objectives:
      - ratio:
          errors:
            metric: nginx_http_requests_total{status=~"5.."}
          total:
            metric: nginx_http_requests_total
```

---

## 自动生成的内容

定义完 SLO 后，Pyrra 自动输出：

### 1. Prometheus Recording Rules

```yaml
# 自动生成（无需手写）
- record: pyrra:vllm_availability:errorbudget
  expr: |
    1 - (
      sum(rate(vllm:request_failure_total[30d]))
      / sum(rate(vllm:request_total[30d]))
    ) / (1 - 0.995)
```

### 2. 多窗口 Alerting Rules

```yaml
# 自动生成（无需手写）
- alert: SLOErrorBudgetBurning-vllm-availability
  expr: |
    pyrra:vllm_availability:burnrate1h > (14.4 * 1)
    and pyrra:vllm_availability:burnrate5m > (14.4 * 1)
  labels:
    severity: warning
    slo: vllm-availability
```

### 3. Grafana Dashboard

Pyrra 内置 UI，直接访问 `:9099`，也可导出 Grafana JSON：

```
http://pyrra:9099
├── SLO 列表（所有服务 SLO 达标状态）
├── Error Budget 燃烧图（过去 30 天消耗曲线）
├── 告警历史（哪些时段拉低了 SLO）
└── 自动生成的 PromQL 查询
```

---

## 与 Sloth 的对比

> Sloth 是另一款类似工具，功能基本相同，选一个即可。

| 维度 | Pyrra | Sloth |
|---|---|---|
| 内置 UI | ✅ 有 SLO 看板 | ❌ 无，只生成规则 |
| K8s CRD 模式 | ✅ | ✅ |
| 文件模式（非 K8s）| ✅ `filesystem` 模式 | ✅ CLI 生成 |
| Grafana 集成 | 🟡 可导出 JSON | ✅ 有官方 Dashboard |
| 活跃度 | 🟡 社区维护 | 🟡 社区维护 |
| **推荐场景** | 想要内置 UI | 只需要生成规则文件 |

---

## 是否引入评估

| 维度 | 评估 |
|---|---|
| **前置条件** | 必须先有 Prometheus + vLLM 指标接入 |
| **引入成本** | 低：一个容器，一个 YAML 文件，30 分钟上线 |
| **核心价值** | 把"SLO 是否达标"变成可量化的图表，不再靠感觉判断 |
| **当前建议** | 🟡 **等 vLLM 指标接入 Prometheus 后，立即引入**（Phase 2）|
| **不引入的代价** | SLO 定义只是文档，没有数据验证，形同虚设 |

---

## 接入路径

```
现在                          接入 Pyrra 的前置条件
  │                                   │
vLLM 暴露 /metrics    →   Prometheus 采集成功   →   部署 Pyrra + 写 SLO YAML
（已有 /metrics 端点）     （加 scrape 配置）         （30 分钟完成）
```
