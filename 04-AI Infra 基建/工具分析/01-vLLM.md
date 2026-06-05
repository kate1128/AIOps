# vLLM — 高吞吐 LLM 推理引擎

> 基于 PagedAttention 的高性能大语言模型推理框架，是生产级 LLM 服务的首选引擎。
> **本项目已在生产使用**（生产 4 个 GPU 节点均有 VLLM::EngineCore 进程运行）。

---

## 是什么

vLLM 是由 UC Berkeley 开源的 LLM 推理服务引擎，核心创新是 **PagedAttention** 内存管理技术——像操作系统管理虚拟内存一样管理 KV Cache，大幅提升 GPU 显存利用率和并发吞吐量。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **PagedAttention** | KV Cache 分页管理，显存利用率提升 3-5x |
| 连续批处理（Continuous Batching）| 动态合并请求，不等全批完成就处理新请求 |
| OpenAI 兼容 API | 直接替换 OpenAI API，无需修改客户端代码 |
| 多 GPU / 张量并行 | 支持单机多卡（TP）和跨机流水线并行（PP）|
| 量化支持 | AWQ、GPTQ、FP8、BitsAndBytes，降低显存需求 |
| 流式输出 | SSE Streaming，降低 TTFT |
| LoRA 动态加载 | 多个 LoRA 适配器共享底座，运行时切换 |
| Prefix Caching | System Prompt 缓存，重复前缀零推理开销 |
| Chunked Prefill | 将长 Prefill 切片处理，减少排队延迟 |
| 投机采样（Speculative Decoding）| 小模型辅助大模型加速解码，提升吞吐 |

---

## 与本项目的关系

```
用户请求
    │
    └── Nginx Ingress / APISIX（限流 + 鉴权）
            │
            └── vLLM Server（OpenAI 兼容接口）
                    │
                    ├── 模型：Qwen2.5 / DeepSeek / 其他
                    ├── 硬件：L20（46GB）× 8 / A100（80GB）
                    ├── HAMI（GPU 显存虚拟化调度）
                    └── DCGM Exporter ──→ Prometheus ──→ Grafana
```

---

## 部署方式

### Docker 启动（当前方式）

```bash
# 基础单卡启动
docker run --runtime nvidia --gpus '"device=0"' \
  -v /data/models:/models \
  -p 8000:8000 \
  --name vllm-qwen-7b \
  vllm/vllm-openai:v0.6.0 \
  --model /models/Qwen2.5-7B-Instruct \
  --served-model-name qwen2.5-7b \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --tensor-parallel-size 1

# 多卡张量并行（大模型，如 70B 用 2 张 A100）
docker run --runtime nvidia --gpus '"device=0,1"' \
  -v /data/models:/models \
  -p 8000:8000 \
  vllm/vllm-openai:v0.6.0 \
  --model /models/Qwen2.5-72B-Instruct \
  --tensor-parallel-size 2 \
  --max-model-len 16384 \
  --gpu-memory-utilization 0.95
```

### K8s Deployment（推荐标准化后使用）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-qwen25-7b
  namespace: ai-infra
  labels:
    app: vllm-qwen25-7b
    team: ai-infra
    gpu-type: L20
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vllm-qwen25-7b
  template:
    metadata:
      labels:
        app: vllm-qwen25-7b
    spec:
      nodeSelector:
        gpu-type: L20
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
      containers:
        - name: vllm
          image: vllm/vllm-openai:v0.6.0
          args:
            - "--model=/models/Qwen2.5-7B-Instruct"
            - "--served-model-name=qwen2.5-7b"
            - "--tensor-parallel-size=1"
            - "--max-model-len=8192"
            - "--gpu-memory-utilization=0.90"
            - "--enable-prefix-caching"     # 开启 Prefix Cache
          ports:
            - containerPort: 8000
          resources:
            limits:
              nvidia.com/gpu: "1"
              nvidia.com/gpumem: "30000"    # HAMI：限制 30GB 显存
          volumeMounts:
            - name: model-storage
              mountPath: /models
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 90         # 等模型加载
            periodSeconds: 10
            failureThreshold: 12
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 120
            periodSeconds: 30
      volumes:
        - name: model-storage
          persistentVolumeClaim:
            claimName: nfs-models-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: vllm-qwen25-7b
  namespace: ai-infra
spec:
  selector:
    app: vllm-qwen25-7b
  ports:
    - port: 8000
      targetPort: 8000
