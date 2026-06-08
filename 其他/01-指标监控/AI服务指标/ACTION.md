# AI 服务监控落地行动清单

> 对应 PLAN.md Phase 3（第 11-12 周）
> 前置：推理服务已运行（Phase 2 完成）、基础监控已部署（Phase 3 前半完成）

## 第一步：GPU 监控（DCGM Exporter）

```bash
# DCGM Exporter 是 NVIDIA 官方的 GPU 指标采集工具
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts

helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace observability \
  --set serviceMonitor.enabled=true

# 验证
kubectl get pods -n observability -l app.kubernetes.io/name=dcgm-exporter
# 应该看到 DCGM Exporter Pod 运行在 GPU 节点上

# 在 Grafana 中导入 Dashboard ID: 12239（NVIDIA DCGM Exporter）
# 现在能看到：GPU 利用率、显存、温度、功耗、ECC 错误
```

## 第二步：推理服务 Token 统计

```python
# 在推理服务前面加一层 API Gateway / Proxy，记录每次请求的 Token 用量
# 推荐方案：写一个轻量 Python 代理

# proxy.py — 放在推理服务前面的 API 代理
from fastapi import FastAPI, Request
import httpx
import time
import asyncpg

app = FastAPI()
pool = None

UPSTREAM_URL = "http://qwen-inference.ai-infra:8000"

@app.on_event("startup")
async def startup():
    global pool
    pool = await asyncpg.create_pool("postgresql://user:pass@db/wenxue")
    await pool.execute("""
        CREATE TABLE IF NOT EXISTS token_usage (
            id SERIAL PRIMARY KEY,
            request_id TEXT,
            user_id TEXT,
            model TEXT,
            input_tokens INT,
            output_tokens INT,
            latency_ms INT,
            created_at TIMESTAMP DEFAULT NOW()
        )
    """)

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    start = time.time()
    body = await request.json()

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{UPSTREAM_URL}/v1/chat/completions",
            json=body,
            timeout=120
        )

    latency = int((time.time() - start) * 1000)
    result = resp.json()

    # 记录用量
    usage = result.get("usage", {})
    await pool.execute(
        """INSERT INTO token_usage
           (request_id, user_id, model, input_tokens, output_tokens, latency_ms)
           VALUES ($1, $2, $3, $4, $5, $6)""",
        body.get("request_id", ""),
        request.headers.get("X-User-ID", "anonymous"),
        body.get("model", "unknown"),
        usage.get("prompt_tokens", 0),
        usage.get("completion_tokens", 0),
        latency
    )

    return result
```

## 第三步：Token 用量 Dashboard

```yaml
# 在 Grafana 中添加 PostgreSQL 数据源，连接 token_usage 数据库
# 然后创建以下 Panel：

# Panel 1: 今日 Token 总消耗
# SQL:
SELECT sum(input_tokens + output_tokens) as total_tokens
FROM token_usage
WHERE created_at > CURRENT_DATE;

# Panel 2: 每小时 Token 消耗趋势
# SQL:
SELECT
  date_trunc('hour', created_at) as time,
  sum(input_tokens) as input,
  sum(output_tokens) as output
FROM token_usage
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY 1
ORDER BY 1;

# Panel 3: 按模型的 Token 消耗
# SQL:
SELECT model, sum(input_tokens + output_tokens) as total
FROM token_usage
WHERE created_at > CURRENT_DATE
GROUP BY model;

# Panel 4: Top 10 用户用量
# SQL:
SELECT user_id, sum(input_tokens + output_tokens) as total
FROM token_usage
WHERE created_at > CURRENT_DATE
GROUP BY user_id
ORDER BY total DESC
LIMIT 10;

# Panel 5: 推理延迟分布
# SQL:
SELECT
  percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms) as p50,
  percentile_cont(0.9) WITHIN GROUP (ORDER BY latency_ms) as p90,
  percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms) as p99
FROM token_usage
WHERE created_at > NOW() - INTERVAL '1 hour';
```

## 第四步：GPU 告警规则

```yaml
# 添加到 PrometheusRule 中
- name: gpu-alerts
  rules:
  # GPU 温度过高
  - alert: GPUTemperatureHigh
    expr: DCGM_FI_DEV_GPU_TEMP > 85
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "GPU {{ $labels.gpu }} 温度 {{ $value }}°C"

  # GPU 显存几乎满了
  - alert: GPUMemoryHigh
    expr: DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.95
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "GPU {{ $labels.gpu }} 显存使用超过 95%"

  # ECC 不可纠正错误
  - alert: GPUECCError
    expr: DCGM_FI_DEV_ECC_DBE_VOL_TOTAL > 0
    labels:
      severity: critical
    annotations:
      summary: "GPU {{ $labels.gpu }} 出现 ECC 不可纠正错误，需要摘除"

  # GPU 利用率持续低（可能浪费资源）
  - alert: GPUIdleWaste
    expr: DCGM_FI_DEV_GPU_UTIL < 10
    for: 30m
    labels:
      severity: info
    annotations:
      summary: "GPU {{ $labels.gpu }} 利用率低于 10% 已 30 分钟"
```

## 验收 Checklist

- [ ] Grafana 能看到 GPU 利用率、温度、显存图
- [ ] 每次推理请求的 Token 用量被记录到数据库
- [ ] Token 用量 Dashboard 有数据展示
- [ ] 推理延迟 P50/P90/P99 可见
- [ ] GPU 温度和 ECC 告警已配置
