# Dify - 自托管 AI 应用开发平台

> 推荐原因：Dify 是当前 SmartVision AI 提效计划中被引用最多的工具（贯穿 00-产品分析、01-需求管理、10-SRE、16-知识管理等 8 个领域），它是构建 RAG 知识库问答、AI 工作流、智能助手的核心平台，自托管避免数据外泄风险。
> 当前状态：❌ 未部署，计划自托管于 K8s，优先级：🔴 高优。

---

## 现状与问题

| 项目 | 现状 |
|------|------|
| AI 工作流构建 | 分散，依赖个人用 Claude 网页端 |
| 内部知识库问答 | ❌ 无统一入口 |
| 飞书 Bot 接入 AI | ❌ 无统一平台 |
| Runbook / FAQ 智能查询 | ❌ 无 RAG 能力 |
| Prompt 版本管理 | ❌ 无 |

---

## Dify 是什么

Dify 是开源的 LLM 应用开发平台，支持：
- **RAG 知识库**：上传文档，自动向量化，支持自然语言检索
- **工作流（Workflow）**：可视化编排多步 AI 任务（如 ETL + LLM + 通知）
- **AI 助手（Chatbot）**：绑定知识库的对话机器人，可接入飞书
- **API 暴露**：每个应用自动生成 API，可被其他系统调用
- **Prompt 版本管理**：生产 Prompt 可版本化管理和 A/B 测试

---

## 在 SmartVision 的核心用途

| 用途 | 领域 | 具体场景 |
|------|------|---------|
| Runbook 智能查询 | 10-SRE | OnCall 飞书问：如何处理 Redis 内存告警 |
| 技术文档知识库 | 16-知识管理 | 自然语言查询本仓库所有 Markdown 文档 |
| 私有化配置助手 | 13-私有化交付 | 输入客户环境信息，AI 生成 Helm values |
| PRD 起草助手 | 01-产品需求管理 | 结构化 PRD 模板自动填写 |
| CVE 分析工作流 | 11-安全治理 | Trivy JSON → AI 定级 → 报告生成 |
| 新员工 Onboarding | 16-知识管理 | 引导式问答助手 |

---

## K8s 部署

```bash
# 方式 1：Docker Compose（快速验证，不推荐生产）
git clone https://github.com/langgenius/dify.git
cd dify/docker
cp .env.example .env  # 修改 SECRET_KEY 等
docker compose up -d

# 方式 2：Helm（推荐，K8s 生产部署）
helm repo add dify https://langgenius.github.io/dify-helm
helm install dify dify/dify \
  --namespace dify \
  --create-namespace \
  -f values-override.yaml
```

```yaml
# values-override.yaml 关键配置
global:
  storageType: s3
  s3:
    endpoint: "http://minio.prod.svc.cluster.local:9000"
    bucketName: dify-storage
    accessKey: minio-admin
    secretKey: minio-secret

postgresql:
  enabled: false  # 使用外部 PostgreSQL
  externalUrl: "postgresql://dify_user:password@postgresql.prod.svc.cluster.local:5432/dify"

redis:
  enabled: false  # 使用外部 Redis
  externalUrl: "redis://redis.prod.svc.cluster.local:6379"

web:
  replicaCount: 2
api:
  replicaCount: 2
```

---

## 知识库接入（RAG 流程）

```
文档来源：
  - 本仓库 Markdown 文件（smartvision2 知识库）
  - Runbook / SOP
  - FAQ 文档

接入步骤：
  1. Dify 后台 → 知识库 → 新建知识库
  2. 上传文档（支持 .md/.pdf/.txt，或 Notion URL）
  3. 选择分块策略（推荐：段落分块，1000 tokens/块）
  4. 选择 Embedding 模型（text-embedding-3-small）
  5. 创建完成后，新建 Chatbot 应用，绑定该知识库

自动同步（可选）：
  # 通过 Dify API 自动推送更新后的文档
  curl -X POST 'http://dify.internal/v1/datasets/{dataset_id}/document/create_by_text' \
    -H 'Authorization: Bearer {API_KEY}' \
    -d '{"name": "运维FAQ.md", "text": "..."}'
```

---

## 飞书 Bot 接入

```
Dify 应用 → 发布为 API → 飞书自定义机器人 Webhook → 飞书群

流程：
  1. Dify 应用发布，获取 API Key
  2. 飞书开放平台 → 自建机器人 → 添加 Bot
  3. 中间层（小 Python 服务）：接收飞书消息 → 调 Dify API → 回复飞书
  4. 部署到 K8s，注册飞书 Bot Event Subscription
```

---

## 资源需求估算

| 组件 | CPU | 内存 | 说明 |
|------|-----|------|------|
| dify-web | 0.5C / 1C | 256Mi / 512Mi | 前端 |
| dify-api | 1C / 2C | 512Mi / 1Gi | 核心 API |
| dify-worker | 1C / 2C | 512Mi / 1Gi | 异步任务（文档向量化）|
| dify-sandbox | 0.5C / 1C | 256Mi / 512Mi | 代码执行沙箱 |
| 合计 | ~3-6C | ~1.5-3Gi | 不含外部依赖 |

*外部依赖（复用现有）：PostgreSQL、Redis、MinIO*

---

## 引入优先级

| 优先级 | 理由 |
|--------|------|
| 🔴 高优（本季度部署）| 被 8+ 个领域 AI 提效计划依赖，是基础平台设施 |

---

## 参考

- 官方文档：https://docs.dify.ai/
- GitHub：https://github.com/langgenius/dify
- Helm Chart：https://github.com/langgenius/dify-helm
