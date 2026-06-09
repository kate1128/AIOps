# NFS 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. Node Exporter：[prometheus/node_exporter](https://github.com/prometheus/node_exporter)
2. Alloy unix exporter：[prometheus.exporter.unix](https://grafana.com/docs/alloy/latest/reference/components/prometheus.exporter.unix/)
3. Linux nfsstat：[nfsstat man page](https://man7.org/linux/man-pages/man8/nfsstat.8.html)

---

## 1. 结论摘要

NFS 本身不提供 HTTP metrics 端点，Linux 主机侧 NFS 指标来自 `/proc/net/rpc/nfs`、`/proc/net/rpc/nfsd`、`/proc/self/mountstats` 和文件系统指标。Grafana Alloy **部分支持 NFS 指标采集**：通过内置 `prometheus.exporter.unix` 采集 node_exporter 等价的 `nfs`、`nfsd`、`mountstats` 指标。其中 `nfs`/`nfsd` 通常默认可用，`mountstats` 需手动启用。Kubernetes NFS Provisioner 若暴露 Prometheus 端点，也可通过 `discovery.kubernetes + prometheus.scrape` 采集。

| 关键信息 | 值 |
| --- | --- |
| 主流采集方式 | Alloy unix exporter / node-exporter |
| 客户端指标 | `nfs` collector（`/proc/net/rpc/nfs`）|
| 服务端指标 | `nfsd` collector（`/proc/net/rpc/nfsd`）|
| 挂载点详细指标 | `mountstats` collector（需启用）|
| K8s Provisioner | 需确认是否暴露 Prometheus 端点 |

---

## 2. 产品概况（NFS 指标来源）

| 来源 | 内容 | 说明 |
| --- | --- | --- |
| `/proc/net/rpc/nfs` | NFS Client RPC 统计 | 客户端请求、认证刷新等 |
| `/proc/net/rpc/nfsd` | NFS Server RPC 统计 | 服务端请求、线程、操作分布 |
| `/proc/self/mountstats` | 单挂载点统计 | 延迟、操作、重传 |
| filesystem collector | 容量与 inode | NFS 挂载点空间告警 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `node_nfs_requests_total` | NFS 客户端请求数 | 按 operation 分析 |
| `node_nfs_rpc_authentication_refreshes_total` | RPC 认证刷新 | 突增排查认证问题 |
| `node_nfsd_server_rpcs_total` | NFS 服务端 RPC | QPS 基线 |
| `node_nfsd_requests_total` | nfsd 请求数 | 按操作类型分析 |
| `node_filesystem_avail_bytes{fstype=~"nfs.*"}` | NFS 可用空间 | < 10% 告警 |
| `node_filesystem_files_free{fstype=~"nfs.*"}` | NFS inode 剩余 | < 5% 告警 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 适用场景 |
| --- | --- | --- | --- |
| node-exporter | 宿主机 / DaemonSet | nfs / nfsd / filesystem | 传统方案 |
| **Alloy unix exporter** | Alloy 内置 | nfs / nfsd / mountstats / filesystem | **本项目首选** |
| Netdata | Agent | NFS + 系统指标 | 快速验证 |
| NFS Provisioner metrics | 应用端点 | Provisioner 自身 | 需验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 Linux 主机 NFS 指标

```alloy
prometheus.exporter.unix "nfs" {
  set_collectors = ["cpu", "meminfo", "filesystem", "diskstats", "netdev", "nfs", "nfsd"]
  enable_collectors = ["mountstats"]
}

prometheus.scrape "nfs" {
  targets = prometheus.exporter.unix.nfs.targets
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "nfs"
}
```

### 5.2 Kubernetes NFS Provisioner（需验证）
```alloy
discovery.kubernetes "nfs_provisioner" {
  role = "pod"
  selectors { role = "pod" label = "app=nfs-subdir-external-provisioner" }
}

prometheus.scrape "nfs_provisioner" {
  targets = discovery.kubernetes.nfs_provisioner.targets
  forward_to = [prometheus.remote_write.central.receiver]
  job_name = "nfs-provisioner"
}
```

---

## 6. 部署方式对比

| 场景 | 采集方式 |
| --- | --- |
| NFS Client | 每个客户端节点部署 Alloy unix exporter |
| NFS Server | 服务端节点启用 `nfsd` collector |
| 容器内挂载 NFS | 在宿主机采集，不在业务容器内采集 |
| K8s NFS Provisioner | Pod metrics（若暴露）+ 宿主机 NFS 指标 |

---

## 7. 告警规则

```yaml
groups:
- name: nfs.rules
  rules:
  - alert: NfsDiskSpaceLow
    expr: node_filesystem_avail_bytes{fstype=~"nfs.*"} / node_filesystem_size_bytes{fstype=~"nfs.*"} < 0.1
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "NFS 挂载点可用空间不足 10%" }

  - alert: NfsInodesLow
    expr: node_filesystem_files_free{fstype=~"nfs.*"} / node_filesystem_files{fstype=~"nfs.*"} < 0.05
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "NFS inode 剩余不足 5%" }
```

---

## 8. Grafana Dashboard

推荐使用 NFS、NFS mountstats、Node Exporter Full 等 Dashboard。基础 NFS 看 `nfs`/`nfsd`，延迟和单挂载点问题看 `mountstats`。

---

## 9. KAgent 集成（NFS 运维 Agent）

推荐绑定 PrometheusServer 查询 NFS 容量、inode、RPC 操作、mountstats 延迟，并用 Git-Based Skills 注入 NFS 卡顿、挂载失效、服务端不可达、Provisioner 异常处理 SOP。

---

## 10. 常见问题

### Grafana Alloy 支持 NFS 指标吗？

**部分支持。** Linux 主机 NFS 客户端/服务端指标由 Alloy 内置 `prometheus.exporter.unix` 支持；Kubernetes NFS Provisioner 是否可采集取决于它是否暴露 Prometheus 端点。

### mountstats 默认启用吗？

通常不是默认启用。需要在 `prometheus.exporter.unix` 中手动启用 `mountstats` collector，用于更详细的 NFS 客户端延迟和操作统计。

### NFS Client 和 Server 要分开看吗？

要分开。Client 侧更适合定位业务节点卡顿、重传和挂载问题；Server 侧更适合定位 NFS 服务端压力、线程和磁盘容量问题。
