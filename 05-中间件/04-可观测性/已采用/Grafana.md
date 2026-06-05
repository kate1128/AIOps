# Grafana - 可视化
> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 指标可视化 |
| 部署方式 | 待确认 |
| 版本 | - |
| Dashboard | 未分类管理 |

---

## Dashboard 目录体系

```
Grafana Dashboards
├── 基础设施
?  ├── Kubernetes 集群概览?15??  └── 节点资源?860?├── 中间??  ├── PostgreSQL?628??  ├── Redis?63??  ├── Kafka
?  ├── RabbitMQ
?  └── Nginx
├── 应用
?  ├── Java 服务（JVM/请求/错误??  ├── ai-backend（推理延?QPS??  └── scheduler（调度队?GPU?└── 业务
    ├── 用户请求?    ├── AI 推理成功率    └── 业务 SLA
```

---

## 告警统一管理

```yaml
apiVersion: 1
groups:
  - orgId: 1
    name: smartvision-alerts
    rules:
      - uid: high_error_rate
        title: "错误率过?
        condition: "avg() of query(A, 5m) > 0.05"
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: 'rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])'
        notifications:
          - uid: feishu-notifier
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | Dashboard 按目录分类管理 |
| P1 | 告警统一收敛?Grafana |
| P1 | 值班首页钉选关键面板 |
