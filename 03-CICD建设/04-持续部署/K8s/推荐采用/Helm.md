# Helm — K8s 应用包管理

> K8s 部署配置的标准打包工具，和 ArgoCD 配合使用构成 GitOps 完整链路。
> 当前状态：🟡 推荐采用（ArgoCD 接入后同步建立 Helm Chart 规范）

---

## 是什么

Helm 是 K8s 的包管理工具（类比 apt/yum），把一个服务的所有 K8s 资源（Deployment、Service、ConfigMap、Ingress 等）打包成一个 **Chart**，通过 `values.yaml` 统一管理环境差异（dev/pre/prod 的镜像版本、副本数、资源限制等）。

---

## 核心概念

| 概念 | 说明 |
|---|---|
| **Chart** | 一个服务的 K8s 资源打包，包含模板 + 默认 values |
| **Release** | Chart 在某个集群/namespace 的一次部署实例 |
| **values.yaml** | 环境差异配置，dev/pre/prod 各一份 |
| **Repository** | Chart 仓库，可以用 Harbor 托管私有 Chart |

---

## 与 ArgoCD 的配合

```
GitLab 仓库
├── charts/
│   └── vllm-service/
│       ├── Chart.yaml
│       ├── templates/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── ingress.yaml
│       └── values.yaml          # 默认值
└── envs/
    ├── dev/values.yaml          # dev 环境覆盖
    ├── pre/values.yaml          # pre 环境覆盖
    └── prod/values.yaml         # prod 环境覆盖
         │
         ▼
    ArgoCD 监听 Git 仓库变更
         │
         ▼
    自动 helm upgrade 到对应集群
```

---

## 目录结构规范（建议）

```
helm-charts/                     # 独立 Git 仓库或 monorepo 子目录
  vllm-qwen7b/
    Chart.yaml
    templates/
      deployment.yaml
      service.yaml
      hpa.yaml
    values.yaml                  # 通用默认值
  platform-api/
    Chart.yaml
    templates/
    values.yaml

envs/
  dev/
    vllm-qwen7b.yaml             # dev 覆盖：副本数 1，资源 limit 小
  pre/
    vllm-qwen7b.yaml
  prod/
    vllm-qwen7b.yaml             # prod 覆盖：副本数 2，GPU 显存限制
```

---

## values.yaml 差异管理示例

```yaml
# values.yaml（默认/通用）
replicaCount: 1
image:
  repository: harbor.internal/ai/vllm-qwen7b
  tag: latest
resources:
  limits:
    "nvidia.com/gpumem": 20480   # HAMI 显存限制 20GB
    cpu: "8"
    memory: "32Gi"
vllm:
  modelPath: /models/Qwen2-7B
  maxNumSeqs: 32
  gpuMemoryUtilization: "0.85"
```

```yaml
# envs/prod/vllm-qwen7b.yaml（prod 覆盖）
replicaCount: 2
image:
  tag: "v1.2.0"                  # prod 用固定版本，不用 latest
resources:
  limits:
    "nvidia.com/gpumem": 40960   # prod 给更多显存
vllm:
  maxNumSeqs: 64
```

---

## 常用命令

```bash
# 安装/升级
helm upgrade --install vllm-qwen7b ./charts/vllm-qwen7b \
  -f envs/prod/vllm-qwen7b.yaml \
  -n ai-service

# 查看当前部署状态
helm list -n ai-service

# 查看 release 历史（可回滚）
helm history vllm-qwen7b -n ai-service

# 回滚到上一版本
helm rollback vllm-qwen7b 0 -n ai-service

# 渲染模板（不实际部署，用于 debug）
helm template vllm-qwen7b ./charts/vllm-qwen7b -f envs/prod/vllm-qwen7b.yaml
```

---

## Harbor 托管私有 Chart 仓库

```bash
# 推送 Chart 到 Harbor（Harbor 2.0+ 支持 OCI 格式）
helm package ./charts/vllm-qwen7b
helm push vllm-qwen7b-1.0.0.tgz oci://harbor.internal/helm-charts

# 拉取
helm pull oci://harbor.internal/helm-charts/vllm-qwen7b --version 1.0.0
```

---

## 与 Kustomize 对比

| 维度 | Helm | Kustomize |
|---|---|---|
| **核心机制** | 模板 + values 参数化 | 原生 YAML overlay（无模板）|
| **学习曲线** | 中等（Go 模板语法）| 低（纯 YAML）|
| **包发布** | ✅ Chart 可打包分发 | ❌ 无打包概念 |
| **环境差异** | values.yaml 覆盖 | kustomization.yaml patch |
| **ArgoCD 支持** | ✅ 原生支持 | ✅ 原生支持 |
| **适合场景** | 复杂服务、需要分发给他人 | 简单配置差异管理 |
| **当前推荐** | ✅ 推荐（和 Harbor 制品仓库配合好）| 暂不采用 |
