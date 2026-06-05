# NFS 可观测性

> NFS 客户端的指标由 node-exporter 的 `nfsCollector` 采集；服务端指标同样通过 node-exporter 的文件系统指标覆盖。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| node-exporter nfsCollector | NFS 客户端操作统计（v2/v3/v4） | TCP 9100 /metrics |
| node-exporter filesystemCollector | 磁盘挂载容量和使用量 | TCP 9100 /metrics |
| NFS Server stats | 服务端 nfsd 统计（只读 procfs）| 需额外脚本或 node-exporter 自定义收集器 |

NFS 自身不提供 HTTP metrics 端点，所有监控依赖 node-exporter 和操作系统 procfs。

---

## 核心指标

### NFS 客户端

| 指标（node-exporter） | 含义 | 告警建议 |
|----------------------|------|---------|
| `node_nfs_requests_total` | NFS 操作请求总数（按操作类型分）| — |
| `node_nfs_requests_total{operation="read"}` | 读操作次数 | — |
| `node_nfs_requests_total{operation="write"}` | 写操作次数 | — |
| `node_nfs_rpc_authentication_refreshes_total` | RPC 认证刷新次数 | 突增说明认证问题 |

### 文件系统

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `node_filesystem_size_bytes{mountpoint=~"/nfs.*"}` | NFS 挂载点总大小 | — |
| `node_filesystem_avail_bytes{mountpoint=~"/nfs.*"}` | NFS 挂载点可用空间 | < 10% 告警 |
| `node_filesystem_files_free{mountpoint=~"/nfs.*"}` | NFS inode 剩余 | < 5% 告警 |
| `node_disk_io_time_seconds_total{device="nfs"}` | NFS 磁盘 IO 时间 | — |

### NFS 服务端（nfsd）

| 指标 | 含义 |
|------|------|
| `node_nfsd_server_rpcs_total` | 服务端处理的 RPC 请求数 |
| `node_nfsd_requests_total` | nfsd 线程处理请求数 |
| `node_nfsd_connections_total` | 当前 NFS 连接数 |

---

## 采集集成

```yaml
# node-exporter 默认启用 nfsCollector 和 filesystemCollector
# 无需额外配置，启动后自动采集

# 确认 nfsCollector 是否启用（默认开启）
node_exporter --collector.nfs --collector.filesystem

# Prometheus scrape
- job_name: nfs-client
  static_configs:
    - targets:
        - "nfs-client-node:9100"
      labels:
        service: nfs
        role: client

- job_name: nfs-server
  static_configs:
    - targets:
        - "nfs-server-node:9100"
      labels:
        service: nfs
        role: server
```

---

## 告警规则

```yaml
- alert: NfsDiskSpaceLow
  expr: node_filesystem_avail_bytes{mountpoint=~".*nfs.*"} / node_filesystem_size_bytes{mountpoint=~".*nfs.*"} * 100 < 10
  for: 5m
  annotations:
    summary: "NFS 挂载点 {{ $labels.mountpoint }} 可用空间不足 10%"

- alert: NfsInodesExhausted
  expr: node_filesystem_files_free{mountpoint=~".*nfs.*"} / node_filesystem_files{mountpoint=~".*nfs.*"} * 100 < 5
  for: 5m
  annotations:
    summary: "NFS 挂载点 inode 即将耗尽（{{ $labels.mountpoint }}）"

- alert: NfsHighWriteRate
  expr: rate(node_disk_io_time_seconds_total{device=~"nfs.*"}[5m]) > 0.8
  for: 10m
  annotations:
    summary: "NFS 磁盘 IO 占用率 > 80%"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| NFS Server（物理机） | node-exporter 覆盖 filesystem + nfsd 统计 |
| NFS Client（所有节点） | node-exporter 采集客户端操作指标 |
| 容器中挂载 NFS | 容器内 node-exporter 无法采集，需在宿主机采集 |

NFS 是基础网络文件系统，没有独立的 metrics 服务。所有指标来自 node-exporter，因此确保所有 NFS 客户端节点都部署了 node-exporter。
