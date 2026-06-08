# 日志可观测性

> 日志是可观测性三大支柱之一（Metrics / Logs / Traces）。本文梳理 Docker、二进制服务、Kubernetes 三种场景下的日志采集方案，对比 Promtail、Alloy、Filebeat 等采集器，并给出 Prometheus + Loki 全链路方案的选型建议。

---

## 一、日志来源分类

### 1.1 Docker 容器日志

| 日志来源 | 路径 | 格式 | 说明 |
|---------|------|------|------|
| json-file driver | `/var/lib/docker/containers/*/*-json.log` | JSON | Docker 默认日志驱动 |
| syslog driver | 系统 syslog | syslog 格式 | 需显式配置 |
| fluentd driver | → Fluentd | 结构化 | 需显式配置 |
| journald driver | → systemd journal | journal 格式 | 宿主机级 |

### 1.2 二进制服务日志

| 日志来源 | 说明 |
|---------|------|
| stdout/stderr | systemd journal 或 nohup 重定向 |
| 应用日志文件 | `/var/log/app/*.log` 或自定义路径 |
| Nginx access/error log | `/var/log/nginx/access.log` |
| Kafka/Redis 日志 | 应用自定义路径 |

### 1.3 Kubernetes 日志

| 日志来源 | 路径 | 说明 |
|---------|------|------|
| Pod stdout | `/var/log/pods/*/*/*.log` | kubelet 重定向 |
| Node 系统日志 | `/var/log/syslog`, `/var/log/messages` | 宿主机级 |
| 容器内日志文件 | 需挂载 hostPath 或 emptyDir | 应用写文件场景 |

---

## 二、日志采集器方案对比

### 2.1 采集器矩阵

| 采集器 | 类型 | 部署方式 | 日志源支持 | 指标提取 | 存储依赖 | 适用场景 |
|--------|------|---------|-----------|---------|---------|---------|
| **Promtail** | Grafana 开源 | DaemonSet/容器 | Docker/K8s/systemd/files | ✅ log指标 | Loki | Loki 原生方案 |
| **Grafana Alloy** | Grafana 开源 | DaemonSet/容器 | Docker/K8s/systemd/files | ✅ log指标 | Loki | 统一采集（替代 Promtail） |
| **Filebeat** | Elastic 开源 | DaemonSet/容器 | Docker/K8s/files/logstash | ✅ | Elasticsearch | ELK 栈 |
| **Fluentd** | CNCF 毕业 | DaemonSet/容器 | 全格式（500+ 插件） | ✅ | Elasticsearch/Loki/S3 | 多目标输出 |
| **Fluent Bit** | CNCF 毕业 | DaemonSet/容器 | 轻量级 Fluentd | ✅ | Elasticsearch/Loki/S3 | 资源受限环境 |
| **Vector** | Datadog 开源 | DaemonSet/容器 | 全格式 | ✅ | 多目标 | 高性能场景 |
| **rsyslog** | 系统内置 | 宿主机 | syslog/files | ❌ | 本地/远程 syslog | 传统 syslog 转发 |

### 2.2 功能对比

| 功能维度 | Promtail | Alloy | Filebeat | Fluent Bit | Vector |
|---------|----------|-------|----------|------------|--------|
| Docker 日志采集 | ✅ | ✅ | ✅ | ✅ | ✅ |
| K8s Pod 日志采集 | ✅ | ✅ | ✅ | ✅ | ✅ |
| systemd journal | ✅ | ✅ | ✅ | ✅ | ✅ |
| 文件 tail | ✅ | ✅ | ✅ | ✅ | ✅ |
| 日志解析（JSON/正则） | ✅ | ✅ | ✅ | ✅ | ✅ |
| 标签/元数据注入 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 日志 → Loki | ✅ 原生 | ✅ 原生 | 需 webhook | ✅ 插件 | ✅ 插件 |
| 日志 → Elasticsearch | ❌ | ❌ | ✅ 原生 | ✅ 插件 | ✅ 插件 |
| 日志 → Prometheus 指标 | ✅ | ✅ | 需 Logstash | ✅ | ✅ |
| 资源占用 | 低 | 低 | 中 | 极低 | 低 |
| 部署复杂度 | 低 | 低 | 中 | 低 | 中 |

---

## 三、方案一：Promtail + Loki（Grafana 标准方案）

### 3.1 架构

