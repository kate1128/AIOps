# MLflow — 模型实验追踪与模型注册中心

> 记录每次训练实验的参数、指标、模型文件，管理模型的完整生命周期。

---

## 是什么

MLflow 是开源的 MLOps 平台，核心功能是**实验追踪**（谁训练了什么、用了什么参数、结果如何）和**模型注册**（哪个版本在生产环境）。它解决了 AI 研发中常见的"这个模型是怎么训出来的？""生产用的哪个版本？"等问题。

---

## 核心能力

| 组件 | 功能 |
|---|---|
| **MLflow Tracking** | 记录训练实验：参数、指标、Artifacts（模型文件）|
| **MLflow Projects** | 打包可复现的训练代码（conda/docker 环境）|
| **MLflow Models** | 统一模型格式，支持多框架（PyTorch、TF、sklearn）|
| **MLflow Registry** | 模型版本管理，Staging/Production/Archived 状态 |
| **MLflow UI** | 可视化对比多次实验结果 |

---

## ⚠️ 对本项目的评估：按需引入

**现状：** 当前生产环境主要是 vLLM 加载开源/微调模型做推理，没有频繁的训练和实验迭代需求。

**是否需要 MLflow 取决于：**

| 场景 | 是否需要 |
|---|---|
| 直接加载开源模型（Qwen/DeepSeek），无微调 | ❌ 不需要 |
| 偶尔做一次性微调，手动管理模型文件 | ⚠️ 可用，但不强依赖 |
| 频繁微调（不同数据集、不同超参实验对比）| ✅ 强烈推荐 |
| 多人协作训练，需要知道"谁训的、用什么数据"| ✅ 推荐 |
| 需要模型版本管理（Staging → Production 流转）| ✅ 推荐 |

**当前最小需求：** 如果只是模型版本管理（哪个模型文件对应哪个版本），用命名规范 + NFS 目录结构就够，不一定需要 MLflow。

---

## 与本项目的关系（如引入）

```
训练脚本（本地 / K8s Job）
    │
    └── MLflow Tracking（记录每次实验）
            │
            ├── 参数：learning_rate, batch_size, epochs, dataset
            ├── 指标：train_loss, eval_loss, BLEU, ROUGE
            └── Artifacts：模型权重 ──→ 存到 NFS 或 MinIO
                                │
                                └── MLflow Registry（版本管理）
                                        │
                                        ├── Staging（预发布验证）
                                        └── Production ──→ vLLM 加载
```

---

## 部署

### Docker 部署（接 PostgreSQL + MinIO / NFS）

```yaml
# docker-compose.yml
services:
  mlflow:
    image: ghcr.io/mlflow/mlflow:v2.14.0
    command: >
      mlflow server
      --backend-store-uri postgresql://mlflow:password@postgres:5432/mlflow
      --default-artifact-root s3://mlflow-artifacts/
      --host 0.0.0.0
      --port 5000
    environment:
      MLFLOW_S3_ENDPOINT_URL: http://minio:9000    # 用 MinIO 替代 S3
      AWS_ACCESS_KEY_ID: minioadmin
      AWS_SECRET_ACCESS_KEY: minioadmin
    ports:
      - "5000:5000"
    depends_on:
      - postgres
      - minio

  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: mlflow
      POSTGRES_USER: mlflow
      POSTGRES_PASSWORD: password
    volumes:
      - pgdata:/var/lib/postgresql/data

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes:
      - minio-data:/data
    ports:
      - "9000:9000"
      - "9001:9001"

volumes:
  pgdata:
  minio-data:
```

> 如果不想引入 MinIO，也可以用 NFS 路径：`--default-artifact-root /mnt/nfs/mlflow-artifacts/`

### K8s 部署

```bash
helm repo add community-charts https://community-charts.github.io/helm-charts
helm install mlflow community-charts/mlflow \
  --namespace ai-infra \
  --set backendStore.postgres.enabled=true \
  --set backendStore.postgres.host=postgres.middleware.svc \
  --set artifactRoot.s3.enabled=true \
  --set artifactRoot.s3.bucket=mlflow \
  --set artifactRoot.s3.endpointUrl=http://minio.storage.svc:9000
```

