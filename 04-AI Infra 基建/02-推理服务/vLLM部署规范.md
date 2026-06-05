# vLLM 推理服务部署规范

> 标准化 vLLM 服务的 K8s 部署方式，消灭宿主机裸进程。

---

## 一、单卡部署模板（L20，7B/14B 模型）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-qwen-7b
  namespace: ai-infra
  labels:
    app: vllm-qwen-7b
    team: ai-infra
    service: llm-inference
    model: qwen2-7b
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vllm-qwen-7b
  template:
    metadata:
      labels:
        app: vllm-qwen-7b
    spec:
      nodeSelector:
        gpu-type: L20
        env: prod
      containers:
        - name: vllm
          image: vllm/vllm-openai:v0.6.0
          args:
            - --model=/models/Qwen2-7B
            - --tensor-parallel-size=1
            - --max-model-len=8192
            - --served-model-name=qwen2-7b
            - --host=0.0.0.0
            - --port=8000
          ports:
            - containerPort: 8000
          resources:
            limits:
              nvidia.com/gpu: 1
              nvidia.com/gpumem: 20000    # 20 GB 显存上限
              cpu: "4"
              memory: "16Gi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 120      # 模型加载需要时间
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 180
            periodSeconds: 30
          volumeMounts:
            - name: model-storage
              mountPath: /models
              readOnly: true
      volumes:
        - name: model-storage
          persistentVolumeClaim:
            claimName: models-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: vllm-qwen-7b
  namespace: ai-infra
spec:
  selector:
    app: vllm-qwen-7b
  ports:
    - port: 8000
      targetPort: 8000
```

---

## 二、张量并行部署模板（A100，70B+ 模型）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-qwen-72b
  namespace: ai-infra
spec:
  replicas: 1
  template:
    spec:
      nodeSelector:
        gpu-type: A100
      containers:
        - name: vllm
          image: vllm/vllm-openai:v0.6.0
          args:
            - --model=/models/Qwen2-72B
            - --tensor-parallel-size=2    # 需要 2 张 A100
            - --max-model-len=4096
          resources:
            limits:
              nvidia.com/gpu: 2
              nvidia.com/gpumem: 75000    # 每张 75 GB，留 5 GB buffer
```

---

## 三、版本管理规范

| 项目 | 规范 |
|---|---|
| 镜像版本 | 锁定具体版本号（如 `v0.6.0`），禁用 `latest` |
| 模型路径 | 挂载 PVC，路径格式 `/models/{ModelName}-{Size}/` |
| 服务命名 | `vllm-{model-family}-{size}`，如 `vllm-qwen-7b` |
| 资源限制 | 必须设置 `nvidia.com/gpumem`，禁止不设上限 |

---

## 四、健康检查与监控

vLLM 内置 `/metrics` Prometheus 端点，需接入 Prometheus：

```yaml
# ServiceMonitor（需要 kube-prometheus-stack）
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm-qwen-7b
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: vllm-qwen-7b
  endpoints:
    - port: "8000"
      path: /metrics
      interval: 30s
```

关键指标：
- `vllm:request_success_total` — 推理成功数
- `vllm:request_latency_seconds` — P99 推理延迟
- `vllm:gpu_cache_usage_perc` — KV Cache 使用率（超 90% 影响吞吐）

---

## 五、回滚操作

```bash
# 查看历史版本
kubectl rollout history deployment/vllm-qwen-7b -n ai-infra

# 回滚到上一版本
kubectl rollout undo deployment/vllm-qwen-7b -n ai-infra

# 回滚到指定版本
kubectl rollout undo deployment/vllm-qwen-7b --to-revision=2 -n ai-infra
```
