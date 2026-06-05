# Gatus — GitOps 健康检查

## 概述

Gatus 是轻量级健康检查工具，核心设计理念：**用 YAML 声明所有健康检查配置，放在 Git 中管理**。支持 HTTP、TCP、DNS、ICMP、ICMP 等多种检查方式。

## 核心能力

- **YAML 配置即代码**: 所有端点、检查条件、告警配置都在一个文件中
- **多条件检查**: 每个端点可配置多个检查条件（状态码、响应时间、证书过期、Body 内容）
- **Prometheus 指标**: 暴露 `/metrics` 端点，可被 Prometheus 抓取并统一告警
- **多告警渠道**: Webhook、Slack、Discord、Email、飞书
- **状态页**: 内置简洁状态页面，对外展示服务可用性

## 使用示例

```yaml
# gatus.yaml
endpoints:
  - name: vLLM API
    group: AI Service
    url: "https://api.smartvision.ai/v1/health"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
      - "[BODY].status == ok"
      - "[RESPONSE_TIME] < 500"
    alerts:
      - type: webhook
        enabled: true
        webhook-url: "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"

  - name: Inference
    group: AI Service
    url: "https://api.smartvision.ai/v1/chat/completions"
    method: POST
    body: '{"model":"default","messages":[{"role":"user","content":"ping"}]}'
    headers:
      Content-Type: application/json
      Authorization: Bearer ${API_KEY}
    conditions:
      - "[STATUS] == 200"
      - "[BODY].choices[0].message.content != null"
```

## 在本项目中的使用

- 声明所有 API 端点的健康检查配置在 Git 仓库中
- Gatus 暴露的 metrics 被 Prometheus 抓取，通过 Alertmanager 发送告警
- 状态页面公开给运维和 Support 团队

## 部署方式

```bash
docker run -d --name gatus \
  -p 8080:8080 \
  -v $(pwd)/gatus.yaml:/config/gatus.yaml \
  twinproduction/gatus
```
