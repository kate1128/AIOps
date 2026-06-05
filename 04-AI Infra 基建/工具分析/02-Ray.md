# Ray — 分布式 AI 计算框架

> 统一的分布式计算平台，覆盖模型训练、推理调度、超参数搜索和强化学习。

---

## 是什么

Ray 是由 UC Berkeley 开源的分布式 Python 框架，专为 AI/ML 工作负载设计。核心思想是：用简单的 Python API 写代码，Ray 自动把任务分布到集群上运行。**Ray Serve** 专门用于 ML 模型的在线推理服务，**Ray Train** 用于分布式训练。

---

## 核心组件

| 组件 | 功能 |
|---|---|
| **Ray Core** | 基础分布式任务调度，`@ray.remote` 装饰器 |
| **Ray Serve** | 模型推理服务，支持动态批处理、多模型编排 |
| **Ray Train** | 分布式模型训练（PyTorch DDP、DeepSpeed、FSDP）|
| **Ray Tune** | 超参数搜索（自动化调参）|
| **Ray Data** | 大规模数据处理流水线 |
| **Ray Dashboard** | 集群资源和任务可视化 |

---

## ⚠️ 对本项目的评估：当前不建议引入

**现状：** 你们目前主要是在线推理（vLLM 跑 LLM 服务），没有大规模分布式训练需求。

| Ray 的优势场景 | 你们当前的情况 | 结论 |
|---|---|---|
| 多节点分布式训练 | 目前无系统性训练任务 | 暂不需要 |
| 复杂多模型 Pipeline 编排 | 目前以单模型推理为主 | 暂不需要 |
| 超参数搜索 / AutoML | 目前无此需求 | 暂不需要 |
| 大批量数据处理 | 有 RAG 向量化需求，但规模不大 | 用 Celery/简单脚本够用 |

**引入 Ray 的代价：** 额外维护一套 Ray 集群（Head + Worker），增加运维复杂度，在收益不明显时不值得。

**重新评估时机：**
- 有频繁的模型微调需求（每周 + 级别）
- 需要多模型串联的复杂 Pipeline（如 Embedding + Rerank + LLM 三级流水线）
- 批量任务处理量超过单机上限

---

## 适用场景（供参考）

- **分布式训练**：多 GPU / 多节点 PyTorch/DeepSpeed 训练作业
- **推理编排**：多模型串联 Pipeline（Embedding + LLM + Reranker）
- **批量推理**：大批量文档向量化、数据处理
- **超参数搜索**：自动化找最优学习率、批大小等

---

## 与本项目的关系（如未来引入）

```
AI 服务层
    ├── 在线推理（低延迟）：vLLM 直接部署（当前方案）
    └── 复杂 Pipeline：Ray Serve 编排
            │
            ├── Stage 1: Embedding Model（文本向量化）
            ├── Stage 2: LLM（生成回答）
            └── Stage 3: Reranker（结果重排）

训练层（如有需求）
    └── Ray Train + DeepSpeed
            └── 多节点 GPU 并行微调
```

---

## 快速上手（K8s 部署）

```bash
# 安装 KubeRay Operator
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system --create-namespace

# 创建 Ray 集群（values.yaml 形式）
cat <<EOF | kubectl apply -f -
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: ai-ray-cluster
  namespace: ai-infra
spec:
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
    template:
      spec:
        containers:
          - name: ray-head
            image: rayproject/ray-ml:2.9.0-gpu
            resources:
              limits:
                cpu: "4"
                memory: "8Gi"
  workerGroupSpecs:
    - groupName: gpu-workers
      replicas: 2
      template:
        spec:
          containers:
            - name: ray-worker
              image: rayproject/ray-ml:2.9.0-gpu
              resources:
                limits:
                  nvidia.com/gpu: "1"
                  cpu: "8"
                  memory: "32Gi"
          nodeSelector:
            gpu-type: L20
EOF
```

### Ray Serve 多模型 Pipeline

```python
import ray
from ray import serve

ray.init(address="ray://ray-cluster-head:10001")
serve.start()

@serve.deployment(num_replicas=2, ray_actor_options={"num_gpus": 0.5})
class EmbeddingModel:
    def __init__(self):
        from sentence_transformers import SentenceTransformer
        self.model = SentenceTransformer("BAAI/bge-m3")

    async def __call__(self, text: str):
        return self.model.encode(text).tolist()

@serve.deployment(num_replicas=1, ray_actor_options={"num_gpus": 1})
class LLMModel:
    def __init__(self):
        from vllm import AsyncLLMEngine
        self.engine = AsyncLLMEngine.from_engine_args(...)

    async def __call__(self, prompt: str):
        async for output in self.engine.generate(prompt, ...):
            yield output

# 组合成 Pipeline
@serve.deployment
class RAGPipeline:
    def __init__(self, embed, llm):
        self.embed = embed
        self.llm = llm

    async def __call__(self, query: str):
        embedding = await self.embed.remote(query)
        # ... 检索 ...
        return await self.llm.remote(prompt)
```