```
Docker Host / K8s Node
├── Promtail（DaemonSet）
│   ├── 采集 Docker json-file 日志
│   ├── 采集 K8s Pod stdout 日志
│   ├── 采集 systemd journal
│   └── 标签注入（container、pod、namespace）
└── Loki（日志存储）
    └── Grafana（日志查询 + 告警）
```

### 3.2 Promtail 配置

```yaml
# promtail-config.yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # ===== Docker 容器日志 =====
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*-json.log
    pipeline_stages:
      - docker: {}
      - label_drop:
          - filename
      # 注入容器元数据
      - match:
          selector: '{job="docker"}'
          stages:
            - json:
                expressions:
                  container: container_name
                  stream: stream
            - labels:
                container:
                stream:

  # ===== K8s Pod 日志 =====
  - job_name: kubernetes
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
    pipeline_stages:
      - cri: {}
      - label_drop:
          - filename

  # ===== systemd journal =====
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd
    relabel_configs:
      - source_labels: [__journal__systemd_unit]
        target_label: unit
```

### 3.3 Docker Compose 部署

```yaml
version: '3.8'
services:
  promtail:
    image: grafana/promtail:latest
    volumes:
      - ./promtail-config.yml:/etc/promtail/config.yml
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
      - /tmp:/tmp
    command: -config.file=/etc/promtail/config.yml

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_LOKI_URL=http://loki:3100
```

### 3.4 Grafana 日志查询（LogQL）

```logql
# 查看某容器日志
{container="nginx"} |= "error"

# 查看某 namespace 所有 Pod 日志
{namespace="production"}

# 统计每分钟错误日志数
rate({job="docker"} |~ "ERROR" [1m])

# Top 10 错误频率容器
topk(10,
  sum by (container) (
    rate({job="docker"} |~ "ERROR" [5m])
  )
)
```

---

## 四、方案二：Grafana Alloy（统一采集）

### 4.1 架构

Alloy 替代 Promtail，同时采集日志和指标：

```
Docker Host / K8s Node
├── Alloy（单 DaemonSet）
│   ├── loki.source.docker / loki.source.file（日志采集）
│   ├── prometheus.exporter.unix（指标采集）
│   └── prometheus.scrape（中间件指标）
├── Loki（日志存储）
└── Prometheus（指标存储）
```

### 4.2 Alloy 配置（Docker 场景）

```alloy
// ===== Docker 日志采集 =====
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
}

loki.source.docker "default" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.linux.targets
  labels     = {"platform" = "docker"}
  relabel_rules = discovery.relabel.logs_integrations_docker.rules
  forward_to = [loki.process.docker_logs.receiver]
}

loki.process "docker_logs" {
  forward_to = [loki.write.loki_backend.receiver]
  stage.drop {
    source     = "container_name"
    expression = "(alloy|grafana|loki)"
  }
}

loki.write "loki_backend" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

### 4.3 Alloy 配置（K8s 场景）

```alloy
// ===== K8s Pod 日志采集 =====
loki.source.kubernetes.podlogs "pods" {
  targets    = discovery.kubernetes.podlogs.targets
  forward_to = [loki.process.k8s_logs.receiver]
}

loki.process "k8s_logs" {
  forward_to = [loki.write.loki_backend.receiver]
  stage.drop {
    source     = "container_name"
    expression = "(alloy|grafana|loki)"
  }
  stage.json {
    expressions = {"level" = "level", "msg" = "message"}
  }
  stage.labels {
    values = {level = "level"}
  }
}

loki.write "loki_backend" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

### 4.4 Alloy vs Promtail 对比

| 维度 | Promtail | Alloy |
|------|----------|-------|
| 组件数 | 独立 DaemonSet | 统一 DaemonSet（含指标采集） |
| 日志采集 | ✅ | ✅ |
| 指标采集 | ❌ | ✅（替代 node-exporter） |
| K8s 日志 | ✅ | ✅ |
| Docker 日志 | ✅ | ✅ |
| 配置语法 | YAML | River（Grafana 专用） |
| 学习成本 | 低 | 中（River 语法新） |
| 社区成熟度 | 高 | 中（较新） |

---

## 五、方案三：ELK 栈（Filebeat + Elasticsearch）

### 5.1 架构

```
Docker Host / K8s Node
├── Filebeat（DaemonSet）
│   ├── Docker 日志
│   ├── K8s Pod 日志
│   └── 文件日志
└── Elasticsearch（日志存储）
    └── Kibana（日志查询 + 可视化）
```

### 5.2 Filebeat 配置

