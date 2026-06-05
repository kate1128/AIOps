# LMDeploy — 国产 LLM 推理部署框架

> 专为国产大语言模型（Qwen、InternLM）深度优化的推理引擎，吞吐量和显存效率均优于 vLLM 在国产模型上的表现。

---

## 是什么

LMDeploy 是上海 AI 实验室（InternLM 团队）开源的大语言模型推理和部署工具包，提供 TurboMind 推理引擎和 PyTorch 后端两种选择。TurboMind 基于 FasterTransformer 和 TensorRT 深度优化，对 Qwen、InternLM 等国产模型性能远超通用推理框架。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **TurboMind 引擎** | C++ 实现，针对国产模型 kernel 级优化，吞吐远超 vLLM |
| **Continuous Batching** | 连续批处理，高并发场景性能优秀 |
| **W4A16 量化（AWQ）** | 内置量化工具，4bit 量化精度损失极小 |
| **KV Cache 量化（KV8）** | KV Cache 也可 8bit 量化，进一步节省显存 |
| **多模态支持** | 支持 InternVL、Qwen-VL 等多模态模型 |
| **OpenAI 兼容接口** | 同 vLLM，可直接替换 |
| **Prefix Caching** | System Prompt 缓存 |
| **张量并行** | 多卡推理 |

---

## 与本项目的关系

你们已在用 vLLM，LMDeploy 是**针对 Qwen 系列模型的增强替代选项**，两者不冲突：

```
模型推理层
    ├── vLLM（通用，多模型统一接口）
    └── LMDeploy TurboMind（Qwen/InternLM 高性能场景）
            │
            ├── 适合：Qwen2.5-7B/14B/32B 高并发在线推理
            ├── 适合：多模态 Qwen-VL 推理
            └── 适合：L20 节点 AWQ + KV8 双量化节省显存
```

---

## 性能对比（Qwen2.5-7B，L20，并发 64）

| 指标 | vLLM | LMDeploy TurboMind | 说明 |
|---|---|---|---|
| Throughput（tokens/s）| ~3500 | ~5200 | LMDeploy 约快 48% |
| 显存占用（FP16）| ~18GB | ~16GB | LMDeploy 更省 |
| 量化后显存（AWQ）| ~10GB | ~8GB | LMDeploy AWQ 更紧凑 |
| 首 Token 延迟 P99 | 中 | 低 | LMDeploy 更优 |

> 数据来源：社区 benchmark，实际数字因场景和模型版本有差异，建议自行实测。

---

## 安装

```bash
pip install lmdeploy

# 或 Docker
docker pull openmmlab/lmdeploy:latest-cu12
```

---

## 快速启动

### Docker 启动推理服务（OpenAI 兼容接口）

```bash
# FP16 模式
docker run --gpus '"device=0"' \
  -v /data/models:/models \
  -p 23333:23333 \
  openmmlab/lmdeploy:latest-cu12 \
  lmdeploy serve api_server /models/Qwen2.5-7B-Instruct \
  --server-port 23333 \
  --tp 1

# AWQ 量化模式（L20 推荐，约 8GB 显存）
docker run --gpus '"device=0"' \
  -v /data/models:/models \
  -p 23333:23333 \
  openmmlab/lmdeploy:latest-cu12 \
  lmdeploy serve api_server /models/Qwen2.5-7B-Instruct-AWQ \
  --server-port 23333 \
  --model-format awq
```

### K8s Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lmdeploy-qwen25-7b
  namespace: ai-infra
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lmdeploy-qwen25-7b
  template:
    metadata:
      labels:
        app: lmdeploy-qwen25-7b
        team: ai-infra
        service: llm-inference
    spec:
      nodeSelector:
        gpu-type: L20
      containers:
        - name: lmdeploy
          image: openmmlab/lmdeploy:latest-cu12
          command:
            - lmdeploy
            - serve
            - api_server
            - /models/Qwen2.5-7B-Instruct
            - --server-port=23333
            - --tp=1
            - --cache-max-entry-count=0.9
          ports:
            - containerPort: 23333
          resources:
            limits:
              nvidia.com/gpu: "1"
              nvidia.com/gpumem: "20000"    # HAMI 显存限制
          volumeMounts:
            - name: model-storage
              mountPath: /models
          readinessProbe:
            httpGet:
              path: /v1/models
              port: 23333
            initialDelaySeconds: 60
            periodSeconds: 10
      volumes:
        - name: model-storage
          persistentVolumeClaim:
            claimName: nfs-models-pvc
```

---

## 量化工具

### 离线 AWQ 量化（减少显存占用 ~50%）

```bash
# 量化 Qwen2.5-14B（FP16 约 28GB → AWQ 约 9GB）
lmdeploy lite auto_awq \
  /models/Qwen2.5-14B-Instruct \
  --calib-dataset ptb \
  --calib-samples 128 \
  --calib-seqlen 2048 \
  --w-bits 4 \
  --w-group-size 128 \
  --work-dir /models/Qwen2.5-14B-Instruct-AWQ
```

### KV Cache 量化（进一步节省显存）

```bash
# 收集 KV 统计（用于 KV8 量化校准）
lmdeploy lite calibrate \
  /models/Qwen2.5-7B-Instruct \
  --calib-dataset ptb \
  --work-dir /models/Qwen2.5-7B-kv-calib

# 启动时开启 KV8 量化
lmdeploy serve api_server /models/Qwen2.5-7B-Instruct \
  --quant-policy 8    # 0=不量化，4=KV4，8=KV8
```

---

## 多模态推理（Qwen-VL）

```bash
# Qwen2-VL 多模态推理
lmdeploy serve api_server /models/Qwen2-VL-7B-Instruct \
  --server-port 23333 \
  --tp 1

# 测试图文问答
curl http://localhost:23333/v1/chat/completions \
  -d '{
    "model": "Qwen2-VL-7B-Instruct",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}},
        {"type": "text", "text": "描述这张图片"}
      ]
    }]
  }'
```

---

## vLLM vs LMDeploy 选型建议

| 维度 | vLLM | LMDeploy |
|---|---|---|
| **模型覆盖** | 极广（几乎所有主流模型）| 国产模型更好（Qwen/InternLM/DeepSeek）|
| **Qwen 性能** | 好 | **更好**（TurboMind 深度优化）|
| **多模态** | 支持（有限）| **更好**（InternVL/Qwen-VL 优先支持）|
| **量化工具** | 加载已量化模型 | **内置量化工具**（AWQ + KV8）|
| **社区生态** | 最大 | 较小，但增长快 |
| **运维复杂度** | 低 | 中（TurboMind 配置项较多）|

**推荐策略：**
- **默认用 vLLM**：部署简单、生态广、已在生产跑
- **高并发 Qwen 场景考虑 LMDeploy**：Qwen 14B+ 高并发时 TurboMind 吞吐优势明显
- **双框架混跑**：A/B 实测，哪个性能好用哪个

---

## GitHub 信息

- 开源状态：开源（Apache 2.0）
- 仓库地址：https://github.com/InternLM/lmdeploy
- Star：6.2k（统计日期：2026-05-27）
