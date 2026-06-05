# HAMI GPU 调度规范

> HAMI 已在生产 K8s 集群中使用，本文档规范其使用方式，减少资源争用和调度失败。

---

## 一、节点 Label 规范

所有 GPU 节点必须打以下标签，用于定向调度：

```bash
# 生产 L20 节点
kubectl label node iz2zehh4uj8wuh64pe836tz gpu-type=L20 gpu-count=8 env=prod
kubectl label node llm-l20-20250909        gpu-type=L20 gpu-count=8 env=prod

# 生产 A100 节点
kubectl label node iz2ze8fusva2xt3sjsi0ywz gpu-type=A100 gpu-count=1 env=prod

# pre 节点
kubectl label node worker3 gpu-type=L20 gpu-count=4 env=pre
kubectl label node worker2 gpu-type=L20 gpu-count=4 env=pre
```

---

## 二、资源申请规范

### 显存绝对值（精确控制，推荐）

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    nvidia.com/gpumem: 20000      # 单位 MiB，20 GB
```

### 显存百分比（弹性场景）

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    nvidia.com/gpumem-percentage: 50   # 50% 物理显存
```

### 张量并行多卡（大模型）

```yaml
resources:
  limits:
    nvidia.com/gpu: 2             # 2 张物理 GPU
    nvidia.com/gpumem: 40000      # 每张 40 GB
```

---

## 三、调度亲和性配置

```yaml
# 大模型（>40GB）走 A100
nodeSelector:
  gpu-type: A100

# 多租户推理（vGPU 共享）走 L20
nodeSelector:
  gpu-type: L20

# 只在 pre 环境调度
nodeSelector:
  gpu-type: L20
  env: pre
```

---

## 四、常见调度失败排查

```bash
# 查看 Pod 调度失败原因
kubectl describe pod <pod-name> -n ai-infra | grep -A5 Events

# 查看 HAMI 调度器日志
kubectl logs -n kube-system -l app=hami-scheduler --tail=100

# 查看节点当前 GPU 分配情况
kubectl describe node <gpu-node> | grep -A10 "Allocated resources"

# 查看 HAMI 设备插件状态
kubectl get pods -n kube-system | grep hami
```

---

## 五、禁止规则

| ❌ 禁止 | 原因 |
|---|---|
| 不申请 `nvidia.com/gpumem` 限制 | 进程可无限申请显存，导致 OOM 影响其他服务 |
| 直接在宿主机运行 GPU 进程 | HAMI 无法管理，资源不可见 |
| 申请多余实际需求的 GPU 数量 | 浪费资源，阻塞其他任务调度 |
| 申请 `nvidia.com/gpu: 0` | 语义不明确，用 CPU 服务就不要声明 GPU |
