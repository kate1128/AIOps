# HAMI 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. HAMI GitHub：[Project-HAMi/HAMi](https://github.com/Project-HAMi/HAMi)
2. HAMI 文档：[HAMi Documentation](https://project-hami.io/)
3. NVIDIA DCGM Exporter：[NVIDIA/dcgm-exporter](https://github.com/NVIDIA/dcgm-exporter)
4. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)

> Grafana 官方知识来源没有 HAMi 专用 Alloy 集成；若 HAMI 暴露 Prometheus `/metrics`，Alloy 可通过通用 `prometheus.scrape` 抓取。

---

## 1. 结论摘要

HAMI 是 Kubernetes GPU 共享与虚拟化中间件，关注 GPU 分配、显存池、vGPU 调度和 Pod 资源申请状态。HAMI 指标需要与 DCGM Exporter 组合使用：HAMI 反映“分配视角”，DCGM 反映“硬件实际使用视角”。在 Alloy 体系下，HAMI 没有专用 exporter 组件，使用 `prometheus.scrape` 抓取 HAMI `/metrics` 和 DCGM `:9400/metrics`。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | HAMI 内置 Prometheus 指标 + DCGM Exporter |
| HAMI 指标 | GPU 分配、显存分配、vGPU、Pending 容器 |
| DCGM 指标 | GPU 实际利用率、显存、温度、ECC/XID |
| Alloy 集成 | `prometheus.scrape` 抓取 HAMI / DCGM 端点 |
| 推荐组合 | HAMI 分配指标 + DCGM 硬件指标 + K8s Pod 指标 |

---

## 2. 产品概况（HAMI）

| 项目 | 内容 |
| --- | --- |
| 产品名称 | HAMi / HAMI |
| 类型 | Kubernetes GPU 共享、隔离与调度中间件 |
| 部署形态 | DaemonSet / Scheduler 扩展 / Device Plugin |
| 数据来源 | HAMI 调度与分配状态、节点 GPU 资源、Pod 注解 |
| 互补组件 | DCGM Exporter、kube-state-metrics、kubelet cAdvisor |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `hami_node_gpu_total` | 节点 GPU 总数 | 与资产清单不一致告警 |
| `hami_node_gpu_allocated` | 已分配 GPU 数 | == total 持续 10m 资源耗尽 |
| `hami_node_gpu_memory_total` | GPU 显存池总量 | — |
| `hami_node_gpu_memory_allocated` | 已分配显存 | > 90% 告警 |
| `hami_pod_gpu_memory` | Pod 分配显存 | 用于租户核算 |
| `hami_vgpu_count` | vGPU 实例数 | 异常突增关注 |
| `hami_container_pending` | 等待 GPU 分配容器数 | > 0 持续 5m 告警 |
| `DCGM_FI_DEV_FB_USED` | 实际显存使用 | 与 HAMI 分配差值用于裸进程识别 |
| `DCGM_FI_DEV_GPU_UTIL` | GPU 实际利用率 | 长期低利用率资源浪费 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 适用场景 |
| --- | --- | --- | --- |
| HAMI 内置 `/metrics` | HAMI 组件端点 | GPU 分配 / vGPU / 显存池 | HAMI 标准指标 |
| DCGM Exporter | DaemonSet | GPU 硬件实际状态 | 必须配合 |
| Grafana Alloy | `prometheus.scrape` | 抓取 HAMI + DCGM | **本项目首选** |
| Netdata | Agent | 基础 GPU 指标 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

```alloy
prometheus.scrape "hami" {
  targets = [{ __address__ = "hami-device-plugin.kube-system.svc:8080", service = "hami" }]
  scrape_interval = "30s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "hami"
}

prometheus.scrape "dcgm" {
  targets = [{ __address__ = "dcgm-exporter.gpu.svc:9400", service = "dcgm" }]
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "dcgm"
}
```

关键分析公式：

```promql
# 裸进程或非 HAMI 管控显存消耗估算
DCGM_FI_DEV_FB_USED - hami_node_gpu_memory_allocated
```

---

## 6. 部署与采集注意事项

| 场景 | 采集方式 |
| --- | --- |
| K8s + HAMI | 抓取 HAMI metrics + DCGM DaemonSet |
| Docker GPU（无 HAMI）| 仅 DCGM + nvidia-gpu-exporter |
| 宿主机裸进程 | DCGM 统计总显存，nvidia-gpu-exporter 做进程归因 |

---

## 7. 告警规则

```yaml
groups:
- name: hami.rules
  rules:
  - alert: HAMIGpuFullyAllocated
    expr: hami_node_gpu_allocated == hami_node_gpu_total
    for: 10m
    labels: { severity: warning }
    annotations: { summary: "HAMI 节点 GPU 已全部分配" }

  - alert: HAMIGpuMemoryAllocatedHigh
    expr: hami_node_gpu_memory_allocated / hami_node_gpu_memory_total > 0.9
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "HAMI GPU 显存分配率超过 90%" }

  - alert: HAMIGpuPendingContainers
    expr: hami_container_pending > 0
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "存在等待 GPU 分配的容器" }
```

---

## 8. Grafana Dashboard

建议自建 HAMI Dashboard，核心面板包括：节点 GPU 分配率、显存分配率、Pod 分配 TopN、Pending 容器、HAMI 分配显存与 DCGM 实际显存差值。

---

## 9. KAgent 集成（HAMI 运维 Agent）

推荐绑定 PrometheusServer 查询 HAMI、DCGM、kube-state-metrics 指标，并通过 Skills 注入 GPU 调度、Pending Pod、裸进程显存排查 SOP。

---

## 10. 常见问题

### Grafana Alloy 能采集 HAMI 指标吗？

**可以，但不是专用集成。** Grafana 官方知识来源没有 HAMI 专用 Alloy 文档；只要 HAMI 暴露 Prometheus `/metrics`，Alloy 就能通过 `prometheus.scrape` 抓取。

### HAMI 指标能替代 DCGM 吗？

不能。HAMI 表示资源“分配”，DCGM 表示硬件“实际使用”。两者差值能发现宿主机裸进程或非 HAMI 管控进程占用显存。