---

## 与 vLLM 的关系

| 场景 | 推荐方案 |
|---|---|
| 单模型高吞吐在线推理 | vLLM 直接部署（当前方案）|
| 多模型 Pipeline（RAG、Agent）| Ray Serve 编排 + vLLM 推理后端 |
| 分布式微调训练 | Ray Train + DeepSpeed / FSDP |
| 批量数据处理（文档向量化）| Ray Data |

> vLLM 可以作为 Ray Serve 的推理后端，两者是组合关系而非竞争关系。

---

## 与同类工具对比

| 工具 | 定位 | 优势 | 劣势 | 推荐场景 |
|---|---|---|---|---|
| **Ray** | 通用分布式 AI 计算 | 功能全，Python 原生 | 重，学习成本高 | 复杂 AI Pipeline |
| Celery | 任务队列 | 简单，成熟 | 不适合 GPU 任务 | 普通后台任务 |
| Kubeflow | K8s ML 平台 | K8s 原生，流水线完整 | 极重 | 大型 MLOps 平台 |
| Prefect / Airflow | 数据工作流 | 调度好，可视化强 | 不适合 ML 训练 | 数据 ETL 流水线 |

---

## GitHub 信息

- 开源状态：开源（Apache 2.0）
- 仓库地址：https://github.com/ray-project/ray
- Star：42.7k（统计日期：2026-05-27）

---

## 核心组件

| 组件 | 功能 |
|---|---|
| **Ray Core** | 基础分布式任务调度，`@ray.remote` 装饰器 |
| **Ray Serve** | 模型推理服务，支持动态批处理、多模型编排 |
| **Ray Train** | 分布式模型训练（PyTorch DDP、DeepSpeed、FSDP） |
| **Ray Tune** | 超参数搜索（自动化调参） |
| **Ray Data** | 大规模数据处理流水线 |
| **Ray Dashboard** | 集群资源和任务可视化 |

---

## 适用场景

- **分布式训练**：多 GPU / 多节点 PyTorch/DeepSpeed 训练作业
- **推理编排**：多模型串联 Pipeline（Embedding + LLM + Reranker）
- **批量推理**：大批量文档向量化、数据处理
- **超参数搜索**：自动化找最优学习率、批大小等超参数

---

## 与本项目的关系

```
AI 服务层
    ├── 在线推理：vLLM（高吞吐单模型）
    └── 复杂推理 Pipeline：Ray Serve
            │
            ├── Stage 1: Embedding Model（文本向量化）
            ├── Stage 2: LLM（生成回答）
            └── Stage 3: Reranker（结果重排）

训练层
    └── Ray Train + DeepSpeed
            └── 多节点 GPU 并行训练
```

---

## 快速上手

### K8s 部署（KubeRay Operator）

```bash
# 安装 KubeRay Operator
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system --create-namespace

# 创建 Ray 集群
kubectl apply -f - <<EOF
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: ai-ray-cluster
spec:
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
    template:
      spec:
        containers:
          - name: ray-head
            image: rayproject/ray-ml:2.9.0-gpu
            resources:
              limits:
                cpu: "4"
                memory: "8Gi"
  workerGroupSpecs:
    - groupName: gpu-workers
      replicas: 2
      template:
        spec:
          containers:
            - name: ray-worker
              image: rayproject/ray-ml:2.9.0-gpu
              resources:
                limits:
                  nvidia.com/gpu: "1"
                  cpu: "8"
                  memory: "32Gi"
EOF
```

### Ray Serve 多模型 Pipeline

```python
import ray
from ray import serve

ray.init(address="ray://ray-cluster-head:10001")
serve.start()

@serve.deployment(num_replicas=2, ray_actor_options={"num_gpus": 0.5})
class EmbeddingModel:
    def __init__(self):
        from sentence_transformers import SentenceTransformer
        self.model = SentenceTransformer("BAAI/bge-m3")

    async def __call__(self, text: str):
        return self.model.encode(text).tolist()

@serve.deployment(num_replicas=1, ray_actor_options={"num_gpus": 1})
class LLMModel:
    def __init__(self):
        from vllm import AsyncLLMEngine
        self.engine = AsyncLLMEngine.from_engine_args(...)

    async def __call__(self, prompt: str):
        # 推理逻辑
        pass

# 部署
embedding_handle = EmbeddingModel.bind()
llm_handle = LLMModel.bind()
```

---

## 与 vLLM 的关系

| 场景 | 推荐方案 |
|---|---|
| 单模型高吞吐在线推理 | vLLM 直接部署 |
| 多模型 Pipeline（RAG、Agent） | Ray Serve 编排 + vLLM 作为推理后端 |
| 分布式训练 | Ray Train + DeepSpeed / FSDP |
| 批量数据处理 | Ray Data |

> vLLM 可以作为 Ray Serve 的推理后端，两者组合而非竞争。

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/ray-project/ray
- Star：42.7k（统计日期：2026-05-27）

