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

---

## 采集器方案对比

| 采集器 | 部署方式 | K8s 指标覆盖 | 日志支持 | 适用场景 |
|--------|---------|-------------|---------|---------|
| kube-prometheus-stack | Helm 一键部署 | kubelet + KSM + cAdvisor + node-exporter | 需 Promtail | K8s 标准方案 |
| Grafana Alloy | DaemonSet | 内置 unix exporter + KSM + kubelet scrape | 内置 loki.source.kubernetes.podlogs | Grafana 全栈 |
| Netdata | DaemonSet/容器 | 系统 + 容器 + 应用层 | 内置日志查看 | 快速部署、小团队 |
| OTel Collector | Sidecar/DaemonSet | kubeletstats receiver | 日志 receiver | OTel 原生全链路 |

### 指标覆盖对比

| 指标维度 | kube-prometheus-stack | Alloy | Netdata |
|---------|----------------------|-------|---------|
| Pod CPU/内存 | ✅ kubelet cAdvisor | ✅ | ✅ |
| Pod 网络 | ✅ kubelet cAdvisor | ✅ | ✅ |
| Pod 磁盘 | ✅ kubelet cAdvisor | ✅ | ✅ |
| 节点资源 | ✅ node-exporter | ✅ 内置 unix exporter | ✅ 内置 |
| K8s 对象状态 | ✅ kube-state-metrics | ✅ 需部署 KSM | ❌ 无 |
| HPA 状态 | ✅ | ✅ | ❌ |
| PVC 使用 | ✅ kubelet | ✅ | ✅ |
| 容器日志 | 需 Promtail | ✅ 内置 | ✅ 内置 |
| K8s 事件 | ✅ event-exporter | ✅ | ❌ |

---

## Alloy 采集配置（K8s 全链路）

```alloy
// ===== 节点指标（替代 node-exporter）=====
prometheus.exporter.unix "node" {
  set_collectors = ["cpu", "meminfo", "diskstats", "filesystem", "netdev", "nfs", "nfsd"]
}

prometheus.scrape "node_metrics" {
  targets    = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.central.receiver]
}

// ===== kube-state-metrics =====
prometheus.scrape "kube_state_metrics" {
  targets = [{ __address__ = "kube-state-metrics.kube-system.svc:8080" }]
  forward_to = [prometheus.remote_write.central.receiver]
}

// ===== kubelet cAdvisor =====
prometheus.scrape "kubelet_cadvisor" {
  targets         = [{ __address__ = "NODE_IP:10250", __scheme__ = "https" }]
  metrics_path    = "/metrics/cadvisor"
  scrape_interval = "30s"
  tls_config { insecure_skip_verify = true }
  forward_to      = [prometheus.remote_write.central.receiver]
}

// ===== kubelet 自身指标 =====
prometheus.scrape "kubelet" {
  targets         = [{ __address__ = "NODE_IP:10250", __scheme__ = "https" }]
  metrics_path    = "/metrics"
  scrape_interval = "30s"
  tls_config { insecure_skip_verify = true }
  forward_to      = [prometheus.remote_write.central.receiver]
}

// ===== 日志采集（K8s Pod） =====
loki.source.kubernetes.podlogs "pods" {
  targets    = discovery.kubernetes.podlogs.targets
  forward_to = [loki.process.k8s_logs.receiver]
}

loki.process "k8s_logs" {
  forward_to = [loki.write.loki_backend.receiver]
  stage.drop { source = "container_name", expression = "(alloy|grafana|loki)" }
}

// ===== 远端写入 =====
prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}

loki.write "loki_backend" {
  endpoint { url = "http://loki.observability.svc:3100/loki/api/v1/push" }
}
```

---

## 方案对比

| 维度 | kube-prometheus-stack | Alloy + Prometheus | Netdata |
|------|----------------------|-------------------|---------|
| 部署复杂度 | 中（Helm 一键） | 中（DaemonSet + Helm） | 低（一键安装） |
| 维护成本 | 低（社区成熟） | 低 | 低 |
| K8s 对象状态 | ✅ KSM 必须独立部署 | ✅ 仍需 KSM | ❌ |
| 日志采集 | 需 Promtail | 内置 | 内置 |
| Grafana 兼容 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 灵活度 | 高（CRD 自定义） | 高（River 语法） | 中 |
| 推荐场景 | K8s 标准方案 | Grafana 全栈统一 | 快速验证、小集群 |

> **SmartVision 建议**：K8s 环境推荐 kube-prometheus-stack 作为基础，Alloy 作为升级方向（统一指标+日志采集）。