```yaml
# filebeat.yml
filebeat.inputs:
  # Docker 容器日志
  - type: container
    paths:
      - /var/lib/docker/containers/*/*.log
    processors:
      - add_docker_metadata:
          host: "unix:///var/run/docker.sock"

  # K8s Pod 日志
  - type: container
    paths:
      - /var/log/pods/*/*/*.log
    processors:
      - add_kubernetes_metadata:
          host: ${NODE_NAME}
          matchers:
            - logs_path:
                logs_path: /var/log/pods/

  # 应用日志文件
  - type: log
    paths:
      - /var/log/app/*.log
    fields:
      app: my-service

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "filebeat-%{[agent.version]}-%{+yyyy.MM.dd}"

setup.kibana:
  host: "kibana:5601"
```

---

## 六、采集器方案总结

### 6.1 决策树

```
需要日志采集？
├── 已有 Grafana + Loki 栈？
│   ├── 是 → 方案一：Promtail（最成熟）
│   │         或 方案二：Alloy（更现代，统一指标+日志）
│   └── 否 → 已有 Elasticsearch？
│       ├── 是 → Filebeat（ELK 栈）
│       └── 否 → Fluent Bit（轻量多目标）
├── 资源受限？
│   ├── 是 → Fluent Bit（~1MB 内存）
│   └── 否 → Promtail / Alloy
└── 需要多目标输出？
    ├── 是 → Fluentd / Vector
    └── 否 → Promtail
```

### 6.2 总结

| 方案 | 部署复杂度 | 资源占用 | 生态兼容 | 推荐场景 |
|------|-----------|---------|---------|---------|
| **Promtail + Loki** | 低 | 低 | ⭐⭐⭐⭐⭐ | Grafana 全栈标准方案 |
| **Alloy + Loki** | 低 | 低 | ⭐⭐⭐⭐ | 统一采集（指标+日志） |
| **Filebeat + ES** | 中 | 中 | ⭐⭐⭐⭐⭐ | ELK 栈 |
| **Fluent Bit** | 低 | 极低 | ⭐⭐⭐⭐ | 资源受限、多目标 |
| **Fluentd** | 中 | 中 | ⭐⭐⭐⭐⭐ | 复杂多目标输出 |
| **Vector** | 中 | 低 | ⭐⭐⭐⭐ | 高性能场景 |

### 6.3 SmartVision 建议

1. **已有 Prometheus + Grafana 栈**：使用 **Promtail + Loki**（最成熟），或升级为 **Alloy**（统一采集）
2. **新项目、从零开始**：使用 **Alloy**（一套组件同时采集指标+日志）
3. **已有 ELK 栈**：使用 **Filebeat**（与 Elasticsearch 原生集成）
4. **资源受限环境**：使用 **Fluent Bit**（~1MB 内存占用）

---

## 七、日志告警规则

```yaml
groups:
  - name: log-alerts
    rules:
      # 错误日志频率告警
      - alert: HighErrorLogRate
        expr: rate({job="docker"} |~ "ERROR|FATAL|CRITICAL" [5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "容器 {{ $labels.container }} 错误日志频率 > 10/s"

      # 容器无日志（可能挂了）
      - alert: ContainerNoLogs
        expr: sum_over_time({container="my-app"}[5m]) == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "容器 {{ $labels.container }} 5 分钟内无日志输出"

      # OOMKilled 日志检测
      - alert: PodOOMKilled
        expr: {namespace="production"} |~ "OOMKilled|out of memory"
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} 发生 OOMKilled"
```

---

## 八、部署注意事项

| 部署方式 | 采集要点 |
|---------|---------|
| Docker 单机 | Promtail/Alloy 挂载 `/var/lib/docker/containers` + `/var/run/docker.sock` |
| Docker Compose | 日志驱动用 json-file（默认），采集端需访问宿主机目录 |
| K8s DaemonSet | Promtail/Alloy 以 DaemonSet 部署，自动发现 Pod |
| K8s 有状态服务 | 日志写文件场景需挂载 hostPath 或 emptyDir |
| 混合部署 | Prometheus 采集指标 + Promtail/Alloy 采集日志，各自独立 |

**关键配置**：
- Docker 默认 json-file driver 限制日志大小：`--log-opt max-size=10m --log-opt max-file=3`
- 生产环境建议配置日志轮转，避免磁盘打满
- Promtail/Alloy 的 positions 文件需持久化（hostPath），避免重启后重复采集
- Loki 查询注意时间范围控制，避免全量扫描
