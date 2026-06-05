# KubeSphere — 企业级容器平台

> 基于 K8s 的全功能容器管理平台，覆盖 DevOps、多租户、监控、日志、网关、中间件管理。

---

## 是什么

KubeSphere 是青云科技开源的企业级 Kubernetes 管理平台，部署在 K8s 之上，提供 Web 控制台和完整的容器化应用生命周期管理能力。它整合了 Prometheus/Grafana、Loki、Jaeger、Argo CD、KubeEdge 等组件，是一个"一站式"的 K8s 平台。

**版本说明：**
- v3.x：传统架构，功能完整，社区使用最广泛，K8s v1.20~v1.26 兼容性好
- v4.x（Luban）：2024 年发布的新架构，插件化设计，资源消耗更低，但生态还在追赶

---

## 核心能力

| 模块 | 能力 |
|---|---|
| **多租户管理** | 企业空间 → 项目（Namespace）两级隔离，RBAC 权限管理 |
| **DevOps 流水线** | 可视化 CI/CD 流水线，基于 Jenkins / Tekton |
| **监控与告警** | 内置 Prometheus + Grafana，开箱即用 |
| **日志系统** | 集成 Loki / Elasticsearch，统一日志查询 |
| **服务网格** | 集成 Istio，支持金丝雀发布、熔断、流量管理 |
| **应用商店** | Helm 应用一键部署（中间件、数据库等） |
| **存储管理** | PVC 可视化管理，多存储后端支持 |
| **网关管理** | Namespace 级别 Ingress 控制器配置 |
| **审计日志** | 所有操作均有审计记录（谁在什么时间做了什么）|
| **镜像仓库集成** | 可直接连接 Harbor，镜像管理一体化 |

---

## 适用场景

- **团队多租户隔离**：不同产品线/团队使用独立的企业空间和配额
- **平台工程**：为研发团队提供 self-service 的 K8s 使用入口，研发不需要懂 kubectl
- **新团队 K8s 上手**：降低 K8s 使用门槛
- **统一审计需求**：操作审计合规要求较高的场景

---

## ⚠️ 对本项目的评估：当前不建议引入

**原因分析：**

1. **功能重叠严重**：你们已独立选型 Prometheus + Grafana + Loki + GitLab CI + ArgoCD，KubeSphere 内置了同一套，引入会导致两套并存，维护成本翻倍

2. **资源消耗不小**：全功能模式需要 ~4 核 8GB，你们生产集群已有 1 节点 NotReady，资源本就紧张

3. **K8s 版本兼容性**：v3.x 在 K8s v1.20 上可运行，但 v4.x 要求 v1.23+；生产集群升级前引入有风险

4. **团队规模不匹配**：KubeSphere 的多租户和平台工程能力是为 50+ 人工程团队设计的，小团队引入收益有限

5. **私有化部署场景**：客户环境资源普遍有限，交付时带上 KubeSphere 会显著增加部署复杂度和资源需求

**重新评估时机：** 当团队规模超过 20 人、有明确 self-service 平台需求时，可以重新评估 KubeSphere v4.x。

---

## 与本项目的关系（假设引入）

```
K8s 集群
    └── KubeSphere（部署在集群内）
            │
            ├── 企业空间：AI 服务 / 基础设施 / 数据团队
            ├── DevOps：GitLab → KubeSphere 流水线 → 部署
            ├── 监控：Prometheus + Grafana（内置）
            ├── 日志：Loki（内置）
            ├── 应用商店：一键部署 Redis、PostgreSQL、Kafka
            └── 服务网格：Istio（可选开启）
```

---

## 安装（在已有 K8s 集群上）

```bash
# 前置条件：K8s 1.20+，StorageClass 已配置（你们已有 nfs-client）

# 安装 KubeSphere Core（v3.4.1）
kubectl apply -f https://github.com/kubesphere/ks-installer/releases/download/v3.4.1/kubesphere-installer.yaml
kubectl apply -f https://github.com/kubesphere/ks-installer/releases/download/v3.4.1/cluster-configuration.yaml

# 查看安装进度（约 15-20 分钟）
kubectl logs -n kubesphere-system -l app=ks-install -f

# 安装完成后获取访问地址
kubectl get svc/ks-console -n kubesphere-system
# 默认账号：admin / P@88w0rd（首次登录强制改密）
```

### 按需启用组件（cluster-configuration.yaml）

```yaml
# 按需开启，不需要的组件关闭，节省资源
devops:
  enabled: false       # 已有 GitLab CI，不需要重复
monitoring:
  enabled: false       # 已有独立 Prometheus + Grafana
logging:
  enabled: false       # 已有独立 Loki
servicemesh:
  enabled: false       # Istio 资源消耗大，按需决定
openpitrix:
  store:
    enabled: true      # 应用商店，按需
auditing:
  enabled: true        # 审计日志，推荐开启
```

---

## 资源需求参考

| 配置 | CPU | 内存 | 说明 |
|---|---|---|---|
| 最小化（仅核心）| 1 核 | 1.5 GB | 只有基础控制台 |
| + 审计日志 | +0.2 核 | +0.5 GB | |
| + DevOps | +0.5 核 | +2 GB | Jenkins 较重 |
| + 监控 | +1 核 | +2 GB | |
| + 日志 | +1 核 | +2 GB | |
| 全功能 | ~4 核 | ~8 GB | 需独立节点 |

---

## 与同类工具对比

| 平台 | 定位 | 优势 | 劣势 | 适用场景 |
|---|---|---|---|---|
| **KubeSphere** | 一站式企业平台 | 中文友好、功能全、免费 | 重，与独立工具栈冲突 | 中大型团队、需要 self-service |
| **Rancher** | 多集群管理 | 多集群统一管理能力强，界面简洁 | 功能深度不如 KubeSphere | 管理多套集群（客户环境）|
| **OpenShift** | 企业 K8s | 安全合规极强，Red Hat 支持 | 收费、极重 | 金融/政府合规场景 |
| **Headlamp** | 轻量 Web UI | 极轻量，可部署在集群内共享 | 功能简单 | 团队共用只读视图 |

---

## GitHub 信息

- 开源状态：开源（Apache 2.0）
- 仓库地址：https://github.com/kubesphere/kubesphere
- Star：16.9k（统计日期：2026-05-27）

