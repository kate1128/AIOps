# Kubernetes - 容器编排

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| scheduler 服务及部分中间件运行 |
| 部署方式 | 手动 kubectl apply |
| 版本 | - |

---

## 存在问题

- 部署手动，无 GitOps
- 监控?Zabbix，未全面接入 Prometheus
- 日志未集中采集
---

## 优化建议

- 引入 ArgoCD 实现 GitOps 部署
- 全面部署 Prometheus Operator + ServiceMonitor
- Promtail DaemonSet 采集所?Pod 日志

> 参考：`03-observability/`、`工具分析/04-ArgoCD.md`
