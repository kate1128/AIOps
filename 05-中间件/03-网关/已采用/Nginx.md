# Nginx + nginx-ingress-controller - 网关

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 南北向流量入?+ K8s Ingress 控制无 |
| 架构 | Nginx 反向代理 + nginx-ingress-controller |
| 版本 | - |
| 治理策略 | 无统一限流/鉴权 |

---

## 当前架构

```
Internet ?Nginx（负载均?+ SSL 卸载?              └── nginx-ingress-controller
                      ├── ai-backend
                      ├── java-service
                      ├── scheduler
                      └── Web UI
```

---

## Ingress 定义

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: smartvision-ingress
  namespace: prod
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
    nginx.ingress.kubernetes.io/limit-rps: "1000"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [api.smartvision.cn]
      secretName: smartvision-tls
  rules:
    - host: api.smartvision.cn
      http:
        paths:
          - path: /api/v1/ai
            pathType: Prefix
            backend:
              service: { name: ai-backend, port: { number: 8080 } }
          - path: /api/v1/business
            pathType: Prefix
            backend:
              service: { name: java-service, port: { number: 8080 } }
```

---

## Nginx 安全配置

```nginx
server_tokens off;
client_max_body_size 100m;
proxy_connect_timeout 30s;
proxy_read_timeout 120s;

# 日志格式（JSON 便于 Loki 采集?log_format json_analytics escape=json '{'
  '"time":"$time_local","remote_addr":"$remote_addr",'
  '"request":"$request","status":$status,'
  '"request_time":$request_time,"request_id":"$request_id"'
'}';
```

---

## 监控

```promql
rate(nginx_http_requests_total[1m])
histogram_quantile(0.99, rate(nginx_ingress_controller_request_duration_seconds_bucket[5m]))
rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) * 100
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 统一限流（防止单服务拖垮整体）|
| P0 | 请求日志 JSON 格式 + 接入 Loki |
| P1 | SSL 证书自动化（cert-manager）|
| P1 | 灰度发布支持（Ingress 权重路由）|
| P2 | 评估 Kong/APISIX 全功能网无 |

> 参考：`工具分析/01-Kong.md`、`03-APISIX.md`