---

## 训练代码接入

```python
import mlflow
import mlflow.pytorch

mlflow.set_tracking_uri("http://mlflow.ai-infra.svc:5000")
mlflow.set_experiment("qwen-finetune-v1")

with mlflow.start_run(run_name="lr-3e-4-bs-32"):
    # 记录超参数
    mlflow.log_params({
        "learning_rate": 3e-4,
        "batch_size": 32,
        "epochs": 3,
        "base_model": "Qwen2.5-7B",
        "dataset": "finance-qa-v2",
        "gpu": "L20",
    })

    for epoch in range(3):
        train_loss = train_one_epoch(...)
        eval_loss = evaluate(...)
        mlflow.log_metrics({
            "train_loss": train_loss,
            "eval_loss": eval_loss,
        }, step=epoch)

    # 保存模型到 Registry
    mlflow.pytorch.log_model(model, "model")
    mlflow.register_model(
        f"runs:/{mlflow.active_run().info.run_id}/model",
        "qwen-finance-finetune"
    )
```

### 模型版本状态流转

```python
from mlflow import MlflowClient
client = MlflowClient()

# Staging 验证
client.transition_model_version_stage(
    name="qwen-finance-finetune",
    version=3,
    stage="Staging"
)

# 生产上线
client.transition_model_version_stage(
    name="qwen-finance-finetune",
    version=3,
    stage="Production"
)
```

---

## 与 CI/CD 集成

```yaml
# .gitlab-ci.yml 模型发布 stage
deploy-model:
  stage: deploy
  script:
    # 从 MLflow Registry 拉取 Production 模型到 NFS
    - python scripts/pull_model_from_registry.py --stage Production --dest /mnt/nfs/models/
    # 更新 vLLM Deployment 的模型路径
    - kubectl set env deployment/vllm -n ai-infra MODEL_PATH=/models/qwen-finance-v3
    - kubectl rollout restart deployment/vllm -n ai-infra
    - kubectl rollout status deployment/vllm -n ai-infra
```

---

## 轻量替代方案

> 如果只需要模型版本管理，不需要完整的实验追踪，可以用更简单的方式：

```
# NFS 目录规范替代模型注册中心
/models/
├── qwen2.5-7b/
│   ├── base/           # 原始模型
│   └── finetune/
│       ├── v1-20250101/   # 带版本+日期
│       ├── v2-20250215/
│       └── prod -> v2-20250215/  # 软链接指向生产版本
└── deepseek-v3/
    └── base/
```

vLLM 加载时指向软链接 `/models/qwen2.5-7b/finetune/prod/`，升级时只需更新软链接。

---

## 与同类工具对比

| 工具 | 定位 | 优势 | 劣势 | 推荐场景 |
|---|---|---|---|---|
| **MLflow** | 实验追踪 + 模型注册 | 开源、轻量、易上手 | 可视化相对基础 | **首选，通用场景** |
| Weights & Biases | 实验追踪为主 | 可视化最好，协作功能强 | 云端付费，私有化复杂 | 大团队、重视可视化 |
| DVC | 数据 + 模型版本管理 | 与 Git 深度集成 | 不做实验追踪 | 数据集版本管理 |
| BentoML | 模型服务打包 | 推理服务打包部署好 | 不做实验追踪 | 推理侧，不是训练侧 |
| Aim | 实验追踪 | 本地化，性能好 | 生态较小 | 轻量替代 W&B |

---

## GitHub 信息

- 开源状态：开源（Apache 2.0）
- 仓库地址：https://github.com/mlflow/mlflow
- Star：26.1k（统计日期：2026-05-27）

---

## 核心能力

