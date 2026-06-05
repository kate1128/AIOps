# Kong - API 网关

> 与Nginx + nginx-ingress-controller 的对比参考> 当前使用：Nginx + nginx-ingress-controller

---

## 是什么
Kong 是基于 OpenResty（Nginx + Lua）的 API 网关，在 Nginx 基础能力之上增加了 **插件生态**。通过插件实现认证、限流、日志、监控等功能，无需手动修改 Nginx 配置，通过 API 或声明式配置管理。
---

## 与Nginx 的核心区别
| 维度 | Nginx + nginx-ingress | Kong |
|------|----------------------|------|
| **配置方式** | 手动 conf / Ingress YAML 需 reload | Admin API / deck CLI 热生效 |
| **插件** | 需自写 Lua 或外挂 sidecar | 200+ 插件（限流/鉴权/日志/监控）|
| **Dashboard** | 无 | Kong Manager / Konga |
| **动态生效 * | 修改配置需 reload Nginx | API 调用立即生效，无需重启 |
| **K8s 集成** | Ingress CRD | KongIngress CRD |
| **性能** | 高（原生 Nginx）| 接近 Nginx（同样基于 OpenResty）|

---

## 引入 Kong 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 图形化 API 管理 | Kong Manager 界面管理所有路由、服务、上游 |
| ✅ 限流开箱即用| 内置 rate-limiting 插件，无需自己实现 |
| ✅ 认证策略丰富 | JWT / OAuth2 / OIDC / Key-Auth / LDAP 等|
| ✅ 动态生效| 路由变更无需 reload，无损流量切换 |
| ✅ 灰度发布 | 通过权重分配流量到不同上游版本 |
| ✅ 可观测性好 | 内置 Prometheus 指标 + 请求日志插件 |

## 引入 Kong 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 多维护一套集群| Kong 需要部署控制面（DB）和 数据面（Proxy）|
| ⛔ 学习成本 | 需要学习 Kong 的插件体系和管理方式 |
| ⛔ 排障链路增加 | 多了一层代理，排查问题时多一个环节 |
| ⛔ 已有 Ingress 迁移 | 现有 nginx-ingress 规则需转为 Kong 配置 |

---

## 参考
- https://konghq.com
- https://github.com/Kong/kong
- K8s 集成: https://github.com/Kong/kubernetes-ingress-controller
