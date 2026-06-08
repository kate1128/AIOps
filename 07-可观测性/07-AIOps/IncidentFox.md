# IncidentFox — 开源 AI SRE 事件调查平台（已归档）

**更新日期：** 2026年06月04日
**信息来源：** GitHub 仓库、官方文档、社区实践
**参考地址：**

1. GitHub：[incidentfox/incidentfox](https://github.com/incidentfox/incidentfox)（~614 stars，⚠️ 已于 2026-05-31 归档）
2. 官网：[incidentfox.ai](https://incidentfox.ai/)
3. 功能文档：[FEATURES.md](https://github.com/incidentfox/incidentfox/blob/main/docs/FEATURES.md)
4. 部署文档：[DEPLOYMENT.md](https://github.com/incidentfox/incidentfox/blob/main/docs/DEPLOYMENT.md)
5. Slack 设置：[SLACK_SETUP.md](https://github.com/incidentfox/incidentfox/blob/main/docs/SLACK_SETUP.md)

> ⚠️ **重要提示**：IncidentFox 仓库已于 2026-05-31 被项目所有者归档（Archive），变为只读状态，不再接受 PR 或 Issue。该项目可能已停止维护或转向闭源/商业化。**不建议在新项目中引入。** 本文档作为竞品分析和参考保留。

> Star 数会持续变化。正式对外汇报前建议以 GitHub 实时数据复核。

---

## 1. 结论摘要

IncidentFox 是面向生产环境事件响应的 AI SRE 平台，核心定位是"**把 AI 带进 Slack 告警流程**"：每当告警触发时，自动在 Slack 线程中调查根因、关联日志/指标/代码变更，并输出结构化的根因分析报告，而无需 On-Call 工程师手动操作。

其技术亮点包括：多 Agent 协作（K8s 专家 Agent + AWS Agent + 代码分析 Agent 按需路由）、3 层告警关联（时间 + 拓扑 + 语义）减少 85-95% 告警噪声、Meta Prophet 算法的季节感知异常检测、基于 RAPTOR 的 RAG 知识库（适合长文档 runbook 检索），以及 gVisor 沙箱隔离的安全调查执行环境。

但 IncidentFox **已于 2026-05-31 宣布归档**，6 名贡献者、614 stars，社区规模较小。作为调研参考，其设计思路（特别是多 Agent 协作、3 层告警关联、RAPTOR 知识库）对构建 AIOps 平台有借鉴价值。

| 关键信息 | 值 |
| --- | --- |
| 项目状态 | ⚠️ 已归档（2026-05-31）不再维护 |
| 开源协议 | Apache 2.0（核心）+ BSL 1.1（安全层）|
| 实现语言 | Python（79.5%）+ TypeScript（15.4%）|
| 集成渠道 | Slack / Microsoft Teams / Google Chat |
| 支持 LLM | 24 个提供商（Claude、OpenAI、Gemini、DeepSeek、Mistral、Ollama 等）|
| 支持集成 | 45+ 数据源（Grafana、Loki、Prometheus、K8s、GitHub、PagerDuty 等）|
| 部署方式 | Docker Compose（本地）/ Helm（K8s）/ IncidentFox Cloud |

---

## 2. 产品概况

| 项目 | 内容 |
| --- | --- |
| 产品名称 | IncidentFox |
| 产品定位 | 开源 AI SRE 平台，自动调查生产事件、定位根因 |
| 开发者 | Jimmy Wei、Long Yi 等（6 贡献者）|
| 项目状态 | ⚠️ 已于 2026-05-31 归档，只读，停止接受贡献 |
| 开源协议 | Apache 2.0（核心）+ BSL 1.1（生产安全层），企业安全层在 2030-02-18 转为 Apache 2.0 |
| 主要形态 | SRE Agent（Slack Bot）+ Web 控制台 + Orchestrator + K8s Agent |
| 目标用户 | 希望在 Slack 中自动化事件响应的 DevOps / SRE 团队 |
| 典型场景 | 告警自动调查、跨系统根因分析、知识库驱动的 runbook 匹配、多团队事件协同 |

---

## 3. 产品定位与典型场景

| 场景 | IncidentFox 解决的问题 | 价值 |
| --- | --- | --- |
| 告警自动调查 | On-Call 工程师在 Slack 看到告警时需要手动切换多个系统排查 | 告警到达 Slack 后自动在线程中投入调查，输出根因摘要 |
| 告警噪声降低 | 同一事件触发大量相关告警淹没 On-Call 频道 | 3 层告警关联（时间 + 拓扑 + 语义）聚合相关告警，减少 85-95% 噪声 |
| 异常检测 | 简单阈值告警遗漏具有周期性规律的异常（周末低峰 / 每日高峰）| Meta Prophet 季节感知算法，识别流量异常时考虑工作日/周末模式 |
| Runbook 智能检索 | 告警触发时 runbook 内容长、章节多，难以快速定位相关段落 | RAPTOR 层次化 RAG 在长文档中精准检索，保持跨段落上下文 |
| 多团队 K8s 事件隔离 | 多个业务团队共用集群，事件调查权限和数据需要隔离 | 组织级 / 团队级分层配置，深度合并 + RBAC + 审计日志 |
| 持续学习 | 每次事件排查经验无法沉淀到下次告警处理 | 每次调查后自动学习，构建团队特定的历史模式库 |

---

## 4. 技术架构

```mermaid
graph TB
    subgraph 告警与触发
        AM["Alertmanager / PagerDuty\nIncident.io / GitHub"]
        Slack["Slack / Teams / Google Chat\n@mention 或 自动响应"]
    end

    subgraph "IncidentFox 核心"
        Orchestrator["Orchestrator\n路由告警 → 对应团队 Agent\n管理 Agent 连接池"]
        SREAgent["SRE Agent\n主调查 Agent\nAgentic Loop"]
        K8sAgent["K8s Agent\n专有 K8s 调查器\n运行于集群内"]
        RAG["RAPTOR 知识库\n层次化 RAG\nRunbook / Confluence / 历史事件"]
        Correlation["告警关联引擎\n时间 + 拓扑 + 语义 3 层分析"]
        Anomaly["异常检测\nMeta Prophet\n季节感知预测"]
    end

    subgraph 数据源层
        Observability["Grafana / Loki / Prometheus\nDatadog / Elasticsearch / Sentry"]
        Code["GitHub / GitLab\nJira / Confluence"]
        K8s["Kubernetes\n（direct + K8s Agent）"]
    end

    subgraph 输出
        SlackOut["Slack 线程\n根因报告 + 修复建议"]
        WebUI["Web 控制台\n调查历史 + Agent 管理"]
    end

    AM --> Orchestrator
    Slack --> Orchestrator
    Orchestrator --> SREAgent
    SREAgent --> K8sAgent
    SREAgent --> RAG & Correlation & Anomaly
    SREAgent --> Observability & Code & K8s
    SREAgent --> SlackOut & WebUI
```

| 组件 | 说明 |
| --- | --- |
| Orchestrator | 接收 webhook 事件（PagerDuty / GitHub / Slack 等），路由到对应团队的 SRE Agent，管理 SSE 连接 |
| SRE Agent | 主调查 Agent，执行 Agentic Loop，协调子 Agent（K8s Agent / AWS Agent 等）|
| K8s Agent | 专用于 K8s 调查的子 Agent，部署在集群内，使用 K8s RBAC 访问资源 |
| RAPTOR 知识库 | 基于分层摘要的 RAG 系统，解决普通 RAG 在长文档中丢失上下文的问题 |
| 告警关联引擎 | 时间相关（同时发生）+ 拓扑相关（服务依赖链）+ 语义相关（描述相似）三层聚合 |
| gVisor 沙箱 | 企业版功能：每次调查在隔离的 gVisor K8s sandbox 中运行，凭据由 Envoy 代理注入，Agent 不直接接触密钥 |

---

## 5. 核心功能详解

### 5.1 多 Agent 协作

IncidentFox 采用专家 Agent 路由模式：

```
告警 → Orchestrator 分析问题类型
  ↓
  ├─ K8s 问题 → K8s 专家 Agent
  ├─ 数据库问题 → DB 专家 Agent
  ├─ 网络问题 → 网络专家 Agent
  └─ 代码相关 → 代码分析 Agent
```

每个专家 Agent 都预配置了特定领域的工具集和系统提示，比通用 Agent 在特定问题上表现更好。

### 5.2 告警关联三层分析

```
时间层：   ±5 分钟窗口内同时触发的告警 → 可能同源
拓扑层：   依赖图中上下游服务的告警 → 追踪影响传播路径
语义层：   告警描述向量相似度 > 阈值 → 描述类似问题的告警
─────────────────────────────────────────
综合评分 → 相关告警聚合为一个事件 → 减少 85-95% 噪声
```

### 5.3 RAPTOR 知识库（RAG for Long Docs）

标准 RAG 对于长 runbook 或包含跨章节依赖关系的文档效果差。RAPTOR 通过层次化摘要树解决这个问题：

```
原始文档（Confluence / GitHub）
  → 段落级摘要
  → 章节级摘要
  → 文档级摘要
  ↓
查询时从摘要树顶层向下检索，保留上下文关联
```

### 5.4 智能日志采样

```
大量日志 → 先统计分析（错误类型分布、频率）
→ 再基于统计结果有目标地采样（只取代表性样本）
→ 有效避免 LLM 上下文窗口溢出
```

---

## 6. 与同类工具对比

| 维度 | IncidentFox（已归档）| HolmesGPT | KAgent |
| --- | --- | --- | --- |
| 项目状态 | ⚠️ 归档停止维护 | ✅ 活跃（CNCF Sandbox）| ✅ 活跃（CNCF）|
| 定位 | AI SRE 平台 + 事件协同 | SRE Agent（告警根因）| AI Agent 框架 |
| Slack 深度集成 | ✅ 原生（线程协作）| ⚠️（需 Robusta）| ❌ |
| 团队协作 | ✅ 多团队 RBAC + 审计 | ⚠️（企业版）| ✅ UI + API |
| 告警关联降噪 | ✅ 3 层关联（核心特性）| ❌ | ❌ |
| 长文档知识库 | ✅ RAPTOR RAG | ⚠️ 基础 RAG | ❌（需自建）|
| 开源可维护性 | ❌ 已归档 | ✅ | ✅ |

**结论：** IncidentFox 的设计思路很完整，特别是 3 层告警关联和 RAPTOR 知识库是值得学习借鉴的创新点。但由于项目已归档，**不建议在生产环境引入**。如果需要类似能力，建议参考其思路，在 HolmesGPT + KAgent 的基础上实现，或关注其商业化产品 incidentfox.ai 的后续动向。

---

## 7. 部署参考（仅供存档）

> 以下内容仅供技术调研参考，不建议部署已归档项目到生产环境。

### 7.1 本地快速启动

```bash
git clone https://github.com/incidentfox/incidentfox
cd incidentfox
cp .env.example .env

# 编辑 .env，填入 LLM API Key
# ANTHROPIC_API_KEY=sk-ant-...
# 或其他 24 个 Provider 的 Key

make dev
# 启动：Postgres + SRE Agent + Config Service + Web Console
```

docker-compose

```yaml
version: '3.8'

# ???????????????????????????????????????????????????????????????????????????????
# IncidentFox ? Local Development Stack
# ???????????????????????????????????????????????????????????????????????????????
#
# Services:
#   postgres, config-service, credential-resolver, envoy, sre-agent, slack-bot
#
# Note: slack-bot requires SLACK_BOT_TOKEN and SLACK_APP_TOKEN in .env
#       If not configured, it will exit gracefully with a warning message
#
# Usage:
#   make dev        Start all services
#   make stop       Stop everything
#   make logs       Follow logs
#   make clean      Remove containers + volumes
#
# ???????????????????????????????????????????????????????????????????????????????

services:
  # ─────────────────────────────────────────────────────────────────────────────
  # PostgreSQL ? backend for config-service
  # ─────────────────────────────────────────────────────────────────────────────
  postgres:
    image: postgres:15-alpine
    container_name: incidentfox-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: incidentfox
      POSTGRES_PASSWORD: localdev
      POSTGRES_DB: incidentfox
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U incidentfox -d incidentfox"]
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - app_network

  # ─────────────────────────────────────────────────────────────────────────────
  # Config Service ? team config, tokens, audit logging
  # ─────────────────────────────────────────────────────────────────────────────
  config-service:
    #build:
    # context: ./config_service
    # dockerfile: Dockerfile
    image: incidentfox/config-service:latest
    container_name: incidentfox-config-service
    restart: unless-stopped
    entrypoint: ["/bin/bash", "/app/scripts/entrypoint-local.sh"]
    env_file:
      - .env
    environment:
      DATABASE_URL: postgresql+psycopg2://incidentfox:localdev@postgres:5432/incidentfox?sslmode=disable
      TOKEN_PEPPER: ${TOKEN_PEPPER:-localdev-pepper-must-be-32-chars-minimum!!}
      ADMIN_TOKEN: ${ADMIN_TOKEN:-local-admin-token}
      ADMIN_AUTH_MODE: token
      TEAM_AUTH_MODE: token
      LOG_LEVEL: ${LOG_LEVEL:-INFO}
      LOG_FORMAT: console
      ENV_FILE_PATH: /repo/.env  # Path to .env file for write-back
    ports:
      - "8080:8080"
    volumes:
      # Mount config directory for YAML config in local mode
      - ./config_service/config:/app/config:rw
      # Mount repo root for .env write-back in local mode
      # (Mounting entire repo allows atomic file operations)
      - .:/repo:rw
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app_network
      - default  # Needs host access for port publishing

  # ─────────────────────────────────────────────────────────────────────────────
  # Credential Resolver ? loads secrets from .env, injects into requests
  # ─────────────────────────────────────────────────────────────────────────────
  credential-resolver:
    build:
      context: ./sre-agent/credential-proxy
      dockerfile: Dockerfile
    container_name: incidentfox-credential-resolver
    restart: unless-stopped
    environment:
      - JWT_MODE=permissive
      - CONFIG_SERVICE_URL=http://config-service:8080
    env_file:
      - .env
    healthcheck:
      test: ["CMD", "python", "-c", "import httpx; httpx.get('http://localhost:8002/health').raise_for_status()"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - app_network
      - default  # Needs external access for LLM proxy to reach upstream APIs

  # ─────────────────────────────────────────────────────────────────────────────
  # Envoy Proxy ? routes requests, calls credential-resolver for auth headers
  # ─────────────────────────────────────────────────────────────────────────────
  envoy:
    image: envoyproxy/envoy:v1.28-latest
    container_name: incidentfox-envoy
    restart: unless-stopped
    ports:
      - "8001:8001"  # Proxy endpoint
      - "9901:9901"  # Admin interface
    volumes:
      - ./sre-agent/credential-proxy/envoy/envoy-local.yaml:/etc/envoy/envoy.yaml:ro
    depends_on:
      credential-resolver:
        condition: service_healthy
    command: ["--config-path", "/etc/envoy/envoy.yaml", "--log-level", "info"]
    dns:
      - 8.8.8.8
      - 8.8.4.4
    networks:
      - app_network
      - default  # Needs external access to reach upstream APIs

  # ─────────────────────────────────────────────────────────────────────────────
  # SRE Agent ? runs investigations (in-process, no K8s sandboxes)
  # ─────────────────────────────────────────────────────────────────────────────
  sre-agent:
    build:
      context: ./sre-agent
      dockerfile: Dockerfile.simple
    container_name: incidentfox-sre-agent
    restart: unless-stopped
    environment:
      # Proxy mode - no secrets in agent!
      - ANTHROPIC_BASE_URL=http://envoy:8001
      - ANTHROPIC_API_KEY=sk-ant-placeholder-proxy-will-inject-real-key
      # Coralogix routed through proxy (credentials injected)
      - CORALOGIX_BASE_URL=http://envoy:8001
      # Config service integration
      - CONFIG_SERVICE_URL=http://config-service:8080
      # Tenant context for credential lookup + config loading
      - INCIDENTFOX_TENANT_ID=local
      - INCIDENTFOX_TEAM_ID=default
      # Coralogix config (no API key - injected by proxy)
      - CORALOGIX_DOMAIN=${CORALOGIX_DOMAIN:-}
      # GitHub integration (credential-resolver proxies to GitHub API)
      - GITHUB_BASE_URL=http://credential-resolver:8002/github
      - CREDENTIAL_RESOLVER_URL=http://credential-resolver:8002
      - GH_HOST=credential-resolver:8443
      - GH_TOKEN=local-dev-placeholder
      # Other services
      - LMNR_PROJECT_API_KEY=${LMNR_PROJECT_API_KEY:-}
    depends_on:
      envoy:
        condition: service_started
      config-service:
        condition: service_healthy
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    # Note: Cannot use read_only:true because Claude Code CLI needs to write
    # But we limit writable locations with tmpfs
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=500m
      - /home/agent/.cache:rw,noexec,nosuid,size=200m
    mem_limit: 2g
    cpus: 2
    pids_limit: 100
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    ports:
      - "8000:8000"
    networks:
      - app_network
      - default  # Needs external access for API calls
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('http://localhost:8000/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  # ─────────────────────────────────────────────────────────────────────────────
  # Slack Bot ? connects Slack to SRE Agent
  # Will exit gracefully if SLACK_BOT_TOKEN and SLACK_APP_TOKEN are not configured
  # ─────────────────────────────────────────────────────────────────────────────
  slack-bot:
    build:
      context: ./slack-bot
      dockerfile: Dockerfile
    container_name: incidentfox-slack-bot
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - SRE_AGENT_URL=http://sre-agent:8000
      - CONFIG_SERVICE_URL=http://config-service:8080
      - CONFIG_MODE=${CONFIG_MODE:-}
    depends_on:
      - sre-agent
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    # Cannot use read_only because app may write logs/temp files
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=100m
    volumes:
      # Mount assets read-only
      - ./slack-bot/assets:/app/assets:ro
    mem_limit: 1g
    cpus: 1
    pids_limit: 50
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - app_network
      - default  # Needs external access to connect to Slack

networks:
  app_network:
    driver: bridge
    internal: true  # Internal network for inter-service communication
  default:
    driver: bridge  # Default network with external access

volumes:
  postgres-data:
    name: incidentfox-postgres-data
```

ui 访问：localhost:8080
admin 访问：http://localhost:8080/admin
metrics 访问：http://localhost:8080/metrics
api文档访问：http://localhost:8080/docs#/


![alt text](images/image.png)

### 7.2 集成 Slack

```bash
# 创建 Slack App（使用 slack-bot/slack-manifest.json）
# 添加到 .env：
# SLACK_BOT_TOKEN=xoxb-...
# SLACK_APP_TOKEN=xapp-...

make dev-slack
```

---

## 8. 常见问题

### IncidentFox 已归档，商业版 incidentfox.ai 还在吗？

截至 2026年6月4日，`incidentfox.ai` 网站仍然在线。GitHub 仓库归档通常意味着开源维护停止，但商业产品可能仍在运营。建议直接联系 `founders@incidentfox.ai` 确认商业版状态。

---

### RAPTOR 知识库和普通 RAG 有什么区别？

普通 RAG（向量化分块检索）在处理长文档时有两个问题：一是相关内容可能分散在不同章节，向量检索只能找到局部相关片段；二是跨章节上下文丢失，导致 LLM 回答不完整。RAPTOR 通过对文档构建层次化摘要树，在检索时从宏观（文档摘要）到微观（原始段落）逐层检索，能保留跨段落的上下文关联。

---

## 9. 参考文档

1. [IncidentFox GitHub 仓库（已归档）](https://github.com/incidentfox/incidentfox)
2. [功能文档 FEATURES.md](https://github.com/incidentfox/incidentfox/blob/main/docs/FEATURES.md)
3. [部署文档 DEPLOYMENT.md](https://github.com/incidentfox/incidentfox/blob/main/docs/DEPLOYMENT.md)
4. [开源 vs 付费功能对比](https://github.com/incidentfox/incidentfox#open-source-vs-paid)
5. [RAPTOR 原始论文](https://arxiv.org/abs/2401.18059)（层次化 RAG 方法论）
6. [IncidentFox 官网](https://incidentfox.ai/)


## 附录：metrics 监控指标（仅供存档）
```plaintext
# HELP python_gc_objects_collected_total Objects collected during gc
# TYPE python_gc_objects_collected_total counter
python_gc_objects_collected_total{generation="0"} 6668.0
python_gc_objects_collected_total{generation="1"} 1093.0
python_gc_objects_collected_total{generation="2"} 115.0
# HELP python_gc_objects_uncollectable_total Uncollectable objects found during GC
# TYPE python_gc_objects_uncollectable_total counter
python_gc_objects_uncollectable_total{generation="0"} 0.0
python_gc_objects_uncollectable_total{generation="1"} 0.0
python_gc_objects_uncollectable_total{generation="2"} 0.0
# HELP python_gc_collections_total Number of times this generation was collected
# TYPE python_gc_collections_total counter
python_gc_collections_total{generation="0"} 490.0
python_gc_collections_total{generation="1"} 44.0
python_gc_collections_total{generation="2"} 3.0
# HELP python_info Python platform information
# TYPE python_info gauge
python_info{implementation="CPython",major="3",minor="11",patchlevel="14",version="3.11.14"} 1.0
# HELP process_virtual_memory_bytes Virtual memory size in bytes.
# TYPE process_virtual_memory_bytes gauge
process_virtual_memory_bytes 2.03026432e+08
# HELP process_resident_memory_bytes Resident memory size in bytes.
# TYPE process_resident_memory_bytes gauge
process_resident_memory_bytes 1.1339776e+08
# HELP process_start_time_seconds Start time of the process since unix epoch in seconds.
# TYPE process_start_time_seconds gauge
process_start_time_seconds 1.78054560966e+09
# HELP process_cpu_seconds_total Total user and system CPU time spent in seconds.
# TYPE process_cpu_seconds_total counter
process_cpu_seconds_total 14.05
# HELP process_open_fds Number of open file descriptors.
# TYPE process_open_fds gauge
process_open_fds 9.0
# HELP process_max_fds Maximum number of open file descriptors.
# TYPE process_max_fds gauge
process_max_fds 1.048576e+06
# HELP config_service_http_requests_total Total HTTP requests
# TYPE config_service_http_requests_total counter
config_service_http_requests_total{method="GET",path="/health",status="200"} 861.0
config_service_http_requests_total{method="CONNECT",path="",status="404"} 2.0
config_service_http_requests_total{method="GET",path="/",status="200"} 3.0
config_service_http_requests_total{method="GET",path="/favicon.ico",status="404"} 3.0
config_service_http_requests_total{method="GET",path="//api.ipify.org/",status="404"} 1.0
config_service_http_requests_total{method="GET",path="/geoserver/web/",status="404"} 1.0
config_service_http_requests_total{method="GET",path="/SDK/webLanguage",status="404"} 1.0
config_service_http_requests_total{method="GET",path="/hudson",status="404"} 1.0
config_service_http_requests_total{method="GET",path="/ui/app.js",status="200"} 1.0
config_service_http_requests_total{method="GET",path="/admin",status="200"} 2.0
config_service_http_requests_total{method="GET",path="/ui/admin.js",status="200"} 1.0
config_service_http_requests_total{method="GET",path="/metrics",status="200"} 2.0
config_service_http_requests_total{method="GET",path="/api/v1/admin/orgs/org1/nodes",status="401"} 3.0
config_service_http_requests_total{method="GET",path="/docs",status="200"} 1.0
config_service_http_requests_total{method="GET",path="/openapi.json",status="200"} 1.0
# HELP config_service_http_requests_created Total HTTP requests
# TYPE config_service_http_requests_created gauge
config_service_http_requests_created{method="GET",path="/health",status="200"} 1.780545620147977e+09
config_service_http_requests_created{method="CONNECT",path="",status="404"} 1.7805498539818988e+09
config_service_http_requests_created{method="GET",path="/",status="200"} 1.7805501015906265e+09
config_service_http_requests_created{method="GET",path="/favicon.ico",status="404"} 1.780550175528842e+09
config_service_http_requests_created{method="GET",path="//api.ipify.org/",status="404"} 1.7805503124855826e+09
config_service_http_requests_created{method="GET",path="/geoserver/web/",status="404"} 1.7805503512953792e+09
config_service_http_requests_created{method="GET",path="/SDK/webLanguage",status="404"} 1.7805506433382685e+09
config_service_http_requests_created{method="GET",path="/hudson",status="404"} 1.7805511785353012e+09
config_service_http_requests_created{method="GET",path="/ui/app.js",status="200"} 1.7805540319505973e+09
config_service_http_requests_created{method="GET",path="/admin",status="200"} 1.7805540411815536e+09
config_service_http_requests_created{method="GET",path="/ui/admin.js",status="200"} 1.7805540412612815e+09
config_service_http_requests_created{method="GET",path="/metrics",status="200"} 1.7805540641677992e+09
config_service_http_requests_created{method="GET",path="/api/v1/admin/orgs/org1/nodes",status="401"} 1.7805541280813484e+09
config_service_http_requests_created{method="GET",path="/docs",status="200"} 1.7805542503851593e+09
config_service_http_requests_created{method="GET",path="/openapi.json",status="200"} 1.780554252732188e+09
# HELP config_service_http_request_duration_seconds HTTP request duration in seconds
# TYPE config_service_http_request_duration_seconds histogram
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/health"} 860.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/health"} 860.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/health"} 860.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_count{method="GET",path="/health"} 861.0
config_service_http_request_duration_seconds_sum{method="GET",path="/health"} 0.6757256984710693
config_service_http_request_duration_seconds_bucket{le="0.005",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_count{method="CONNECT",path=""} 2.0
config_service_http_request_duration_seconds_sum{method="CONNECT",path=""} 0.002537965774536133
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_count{method="GET",path="/"} 3.0
config_service_http_request_duration_seconds_sum{method="GET",path="/"} 0.00844717025756836
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_count{method="GET",path="/favicon.ico"} 3.0
config_service_http_request_duration_seconds_sum{method="GET",path="/favicon.ico"} 0.002742767333984375
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="//api.ipify.org/"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="//api.ipify.org/"} 0.0009734630584716797
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="/geoserver/web/"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="/geoserver/web/"} 0.0009930133819580078
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="/SDK/webLanguage"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="/SDK/webLanguage"} 0.0009367465972900391
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="/hudson"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="/hudson"} 0.0011265277862548828
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="/ui/app.js"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="/ui/app.js"} 0.0011544227600097656
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_count{method="GET",path="/admin"} 2.0
config_service_http_request_duration_seconds_sum{method="GET",path="/admin"} 0.003081083297729492
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="/ui/admin.js"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="/ui/admin.js"} 0.0016393661499023438
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_count{method="GET",path="/metrics"} 2.0
config_service_http_request_duration_seconds_sum{method="GET",path="/metrics"} 0.0066738128662109375
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_count{method="GET",path="/api/v1/admin/orgs/org1/nodes"} 3.0
config_service_http_request_duration_seconds_sum{method="GET",path="/api/v1/admin/orgs/org1/nodes"} 0.0035142898559570312
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="/docs"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="/docs"} 0.0005173683166503906
config_service_http_request_duration_seconds_bucket{le="0.005",method="GET",path="/openapi.json"} 0.0
config_service_http_request_duration_seconds_bucket{le="0.01",method="GET",path="/openapi.json"} 0.0
config_service_http_request_duration_seconds_bucket{le="0.025",method="GET",path="/openapi.json"} 0.0
config_service_http_request_duration_seconds_bucket{le="0.05",method="GET",path="/openapi.json"} 0.0
config_service_http_request_duration_seconds_bucket{le="0.1",method="GET",path="/openapi.json"} 0.0
config_service_http_request_duration_seconds_bucket{le="0.25",method="GET",path="/openapi.json"} 0.0
config_service_http_request_duration_seconds_bucket{le="0.5",method="GET",path="/openapi.json"} 0.0
config_service_http_request_duration_seconds_bucket{le="1.0",method="GET",path="/openapi.json"} 1.0
config_service_http_request_duration_seconds_bucket{le="2.5",method="GET",path="/openapi.json"} 1.0
config_service_http_request_duration_seconds_bucket{le="5.0",method="GET",path="/openapi.json"} 1.0
config_service_http_request_duration_seconds_bucket{le="10.0",method="GET",path="/openapi.json"} 1.0
config_service_http_request_duration_seconds_bucket{le="+Inf",method="GET",path="/openapi.json"} 1.0
config_service_http_request_duration_seconds_count{method="GET",path="/openapi.json"} 1.0
config_service_http_request_duration_seconds_sum{method="GET",path="/openapi.json"} 0.5261178016662598
# HELP config_service_http_request_duration_seconds_created HTTP request duration in seconds
# TYPE config_service_http_request_duration_seconds_created gauge
config_service_http_request_duration_seconds_created{method="GET",path="/health"} 1.7805456201480265e+09
config_service_http_request_duration_seconds_created{method="CONNECT",path=""} 1.7805498539819345e+09
config_service_http_request_duration_seconds_created{method="GET",path="/"} 1.7805501015906594e+09
config_service_http_request_duration_seconds_created{method="GET",path="/favicon.ico"} 1.7805501755288699e+09
config_service_http_request_duration_seconds_created{method="GET",path="//api.ipify.org/"} 1.7805503124856064e+09
config_service_http_request_duration_seconds_created{method="GET",path="/geoserver/web/"} 1.780550351295403e+09
config_service_http_request_duration_seconds_created{method="GET",path="/SDK/webLanguage"} 1.7805506433383045e+09
config_service_http_request_duration_seconds_created{method="GET",path="/hudson"} 1.7805511785353343e+09
config_service_http_request_duration_seconds_created{method="GET",path="/ui/app.js"} 1.7805540319506245e+09
config_service_http_request_duration_seconds_created{method="GET",path="/admin"} 1.7805540411815856e+09
config_service_http_request_duration_seconds_created{method="GET",path="/ui/admin.js"} 1.780554041261313e+09
config_service_http_request_duration_seconds_created{method="GET",path="/metrics"} 1.780554064167819e+09
config_service_http_request_duration_seconds_created{method="GET",path="/api/v1/admin/orgs/org1/nodes"} 1.7805541280813692e+09
config_service_http_request_duration_seconds_created{method="GET",path="/docs"} 1.7805542503851812e+09
config_service_http_request_duration_seconds_created{method="GET",path="/openapi.json"} 1.780554252732217e+09
# HELP config_service_auth_failures_total Total authentication failures
# TYPE config_service_auth_failures_total counter
# HELP config_service_config_updates_total Total successful team config updates
# TYPE config_service_config_updates_total counter
config_service_config_updates_total 0.0
# HELP config_service_config_updates_created Total successful team config updates
# TYPE config_service_config_updates_created gauge
config_service_config_updates_created 1.7805456141135833e+09
# HELP config_service_config_cache_events_total Config cache events
# TYPE config_service_config_cache_events_total counter
# HELP config_service_admin_actions_total Total admin actions
# TYPE config_service_admin_actions_total counter
config_service_admin_actions_total{action="auth",outcome="denied"} 3.0
# HELP config_service_admin_actions_created Total admin actions
# TYPE config_service_admin_actions_created gauge
config_service_admin_actions_created{action="auth",outcome="denied"} 1.78055412808098e+09
# HELP incidentfox_agent_feedback_total Total agent feedback received
# TYPE incidentfox_agent_feedback_total counter
```