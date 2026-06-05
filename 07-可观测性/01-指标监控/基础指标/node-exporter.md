# node-exporter — 主机系统指标采集器

## 概述

node-exporter 是 Prometheus 官方维护的主机指标采集器（CNCF Graduated），以 Go 编写，通过读取 Linux 内核 `/proc` 和 `/sys` 伪文件系统获取主机资源数据，暴露为 Prometheus 格式的 HTTP 端点。

- GitHub: [prometheus/node_exporter](https://github.com/prometheus/node_exporter) ⭐ ~11k
- 默认端口: `9100/metrics`
- 无需 root 权限（部分 collector 除外）

---

## 核心能力

| Collector | 监测内容 | 默认状态 |
|-----------|---------|---------|
| cpu | CPU 使用率（每核、模式分类）| 开启 |
| meminfo | 内存 / Swap 使用 | 开启 |
| diskstats | 磁盘 IO、IOPS、延迟 | 开启 |
| filesystem | 挂载点容量、inode 使用 | 开启 |
| netdev | 网卡流量、包数、错误数 | 开启 |
| loadavg | 系统负载（1/5/15 分钟）| 开启 |
| nfs / nfsd | NFS 客户端 / 服务端统计 | 开启 |
| hwmon | 硬件温度、风扇转速 | 开启 |
| uname | 内核版本信息 | 开启 |
| systemd | Systemd Unit 运行状态 | **关闭**（需手动开启）|
| processes | 进程数统计 | **关闭** |
| ipvs | LVS / IPVS 连接统计 | **关闭** |

---

## 核心指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `node_cpu_seconds_total{mode="idle"}` | CPU 空闲时间 | `1 - rate(idle) > 0.85` 持续 5m 告警 |
| `node_memory_MemAvailable_bytes` | 可用内存 | < 总内存 10% 告警 |
| `node_filesystem_avail_bytes` | 磁盘剩余 | < 总量 10% 告警 |
| `node_filesystem_files_free` | inode 剩余 | < 5% 告警 |
| `node_disk_io_time_seconds_total` | 磁盘 IO 繁忙时间 | `rate > 0.9` 持续 5m 关注 |
| `node_network_receive_bytes_total` | 网卡入流量 | — |
| `node_network_transmit_bytes_total` | 网卡出流量 | — |
| `node_load1` / `node_load5` / `node_load15` | 系统负载 | load1 > CPU 核数 × 2 告警 |
| `node_nfs_requests_total` | NFS 操作请求数 | — |
| `node_hwmon_temp_celsius` | 硬件温度 | > 80°C 告警 |

---

## 在本项目中的使用

### 部署方式

| 场景 | 部署方式 | 备注 |
|------|---------|------|
| K8s 节点 | DaemonSet（kube-prometheus-stack 已包含）| 推荐 |
| Docker 宿主机 | systemd 服务 | 手动安装 |
| 裸金属/VM | systemd 服务 | 手动安装 |
| 方案一（Alloy）| **内置**，无需独立部署 | Alloy `prometheus.exporter.unix` 组件替代 |

### 方案一 Alloy 替代配置

```river
// Alloy 内置 unix exporter = node-exporter 等价物
prometheus.exporter.unix "node" {
  // 按需开启额外 collector
  set_collectors = [
    "cpu", "meminfo", "diskstats", "filesystem",
    "netdev", "loadavg", "nfs", "nfsd", "hwmon",
    "uname", "systemd",
  ]
  // 排除无关挂载点（避免噪声）
  filesystem {
    mount_points_exclude = "^/(dev|proc|sys|run|snap)($|/)"
  }
}

prometheus.scrape "unix_metrics" {
  targets    = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 独立部署（非 K8s 主机）

```bash
# 安装（二进制）
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.0/node_exporter-1.8.0.linux-amd64.tar.gz
tar xvf node_exporter-1.8.0.linux-amd64.tar.gz
cp node_exporter-1.8.0.linux-amd64/node_exporter /usr/local/bin/

# Systemd 服务
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes \
  --web.listen-address=:9100
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter
```

### Prometheus 采集配置

```yaml
# K8s ServiceMonitor（DaemonSet 已由 kube-prometheus-stack 自动创建）

# 非 K8s 静态目标
scrape_configs:
  - job_name: node_exporter
    static_configs:
      - targets:
          - "10.0.1.50:9100"
          - "10.0.1.51:9100"
          - "10.0.1.52:9100"
        labels:
          env: prod
          cluster: smartvision
```

---

## 与 Grafana Alloy 的关系

> **结论**：方案一（Grafana Alloy）中，node-exporter 不需要独立部署。Alloy DaemonSet 通过内置的 `prometheus.exporter.unix` 组件采集完全相同的指标，减少一个 DaemonSet。

| 维度 | 独立 node-exporter | Alloy 内置 unix exporter |
|------|------------------|-------------------------|
| 独立进程 | 需要 | **不需要** |
| 指标完整性 | 全量 | 全量（相同代码库）|
| 配置方式 | 命令行参数 | River 配置块 |
| 资源消耗 | ~15 MB | 包含在 Alloy 进程内 |

---

## 常用 Grafana Dashboard

| Dashboard | ID | 说明 |
|-----------|-----|------|
| Node Exporter Full | 1860 | 社区最全主机指标面板 |
| Node Exporter for Prometheus | 11074 | 紧凑版 |
