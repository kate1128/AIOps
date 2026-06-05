# HAMI — K8s GPU 虚拟化调度器

> 让多个 Pod 共享同一张 GPU，实现细粒度显存和算力分配。
> **本项目已在生产使用**（L20 × 16 + A100 × 2 均通过 HAMI 管理）。

---

## 是什么

HAMI（Heterogeneous AI Computing Virtualization Middleware）是 CNCF Sandbox 项目，原名 k8s-vGPU-scheduler，由华为云开源。它在 Kubernetes 上实现 GPU 虚拟化，允许多个 Pod 按显存/算力配额共享同一张物理 GPU，并支持 NVIDIA、Cambricon（寒武纪）、Hygon（海光）等异构 GPU。

**核心价值：** 一张 L20 46GB 的 GPU 可以同时运行多个 vLLM 或 Python 推理进程，每个进程使用指定的显存上限，互不影响。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **GPU 显存虚拟化** | 按 MiB 或百分比限制容器可用显存上限 |
| **GPU 算力限制** | 限制容器可用的 GPU 核心算力百分比 |
| **多 GPU 支持** | NVIDIA / Cambricon / Hygon / Iluvatar / Volcano 等 |
| **K8s 原生集成** | 通过 Device Plugin + Scheduler Extender 实现 |
| **动态分配** | 无需重启，可动态调整 GPU 配额 |
| **Metrics 导出** | 支持 Prometheus 监控各 vGPU 使用情况 |

---

## 与本项目的关系

```
K8s 调度器
    │
    └── HAMI Scheduler Extender（GPU 分配决策）
            │
            ├── L20 节点（46GB × 8）
            │       ├── Pod A：限制 20GB + 50% 算力（vLLM 实例）
            │       ├── Pod B：限制 10GB + 30% 算力（嵌入模型）
            │       └── Pod C：限制 5GB + 20% 算力（小模型）
            │
            └── A100 节点（80GB × 1）
                    └── Pod D：限制 70GB + 100% 算力（大模型独占）
```

---

## 安装

```bash
# Helm 安装（推荐方式）
helm repo add hami-charts https://project-hami.github.io/HAMi/
helm repo update

helm install hami hami-charts/hami \
  --namespace kube-system \
  --set scheduler.kubeScheduler.imageTag=v1.28.4 \   # 对应集群版本
  --set devicePlugin.nvidiaGPU.enabled=true

# 验证安装
kubectl get pods -n kube-system | grep hami
kubectl get node <gpu-node> -o json | jq '.status.allocatable'
# 应看到 nvidia.com/gpu 等资源
```

### 与 K8s 版本对应

| HAMI 版本 | 支持 K8s 版本 |
|---|---|
| v2.3.x | K8s 1.22 ~ 1.28 |
| v2.4.x | K8s 1.24 ~ 1.30 |

> **注意：** 你们生产集群 v1.20.1 对应需要使用较旧的 HAMI 版本，升级 K8s 时需同步确认 HAMI 兼容性。

---

## 使用规范

### 申请 GPU 资源的三种方式

```yaml
# 方式 1：申请整张 GPU（传统方式，不经过 HAMI 虚拟化）
resources:
  limits:
    nvidia.com/gpu: "1"

# 方式 2：指定显存上限（MiB），推荐
resources:
  limits:
    nvidia.com/gpu: "1"
    nvidia.com/gpumem: "20000"       # 限制最多使用 20GB 显存

# 方式 3：指定显存百分比
resources:
  limits:
    nvidia.com/gpu: "1"
    nvidia.com/gpumem-percentage: "50"    # 使用该卡 50% 显存

# 方式 4：同时限制显存和算力
resources:
  limits:
    nvidia.com/gpu: "1"
    nvidia.com/gpumem: "15000"
    nvidia.com/gpucores: "30"        # 限制 30% GPU 算力（0~100）
```

### 指定 GPU 型号调度

```yaml
# 只调度到 L20 节点
nodeSelector:
  gpu-type: L20

# 或通过 HAMI 的 GPU 型号选择（无需 nodeSelector）
env:
  - name: GPU_PRODUCT
    value: "NVIDIA-L20"
```

