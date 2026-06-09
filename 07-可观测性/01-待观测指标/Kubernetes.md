# Kubernetes 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Kubernetes Metrics：[Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
2. kube-state-metrics：[kubernetes/kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
3. kube-prometheus-stack：[prometheus-community/helm-charts](https://github.com/prometheus-community/helm-charts)
4. Grafana Kubernetes Monitoring：[Grafana Kubernetes Monitoring](https://grafana.com/docs/grafana-cloud/monitor-infrastructure/kubernetes-monitoring/)
5. Alloy Kubernetes discovery：[discovery.kubernetes](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.kubernetes/)

---

## 1. 结论摘要

Kubernetes 可观测性由 kubelet/cAdvisor、kube-state-metrics、node-exporter（或 Alloy unix exporter）、API Server、事件和日志共同组成。Grafana Alloy **完全支持 Kubernetes 指标采集**，可通过 `discovery.kubernetes`、`prometheus.scrape`、`prometheus.exporter.unix`、`loki.source.kubernetes` 构建统一指标+日志管道。注意：Alloy 不能替代 kube-state-metrics，KSM 仍需独立部署以生成 K8s 对象状态指标。

| 关键信息 | 值 |
| --- | --- |
| Pod/容器资源 | kubelet `/metrics/cadvisor` |
| K8s 对象状态 | kube-state-metrics |
| 节点指标 | node-exporter 或 Alloy `prometheus.exporter.unix` |
| 日志 | Alloy `loki.source.kubernetes` / PodLogs |
| 推荐方案 | kube-prometheus-stack 或 Grafana Alloy Kubernetes Monitoring |

---

## 2. 产品概况

| 组件 | 指标内容 | 说明 |
| --- | --- | --- |
| kubelet | Pod/容器资源、kubelet 自身 | 每节点 |
| cAdvisor | 容器 CPU/内存/网络/磁盘 | kubelet 内置 |
| kube-state-metrics | Pod/Deployment/Node/PVC 状态 | 对象状态必需 |
| node-exporter / unix exporter | 节点 CPU/内存/磁盘/网络 | 主机层 |
| metrics-server | HPA 资源指标 | 非长期监控 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `kube_node_status_condition{condition="Ready"}` | 节点 Ready 状态 | NotReady > 2m 告警 |
| `kube_pod_status_phase{phase="Pending"}` | Pending Pod | > 0 持续 5m 关注 |
| `kube_deployment_status_replicas_unavailable` | 不可用副本 | > 0 告警 |
| `kube_pod_container_status_restarts_total` | 容器重启 | 15m 内增长告警 |
| `container_cpu_usage_seconds_total` | 容器 CPU | 接近 limit 告警 |
| `container_memory_working_set_bytes` | 容器工作集内存 | > 90% limit 告警 |
| `kube_persistentvolumeclaim_resource_requests_storage_bytes` | PVC 申请容量 | 容量规划 |
| `node_filesystem_avail_bytes` | 节点磁盘剩余 | < 10% 告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| kube-prometheus-stack | Helm | K8s 标准全套 | 需 Loki/Promtail | 传统标准方案 |
| **Grafana Alloy** | DaemonSet / Helm | kubelet、unix、KSM scrape | 内置 Loki | **统一采集推荐** |
| OpenTelemetry Collector | DaemonSet | kubeletstats / logs | 支持 | OTel 体系 |
| Netdata | DaemonSet | 系统和容器 | 内置 | 小规模快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 Pod 指标自动发现

```alloy
discovery.kubernetes "pods" {
  role = "pod"
  namespaces { own_namespace = false }
}

prometheus.scrape "pods" {
  targets = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.2 kube-state-metrics

```alloy
prometheus.scrape "kube_state_metrics" {
  targets = [{ __address__ = "kube-state-metrics.kube-system.svc:8080" }]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.3 kubelet / cAdvisor

```alloy
prometheus.scrape "kubelet_cadvisor" {
  targets = [{ __address__ = "NODE_IP:10250", __scheme__ = "https" }]
  metrics_path = "/metrics/cadvisor"
  tls_config { insecure_skip_verify = true }
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.4 节点指标（替代 node-exporter）

```alloy
prometheus.exporter.unix "node" {
  set_collectors = ["cpu", "meminfo", "diskstats", "filesystem", "netdev", "nfs", "nfsd"]
}

prometheus.scrape "node" {
  targets = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.5 Pod 日志

```alloy
loki.source.kubernetes.podlogs "pods" {
  targets = discovery.kubernetes.pods.targets
  forward_to = [loki.write.default.receiver]
}
```

---

## 6. 部署方案

| 方案 | 说明 |
| --- | --- |
| kube-prometheus-stack | Prometheus Operator 标准方案 |
| Grafana k8s-monitoring Helm | Alloy 为核心采集组件 |
| 混合部署 | 保留 KSM/Prometheus，使用 Alloy 替代 node-exporter/Promtail |

---

## 7. 告警规则

```yaml
groups:
- name: kubernetes.rules
  rules:
  - alert: KubeNodeNotReady
    expr: kube_node_status_condition{condition="Ready",status="true"} == 0
    for: 2m
    labels: { severity: critical }
    annotations: { summary: "Kubernetes 节点 NotReady" }

  - alert: KubePodCrashLooping
    expr: increase(kube_pod_container_status_restarts_total[15m]) > 3
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Pod 频繁重启" }

  - alert: KubeDeploymentReplicasUnavailable
    expr: kube_deployment_status_replicas_unavailable > 0
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Deployment 存在不可用副本" }
```

---

## 8. Grafana Dashboard

推荐使用 Kubernetes / Compute Resources / Nodes / Pods / Deployments 等 kube-prometheus-stack 或 Grafana Kubernetes Monitoring 预置 Dashboard。

---

## 9. KAgent 集成（Kubernetes 运维 Agent）

KAgent 本身是 Kubernetes-native Agent，推荐绑定 PrometheusServer 查询 K8s 指标，并通过 Skills 注入 Pod Pending、CrashLoopBackOff、节点 NotReady、PVC 满等 Runbook。

---

## 10. 常见问题

### Grafana Alloy 支持 Kubernetes 指标采集吗？

**完全支持。** Alloy 是 Grafana Kubernetes Monitoring 的核心采集组件，可采集 Pod、kubelet、cAdvisor、KSM、节点和日志。

### Alloy 能替代 kube-state-metrics 吗？

不能。Alloy 负责采集和转发；kube-state-metrics 负责生成 K8s 对象状态指标，仍需独立部署。

### metrics-server 能替代 Prometheus 吗？

不能。metrics-server 面向 HPA/VPA 等资源调度，不适合长期存储、告警和 Dashboard 分析。
# Kubernetes 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Kubernetes Metrics：[Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
2. kube-state-metrics：[kubernetes/kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
3. kube-prometheus-stack：[prometheus-community/helm-charts](https://github.com/prometheus-community/helm-charts)
4. Alloy Kubernetes discovery：[discovery.kubernetes](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.kubernetes/)
5. Grafana k8s-monitoring Helm Chart：[k8s-monitoring](https://grafana.com/docs/grafana-cloud/monitor-infrastructure/kubernetes-monitoring/)

---

## 1. 结论摘要

Kubernetes 可观测性由 kubelet/cAdvisor、kube-state-metrics、node-exporter（或 Alloy `prometheus.exporter.unix`）、metrics-server、事件和日志共同组成。Grafana Alloy **完全支持 Kubernetes 指标采集**，可通过 `discovery.kubernetes`、`prometheus.scrape`、`prometheus.exporter.unix`、`loki.source.kubernetes` 统一采集指标和日志；但 kube-state-metrics 仍需独立部署，Alloy 不能替代它生成 K8s 对象状态指标。

| 关键信息 | 值 |
| --- | --- |
| Pod/容器资源 | kubelet `/metrics/cadvisor` |
| K8s 对象状态 | kube-state-metrics |
| 节点指标 | node-exporter 或 Alloy `prometheus.exporter.unix` |
| 日志 | Alloy Kubernetes Pod logs / Loki |
| 推荐方案 | kube-state-metrics + Alloy 统一采集 |

---

## 2. 产品概况

| 组件 | 指标内容 | 说明 |
| --- | --- | --- |
| kubelet | Pod、容器、Volume、节点运行指标 | 每个节点内置 |
| cAdvisor | 容器 CPU/内存/网络/磁盘 | kubelet 内置 |
| kube-state-metrics | Deployment、Pod、Node、PVC 等对象状态 | 必须独立部署 |
| node-exporter / unix exporter | Linux 节点 CPU/内存/磁盘/网络 | Alloy 可替代 node-exporter |
| metrics-server | HPA/VPA 资源指标 | 不建议作为监控长期存储 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `kube_node_status_condition{condition="Ready"}` | 节点 Ready 状态 | 非 Ready > 0 告警 |
| `kube_pod_status_phase{phase="Pending"}` | Pending Pod | > 0 持续 10m 告警 |
| `kube_deployment_status_replicas_unavailable` | 不可用副本 | > 0 告警 |
| `kube_pod_container_status_restarts_total` | 容器重启次数 | 15m 内增长告警 |
| `kube_pod_container_status_waiting_reason` | 等待原因 | CrashLoopBackOff 立即告警 |
| `container_cpu_usage_seconds_total` | 容器 CPU | 超 request/limit 关注 |
| `container_memory_working_set_bytes` | 容器工作集内存 | > 90% limit 告警 |
| `kubelet_volume_stats_used_bytes` | PVC 使用量 | > 85% 告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| kube-prometheus-stack | Helm | Prometheus + KSM + node-exporter | 需 Promtail/Alloy | 传统标准方案 |
| **Grafana Alloy** | DaemonSet / Helm | kubelet scrape + unix exporter + logs | 内置 | **本项目推荐** |
| k8s-monitoring Helm Chart | Helm | Alloy 全栈封装 | 内置 | Grafana Cloud / Mimir |
| Netdata | DaemonSet | 系统/容器 | 内置 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 Kubernetes 自动发现

```alloy
discovery.kubernetes "pods" {
  role = "pod"
  selectors { role = "pod" label = "environment=production" }
}

prometheus.scrape "pods" {
  targets = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.2 kubelet / cAdvisor

```alloy
prometheus.scrape "kubelet_cadvisor" {
  targets = [{ __address__ = "NODE_IP:10250", __scheme__ = "https" }]
  metrics_path = "/metrics/cadvisor"
  tls_config { insecure_skip_verify = true }
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.3 kube-state-metrics

```alloy
prometheus.scrape "kube_state_metrics" {
  targets = [{ __address__ = "kube-state-metrics.kube-system.svc:8080" }]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.4 节点指标（替代 node-exporter）

```alloy
prometheus.exporter.unix "node" {
  set_collectors = ["cpu", "meminfo", "diskstats", "filesystem", "netdev", "nfs", "nfsd"]
}

prometheus.scrape "node" {
  targets = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.5 Pod 日志采集

```alloy
loki.source.kubernetes.podlogs "pods" {
  targets = discovery.kubernetes.pods.targets
  forward_to = [loki.write.default.receiver]
}
```

---

## 6. 部署方式对比

| 部署方式 | 采集方式 |
| --- | --- |
| K3s / K8s | Alloy DaemonSet + kube-state-metrics |
| 传统 Prometheus | kube-prometheus-stack |
| Grafana Cloud | k8s-monitoring Helm Chart |
| 混合部署 | Kubernetes discovery + static_configs |

---

## 7. 告警规则

```yaml
groups:
- name: kubernetes.rules
  rules:
  - alert: KubeNodeNotReady
    expr: kube_node_status_condition{condition="Ready",status="true"} == 0
    for: 5m
    labels: { severity: critical }
    annotations: { summary: "Kubernetes 节点不可用" }

  - alert: KubePodCrashLooping
    expr: increase(kube_pod_container_status_restarts_total[15m]) > 3
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "Pod 频繁重启" }

  - alert: KubePersistentVolumeUsageHigh
    expr: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
    for: 10m
    labels: { severity: warning }
    annotations: { summary: "PVC 使用率超过 85%" }
```

---

## 8. Grafana Dashboard

推荐使用 Kubernetes / Compute Resources / Node Exporter / Kubelet / kube-state-metrics 系列 Dashboard，并按集群、命名空间、工作负载、Pod 四层组织。

---

## 9. KAgent 集成（Kubernetes 运维 Agent）

推荐绑定 PrometheusServer 和 Kubernetes ToolServer，支持查询指标、Pod 状态、事件和日志；Skills 中注入 CrashLoopBackOff、Pending、PVC 满、节点 NotReady 的处理 SOP。

---

## 10. 常见问题

### Grafana Alloy 支持 Kubernetes 指标采集吗？

**完全支持。** Alloy 可通过 `discovery.kubernetes` 自动发现目标，通过 `prometheus.scrape` 抓取 kubelet、KSM、应用指标，并通过 Loki 组件采集 Pod 日志。

### Alloy 能替代 kube-state-metrics 吗？

不能。kube-state-metrics 负责把 Kubernetes 对象状态转换为 Prometheus 指标，Alloy 负责抓取与转发，二者角色不同。

### Alloy 能替代 node-exporter 吗？

可以在 Linux 节点指标层面替代。Alloy 内置 `prometheus.exporter.unix`，可采集 CPU、内存、磁盘、网络、NFS 等宿主机指标。
