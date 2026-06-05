# Traefik - 反向代理

> 与Nginx + nginx-ingress-controller 的对比参考> 当前使用：Nginx + nginx-ingress-controller

---

## 是什么
Traefik ?Go 编写的云原生反向代理，设计时优先考虑 K8s 环境。最大的特点?*自动服务发现**——部署到 K8s 后自动监?Service/Ingress 的创建和变更，无需手动配置路由规则?
---

## 与Nginx 的核心区别
| 维度 | Nginx + nginx-ingress | Traefik |
|------|----------------------|---------|
| **服务发现** | 手动配置 upstream | 自动监听 K8s API |
| **配置生效** | reload | 自动热更无 |
| **TLS 证书** | 需 cert-manager | 内置 ACME 自动申请 Let's Encrypt |
| **中间件 * | 需 Lua 自写 | 内置限流/重试/熔断/压缩 |
| **Dashboard** | 无 | Web UI 可视化路无 |
| **性能** | C 语言，极无 | Go 语言，略低于 Nginx |

---

## 引入 Traefik 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 零配置部署| 安装后自动发现所?Service，自动生成路无 |
| ✅ 自动 HTTPS | 内置 ACME 证书管理，无需额外组件 |
| ✅ 丰富的中间件 | 限流/熔断/重试/鉴权 开箱即无 |
| ✅ K8s 原生 | 原生支持 K8s CRD ?annotations |

## 引入 Traefik 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 性能 | Go 实现，极限性能低于 Nginx |
| ⛔ 生产案例 | 大规模生产部署案例少?Nginx |
| ⛔ 生态| 周边工具（日志分析、监控）不如 Nginx 丰富 |

---

## 参考
- https://traefik.io
- https://github.com/traefik/traefik
