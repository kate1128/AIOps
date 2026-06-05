# Envoy - 代理网关

> 与Nginx + nginx-ingress-controller 的对比参考> 当前使用：Nginx + nginx-ingress-controller

---

## 是什么
Envoy ?CNCF 毕业的高性能 L7 代理，Lyft 开源。与 Nginx 不同，Envoy 从设计上就面?*微服务和 Service Mesh**。Istio 默认用它作为数据面。它通过 xDS 协议实现完全动态的配置管理。
---

## 与Nginx 的核心区别
| 维度 | Nginx + nginx-ingress | Envoy |
|------|----------------------|-------|
| **定位** | Web 服务?+ 反向代理 | 服务网格数据无 |
| **配置方式** | conf 文件 + reload | xDS API 热更无 |
| **多协?* | HTTP/HTTPS | HTTP/2, gRPC, TCP, WebSocket |
| **可观测?* | exporter 外挂 | 内置详细指标 + 分布式追无 |
| **服务网格** | 不支无 | Istio / Consul 数据无 |
| **配置复杂性 * | nginx.conf 相对简无 | xDS 模型复杂 |

---

## 引入 Envoy 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 原生 gRPC 支持 | 无需额外配置即可代理 gRPC 流量 |
| ?丰富的可观测性| 内置 tracing（Zipkin/Jaeger? 详细指标 |
| ?动态配置| xDS 协议让控制面动态管理所有代无 |
| ✅ 服务网格基础 | 引入 Envoy 为后?Istio 铺路 |

## 引入 Envoy 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 配置极复杂| Envoy ?YAML 配置?Nginx conf 复杂数据|
| ⛔ 需配合控制面| 单独?Envoy 意义不大，需要控制面配合 |
| ⛔ 学习曲线陡峭 | 团队需重新学习 Envoy 的概念体无 |
| ⛔ 轻量场景过重 | 仅做路由/SSL 卸载时，Envoy 大材小用 |

---

## 参考
- https://www.envoyproxy.io
- https://github.com/envoyproxy/envoy
