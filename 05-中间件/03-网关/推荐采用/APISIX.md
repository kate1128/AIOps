# APISIX - 云原生 API 网关

> 推荐原因：SmartVision 当前仅用 Nginx 做反向代理，缺乏 API 鉴权、限流、插件化管理能力。APISIX 是 K8s-native、高性能的 API 网关，比 Kong 更轻量，有完整的管理 Dashboard，可作为 Nginx Ingress 的上层 API 管理层。
> 当前状态：❌ 未部署，推荐在 API 对外开放或多租户场景扩展时引入。

---

## 现状与问题

| 项目 | 现状 |
|------|------|
| 当前 API 入口 | Nginx / K8s Ingress |
| API 鉴权 | 各服务自行实现，不统一 |
| 限流 | 无统一限流，依赖服务自身 |
| API 监控 | 无 API 级别的调用量/延迟统计 |
| 多租户隔离 | License 系统控制，无网关层隔离 |

---

## APISIX 是什么

Apache APISIX 是 CNCF 毕业的云原生 API 网关，基于 Nginx + etcd，支持 80+ 内置插件，可以在不修改业务代码的情况下为 API 添加：鉴权、限流、熔断、监控、日志、灰度路由、WAF 等能力。

---

## 核心能力对比

| 能力 | Nginx Ingress | APISIX |
|------|--------------|--------|
| 反向代理 | ✅ | ✅ |
| TLS 终止 | ✅ | ✅ |
| API Key 鉴权 | ❌ 需自行实现 | ✅ 内置插件 |
| JWT 验证 | ❌ | ✅ 内置插件 |
| 限流（rate-limit）| ❌ | ✅ 内置，支持 IP/用户/路由维度 |
| 熔断（circuit-breaker）| ❌ | ✅ 内置插件 |
| 灰度路由 | ❌ | ✅ 支持按 Header/比例分流 |
| API 级别监控 | ❌ | ✅ 内置 Prometheus 插件 |
| Dashboard | ❌ | ✅ APISIX Dashboard |
| 动态配置（无需重启）| ❌ | ✅ etcd 热更新 |

---

## K8s 部署

```bash
# 使用 Helm 部署 APISIX + Dashboard + Ingress Controller
helm repo add apisix https://charts.apiseven.com
helm repo update

helm install apisix apisix/apisix \
  --namespace apisix \
  --create-namespace \
  --set gateway.type=NodePort \
  --set ingress-controller.enabled=true \
  --set dashboard.enabled=true \
  --set etcd.replicaCount=1  # 生产建议 3
```

---

## 核心插件配置示例

```yaml
# 1. API Key 鉴权（为 SmartVision API 添加 key-auth）
curl -X POST http://apisix-admin:9180/apisix/admin/consumers \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -d '{
    "username": "client-001",
    "plugins": {
      "key-auth": {
        "key": "client-001-api-key-xxxx"
      }
    }
  }'

# 2. 限流（按 IP，每分钟 100 次）
{
  "plugins": {
    "limit-req": {
      "rate": 100,
      "burst": 10,
      "key": "remote_addr",
      "rejected_code": 429
    }
  }
}

# 3. Prometheus 监控指标暴露
{
  "plugins": {
    "prometheus": {
      "prefer_name": true
    }
  }
}
# 采集路径：http://apisix:9091/apisix/prometheus/metrics
```

---

## 与 Nginx Ingress 的协作方案

APISIX 不需要完全替换 Nginx，可以分层使用：

```
外部流量
   │
   ▼
Nginx Ingress（TLS 终止，7层负载均衡）
   │
   ▼
APISIX Gateway（API 管理层：鉴权、限流、监控）
   │
   ▼
业务服务（vLLM、SmartVision API）
```

或直接使用 APISIX 替代 Nginx Ingress（更彻底）。

---

## 监控接入

```yaml
# Prometheus ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: apisix
  namespace: apisix
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: apisix
  endpoints:
  - port: prometheus
    path: /apisix/prometheus/metrics
    interval: 15s
```

**关键指标：**
- `apisix_http_requests_total` - API 请求量（按路由）
- `apisix_http_latency_bucket` - 请求延迟分布
- `apisix_http_status` - HTTP 状态码分布（监控 5xx）

---

## 引入优先级

| 触发条件 | 优先级 |
|---------|--------|
| 需要为 API 添加统一鉴权（多租户场景）| 🔴 高优 |
| 需要 API 限流防止滥用 | 🟡 中优 |
| 需要 API 级别监控和 Dashboard | 🟡 中优 |
| 当前只是内部服务互通，无外部 API | ⚪ 暂缓 |

---

## 参考

- 官方文档：https://apisix.apache.org/docs/apisix/getting-started/
- K8s Ingress Controller：https://apisix.apache.org/docs/ingress-controller/getting-started/
- 插件列表：https://apisix.apache.org/plugins/
