# Kubernetes 可观测性

> K8s / K3s 通过 kubelet、kube-state-metrics、cAdvisor 提供多层级指标。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| kubelet /metrics | Kubelet 内置 cAdvisor + pod 指标 | TCP 10250 /metrics |
| kube-state-metrics | K8s 对象状态（Pod/Deployment/Node）| TCP 8080 /metrics |
| node-exporter | 节点资源指标 | TCP 9100 /metrics |
| metrics-server | 资源用量（CPU/Memory 用于 HPA）| TCP 443 /metrics |
| kube-prometheus-stack | 上述组件一键部署 + Prometheus Operator | Helm Chart |

---

## 核心指标

### 集群级

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `kube_node_status_condition{condition="Ready",status="true"}` | 节点就绪数 | == 0 告警 |
| `kube_node_status_capacity` / `kube_node_status_allocatable` | 节点资源容量 | 超分比 > 100% 告警 |
| `kube_pod_status_phase{phase="Pending"}` | Pending Pod 数 | > 0 关注 |
| `kube_pod_status_phase{phase="Failed"}` | Failed Pod 数 | > 0 告警 |
| `kube_deployment_status_replicas_unavailable` | Deployment 不可用副本数 | > 0 告警 |

### Pod 级（cAdvisor）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `container_cpu_usage_seconds_total` | CPU 使用率 | — |
| `container_memory_working_set_bytes` | 内存 RSS | > 90% request/limit 告警 |
| `container_network_receive_bytes_total` | 网络入流量 | — |

### 调度级

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `kube_pod_container_status_restarts_total` | Pod 重启次数 | > 5 次告警 |
| `kube_pod_container_status_waiting_reason` | Pod 等待原因（CrashLoopBackOff）| 立即告警 |
| `kube_job_status_failed` | Job 失败数 | > 0 告警 |

---

## 采集集成

```yaml
# kube-prometheus-stack 一键安装
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace

# 默认自动采集
# - kubelet /metrics/cadvisor（Pod 资源）
# - kube-state-metrics（对象状态）
# - node-exporter（节点状态）
# 无需额外配置

# 自定义 ServiceMonitor（采集特定服务）
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: observability
spec:
  selector:
    matchLabels:
      app: my-service
  endpoints:
    - port: metrics
      interval: 15s
```

---

## 告警规则

```yaml
- alert: KubeNodeNotReady
  expr: kube_node_status_condition{condition="Ready",status="true"} == 0
  for: 2m
  annotations:
    summary: "节点 {{ $labels.node }} 不可用"

- alert: KubePodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
  for: 5m
  annotations:
    summary: "Pod {{ $labels.pod }} 频繁重启"

- alert: KubeDeploymentReplicasUnavailable
  expr: kube_deployment_status_replicas_unavailable > 0
  for: 5m
  annotations:
    summary: "Deployment {{ $labels.deployment }} 副本不可用"

- alert: KubePersistentVolumeUsageCritical
  expr: klet_pvc_usage_bytes / klet_pvc_capacity_bytes > 0.9
  for: 5m
  annotations:
    summary: "PVC {{ $labels.persistentvolumeclaim }} 使用率超过 90%"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| K3s 生产集群 | kube-prometheus-stack Helm 安装，ServiceMonitor 自动发现 |
| 非 K8s 节点 | node-exporter 裸机部署覆盖 |
| 混合部署 | Prometheus 同时配置 static_configs（二进制/Docker 宿主机）+ ServiceMonitor（K8s）|

K3s 默认不启用 kube-state-metrics，需通过 Helm 添加。K3s 使用 containerd 而非 docker，cAdvisor 的容器指标仍可通过 kubelet /metrics/cadvisor 获取。