| 组件 | 功能 |
|---|---|
| **MLflow Tracking** | 记录训练实验：参数、指标、Artifacts（模型文件）|
| **MLflow Projects** | 打包可复现的训练代码（conda/docker 环境） |
| **MLflow Models** | 统一模型格式，支持多框架（PyTorch、TF、sklearn）|
| **MLflow Registry** | 模型版本管理，Staging/Production/Archived 状态 |
| **MLflow UI** | 可视化对比多次实验结果 |

---

## 与本项目的关系

```
训练脚本
    │
    └── MLflow Tracking（记录每次实验）
            │
            ├── 参数：learning_rate, batch_size, epochs
            ├── 指标：train_loss, eval_loss, BLEU, ROUGE
            └── Artifacts：模型权重文件 ──→ 存储到 MinIO/S3
                                │
                                └── MLflow Registry（版本管理）
                                        │
                                        ├── Staging（预发布验证）
                                        └── Production ──→ 部署到 vLLM
```

---

## 快速部署

### Docker 部署（接 PostgreSQL + MinIO）

```yaml
# docker-compose.yml
services:
  mlflow:
    image: ghcr.io/mlflow/mlflow:v2.10.0
    command: >
      mlflow server
      --backend-store-uri postgresql://mlflow:password@postgres/mlflow
      --default-artifact-root s3://mlflow-artifacts/
      --host 0.0.0.0
      --port 5000
    environment:
      MLFLOW_S3_ENDPOINT_URL: http://minio:9000
      AWS_ACCESS_KEY_ID: minioadmin
      AWS_SECRET_ACCESS_KEY: minioadmin
    ports:
      - "5000:5000"
```

### 训练代码接入

```python
import mlflow
import mlflow.pytorch

mlflow.set_tracking_uri("http://mlflow.example.com:5000")
mlflow.set_experiment("qwen-finetune-v1")

with mlflow.start_run(run_name="lr-3e-4-bs-32"):
    # 记录超参数
    mlflow.log_params({
        "learning_rate": 3e-4,
        "batch_size": 32,
        "epochs": 3,
        "base_model": "Qwen2.5-7B",
        "dataset": "finance-qa-v2",
    })

    # 训练过程中记录指标
    for epoch in range(3):
        train_loss = train_one_epoch(...)
        eval_loss = evaluate(...)
        mlflow.log_metrics({
            "train_loss": train_loss,
            "eval_loss": eval_loss,
        }, step=epoch)

    # 保存模型
    mlflow.pytorch.log_model(model, "model")

    # 标记为最优模型
    mlflow.register_model(
        f"runs:/{mlflow.active_run().info.run_id}/model",
        "qwen-finance-finetune"
    )
```

### 模型状态流转

```python
from mlflow import MlflowClient

client = MlflowClient()

# 将版本 3 推到 Staging
client.transition_model_version_stage(
    name="qwen-finance-finetune",
    version=3,
    stage="Staging"
)

# 验证通过后推到 Production
client.transition_model_version_stage(
    name="qwen-finance-finetune",
    version=3,
    stage="Production"
)
```

---

## 与 CI/CD 集成

```yaml
# .gitlab-ci.yml 中的模型部署 stage
deploy-model:
  stage: deploy
  script:
    # 从 MLflow Registry 拉取 Production 模型
    - python scripts/pull_model.py --stage Production
    # 更新 vLLM 加载的模型路径
    - kubectl set env deployment/vllm MODEL_PATH=/models/qwen-finance-v3
    - kubectl rollout status deployment/vllm
```

---

## 与同类工具对比

| 工具 | 定位 | 区别 |
|---|---|---|
| **MLflow** | 全生命周期，开源 | 轻量，易上手，最通用 |
| Weights & Biases (W&B) | 实验追踪为主 | 可视化更好，付费版功能强 |
| DVC | 数据版本管理 | 侧重数据集版本，与 Git 集成 |
| BentoML | 模型服务 | 侧重推理服务打包，而非追踪 |

> 起步选 MLflow，团队大了可以升级 W&B 企业版。

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/mlflow/mlflow
- Star：26.1k（统计日期：2026-05-27）

