# Lens — Kubernetes IDE

> K8s 集群的桌面管理工具，排障和资源查看最高效的客户端。

---

## 是什么

Lens 是一个 Kubernetes 桌面 IDE，可连接多个集群，提供图形化的 Pod/Service/Deployment 管理界面，内置实时日志、Shell 进入容器、资源使用监控等功能。它是 kubectl 的图形化增强版，而不是服务端平台。

**⚠️ 重要：License 变更**  
Lens 从 v6.0 开始不再完全开源，使用需要注册免费账号（Lens ID），部分高级功能需要付费订阅。真正的开源替代版本是 **OpenLens**（社区 fork，无需账号）。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| 多集群管理 | 导入多个 kubeconfig，一个界面切换，支持 kubectx |
| 资源总览 | Pod、Deployment、Service、ConfigMap、CRD 全览，支持实时过滤 |
| 实时日志 | 多 Pod 日志流合并查看，支持搜索、时间过滤 |
| 容器 Shell | 一键 exec 进入容器，不需要记 kubectl 命令 |
| 内置 Metrics | 集成 Prometheus，直接显示 CPU/内存用量（需集群已装 metrics-server）|
| Helm 管理 | 查看和管理已安装的 Helm Release，支持升级/回滚 |
| 端口转发 | 右键 Service/Pod 即可 Port Forward，无需命令行 |
| 事件告警 | 实时显示 K8s Events，Warning 级别高亮 |
| 资源 YAML 编辑 | 直接在界面编辑资源 YAML，并 apply 到集群 |
| 插件扩展 | 支持 npm 插件，社区有 ArgoCD、Lens-GitOps 等插件 |

---

## 适用场景

- **日常运维**：查看 Pod 状态、重启、查日志，比敲命令快 3-5 倍
- **排障**：事故时快速定位哪个 Pod 异常、查资源占用、看 Event
- **开发调试**：本地 Port Forward 到集群服务，不需要暴露端口
- **多环境切换**：生产/pre/dev 三套集群一个窗口切换，不会混淆 context
- **新成员上手**：图形界面降低 K8s 学习门槛

---

## 与本项目的关系

当前你们有 3 套集群（生产 ACK + pre + dev），Lens 正好覆盖这个场景：

```
开发/运维人员的本地机器
    └── Lens（桌面应用）
            │
            ├── 连接生产集群（建议配置只读 RBAC）
            ├── 连接 pre 环境（读写权限）
            └── 连接 dev 环境（全权限）
```

本项目建议：
- 每个运维/后端工程师本地安装 OpenLens（免账号，完全免费）
- 生产集群通过独立 ServiceAccount + RBAC 只读角色绑定，防止误操作
- 与 k9s 配合使用：日常浏览用 Lens，高频操作用 k9s

### 生产集群只读账号配置

```yaml
# readonly-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: lens-readonly
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: lens-readonly-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view           # K8s 内置只读角色
subjects:
  - kind: ServiceAccount
    name: lens-readonly
    namespace: kube-system
```

```bash
kubectl apply -f readonly-sa.yaml

# 获取 Token（K8s 1.24+ 需手动创建）
kubectl create token lens-readonly -n kube-system --duration=8760h
```

---

## 安装

```bash
# Lens（需要账号）
# macOS
brew install --cask lens

# OpenLens（推荐，无需账号）
# 从 GitHub Releases 下载：https://github.com/MuhammedKalkan/OpenLens/releases
# 支持 Windows / macOS / Linux
```

### 连接集群

```bash
# Lens 会自动读取 ~/.kube/config
# 多个集群写在同一个 kubeconfig 文件里，或通过 KUBECONFIG 环境变量合并：
export KUBECONFIG=~/.kube/prod:~/.kube/pre:~/.kube/dev
kubectl config view --merge --flatten > ~/.kube/config
```

---

## Lens vs OpenLens 区别

| 维度 | Lens（官方）| OpenLens（社区 fork）|
|---|---|---|
| License | 需要免费账号，部分功能付费 | 完全开源，MIT License |
| 功能 | 更多扩展功能，企业版有团队功能 | 核心功能完整，插件生态略少 |
| 隐私 | 遥测数据上传 Lens 服务器 | 无强制遥测 |
| 推荐 | 无特殊需求 | **推荐，尤其是私有化部署场景** |

---

## 局限性

- 纯本地工具，无法多人协作共享视图
- 不支持操作审计（谁删了哪个 Pod 不可查）—— 需配合 JumpServer 或 K8s Audit Log
- 部分功能（如 GPU 资源可视化）需要额外插件
- 大集群（节点数 > 100）时 UI 性能有所下降

---

## 同类工具对比

| 工具 | 类型 | 特点 | 推荐场景 |
|---|---|---|---|
| **Lens / OpenLens** | 桌面 GUI | 功能最全，上手最快 | 个人日常使用 |
| **k9s** | 终端 TUI | 键盘驱动，极高效，零资源 | 熟练运维，SSH 环境 |
| **Headlamp** | Web UI | 轻量，可部署在集群内共享 | 团队共用只读面板 |
| **K8s Dashboard** | Web UI | 官方出品，功能简单 | 演示 / 新手入门 |
| **Rancher** | 平台 | 多集群统一管理 | 管理多套客户集群 |

---

## GitHub 信息

- 开源状态：部分开源（v6+ 需账号），OpenLens 完全开源
- 仓库地址：https://github.com/lensapp/lens
- OpenLens 地址：https://github.com/MuhammedKalkan/OpenLens
- Star：23.2k（统计日期：2026-05-27）

