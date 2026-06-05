# MLflow - 机器学习实验管理与模型注册

> 推荐原因：SmartVision 的 AI 团队有大量 vLLM 参数调优、模型 fine-tuning 实验，当前缺乏结构化的实验记录，无法对比不同参数下的性能差异。MLflow 提供实验追踪 + 模型版本管理，与现有 K8s 部署流程可无缝集成。
> 当前状态：❌ 未部署，计划在 04-AI Infra 基建 Phase 2 引入。

---

## 现状与问题

| 项目 | 现状 |
|------|------|
| 推理参数调优记录 | 靠文档或口头传递，无系统化追踪 |
| 模型版本管理 | 手动命名（qwen-v1, qwen-v2），无规范 |
| Fine-tuning 实验对比 | 无法横向对比多次实验的指标 |
| 模型上线流程 | 手动替换 volume 路径，无审批记录 |
| 模型回滚 | 需要手动找旧模型文件，耗时 |

---

## MLflow 是什么

MLflow 是 Databricks 开源的机器学习全生命周期管理平台，核心功能：

| 功能 | 说明 |
|------|------|
| **Experiment Tracking** | 记录每次实验的参数、指标、artifact（日志/图表）|
| **Model Registry** | 模型版本管理，支持 Staging → Production 状态流转 |
| **Model Serving** | 可选，MLflow 可直接 serve 模型（SmartVision 用 vLLM）|
| **Projects** | 可打包训练代码，确保实验可复现 |

---

## 在 SmartVision 的核心用途

| 用途 | 说明 |
|------|------|
| vLLM 参数调优记录 | 每次调整 max_model_len/gpu_memory_utilization 等参数后，记录 TPS/延迟/显存使用 |
| Fine-tuning 实验管理 | LoRA 训练时记录 loss/eval_perplexity，对比不同超参数 |
| 模型版本注册 | 每个模型（qwen2.5-7b/llava 等）有明确的版本 + 上线审批记录 |
| CI/CD 集成 | GitLab CI 训练完成后自动注册模型版本，触发部署流程 |

---

## K8s 部署

```bash
# Helm 部署 MLflow
helm repo add community-charts https://community-charts.github.io/helm-charts
helm install mlflow community-charts/mlflow \
  --namespace mlflow \
  --create-namespace \
  --set backendStore.postgres.enabled=true \
  --set backendStore.postgres.host=postgresql.prod.svc.cluster.local \
  --set backendStore.postgres.database=mlflow \
  --set backendStore.postgres.user=mlflow_user \
  --set backendStore.postgres.password=mlflow_password \
  --set artifactRoot.s3.enabled=true \
  --set artifactRoot.s3.bucket=mlflow-artifacts \
  --set artifactRoot.s3.awsAccessKeyId=minio-admin \
  --set artifactRoot.s3.awsSecretAccessKey=minio-secret \
  --set artifactRoot.s3.s3EndpointUrl=http://minio.prod.svc.cluster.local:9000
```

---

## 实验追踪代码示例

```python
# vLLM 调优实验记录
import mlflow

MLFLOW_TRACKING_URI = "http://mlflow.mlflow.svc.cluster.local:5000"
mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)

with mlflow.start_run(experiment_id=mlflow.set_experiment("vllm-tuning").experiment_id):
    # 记录参数
    mlflow.log_params({
        "model_name": "Qwen2.5-7B-Instruct",
        "gpu_memory_utilization": 0.85,
        "max_model_len": 8192,
        "tensor_parallel_size": 2,
        "batch_size": 32
    })

    # 运行负载测试
    results = run_locust_benchmark()

    # 记录指标
    mlflow.log_metrics({
        "throughput_tps": results.tps,
        "p99_latency_ms": results.p99,
        "p50_latency_ms": results.p50,
        "gpu_memory_used_gb": results.gpu_mem_gb
    })

    # 记录 artifact（详细报告）
    mlflow.log_artifact("benchmark_report.json")
    mlflow.log_artifact("grafana_screenshot.png")
```

---

## 模型注册与晋级流程

```python
# 模型训练完成后注册
from mlflow.tracking import MlflowClient

client = MlflowClient()

# 注册模型版本
result = mlflow.register_model(
    model_uri=f"runs:/{run_id}/model",
    name="smartvision-qwen-finetuned"
)

# 将版本推进到 Staging（QA 测试）
client.transition_model_version_stage(
    name="smartvision-qwen-finetuned",
    version=result.version,
    stage="Staging"
)

# 测试通过后晋级到 Production
client.transition_model_version_stage(
    name="smartvision-qwen-finetuned",
    version=result.version,
    stage="Production",
    archive_existing_versions=True  # 自动归档旧版本
)
```

---

## 与 CI/CD 集成

```yaml
# GitLab CI - 训练完成后自动注册模型
fine-tune-and-register:
  stage: train
  script:
    - python train.py --config ${CONFIG_FILE}
    - python -c "
        import mlflow
        mlflow.set_tracking_uri('http://mlflow.mlflow.svc.cluster.local:5000')
        # 注册到 Model Registry
        model_uri = f'runs:/{run_id}/model'
        mlflow.register_model(model_uri, '${MODEL_NAME}')
      "
  artifacts:
    paths:
      - mlflow_run_id.txt
```

---

## 引入优先级

| 触发条件 | 优先级 |
|---------|--------|
| AI 团队开始做 Fine-tuning | 🔴 高优（立即接入）|
| vLLM 参数需要系统化调优 | 🟡 中优 |
| 当前只是跑通推理，无调优需求 | ⚪ 暂缓 |

---

## 参考

- 官方文档：https://mlflow.org/docs/latest/
- Model Registry：https://mlflow.org/docs/latest/model-registry.html
- Helm Chart：https://community-charts.github.io/helm-charts/