```

---

## 量化方案选型

> 当前生产 L20 每卡 46GB，A100 80GB，量化可以显著扩大并发能力。

| 量化方式 | 显存节省 | 精度损失 | 推理速度 | 推荐场景 |
|---|---|---|---|---|
| FP16（默认）| - | 无 | 基准 | 精度优先 |
| BF16 | 同 FP16 | 极小 | 略快 | L20/A100 优先 BF16 |
| AWQ（W4A16）| ~50% | 极小 | 快 | **推荐：L20 跑 7B/14B** |
| GPTQ（W4A16）| ~50% | 小 | 快 | 社区预量化模型多 |
| FP8（W8A8）| ~50% | 极小 | 最快 | A100/H100 原生支持 |

```bash
# 使用 AWQ 量化模型（L20 节点推荐）
docker run ... vllm/vllm-openai:v0.6.0 \
  --model /models/Qwen2.5-14B-Instruct-AWQ \
  --quantization awq \
  --gpu-memory-utilization 0.90

# FP8 量化（A100 节点）
docker run ... vllm/vllm-openai:v0.6.0 \
  --model /models/Qwen2.5-7B-Instruct \
  --quantization fp8 \
  --gpu-memory-utilization 0.90
```

---

## LoRA 多适配器热加载

> 一个底座模型 + 多个领域 LoRA，共享 GPU 显存，按请求切换。

```bash
# 启动时开启 LoRA 支持
vllm serve /models/Qwen2.5-7B \
  --enable-lora \
  --max-loras 4 \           # 最多同时加载 4 个 LoRA
  --max-lora-rank 64

# 请求时指定 LoRA
curl http://localhost:8000/v1/completions \
  -d '{
    "model": "qwen-finance-v2",   # LoRA 名称
    "prompt": "...",
    "max_tokens": 512
  }'

# 动态加载新 LoRA（无需重启）
curl http://localhost:8000/v1/load_lora_adapter \
  -d '{"lora_name": "qwen-finance-v2", "lora_path": "/models/lora/finance-v2"}'
```

---

## 关键监控指标

```promql
# 推理吞吐量（tokens/s）
rate(vllm:generation_tokens_total[1m])

# GPU KV Cache 使用率（接近 1 时需扩容或优化）
vllm:gpu_cache_usage_perc

# 请求队列积压
vllm:num_requests_waiting

# TTFT P99（Time To First Token）
histogram_quantile(0.99, rate(vllm:time_to_first_token_seconds_bucket[5m]))

# ITL P99（流式输出 token 间隔延迟）
histogram_quantile(0.99, rate(vllm:time_per_output_token_seconds_bucket[5m]))

# 当前并发请求数
vllm:num_requests_running
```

**Grafana Dashboard：** 社区提供官方 Dashboard，ID `21766`，直接导入。

---

## 生产配置建议

| 场景 | 推荐参数 |
|---|---|
| L20 + 7B 模型 | `--gpu-memory-utilization 0.90 --max-model-len 8192` |
| L20 + 14B AWQ | `--quantization awq --gpu-memory-utilization 0.90` |
| A100 + 70B 双卡 | `--tensor-parallel-size 2 --gpu-memory-utilization 0.92` |
| 长上下文场景 | `--enable-chunked-prefill --max-num-batched-tokens 4096` |
| 多租户/多 LoRA | `--enable-lora --max-loras 4 --enable-prefix-caching` |

---

## 常见问题

**Q: OOM Killed 怎么排查？**
```bash
# 降低 gpu-memory-utilization（从 0.9 降到 0.85）
# 或减小 max-model-len
# 用 HAMI 限制显存上限：nvidia.com/gpumem: "20000"
```

**Q: 请求延迟高？**
```bash
# 查看队列积压
curl http://vllm:8000/metrics | grep vllm:num_requests_waiting
# 队列积压说明并发超过处理能力，需要扩容或增加实例
```

**Q: 模型加载慢？**
```bash
# 使用模型缓存（--download-dir 指向 NFS 挂载路径）
# 或在节点本地预先下载模型，用 hostPath 挂载
```

---

## 选型对比

| 引擎 | 吞吐量 | 国产模型支持 | 适用场景 |
|---|---|---|---|
| **vLLM** | 最高 | 好（Qwen/DeepSeek 等官方支持）| **生产首选** |
| LMDeploy | 高 | 最好（专门优化 Qwen/InternLM）| 国产模型深度优化 |
| TGI | 高 | 一般 | HuggingFace 生态快速接入 |
| Triton Inference Server | 高 | 一般 | NVIDIA 全栈，多框架 |
| Ollama | 低 | 好 | 本地开发调试 |

---

## GitHub 信息

- 开源状态：开源（Apache 2.0）
- 仓库地址：https://github.com/vllm-project/vllm
- Star：81.1k（统计日期：2026-05-27）

