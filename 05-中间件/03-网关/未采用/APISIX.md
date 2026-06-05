# APISIX ?API 网关

> 与Nginx + nginx-ingress-controller 的对比参考> 当前使用：Nginx + nginx-ingress-controller

---

## 是什么
APISIX ?Apache 基金会孵化的云原?API 网关，基?OpenResty。与 Kong 同样定位，但更轻量。核心特点是**插件热加载 *（修改插件不重启进程）和 **radixtree 路由**（毫秒级匹配）?
---

## 与Nginx 的核心区别
| 维度 | Nginx + nginx-ingress | APISIX |
|------|----------------------|--------|
| **路由性能** | Nginx 正则匹配 | radixtree 前缀树（O(1) 匹配）|
| **插件热加载 * | 改配置需 reload | 增删插件不重写 |
| **Dashboard** | 无 | APISIX Dashboard |
| **多集群管理 * | 各集群独?ingress | 统一控制面管理多个集无 |
| **K8s Ingress** | nginx-ingress-controller | apisix-ingress-controller |
| **性能** | 无 | 更高（路由算法优势）|

---

## 引入 APISIX 你能得到什么
| 收益 | 说明 |
|------|------|
| ✅ 热加载| 插件和路由变更不中断服务，适合频繁调整的场景 |
| ✅ 高性能路由 | radixtree 算法在大量路由规则下性能优于 Nginx |
| ✅ 多集群统一管理 | 一?APISIX 控制面管理多?K8s 集群 |
| ✅ 内置功能丰富 | 限流/熔断/重试/日志/监控 插件齐全 |

## 引入 APISIX 的代价
| 代价 | 说明 |
|------|------|
| ⛔ 社区规模 | ?Kong ?Nginx 社区小，中文资料为主 |
| ⛔ 生态成熟度 | 部分插件不如 Kong 丰富 |
| ⛔ 运维工具链| 周边工具（日?监控集成）不?Nginx 成熟 |

---

## 参考
- https://apisix.apache.org
- https://github.com/apache/apisix
