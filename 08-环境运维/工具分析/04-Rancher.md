# Rancher — 多集群 Kubernetes 管理平台

> 统一管理多套 K8s 集群的 Web 平台，特别适合管理客户私有化部署环境。

---

## 是什么

Rancher 是 SUSE 开源的 Kubernetes 多集群管理平台，部署在一个"管理集群"上，可以纳管任意数量的下游 K8s 集群（无论是 ACK、自建 kubeadm、K3s 还是 RKE2）。它提供统一的 Web 控制台、RBAC、监控、日志、应用商店等能力。

**核心定位**：不是替代 kubectl 的工具，而是**跨集群的统一控制平面**。

---

## 核心能力

| 模块 | 能力 |
|---|---|
| **多集群纳管** | 导入任意 K8s 集群，统一在一个界面管理 |
| **集群创建** | 支持创建 RKE/RKE2/K3s 集群，也可导入已有集群 |
| **统一 RBAC** | 跨集群的用户权限管理，一个账号控制所有集群 |
| **应用目录** | Helm Charts 统一管理，跨集群一键部署 |
| **Fleet GitOps** | 内置 Fleet，做跨集群 GitOps 部署 |
| **监控集成** | 内置 Prometheus + Grafana（每集群独立）|
| **日志集成** | 支持 Loki / Elasticsearch 日志聚合 |
| **CIS 扫描** | 集群安全基线扫描（CIS Kubernetes Benchmark）|
| **备份恢复** | rancher-backup-operator，支持 Rancher 配置备份 |
| **OPA 集成** | 支持 OPA/Gatekeeper 策略管理 |

---

## 适用场景

- **管理多套集群**：你们有生产 + pre + dev，未来还有多个客户的私有化集群，Rancher 可以统一管理
- **客户环境运维**：客户私有化部署后，通过 Rancher Agent 将客户集群纳管，远程运维不需要逐一 SSH
- **跨集群 GitOps**：Fleet 可以同时向多个集群推送配置，适合标准化客户交付
- **权限统一管理**：新员工入职只需在 Rancher 配置一次权限，所有集群权限统一发放

---

## 与本项目的关系

**关键价值点**：你们的客户环境全部是私有化部署，每个客户都是一套独立集群，未来集群数量会随客户增长而增加。

```
Rancher Server（部署在你们内部的一个集群/VM）
    │
    ├── 纳管：生产集群（阿里云 ACK）
    ├── 纳管：pre 集群（自建）
    ├── 纳管：dev 集群（自建）
    ├── 纳管：客户 A 集群（私有化部署）
    ├── 纳管：客户 B 集群（私有化部署）
    └── 纳管：客户 N 集群 ...
```

**具体收益：**
- 客户集群出问题时，不需要每次要 kubeconfig，直接通过 Rancher 查看
- 跨客户集群统一发布配置变更（Fleet）
- 新客户交付时通过 Rancher 完成集群初始化配置

---

## ⚠️ 引入评估

**推荐引入时机：** 客户数量达到 3+ 套私有化集群时，手动管理成本明显上升，此时 Rancher 价值显现。

**当前（3套自有集群）是否需要：** 可选，不紧迫。3套集群用 Lens + k9s + 各自 kubeconfig 够用。但如果客户侧已有多套在跑，可以提前布局。

**注意事项：**
- Rancher Server 本身需要一套稳定的 K8s 或 RKE2 集群来运行（推荐独立部署，不要和业务共用）
- Rancher Agent 需要能访问 Rancher Server（客户内网需要打通网络或开放特定端口）
- 如果客户网络完全隔离，可以用 Rancher 的 "导入集群" + 代理模式

---

## 安装

### 方式一：使用 Helm 安装（推荐）

```bash
# 前置条件：有一套 K8s 集群作为 Rancher 管理节点
# 推荐用 RKE2 或 K3s 搭建专用管理集群

# 添加 Helm 仓库
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# 安装 cert-manager（Rancher 依赖）
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml

# 安装 Rancher
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.yourdomain.com \
  --set bootstrapPassword=admin123456 \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=ops@yourcompany.com
```

### 方式二：导入已有集群

```bash
# 在 Rancher UI 中：
# 集群管理 → 导入已有集群 → 复制 kubectl apply 命令
# 在目标集群执行该命令即可完成 Agent 注册

# 示例命令（由 Rancher 生成）
kubectl apply -f https://rancher.yourdomain.com/v3/import/xxxx.yaml
```

---

## 资源需求

| 部署规模 | CPU | 内存 | 说明 |
|---|---|---|---|
| 最小（≤5 集群）| 2 核 | 4 GB | 单节点 K3s 上运行 Rancher |
| 中等（5-20 集群）| 4 核 | 8 GB | 3 节点 RKE2 高可用 |
| 大型（>20 集群）| 8 核+ | 16 GB+ | 专用集群 |

---

## 与 KubeSphere 对比

| 维度 | Rancher | KubeSphere |
|---|---|---|
| **核心定位** | 多集群管理 | 单集群增强平台 |
| **多集群支持** | 原生，最强 | 支持但非重点 |
| **界面语言** | 英文为主（有中文）| 中文友好 |
| **DevOps 功能** | 基础 | 较完整（Jenkins/Tekton）|
| **资源消耗** | 中等 | 较重（全功能时）|
| **客户私有化场景** | ✅ 非常适合 | 一般 |
| **开源 License** | Apache 2.0 | Apache 2.0 |

**结论**：两者并不是竞争关系——Rancher 管多集群，KubeSphere 强化单集群体验。你们如果只用一个，优先 Rancher（因为有客户私有化集群管理需求）。

---

## GitHub 信息

- 开源状态：开源（Apache 2.0）
- 仓库地址：https://github.com/rancher/rancher
- Star：23.5k（统计日期：2026-05-27）
