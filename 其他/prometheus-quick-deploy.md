# Prometheus + Grafana 快速部署（含 GPU 监控）

> 跳过 Netdata，直接用 Prometheus + Grafana + DCGM Exporter，5 分钟出图。

---

## 一键部署脚本

```bash
#!/bin/bash
# deploy-prometheus.sh

NAMESPACE="observability"

# 1. 创建命名空间
kubectl create namespace $NAMESPACE 2>/dev/null || true

# 2. 添加 Helm 仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# 3. 部署 kube-prometheus-stack（Prometheus + Alertmanager + Grafana）
echo "部署 Prometheus + Grafana..."
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --set grafana.enabled=true \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.retention=30d \
  --set defaultRules.create=true

# 4. 部署 DCGM Exporter（GPU 监控）
echo "部署 DCGM Exporter..."
helm upgrade --install dcgm-exporter nvidia/dcgm-exporter \
  --namespace $NAMESPACE \
  --set serviceMonitor.enabled=true

# 5. 等待就绪
echo "等待 Pod 就绪..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n $NAMESPACE --timeout=300s

# 6. 暴露端口（测试用）
echo ""
echo "========================================"
echo "部署完成！"
echo "========================================"
echo ""
echo "Grafana:     http://localhost:3000  (admin/admin123)"
echo "Prometheus:  http://localhost:9090"
echo ""
echo "运行以下命令暴露端口："
echo "  kubectl port-forward -n $NAMESPACE svc/kube-prometheus-grafana 3000:80"
echo "  kubectl port-forward -n $NAMESPACE svc/kube-prometheus-prometheus 9090:9090"
```

---

## GPU 监控验证

```bash
# 查看 DCGM Exporter 指标
kubectl port-forward -n observability svc/dcgm-exporter 9400:9400
curl http://localhost:9400/metrics | grep DCGM

# 关键指标：
# DCGM_FI_DEV_GPU_UTIL        -- GPU 利用率
# DCGM_FI_DEV_FB_USED         -- 显存使用
# DCGM_FI_DEV_GPU_TEMP        -- GPU 温度
# DCGM_FI_DEV_POWER_USAGE     -- GPU 功耗
```

---

## 导入 GPU Dashboard

```
Grafana → Dashboards → Import
输入 Dashboard ID: 12239  （NVIDIA DCGM Exporter Dashboard）
选择 Prometheus 数据源
```

---

## 核心告警规则

```yaml
# gpu-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
  namespace: observability
spec:
  groups:
    - name: gpu
      rules:
        - alert: GPUHighTemperature
          expr: DCGM_FI_DEV_GPU_TEMP > 85
          for: 5m
          labels:
            severity: P1
          annotations:
            summary: "GPU {{ $labels.gpu }} 温度过高: {{ $value }}°C"
            
        - alert: GPUHighMemoryUsage
          expr: DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE > 0.9
          for: 10m
          labels:
            severity: P1
          annotations:
            summary: "GPU {{ $labels.gpu }} 显存使用率超过 90%"
```

---

## 与 Netdata 的对比

| 维度 | Netdata | Prometheus + Grafana |
|---|---|---|
| 部署 | Helm 一键 | Helm 一键 |
| GPU 支持 | 需配置 nvidia-smi | DCGM Exporter 原生支持 |
| 登录要求 | 需要注册登录 | 不需要 |
| 告警能力 | 基础 | 强大（Alertmanager） |
| 自定义查询 | 弱 | PromQL 强大 |
| 社区生态 | 小 | 大 |
| 长期趋势 | 弱（默认几天） | 强（可配置长期存储） |

---

## 下一步

1. 运行上面的脚本（5 分钟）
2. 访问 Grafana 看 GPU 指标
3. 导入 Dashboard ID: 12239
4. 配置飞书告警（Alertmanager Webhook）

试完告诉我效果。
