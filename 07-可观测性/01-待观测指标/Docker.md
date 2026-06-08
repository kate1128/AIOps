# Docker 可观测性

> Docker Daemon 内置 metrics 端点，配合 cAdvisor/Alloy/Netdata 等采集器实现容器级资源监控。本文梳理各采集器的指标覆盖、部署复杂度，并给出 Prometheus 全链路方案的选型建议。

---

## 一、Docker 可观测指标全景

### 1.1 Docker Daemon 指标（内置）

Docker Daemon 原生支持 Prometheus 格式 metrics，需在 `daemon.json` 中开启：

```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

| 指标 | 含义 | 类型 |
|------|------|------|
| `engine_daemon_container_states_containers` | 容器状态分布（running/paused/stopped） | Gauge |
| `engine_daemon_events_total` | Docker 事件计数（start/destroy/restart） | Counter |
| `engine_daemon_engine_memory_bytes` | Docker Daemon 自身内存占用 | Gauge |
| `engine_daemon_network_actions_seconds_count` | 网络操作计数 | Counter |
| `engine_daemon_image_pulls_by_scheme` | 镜像拉取次数（按 scheme 分类） | Counter |
| `engine_daemon_container_start_latency_seconds` | 容器启动延迟 | Histogram |
| `engine_daemon_container_creation_errors_total` | 容器创建失败计数 | Counter |

> **局限性**：Daemon metrics 只反映 Docker 引擎自身健康状态，不包含容器级资源使用（CPU/内存/网络/磁盘），必须配合 cAdvisor 等采集器。

### 1.2 cAdvisor 指标（容器级核心）

cAdvisor（Container Advisor）是 Google 开源的容器资源采集器，读取 Linux cgroup 数据，无需在容器内安装任何 agent。已内嵌于 Kubernetes kubelet。

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `container_cpu_usage_seconds_total` | 容器 CPU 使用总量 | — |
| `container_cpu_cfs_throttled_seconds_total` | CPU 被限流的时长 | > 20% 告警 |
| `container_memory_usage_bytes` | 容器内存使用 | > 90% limit 告警 |
| `container_memory_rss` | 容器 RSS 内存 | — |
| `container_network_receive_bytes_total` | 容器网络入流量 | — |
| `container_network_transmit_bytes_total` | 容器网络出流量 | — |
| `container_fs_usage_bytes` | 容器磁盘使用 | — |
| `container_fs_io_time_seconds_total` | 容器磁盘 I/O 时间 | — |
| `container_restarts_total` | 容器重启次数 | > 3 次/10min 告警 |
| `container_last_seen` | 容器最后可见时间 | absent() 检测容器存活 |
| `container_spec_cpu_quota` | 容器 CPU 限额 | — |
| `container_spec_memory_limit_bytes` | 容器内存限额 | — |
| `container_start_time_seconds` | 容器启动时间 | — |

### 1.3 Docker 日志指标

通过 Docker json-file log driver 输出日志，由 Promtail/Loki/Alloy 等采集：

| 采集方式 | 说明 |
|---------|------|
| `/var/lib/docker/containers/*/*-json.log` | 宿主机日志文件路径 |
| `loki.source.docker` | Alloy 通过 Docker socket 实时采集 |
| Promtail | Promtail 通过文件 tail 采集 |

---

## 二、采集器方案对比

### 2.1 采集器矩阵

| 采集器 | 类型 | 部署方式 | 指标覆盖 | 日志支持 | 存储依赖 | 适用场景 |
|--------|------|---------|---------|---------|---------|---------|
| **cAdvisor** | Google 开源 | 容器化部署 | 容器级 CPU/内存/网络/磁盘 | 无 | 无（需外部存储） | Prometheus 全链路标准方案 |
| **Alloy** | Grafana 开源 | 二进制/容器 | cAdvisor 全部 + 自动发现 | 有（loki.source.docker） | 需 Loki + Prometheus | Grafana 全栈可观测 |
| **Netdata** | Netdata 开源 | 一键安装/容器 | 系统 + 容器 + 应用层全覆盖 | 有（内置日志查看） | 内置数据库（可远程） | 快速部署、小团队独立监控 |
| **OpenTelemetry Collector** | CNCF 开源 | 二进制/容器 | Docker Stats Receiver | 有（日志 receiver） | 需后端（Prometheus/Jaeger 等） | OTel 原生全链路 |
| **node-exporter** | Prometheus 官方 | 容器/二进制 | 宿主机级指标 | 无 | 无 | 宿主机资源监控 |

### 2.2 指标覆盖对比

| 指标维度 | cAdvisor | Alloy | Netdata | OTel Collector |
|---------|----------|-------|---------|----------------|
| 容器 CPU 使用 | ✅ | ✅ | ✅ | ✅ |
| 容器内存使用 | ✅ | ✅ | ✅ | ✅ |
| 容器网络流量 | ✅ | ✅ | ✅ | ✅ |
| 容器磁盘使用 | ✅ | ✅ | ✅ | ✅ |
| 容器磁盘 I/O | ✅ | ✅ | ✅ | ✅ |
| 容器重启次数 | ✅ | ✅ | ✅ | ✅ |
| 容器存活状态 | ✅ | ✅ | ✅ | ✅ |
| Docker Daemon 指标 | ❌（需单独抓 9323） | ❌（需单独配置） | ✅（内置 dockerd collector） | ❌ |
| 宿主机系统指标 | ❌ | 需 node_exporter | ✅（内置） | 需 node receiver |
| 容器日志采集 | ❌ | ✅ | ✅ | ✅ |
| 容器自动发现 | ✅（读 cgroup） | ✅（discovery.docker） | ✅ | ✅ |
| 应用层指标（Redis/Nginx 等） | ❌ | 需额外集成 | ✅（内置 800+ 插件） | 需额外 receiver |
| ML 异常检测 | ❌ | ❌ | ✅ | ❌ |

---

## 三、方案一：Prometheus 全链路 + cAdvisor（标准方案）

### 3.1 架构

```
Docker Host
├── Docker Daemon (port 9323)  ──→  Prometheus scrape
├── cAdvisor (port 8080)       ──→  Prometheus scrape
├── Node Exporter (port 9100)  ──→  Prometheus scrape
└── 容器日志 → Promtail → Loki
                                    ↓
                            Prometheus (TSDB)
                                    ↓
                            Grafana (Dashboard + Alert)
```

### 3.2 部署配置

```yaml
# docker-compose.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.47.1
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro

  node-exporter:
    image: prom/node-exporter:latest
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"

  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"

volumes:
  prometheus_data:
```

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: docker-daemon
    static_configs:
      - targets: ["host.docker.internal:9323"]
    # 或使用文件发现，动态识别容器

  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]
    metric_relabel_configs:
      # 只保留有用的 label，降低 TSDB 膨胀
      - source_labels: [__name__]
        regex: "container_(cpu|memory|network|fs|restarts|last_seen).*"
        action: keep

  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]
```

### 3.3 告警规则

```yaml
groups:
  - name: docker-alerts
    rules:
      - alert: ContainerRestarting
        expr: rate(container_restarts_total[10m]) > 0.3
        for: 5m
        annotations:
          summary: "容器 {{ $labels.name }} 频繁重启"

      - alert: ContainerMemoryNearLimit
        expr: |
          container_memory_usage_bytes{container_label_com_docker_compose_service!=""}
          / on(container_label_com_docker_compose_service)
          container_spec_memory_limit_bytes > 0.9
        for: 3m
        annotations:
          summary: "容器内存使用超过 90% limit"

      - alert: ContainerCPULimitExceeded
        expr: |
          rate(container_cpu_usage_seconds_total[5m])
          / on(name) container_spec_cpu_quota * 100000 > 0.9
        for: 5m
        annotations:
          summary: "容器 CPU 使用超过 90% quota"

      - alert: ContainerDown
        expr: absent(container_last_seen{name="my_container"})
        for: 1m
        annotations:
          summary: "容器 {{ $labels.name }} 已不可见"
```

---

## 四、方案二：Grafana Alloy 方案

### 4.1 架构

Grafana Alloy 是 Grafana 推出的统一采集器，内置 cAdvisor exporter + Docker 自动发现 + 日志采集，可替代 cAdvisor + Promtail。

```
Docker Host
├── Alloy (单 binary)
│   ├── prometheus.exporter.cadvisor → Prometheus
│   ├── loki.source.docker → Loki
│   └── discovery.docker → 自动发现容器
└── Grafana Stack (Prometheus + Loki + Grafana)
```

### 4.2 Alloy 配置（config.alloy）

参考 [alloy-scenarios/docker-monitoring](https://github.com/grafana/alloy-scenarios/tree/main/docker-monitoring)：

```alloy
// ==============================
// 指标采集：内置 cAdvisor exporter
// ==============================
prometheus.exporter.cadvisor "example" {
  docker_only = true
}

discovery.relabel "example" {
  targets = prometheus.exporter.cadvisor.example.targets
  rule {
    target_label = "job"
    replacement  = "integrations/docker"
  }
  rule {
    target_label = "instance"
    replacement  = constants.hostname
  }
}

prometheus.scrape "scraper" {
  targets    = discovery.relabel.example.output
  forward_to = [ prometheus.remote_write.demo.receiver ]
  scrape_interval = "10s"
}

prometheus.remote_write "demo" {
  endpoint {
    url = "http://prometheus:9090/api/v1/write"
  }
}

// ==============================
// 日志采集：通过 Docker socket 自动发现
// ==============================
discovery.docker "linux" {
  host = "unix:///var/run/docker.sock"
}

discovery.relabel "logs_integrations_docker" {
  targets = []
  rule {
    source_labels = ["__meta_docker_container_name"]
    regex = "/(.*)"
    target_label = "container_name"
  }
  rule {
    target_label = "instance"
    replacement  = constants.hostname
  }
}

loki.source.docker "default" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.linux.targets
  labels     = {"platform" = "docker"}
  relabel_rules = discovery.relabel.logs_integrations_docker.rules
  forward_to = [loki.process.docker_logs.receiver]
}

loki.process "docker_logs" {
  forward_to = [loki.write.local.receiver]
  stage.drop {
    source     = "container_name"
    expression = "(alloy|grafana|loki)"
  }
}

loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

### 4.3 Alloy vs cAdvisor 对比

| 维度 | cAdvisor + Promtail | Alloy |
|------|-------------------|-------|
| 组件数 | 2 个（cAdvisor + Promtail） | 1 个（Alloy） |
| 配置复杂度 | 中等（两套配置） | 较低（统一 config.alloy） |
| Docker Daemon 指标 | 需单独开启 9323 | 同样需要单独开启 |
| 日志采集 | 需 Promtail 配置 | 内置 loki.source.docker |
| 自动发现 | 读 cgroup | 读 Docker socket |
| 远程写 | Prometheus 原生 | 支持 Prometheus remote_write |
| 学习成本 | 中等（社区资料丰富） | 较高（Grafana Alloy 新项目） |

---

## 五、方案三：Netdata 方案

### 5.1 架构

Netdata 是"开箱即用"的实时监控平台，安装即自动采集系统 + Docker + 应用层指标，内置 ML 异常检测。

```
Docker Host
├── Netdata Agent（单 binary，自动采集一切）
│   ├── 系统指标（CPU/Memory/Disk/Network）
│   ├── Docker 容器指标（cgroup 级）
│   ├── dockerd 指标（Daemon API）
│   ├── 800+ 应用插件（Redis/Nginx/PostgreSQL...）
│   └── 日志查看
└── Netdata Cloud（可选，聚合多节点）
```

### 5.2 部署

```bash
# 一键安装（Linux）
wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh
sh /tmp/netdata-kickstart.sh

# 或 Docker 部署
docker run -d --name=netdata \
  -p 19999:19999 \
  --cap-add SYS_PTRACE \
  --security-opt apparmor=unconfined \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/passwd:/host/etc/passwd:ro \
  -v /etc/group:/host/etc/group:ro \
  -v /etc/localtime:/etc/localtime:ro \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /var/run:/host/var/run:ro \
  netdata/netdata
```

### 5.3 Docker 相关采集器

Netdata 内置以下 Docker 相关 collector：

| Collector | 数据源 | 采集指标 |
|-----------|--------|---------|
| `cgroups` | /sys/fs/cgroup | 容器 CPU/内存/磁盘/网络（cgroup 级） |
| `dockerd` | Docker Engine API | Daemon 容器状态/事件/镜像/网络 |
| `docker_container_*` | cgroup + namespace | 单容器级详细指标 |
| `containerd` | containerd API | 非 Docker 容器运行时指标 |

### 5.4 Netdata 指标特点

- **秒级精度**：1 秒采集间隔（vs Prometheus 默认 15 秒）
- **零配置**：安装后自动发现所有容器
- **内置 ML**：异常检测无需额外配置
- **800+ 应用插件**：自动采集 Redis/Nginx/PostgreSQL/Java/JVM 等
- **内置告警**：预置 500+ 告警规则
- **内置 Dashboard**：无需额外部署 Grafana

---

## 六、方案四：Netdata 作为采集器 + Prometheus（混合方案）

### 6.1 可行性分析

**可以结合使用**，但需要理解两者的角色定位：

| 角色 | 说明 |
|------|------|
| Netdata 作为采集器 | Netdata 支持将指标 remote_write 到 Prometheus |
| Netdata 作为独立监控 | Netdata Cloud 提供免费 5 节点聚合 |

### 6.2 架构

```
Docker Host
├── Netdata Agent
│   ├── 自动采集全部指标
│   └── remote_write → Prometheus
└── Prometheus（接收 Netdata remote_write）
    └── Grafana（可视化）
```

### 6.3 Netdata remote_write 配置

```yaml
# /etc/netdata/stream.conf
[stream]
  destination = prometheus-server:19999
  api key = your-api-key

# 或在 netdata.conf 中配置 remote_write
[remote_write]
  enabled = yes
  destination = http://prometheus:9090/api/v1/write
```

### 6.4 混合方案评估

| 优势 | 劣势 |
|------|------|
| Netdata 秒级精度远超 Prometheus 默认 15s | 两套系统运维复杂度增加 |
| Netdata 自动发现 + 800+ 插件免配置 | Netdata 的指标命名与 Prometheus 生态不完全兼容 |
| 保留 Prometheus 生态（Grafana/Alertmanager） | Netdata 远程写入 Prometheus 可能有数据量问题 |
| Netdata 内置 ML 异常检测 | Prometheus 原生 cAdvisor 方案更成熟、社区更丰富 |
| 快速部署、即时可用 | 本质是两套系统的拼接，不如单一方案简洁 |

---

## 七、选型建议

### 7.1 决策树

```
需要 Docker 监控？
├── 已有 Prometheus + Grafana 栈？
│   ├── 是 → 方案一：cAdvisor（标准方案，最成熟）
│   │         或 方案二：Alloy（统一采集，更现代）
│   └── 否 → 方案三：Netdata（最简单，5 分钟部署）
├── 团队规模？
│   ├── 小团队（< 10 节点）→ Netdata
│   ├── 中团队 → Alloy 或 cAdvisor
│   └── 大团队/已有 Prometheus → cAdvisor
└── 是否需要日志 + 指标统一？
    ├── 是 → Alloy（指标 + 日志一体化）
    └── 否 → cAdvisor + Promtail
```

### 7.2 总结

| 方案 | 部署复杂度 | 维护成本 | 指标丰富度 | 生态兼容 | 推荐场景 |
|------|-----------|---------|-----------|---------|---------|
| **cAdvisor + Prometheus** | 中 | 低 | 高 | ⭐⭐⭐⭐⭐ | 已有 Prometheus 栈的标准方案 |
| **Alloy + Prometheus** | 中 | 低 | 高 | ⭐⭐⭐⭐ | Grafana 全栈、需指标+日志统一 |
| **Netdata** | 低 | 低 | 极高 | ⭐⭐⭐ | 快速部署、小团队独立监控 |
| **Netdata + Prometheus** | 中高 | 中 | 极高 | ⭐⭐⭐ | 需要秒级精度+Prometheus 生态 |

### 7.3 推荐

1. **如果已有 Prometheus 栈**：使用 **cAdvisor**（最成熟）或 **Alloy**（更现代、统一采集）
2. **如果从零开始、团队小**：使用 **Netdata**（零配置、秒级精度、内置 Dashboard）
3. **如果需要秒级精度 + Prometheus 生态**：Netdata remote_write 到 Prometheus，但需评估运维复杂度

---

## 八、部署注意事项

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 + Docker 混合 | 宿主机起 cAdvisor 容器 + Daemon metrics，统一给 Prometheus |
| 纯 Docker 环境 | cAdvisor + node-exporter 覆盖全部 |
| Docker → K8s 迁移过渡 | cAdvisor 和 kubelet metrics 重复采集无妨，逐步移除 cAdvisor |
| 远程 Docker 主机 | 需开启 Docker TCP 远程访问 + TLS 认证 |

**关键配置**：
- Docker Daemon 默认不开启 metrics，需在 `daemon.json` 配置 `metrics-addr` 并重启 dockerd
- 生产环境限制 metrics 端口访问来源，避免暴露到公网
- cAdvisor 需挂载宿主机 `/`, `/var/run`, `/sys`, `/var/lib/docker` 等目录（只读）
