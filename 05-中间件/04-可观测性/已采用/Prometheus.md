# Prometheus - 指标采集

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 指标采集 |
| 部署方式 | 待确认 |
| 版本 | - |
| 存储 | - |
| 覆盖 | 与 Zabbix 并存，覆盖面不全 |

---

## K8s 部署

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storage=100Gi
```

---

## 关键告警规则

```yaml
- alert: InstanceDown
  expr: up == 0
  for: 1m
  labels: { severity: critical }
- alert: NodeHighMemory
  expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
  for: 5m
  labels: { severity: warning }
- alert: PodCrashLooping
  expr: increase(kube_pod_container_status_restarts_total[5m]) > 3
  for: 2m
  labels: { severity: warning }
```

---

## ServiceMonitor 自动发现

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: smartvision-app
  namespace: observability
spec:
  selector:
    matchLabels:
      app.kubernetes.io/monitored: "true"
  endpoints:
    - port: metrics
      interval: 15s
  namespaceSelector:
    matchNames: [prod, dev]
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 全面替代 Zabbix，统一监控面板|
| P0 | 告警接入飞书（AlertManager Webhook）|
| P1 | ServiceMonitor 标注标准化 |
| P1 | 业务指标 /metrics 端点接入 |