---

## 典型部署场景

### 场景 1：多 vLLM 实例共享一张 L20

```yaml
# vLLM 实例 A（Qwen 7B，约 16GB 显存）
resources:
  limits:
    nvidia.com/gpu: "1"
    nvidia.com/gpumem: "18000"    # 限制 18GB

# vLLM 实例 B（嵌入模型，约 4GB 显存）
resources:
  limits:
    nvidia.com/gpu: "1"
    nvidia.com/gpumem: "5000"     # 限制 5GB

# 两个实例可以共享同一张 46GB L20，剩余约 23GB 供其他任务
```

### 场景 2：A100 独占大模型

```yaml
# Qwen 70B 需要 ~70GB 显存，独占 A100
resources:
  limits:
    nvidia.com/gpu: "1"
    nvidia.com/gpumem: "75000"    # 接近 A100 全量 80GB
```

---

## 监控 HAMI 分配情况

```bash
# 查看节点 GPU 分配情况
kubectl describe node llm-l20-20250909 | grep -A 10 "Allocated resources"

# 查看 HAMI 虚拟 GPU 使用率（Prometheus 指标）
# 安装 hami-device-exporter 后可采集以下指标：
# hami_container_gpu_utilization    # 容器 GPU 算力使用率
# hami_container_gpu_memory_used    # 容器 GPU 显存使用量（MiB）
# hami_container_gpu_memory_limit   # 容器 GPU 显存配额（MiB）
```

**Prometheus 告警规则：**

```yaml
- alert: HamiGpuMemoryExceeding
  expr: hami_container_gpu_memory_used / hami_container_gpu_memory_limit > 0.95
  for: 3m
  labels:
    severity: warning
  annotations:
    summary: "容器 {{ $labels.pod_name }} GPU 显存使用率超过 95%"
```

---

## 常见问题

**Q: Pod 一直 Pending，提示 Insufficient nvidia.com/gpu？**
```bash
# 检查节点是否正确注册了 HAMI 资源
kubectl describe node <gpu-node> | grep nvidia.com
# 检查 HAMI Device Plugin 是否正常运行
kubectl get pods -n kube-system | grep hami-device-plugin
kubectl logs -n kube-system <hami-device-plugin-pod>
```

**Q: 多个 Pod 共享 GPU 后出现 OOM？**
```bash
# HAMI 的显存限制是软限制，进程可能突破限制
# 解决方案：降低每个 Pod 的 gpumem 配额，留出缓冲
# 或开启 HAMI 的 GPU 显存硬隔离模式（需 Driver 560+）
```

**Q: 升级 K8s 后 HAMI 不工作？**
```bash
# 需要同步升级 HAMI，特别注意 scheduler image tag 对应 K8s 版本
helm upgrade hami hami-charts/hami \
  --set scheduler.kubeScheduler.imageTag=v1.28.4
```

---

## 与同类 GPU 虚拟化方案对比

| 方案 | 原理 | 隔离强度 | 支持硬件 | 推荐场景 |
|---|---|---|---|---|
| **HAMI** | K8s Device Plugin + 拦截层 | 软隔离 | NVIDIA + 国产 GPU | **已在用，推荐** |
| NVIDIA MIG | 硬件级切分（固定规格）| 硬隔离 | 仅 A100/H100/A30 | A100 独占场景 |
| NVIDIA MPS | 多进程共享 CUDA context | 中等 | 仅 NVIDIA | 低延迟多进程 |
| GPU Operator | 管理 Driver/Device Plugin | 不提供虚拟化 | NVIDIA | 简化 NVIDIA 组件部署 |
| 趋动科技 OrionX | 用户态拦截 | 软隔离 | NVIDIA | 商业方案，功能更强 |

---

## GitHub 信息

- 开源状态：开源（Apache 2.0，CNCF Sandbox）
- 仓库地址：https://github.com/Project-HAMi/HAMi
- Star：3.4k（统计日期：2026-05-27）
