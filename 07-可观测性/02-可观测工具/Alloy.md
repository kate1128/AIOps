# Grafana Alloy — 下一代全能遥测采集器

**更新日期：** 2026年06月04日
**信息来源：** 官方文档、GitHub 仓库、用户实测记录
**参考地址：**

1. GitHub：[grafana/alloy](https://github.com/grafana/alloy)（~3.2k stars）
2. 官方文档：[Grafana Alloy Docs](https://grafana.com/docs/alloy/latest/)
3. Loki 日志采集：[Send logs to Loki via Alloy](https://grafana.com/docs/loki/latest/send-data/alloy/)
4. River 配置语言：[River Reference](https://grafana.com/docs/alloy/latest/reference/)
5. ai-问答：https://grafana.com/grot/

> Star 数会持续变化。正式对外汇报前建议以 GitHub 实时数据复核。

---

## 1. 结论摘要

Grafana Alloy 是 Grafana Labs 于 2024 年推出的下一代可观测性采集器，基于 OpenTelemetry Collector 核心扩展，使用声明式的 River 配置语言编写采集管道。其核心价值是**一个 DaemonSet 替代 Promtail + node-exporter + OTel Collector 三个独立组件**，大幅降低采集层的运维成本。

2024 年 Grafana 官方宣布 Promtail 进入维护模式，Alloy 成为日志采集端的唯一主推替代方案。

**对本项目的核心价值：** 已作为 DaemonSet 部署在 `logging` 命名空间，负责采集全集群容器日志并推送至 Loki（携带 X-Scope-OrgID: 101 租户头）。后续如需同时采集节点指标或 OTel Traces，只需扩展 `config.alloy` 管道，无需新增独立组件。

| 关键信息 | 值 |
| --- | --- |
| 命名空间 | `logging` |
| 部署方式 | DaemonSet（每节点 1 Pod） |
| Web UI 端口 | NodePort `30272`（内部 `12345`） |
| Loki 推送端点 | `http://loki-gateway.logging.svc.cluster.local:80/loki/api/v1/push` |
| 多租户头 | `X-Scope-OrgID: 101` |
| 配置方式 | ConfigMap `alloy`（key: `config.alloy`） |
| Promtail 状态 | ⚠️ 官方维护模式，已被 Alloy 替代 |

---

## 2. 产品概况

| 项目 | 内容 |
| --- | --- |
| 产品名称 | Grafana Alloy |
| 开发者 | Grafana Labs |
| CNCF 状态 | 非 CNCF（Grafana Labs 主导） |
| 开源协议 | Apache-2.0 |
| 配置语言 | River（声明式，支持热重载、条件、循环） |
| 内核 | 基于 OpenTelemetry Collector 扩展 |
| 部署形态 | DaemonSet / 独立进程 / Docker |
| 替代组件 | Promtail、node-exporter、OTel Collector |
| 适用场景 | Grafana 全家桶（Loki + Prometheus + Tempo）的统一采集端 |

---

## 3. 产品定位与典型场景

| 场景 | Alloy 解决的问题 | 价值 |
| --- | --- | --- |
| K8s 容器日志采集 | Promtail 进入维护模式，官方不再投入 | `loki.source.kubernetes` 替代 Promtail，自动发现 Pod 日志 |
| 节点系统指标 | 需要额外部署 node-exporter DaemonSet | `prometheus.exporter.unix` 内置等价功能，合并为一个 DaemonSet |
| OTel Traces 接收 | OTel Collector 单独部署增加运维成本 | `otelcol.receiver.otlp` 原生接收 gRPC/HTTP Traces，转发至 Tempo |
| 中间件指标抓取 | 各组件 Exporter 需单独配置 scrape | `prometheus.scrape` 统一配置所有 Exporter 采集目标 |
| 日志脱敏与结构化 | 原始日志含敏感字段或格式不统一 | `loki.process` Pipeline 支持 JSON 解析、字段提取、脱敏替换 |
| 配置热更新 | Promtail 改配置需 SIGHUP 或重启 | River 内置热重载，修改 ConfigMap 后无需重启 Pod |

---

## 4. 技术架构与核心机制

### 4.1 整体数据流

```mermaid
graph LR
    subgraph Node[每个 K8s 节点]
        PodLogs["/var/log/pods/**/*.log"] --> KubeSrc["loki.source.kubernetes\nK8s API 自动发现"]
        HostFiles["/var/log/*.log"] --> FileSrc["loki.source.file\n主机文件采集"]
        NodeHW[节点硬件] --> UnixExp["prometheus.exporter.unix\n替代 node-exporter"]
        Exporters[中间件 Exporter] --> Scrape["prometheus.scrape\n指标抓取"]
        OTelApp[应用 OTel SDK] --> OtelRecv["otelcol.receiver.otlp\ngRPC :4317 / HTTP :4318"]
    end

    KubeSrc --> Process["loki.process\nJSON解析 / 标签提取 / 脱敏"]
    FileSrc --> Process
    Process --> LokiWrite["loki.write\n推送至 Loki"]

    UnixExp --> RemoteWrite["prometheus.remote_write\n推送至 Prometheus"]
    Scrape --> RemoteWrite

    OtelRecv --> TempoExp["otelcol.exporter.otlphttp\n转发至 Tempo"]

    LokiWrite --> Loki[(Loki)]
    RemoteWrite --> Prometheus[(Prometheus)]
    TempoExp --> Tempo[(Tempo)]
```

| 组件 | 替代对象 | 说明 |
| --- | --- | --- |
| `loki.source.kubernetes` | Promtail | 通过 K8s API Watch 自动发现 Pod 日志路径 |
| `prometheus.exporter.unix` | node-exporter | 采集 CPU/内存/磁盘/网络等节点指标 |
| `prometheus.scrape` | Prometheus scrape_configs | 抓取各中间件 Exporter 暴露的指标 |
| `otelcol.receiver.otlp` | OTel Collector | 接收应用上报的 Traces，转发至 Tempo |
| `loki.process` | Promtail pipeline_stages | 日志结构化解析、标签提取、敏感字段脱敏 |

---

### 4.2 Alloy 配置语言（Alloy syntax）

Alloy 使用自己的声明式配置语言（文件扩展名 `.alloy`），语法由三个基本元素组成：**Block（块）**、**Attribute（属性）**、**Expression（表达式）**。

#### Block（块）

Block 是配置的主要结构单元，用于定义组件实例或嵌套配置。格式：

```alloy
COMPONENT_NAME "LABEL" {
  // 属性或嵌套 Block
}
```

- `COMPONENT_NAME`：决定这是哪种类型的组件，如 `loki.write`、`prometheus.scrape`
- `"LABEL"`：用户自定义的唯一标识符，同一类型的组件可以创建多个实例，用 Label 区分

```alloy
// 同类型组件的两个实例，Label 不同
prometheus.scrape "api_metrics" {
  targets = [{"__address__" = "api:8080"}]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.scrape "db_metrics" {
  targets = [{"__address__" = "db:9187"}]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

#### Attribute（属性）

Attribute 在 Block 内设置具体的配置值，格式为 `key = value`：

```alloy
log_level = "info"
timeout   = 30
enabled   = true
tags      = ["web", "api"]
```

#### Expression（表达式）与组件引用

Expression 是 Alloy 配置语言中最重要的特性，允许**一个组件的输出直接作为另一个组件的输入**，形成组件间的数据依赖关系。

引用格式：`COMPONENT_NAME.LABEL.EXPORT_NAME`

```alloy
// 组件 A：读取文件内容
local.file "api_key" {
  filename = "/etc/secrets/api.key"
}

// 组件 B：引用组件 A 的输出（content 是 local.file 的 export）
prometheus.remote_write "production" {
  endpoint {
    url = "https://prometheus.example.com/api/v1/write"
    basic_auth {
      password = local.file.api_key.content   // ← 直接引用 A 的导出值
    }
  }
}
```

当 `api.key` 文件内容发生变化时，Alloy 自动重新评估 `local.file.api_key`，并将新值传播给引用它的所有下游组件——这就是 Alloy 热重载的底层机制。

也可以使用内置函数和系统调用：

```alloy
// 从环境变量读取值
loki_url = sys.env("LOKI_URL")

// 字符串拼接
config_path = sys.env("HOME") + "/config.yaml"
```

---

### 4.3 Component Controller（组件控制器）

Component Controller 是 Alloy 的运行时核心，负责管理所有组件的生命周期。工作方式：

1. **启动时**：读取 `.alloy` 配置文件，解析所有组件及其依赖关系，构建一个**有向无环图（DAG）**
2. **运行时**：每个组件独立运行，当一个组件的 Export 发生变化时，Controller 自动通知所有引用该 Export 的下游组件重新评估
3. **热重载时**：ConfigMap 更新后，Controller 只重建发生变化的组件，不影响其余正常运行的组件

```
配置文件变更
      ↓
Component Controller 解析新配置
      ↓
构建新 DAG，与旧 DAG 对比差异
      ↓
只重建/更新有变化的组件
未变化的组件继续运行，不中断数据流
```

这就是为什么修改 `config.alloy` 后日志采集不会中断——Controller 只对变更部分做手术式更新。

> **本项目热重载说明：** Alloy 的热重载依赖 ConfigMap 挂载变更事件（由 Kubelet 同步，最长约 60 秒）。如果需要立即生效，执行 `kubectl rollout restart daemonset alloy -n logging`。

---

### 4.4 Remote Configuration（远端配置）

Remote Configuration 是 Alloy 的进阶特性：Alloy 实例不读取本地 `.alloy` 文件，而是**从远端服务器拉取配置**，实现多集群、多 Alloy 实例的集中化配置管理。

```
本地模式（本项目当前方式）：
  Alloy Pod ──读取──▶ K8s ConfigMap (config.alloy)

远端配置模式（多集群场景）：
  Alloy Pod ──HTTP 拉取──▶ 配置服务器（Grafana Cloud Fleet Management 或自建）
                              ↑
                         统一管理 N 个集群的所有 Alloy 配置
```

**Web UI 中的 "Remote configuration" 页面**显示当前配置拉取状态：
- **本项目**：使用本地 ConfigMap，该页面无活跃远端地址，可忽略
- **何时需要**：管理超过 5 个以上集群的 Alloy 实例时，避免逐一 SSH/kubectl 修改 ConfigMap

---

### 4.5 Modules（模块）与自定义组件

Alloy 支持将一组组件封装成**可复用的 Module（模块）**，类似编程语言中的函数或库。

```alloy
// 定义一个自定义组件（封装日志采集+多租户写入逻辑）
declare "loki_pipeline" {
  argument "tenant_id" {}
  argument "namespace" {}

  loki.source.kubernetes "pods" {
    targets    = discovery.kubernetes.pods.targets
    forward_to = [loki.write.output.receiver]
  }

  loki.write "output" {
    endpoint {
      url     = "http://loki-gateway.logging.svc:80/loki/api/v1/push"
      headers = { "X-Scope-OrgID" = argument.tenant_id.value }
    }
  }
}

// 复用模块：同一套逻辑应用到不同租户
loki_pipeline "prod" {
  tenant_id = "101"
  namespace = "prod"
}

loki_pipeline "staging" {
  tenant_id = "102"
  namespace = "staging"
}
```

**本项目目前不使用 Modules**，单一管道配置已足够；多租户扩展时可考虑。

---

### 4.6 Clustering（集群模式）

当单个 Alloy 实例无法处理全部采集目标时，可以配置多个 Alloy 实例组成集群，**自动均衡负载**：

```alloy
clustering {
  enabled = true
}

prometheus.scrape "targets" {
  targets    = discovery.kubernetes.services.targets
  clustering { enabled = true }   // 自动将 targets 分配给集群中的各节点
  forward_to = [prometheus.remote_write.central.receiver]
}
```

集群模式下，所有节点通过 gossip 协议自动发现彼此，抓取目标自动分片，某节点故障后其任务由其余节点接管。

**本项目**：单节点 K8s 集群，DaemonSet 模式已足够，不需要 Clustering。



---

## 5. 部署

### 5.1 Helm 安装

```bash
# 在线安装
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install alloy grafana/alloy -f alloy-values.yaml --namespace logging --create-namespace

# 离线安装
helm pull grafana/alloy
helm install alloy alloy-1.8.2.tgz -f alloy-values.yaml --namespace logging --create-namespace

# 更新配置
helm upgrade alloy alloy-1.8.2.tgz -f alloy-values.yaml --namespace logging
```

### 5.2 alloy-values.yaml

```yaml
alloy:
  configMap:
    create: false   # 使用外部 ConfigMap 管理配置
    name: alloy
    key: config.alloy
  controller:
    type: daemonset
  crds:
    create: false
```

### 5.3 基础 config.alloy（日志采集，当前生效）

```river
logging {
  level  = "info"
  format = "logfmt"
}

// 1. 发现 Kubernetes Pods
discovery.kubernetes "pods" {
  role = "pod"
}

// 2. 从 Kubernetes 采集 Pod 日志
loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.write.default.receiver]
}

// 3. 将日志写入 Loki（多租户模式，携带 X-Scope-OrgID）
loki.write "default" {
  endpoint {
    url     = "http://loki-gateway.logging.svc.cluster.local:80/loki/api/v1/push"
    headers = { "X-Scope-OrgID" = "101" }
  }
}
```

### 5.4 应用 ConfigMap

```bash
kubectl create configmap alloy \
  --from-file=config.alloy=alloy-config.alloy \
  -n logging --dry-run=client -o yaml | kubectl apply -f -
```

---

## 6. 访问与验证

### 6.1 访问地址

| 服务 | 地址 | 说明 |
| --- | --- | --- |
| Alloy Web UI | `http://<NodeIP>:30272` | 管道可视化、组件状态、指标查看 |
| 集群内地址 | `alloy.logging.svc.cluster.local:12345` | 内部访问 |

### 6.2 Web UI 三个页面说明

Alloy Web UI 顶部导航有三个主要入口，对应三个不同视角：

#### Components health（首页）

首页列出 `config.alloy` 中定义的**所有组件**，每行显示：

- **组件 ID**：如 `loki.source.kubernetes.pods`、`loki.write.default`，格式是 `<类型>.<标签名>`
- **Health 状态**：
  - `healthy` — 正常运行
  - `unhealthy` — 出错，行会变红，点击进去可看错误详情
  - `unknown` — 刚启动尚未完成首次评估

**使用场景：** 日志/指标推送异常时，第一步就来这里看哪个组件变红，直接定位故障组件。点击组件名可进入详情页，看到该组件当前的参数值、内部状态和最近的错误信息。

![Alloy index](images/alloy-index.png)

点击某个组件（如 `loki.source.kubernetes.pods`）可查看该组件当前的运行状态和已处理的日志流数量：

![Alloy 组件架构](images/alloy-Component.png)

#### Graph（采集管道拓扑图）

Graph 页面将 `config.alloy` 中所有组件及其依赖关系渲染成**有向图**，箭头方向代表数据流向。

例如本项目的基础配置渲染出来是：

```
discovery.kubernetes.pods
        ↓
loki.source.kubernetes.pods
        ↓
loki.write.default
        ↓
    [Loki]
```

**使用场景：**
- 快速理解当前管道的数据流向，确认组件间连接是否正确
- 检查扩展配置后新增的组件（如 `loki.process`）是否已正确插入管道中间
- 节点颜色和边的颜色也反映组件健康状态，红色节点代表 unhealthy

![alloy-Graph](images/alloy-Graph.png)

#### Remote configuration（远端配置）

这个页面显示 Alloy 的**配置来源**：

| 状态 | 含义 |
| --- | --- |
| `Local` / 页面显示空或无远端地址 | 当前使用本地 ConfigMap（`config.alloy`）作为配置来源，即本项目的方式 |
| 显示远端 URL | Alloy 从 Grafana Cloud 或自建的 Alloy config server 拉取配置，本地不维护 config 文件 |

**本项目状态：** 使用本地 ConfigMap，Remote configuration 页面不会有活跃的远端地址，可以忽略。该功能是 Grafana Cloud 或大规模多集群统一下发配置时才会用到的进阶特性。

### 6.3 已部署状态

```bash
kubectl get all -n logging
# NAME                                READY   STATUS    RESTARTS   AGE
# pod/alloy-zgjt6                     2/2     Running   0          3h39m
# ...
# NAME                            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)
# service/alloy                   NodePort    10.1.238.214   <none>        12345:30272/TCP
# ...
# NAME                         DESIRED   CURRENT   READY
# daemonset.apps/alloy         1         1         1
```

### 6.4 验证日志推送

```bash
# 查看 Alloy Pod 日志，确认无错误
kubectl logs -n logging -l app.kubernetes.io/name=alloy --tail=50

# 在 Grafana Explore 中执行 LogQL 查询，确认日志流入
# 数据源: Loki，查询: {namespace="logging"}
```

---

## 7. 各类数据接入配置详解

每个小节给出**完整链路配置**，可以直接复制追加到现有 `config.alloy` 末尾，无需重启 Alloy Pod（等待 ConfigMap 同步约 60 秒后自动生效）。所有示例共用同一个 `prometheus.remote_write` 写出端，只需配置一次。

> **通用写出端（所有指标类配置都依赖这个，配置一次即可）：**
> ```alloy
> prometheus.remote_write "central" {
>   endpoint {
>     url = "http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090/api/v1/write"
>   }
> }
> ```

---

### 7.1 K8s Pod 日志采集（当前已部署）

**链路：** K8s API → 发现 Pod → tail 日志文件 → 可选解析 → 写入 Loki

**最小配置（已生效）：**

```alloy
discovery.kubernetes "pods" {
  role = "pod"
}

loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url     = "http://loki-gateway.logging.svc.cluster.local:80/loki/api/v1/push"
    headers = { "X-Scope-OrgID" = "101" }
  }
}
```

**扩展：加标签提取 + JSON 解析（推荐生产使用）**

在 `loki.source.kubernetes` 和 `loki.write` 之间插入 `discovery.relabel` 和 `loki.process`：

```alloy
// Graph 视图中会变成：
// discovery.kubernetes.pods
//         ↓
// discovery.relabel.pods       ← 新增：提取 namespace/pod/container 标签
//         ↓
// loki.source.kubernetes.pods
//         ↓
// loki.process.parse           ← 新增：JSON 解析，提取 level/trace_id
//         ↓
// loki.write.default

discovery.kubernetes "pods" {
  role = "pod"
}

discovery.relabel "pods" {
  targets = discovery.kubernetes.pods.targets

  // 把 K8s 元数据注入为 Loki 标签
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "pod"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_container_name"]
    target_label  = "container"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_label_app"]
    target_label  = "app"
  }
  // 只采集 Running 状态的 Pod，终止中的 Pod 跳过
  rule {
    source_labels = ["__meta_kubernetes_pod_phase"]
    regex         = "Running"
    action        = "keep"
  }
}

loki.source.kubernetes "pods" {
  targets    = discovery.relabel.pods.output   // 引用 relabel 的输出
  forward_to = [loki.process.parse.receiver]
}

loki.process "parse" {
  // 适用于 JSON 格式日志（如 Python structlog、Java logback JSON appender）
  stage.json {
    expressions = {
      level    = "level",
      trace_id = "traceId",
      message  = "message",
    }
  }
  stage.labels {
    values = {
      level    = "level",       // 使日志在 Loki 中可按 level 过滤
      trace_id = "trace_id",    // 使 Grafana 可从日志行直接跳转到 Tempo 链路
    }
  }
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url     = "http://loki-gateway.logging.svc.cluster.local:80/loki/api/v1/push"
    headers = { "X-Scope-OrgID" = "101" }
  }
  external_labels = { cluster = "smartvision-prod" }
}
```

---

### 7.2 节点系统指标（替代 node-exporter）

**链路：** 节点硬件/OS → 内置 unix exporter → scrape → Remote Write → Prometheus

**前提：** kube-prometheus-stack 已部署了 node-exporter DaemonSet 时，可以跳过此节，避免重复采集。此配置适合**不想单独部署 node-exporter** 的场景。

```alloy
// Graph 视图：
// prometheus.exporter.unix.node
//         ↓
// prometheus.scrape.node_metrics
//         ↓
// prometheus.remote_write.central

prometheus.exporter.unix "node" {
  // set_collectors 限制只启用需要的采集器，减少内存占用
  set_collectors = [
    "cpu",        // CPU 使用率（替代 node_cpu_seconds_total）
    "meminfo",    // 内存使用（替代 node_memory_*）
    "diskstats",  // 磁盘 IO
    "filesystem", // 磁盘空间
    "netdev",     // 网络流量
    "loadavg",    // 系统负载
    "hwmon",      // 温度/风扇（物理机有效）
    "uname",      // 系统信息标签
    "processes",  // 进程数量
  ]
  filesystem {
    // 排除 proc/sys/dev 等虚拟文件系统，避免采集噪音
    mount_points_exclude = "^/(dev|proc|sys|run|snap)($|/)"
  }
}

prometheus.scrape "node_metrics" {
  targets         = prometheus.exporter.unix.node.targets
  scrape_interval = "15s"
  forward_to      = [prometheus.remote_write.central.receiver]
}

// 写出端（所有指标类配置共用）
prometheus.remote_write "central" {
  endpoint {
    url = "http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090/api/v1/write"
  }
}
```

**在 Grafana 中查看：** 导入 Dashboard [1860](https://grafana.com/grafana/dashboards/1860)（Node Exporter Full），数据源选 Prometheus，指标与 node-exporter 完全兼容。

---

### 7.3 Redis 指标接入

Redis **有内置 Exporter**，**不需要单独部署** `redis-exporter` Pod，直接在 `config.alloy` 里配置连接地址即可。

**方式一：内置 Exporter（推荐，无需额外 Pod）**

**链路：** Alloy 内置 → 直连 Redis → 采集指标 → Remote Write

```alloy
// Graph 视图：
// prometheus.exporter.redis.main
//         ↓
// prometheus.scrape.redis
//         ↓
// prometheus.remote_write.central

prometheus.exporter.redis "main" {
  redis_addr     = "redis-master.cache.svc.cluster.local:6379"
  redis_password = sys.env("REDIS_PASSWORD")   // 密码通过环境变量注入，不写死
}

prometheus.scrape "redis" {
  targets    = prometheus.exporter.redis.main.targets
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
}
```

**方式二：外部 Exporter（已有独立 redis-exporter Pod 时使用）**

```alloy
// Graph 视图：
// prometheus.scrape.redis
//         ↓
// prometheus.remote_write.central

prometheus.scrape "redis" {
  targets = [
    { __address__ = "redis-exporter.cache.svc.cluster.local:9121" },
  ]
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
}
```

> **两种方式选哪个？** 新部署选内置，省一个 Pod；已经跑着独立 redis-exporter 的，用方式二 scrape 就好，不必迁移。指标名称两种方式完全一致，Grafana Dashboard 通用。

**如何确认接入成功：**
```bash
# Grafana Explore → Prometheus，执行：
redis_connected_clients
```

**推荐 Grafana Dashboard：** ID [11835](https://grafana.com/grafana/dashboards/11835)

---

### 7.4 PostgreSQL 指标接入

PostgreSQL **有内置 Exporter**，不需要单独部署 `postgres-exporter` Pod。

**方式一：内置 Exporter（推荐）**

```alloy
prometheus.exporter.postgres "main" {
  // DSN 格式：postgresql://user:pass@host:5432/dbname?sslmode=disable
  data_source_names = [sys.env("POSTGRES_DSN")]
}

prometheus.scrape "postgres" {
  targets    = prometheus.exporter.postgres.main.targets
  scrape_interval = "30s"
  forward_to = [prometheus.remote_write.central.receiver]
}
```

**方式二：外部 Exporter（已有独立 postgres-exporter Pod 时使用）**

```alloy
prometheus.scrape "postgres" {
  targets = [
    { __address__ = "postgres-exporter.db.svc.cluster.local:9187" },
  ]
  scrape_interval = "30s"
  forward_to = [prometheus.remote_write.central.receiver]
}
```

**推荐 Grafana Dashboard：** ID [9628](https://grafana.com/grafana/dashboards/9628)

---

### 7.5 GPU 指标接入（DCGM Exporter）

**前提：** 已部署 `dcgm-exporter` DaemonSet（NVIDIA 官方）。

```alloy
// Graph 视图：
// discovery.kubernetes.dcgm_pods   ← 自动发现 dcgm-exporter Pod
//         ↓
// prometheus.scrape.dcgm
//         ↓
// prometheus.remote_write.central

// 方式一：静态地址（简单）
prometheus.scrape "dcgm" {
  targets = [
    { __address__ = "dcgm-exporter.gpu.svc.cluster.local:9400" },
  ]
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
}

// 方式二：K8s 服务发现（多节点 GPU 时推荐，自动发现所有节点的 dcgm-exporter）
discovery.kubernetes "dcgm_pods" {
  role = "pod"
  namespaces { names = ["gpu"] }
  selectors {
    role  = "pod"
    label = "app.kubernetes.io/name=dcgm-exporter"
  }
}

discovery.relabel "dcgm_pods" {
  targets = discovery.kubernetes.dcgm_pods.targets
  rule {
    source_labels = ["__address__"]
    target_label  = "__address__"
    regex         = "(.+):\\d+"
    replacement   = "$1:9400"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_node_name"]
    target_label  = "node"
  }
}

prometheus.scrape "dcgm" {
  targets    = discovery.relabel.dcgm_pods.output
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
}
```

**推荐 Grafana Dashboard：** ID [12239](https://grafana.com/grafana/dashboards/12239)

---

### 7.6 OTel Traces 接收（应用链路追踪）

**链路：** 应用（Java Agent / Python OTel SDK）→ OTLP gRPC/HTTP → Alloy → Tempo

**前提：** 已部署 Tempo，且应用已集成 OTel SDK 或 Java Agent。

```alloy
// Graph 视图：
// otelcol.receiver.otlp.default
//         ↓
// otelcol.processor.batch.default   ← 批量发送，降低请求频率
//         ↓
// otelcol.exporter.otlphttp.tempo
//         ↓
//       [Tempo]

otelcol.receiver.otlp "default" {
  // gRPC 端口：Java Agent / Python SDK 默认使用 4317
  grpc { endpoint = "0.0.0.0:4317" }
  // HTTP 端口：浏览器/某些 SDK 使用 4318
  http { endpoint = "0.0.0.0:4318" }

  output {
    traces = [otelcol.processor.batch.default.input]
  }
}

// 批量处理器：攒够 200 条或等待 5 秒后一次性发送，减少 Tempo 请求压力
otelcol.processor.batch "default" {
  send_batch_size    = 200
  timeout            = "5s"
  output {
    traces = [otelcol.exporter.otlphttp.tempo.input]
  }
}

otelcol.exporter.otlphttp "tempo" {
  client {
    endpoint = "http://tempo.tracing.svc.cluster.local:4318"
  }
}
```

**应用侧配置（Java Agent 示例）：**

```yaml
# K8s Deployment 环境变量中加入
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://alloy.logging.svc.cluster.local:4317"   # 指向 Alloy 的 gRPC 端口
  - name: OTEL_SERVICE_NAME
    value: "my-service"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "namespace=$(POD_NAMESPACE),pod=$(POD_NAME)"
```

---

### 7.7 节点文件日志采集（loki.source.file）

**适用场景：** 采集节点上的非容器日志，如 `/var/log/syslog`、Nginx access log、自定义应用写到宿主机的日志文件。

**链路：** 节点文件系统 → `loki.source.file` 读取文件 → `loki.write`

```alloy
// Graph 视图：
// loki.source.file.varlog
//         ↓
// loki.write.default

loki.source.file "varlog" {
  targets = [
    // path 是文件路径，labels 是附加到日志上的标签
    { __path__ = "/var/log/syslog",         job = "syslog"  },
    { __path__ = "/var/log/nginx/access.log", job = "nginx" },
  ]
  forward_to = [loki.write.default.receiver]
}
```

> **注意：** DaemonSet 部署时 Alloy Pod 看不到宿主机文件，需要在 `alloy-values.yaml` 中将宿主机目录挂载进容器：
> ```yaml
> # alloy-values.yaml
> alloy:
>   controller:
>     volumes:
>       extra:
>         - name: varlog
>           hostPath:
>             path: /var/log
>   mounts:
>     extra:
>       - name: varlog
>         mountPath: /var/log
>         readOnly: true
> ```

---

### 7.8 systemd Journal 日志采集（loki.source.journal）

**适用场景：** 采集节点上 `systemd` 管理的服务日志（kubelet、containerd、sshd 等），等价于 `journalctl -f`。

```alloy
// Graph 视图：
// loki.source.journal.system
//         ↓
// loki.write.default

loki.source.journal "system" {
  // path 默认 /var/log/journal，一般不需要改
  path      = "/var/log/journal"
  // 只采集这些 systemd 服务的日志
  matches   = "_SYSTEMD_UNIT=kubelet.service _SYSTEMD_UNIT=containerd.service"
  // 把 systemd 字段作为 Loki 标签
  labels    = { job = "systemd" }
  forward_to = [loki.write.default.receiver]
}
```

> 同样需要在 `alloy-values.yaml` 中挂载 `/var/log/journal`（见 §7.7 挂载方式）。

---

### 7.9 Docker 容器日志采集（loki.source.docker）

**适用场景：** 节点上直接跑 Docker 容器（**非 K8s**）时使用。本项目是 K8s 集群，**优先用 §7.1 的 `loki.source.kubernetes`**；此节适合混合环境或裸机 Docker 场景。

**链路：** Docker Daemon API → `loki.source.docker` → `loki.write`

```alloy
// Graph 视图：
// discovery.docker.containers
//         ↓
// loki.source.docker.containers
//         ↓
// loki.write.default

// 1. 通过 Docker API 发现所有容器
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
  // 只发现运行中的容器
  filter {
    name   = "status"
    values = ["running"]
  }
}

// 2. 采集所有发现容器的日志
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  labels     = { job = "docker" }
  forward_to = [loki.write.default.receiver]
}
```

> DaemonSet 中需要挂载 Docker socket：
> ```yaml
> # alloy-values.yaml
> alloy:
>   controller:
>     volumes:
>       extra:
>         - name: docker-sock
>           hostPath:
>             path: /var/run/docker.sock
>   mounts:
>     extra:
>       - name: docker-sock
>         mountPath: /var/run/docker.sock
> ```

---

### 7.10 内置 Exporter 完整清单

Alloy 内置了大量中间件的 Exporter（`prometheus.exporter.*`），**有内置的就不需要单独部署对应的 exporter Pod**。以下是完整清单（来自官方文档）：

| 内置组件 | 对应独立 Exporter | 适用场景 |
|----------|------------------|----------|
| `prometheus.exporter.redis` | oliver006/redis_exporter | Redis |
| `prometheus.exporter.mysql` | prometheus/mysqld_exporter | MySQL |
| `prometheus.exporter.postgres` | prometheuscommunity/postgres-exporter | PostgreSQL |
| `prometheus.exporter.mongodb` | percona/mongodb_exporter | MongoDB |
| `prometheus.exporter.kafka` | danielqsj/kafka_exporter | Kafka |
| `prometheus.exporter.elasticsearch` | prometheus-community/elasticsearch_exporter | Elasticsearch |
| `prometheus.exporter.memcached` | prometheus/memcached_exporter | Memcached |
| `prometheus.exporter.mssql` | awaragi/prometheus-mssql-exporter | SQL Server |
| `prometheus.exporter.oracledb` | iamseth/oracledb_exporter | Oracle DB |
| `prometheus.exporter.unix` | prometheus/node_exporter | Linux 节点指标 |
| `prometheus.exporter.windows` | prometheus-community/windows_exporter | Windows 节点 |
| `prometheus.exporter.blackbox` | prometheus/blackbox_exporter | HTTP/TCP/DNS 探测 |
| `prometheus.exporter.snmp` | prometheus/snmp_exporter | 网络设备 SNMP |
| `prometheus.exporter.apache` | Lusitaniae/apache_exporter | Apache Web Server |
| `prometheus.exporter.consul` | prometheus/consul_exporter | Consul |
| `prometheus.exporter.statsd` | prometheus/statsd_exporter | StatsD 指标接收 |
| `prometheus.exporter.cadvisor` | google/cadvisor | 容器资源指标 |
| `prometheus.exporter.cloudwatch` | prometheus-community/yet-another-cloudwatch-exporter | AWS CloudWatch |
| `prometheus.exporter.gcp` | —（内置 GCP 采集） | Google Cloud 指标 |
| `prometheus.exporter.azure` | —（内置 Azure 采集） | Azure 指标 |
| `prometheus.exporter.process` | ncabatoff/process-exporter | 进程级指标 |
| `prometheus.exporter.self` | — | Alloy 自身运行指标 |
| `prometheus.exporter.catchpoint` | — | Catchpoint 数字体验监控 |
| `prometheus.exporter.databricks` | — | Databricks 作业/集群指标 |
| `prometheus.exporter.dnsmasq` | google/dnsmasq_exporter | dnsmasq DNS 缓存 |
| `prometheus.exporter.github` | infinityworks/github-exporter | GitHub 仓库/速率指标 |
| `prometheus.exporter.snowflake` | — | Snowflake 数据仓库 |
| `prometheus.exporter.squid` | boynux/squid-exporter | Squid 代理缓存 |
| `prometheus.exporter.static` | — | 静态指标（手动定义固定值） |

> **没有内置的中间件**（如 dcgm-exporter/nvidia-smi、rabbitmq_exporter 等），需要单独部署对应 Pod，然后用 `prometheus.scrape` 抓取其 `/metrics` 端点（参考 §7.5）。

**通用配置模式（所有内置 exporter 都遵循相同的两步）：**

```alloy
// 步骤1：声明内置 exporter，配置连接信息
prometheus.exporter.<NAME> "<LABEL>" {
  // 各 exporter 特有的连接参数
}

// 步骤2：scrape 它的输出，转发到 Prometheus
prometheus.scrape "<LABEL>" {
  targets    = prometheus.exporter.<NAME>.<LABEL>.targets
  forward_to = [prometheus.remote_write.central.receiver]
}
```

**内置 vs 独立部署 Pod 选型：**

| 维度 | 内置 Exporter | 独立 Exporter Pod |
|------|--------------|------------------|
| 部署复杂度 | ✅ 低（只改 config.alloy） | ⚠️ 需额外 Helm Chart/Deployment |
| 故障隔离 | ⚠️ Alloy 重启所有采集短暂中断 | ✅ 互不影响 |
| 独立升级 | ⚠️ 随 Alloy 版本绑定 | ✅ 可独立升级 |
| 凭据管理 | 统一在 config.alloy 或 env | 各自独立管理 |
| **推荐场景** | 新部署、中小规模 | 生产关键组件、已有独立 exporter |


### 附录：
grafana的rag地址：https://grafana.com/grot/

以下是 Grafana Alloy 内置的 exporter 完整清单，分为两大类：

一、Prometheus Exporters（prometheus.exporter.*）
```text
[Alloy 兼容组件]

prometheus.exporter.apache
prometheus.exporter.azure
prometheus.exporter.blackbox
prometheus.exporter.cadvisor
prometheus.exporter.catchpoint
prometheus.exporter.cloudwatch
prometheus.exporter.consul
prometheus.exporter.databricks
prometheus.exporter.dnsmasq
prometheus.exporter.elasticsearch
prometheus.exporter.gcp
prometheus.exporter.github
prometheus.exporter.kafka
prometheus.exporter.memcached
prometheus.exporter.mongodb
prometheus.exporter.mssql
prometheus.exporter.mysql
prometheus.exporter.oracledb
prometheus.exporter.postgres
prometheus.exporter.process
prometheus.exporter.redis
prometheus.exporter.self
prometheus.exporter.snmp
prometheus.exporter.snowflake
prometheus.exporter.squid
prometheus.exporter.static
prometheus.exporter.statsd
prometheus.exporter.unix
prometheus.exporter.windows
```
二、OTel Exporters（otelcol.exporter.*）
```text
[Alloy OTel 组件]

otelcol.exporter.awss3
otelcol.exporter.datadog
otelcol.exporter.debug
otelcol.exporter.faro
otelcol.exporter.file
otelcol.exporter.googlecloud
otelcol.exporter.googlecloudpubsub
otelcol.exporter.kafka
otelcol.exporter.loadbalancing
otelcol.exporter.loki
otelcol.exporter.otlp
otelcol.exporter.otlphttp
otelcol.exporter.prometheus
otelcol.exporter.splunkhec
otelcol.exporter.syslog
```
说明： OTel 侧还包含 Connector 组件（如 otelcol.connector.spanmetrics、otelcol.connector.servicegraph 等），它们在管道中同时充当消费者和生产者，功能上类似 exporter，但严格来说属于 connector 类别。完整的 OTel 组件版本信息可参考 OpenTelemetry Collector Builder manifest。[OTel in Alloy]

---

### 7.11 接收外部 Push 指标（prometheus.receive_http）

**适用场景：** 某些组件不支持被 scrape（如定时任务、Lambda、短生命周期容器），只能主动 push 指标。Alloy 可以开一个 HTTP 端点接收这些 push 请求。

```alloy
// Graph 视图：
// prometheus.receive_http.push_gateway
//         ↓
// prometheus.remote_write.central

prometheus.receive_http "push_gateway" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = 9091   // 应用往这个端口 POST 指标
  }
  forward_to = [prometheus.remote_write.central.receiver]
}
```

应用侧发送指标（等价于 Pushgateway）：
```bash
# 发送一个指标到 Alloy
echo 'my_job_duration_seconds 1.23' | \
  curl --data-binary @- http://<NodeIP>:9091/metrics/job/my_job
```

> Alloy 的 `prometheus.receive_http` 与 Prometheus Pushgateway 接口兼容，可以直接替代。

---

### 7.12 完整 config.alloy（所有场景合并）

如需同时启用以上所有采集，将各节配置合并到同一个文件，注意 `prometheus.remote_write "central"` 只定义一次：

```alloy
// ── 公共写出端（只定义一次）──────────────────────────────
prometheus.remote_write "central" {
  endpoint {
    url = "http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090/api/v1/write"
  }
}

loki.write "default" {
  endpoint {
    url     = "http://loki-gateway.logging.svc.cluster.local:80/loki/api/v1/push"
    headers = { "X-Scope-OrgID" = "101" }
  }
}

// ── 日志 ──────────────────────────────────────────────────
discovery.kubernetes "pods" { role = "pod" }

loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.write.default.receiver]
}

// ── 节点指标 ──────────────────────────────────────────────
prometheus.exporter.unix "node" {
  set_collectors = ["cpu","meminfo","diskstats","filesystem","netdev","loadavg"]
  filesystem { mount_points_exclude = "^/(dev|proc|sys|run|snap)($|/)" }
}
prometheus.scrape "node_metrics" {
  targets = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.central.receiver]
}

// ── 中间件 Exporter ───────────────────────────────────────
prometheus.scrape "middleware" {
  targets = [
    { __address__ = "redis-exporter.cache.svc:9121",    job = "redis"    },
    { __address__ = "postgres-exporter.db.svc:9187",    job = "postgres" },
    { __address__ = "dcgm-exporter.gpu.svc:9400",       job = "dcgm"     },
  ]
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.central.receiver]
}

// ── OTel Traces ───────────────────────────────────────────
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output { traces = [otelcol.exporter.otlphttp.tempo.input] }
}
otelcol.exporter.otlphttp "tempo" {
  client { endpoint = "http://tempo.tracing.svc.cluster.local:4318" }
}
```



---

## 8. 组件对比

### 8.1 Alloy vs Promtail

| 维度 | Promtail | Grafana Alloy |
| --- | --- | --- |
| 官方状态 | ⚠️ 维护模式（不再开发新功能） | ✅ 主力产品 |
| 配置语言 | YAML | River（支持条件/循环，更强） |
| 内置指标采集 | ❌ | ✅ 含 node-exporter 等价物 |
| OTel 支持 | ❌ | ✅ 原生 |
| 配置热重载 | 需 SIGHUP | ✅ 内置 |
| 内存消耗 | ~60 MB | ~100 MB（含更多功能） |
| 迁移成本 | — | 中（River 语法需学习） |

### 8.2 Alloy vs OTel Collector

| 维度 | Grafana Alloy | OTel Collector |
| --- | --- | --- |
| CNCF 标准 | ❌（Grafana 主导） | ✅ CNCF Graduated |
| 日志采集能力 | ✅ 强（内置 Loki 集成） | ⚠️ 需 filelog receiver |
| node-exporter 替代 | ✅ 内置 unix exporter | ❌ 不支持 |
| 配置语言 | River（直观） | YAML（通用） |
| Grafana 生态集成 | ✅ 无缝 | ⚠️ 需额外配置 |
| 厂商中立性 | ❌ Grafana 绑定 | ✅ 完全中立 |
| SmartVision 场景推荐 | **✅ 首选** | 备选（跨平台场景） |

---

## 9. 常见问题

### Pod 日志采集不到

1. 检查 Alloy 是否正常运行：`kubectl get daemonset alloy -n logging`
2. 查看 Alloy 日志中是否有权限错误：`kubectl logs -n logging -l app.kubernetes.io/name=alloy --tail=100`
3. 确认 `discovery.kubernetes` 权限——Alloy DaemonSet 需要 ClusterRole 读取 Pods/Nodes

---

### 日志推送到 Loki 报 401 / 403

**原因：** Loki 开启了 `auth_enabled: true`，请求缺少或携带了错误的 `X-Scope-OrgID`。

**解决：** 确认 `loki.write.endpoint.headers` 中 `X-Scope-OrgID` 值为 `101`（本项目约定租户）。

---

### 修改 config.alloy 后不生效

River 热重载依赖 ConfigMap 变更事件。如果直接编辑 ConfigMap，需等待 Kubelet 同步（最长约 1 分钟），或执行：
```bash
kubectl rollout restart daemonset alloy -n logging
```

### Alloy 能取代 node-exporter 吗

**可以，但有前提条件。** Grafana Alloy 通过内置的 `prometheus.exporter.unix` 组件实现了与 node-exporter 等价的功能，无需单独部署 node-exporter Pod。

**方式一：`prometheus.exporter.unix`（Prometheus 原生，推荐）**

Alloy 内嵌了 node_exporter，直接通过配置组件采集系统指标，生成的指标名称与 node-exporter 完全兼容：

```alloy
prometheus.exporter.unix "node" {
  disable_collectors = ["ipvs", "btrfs", "infiniband", "xfs", "zfs"]
}

prometheus.scrape "node" {
  targets    = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.central.receiver]
}
```

**方式二：OTel `hostmetrics` receiver（OTel 原生方式）**

如果已使用 OpenTelemetry 管道，可用 `otelcol.receiver.hostmetrics` 采集 CPU、内存、磁盘、网络等指标，无需外部 exporter。

**部署要求：** Alloy 需以 DaemonSet（每节点一个实例）部署，并挂载宿主机 `/proc`、`/sys` 才能读取系统文件。

**注意事项：** 从 Grafana Agent 迁移到 Alloy 时，部分指标的 `integration` 标签可能发生变化，导致已有 Dashboard 或告警规则失效。迁移后建议在 Grafana Explore 中验证指标标签是否正确。

| 方式 | 组件 | 适用场景 |
| --- | --- | --- |
| Prometheus 原生 | `prometheus.exporter.unix` | 已有 Prometheus 体系（本项目推荐）|
| OTel 原生 | `otelcol.receiver.hostmetrics` | 纯 OTel 管道 |


### Alloy 能取代 kube-state-metrics 吗

**不能。** Alloy 和 kube-state-metrics 的职责完全不同，两者是互补关系。

- **kube-state-metrics**：监听 Kubernetes API Server 事件，将集群对象（Pod、Deployment、DaemonSet、Node 等）的状态转换为 Prometheus 指标（如 `kube_pod_status_phase`、`kube_node_status_condition`）。它是**指标生成器**。
- **Grafana Alloy**：负责采集（scrape）这些指标并转发到 Prometheus 等后端。它是**数据管道**，本身不生成集群状态指标。

**两者的协作关系：**

| 组件 | 类型 | 职责 |
| --- | --- | --- |
| kube-state-metrics | Deployment | 监听 K8s API，生成集群对象状态指标 |
| Grafana Alloy | DaemonSet | scrape kube-state-metrics，转发到 Prometheus |

**为什么不能替代？**

以下指标只能由 kube-state-metrics 通过监听 Kubernetes API 生成，Alloy 无法自行产生：

```
kube_pod_status_phase
kube_namespace_status_phase
kube_daemonset_*
kube_node_*
```

Alloy 是"搬运工"，kube-state-metrics 是"生产者"，两者缺一不可。

### Alloy 能取代哪些 Exporter

Alloy 内置了大量 `prometheus.exporter.*` 组件，凡是有内置对应的中间件，**无需单独部署 exporter Pod**，直接在 `config.alloy` 中声明即可。完整清单见 §7.10。

常见可取代的独立 Exporter：

| Alloy 内置组件 | 取代的独立 Exporter |
| --- | --- |
| `prometheus.exporter.unix` | node_exporter（Linux/Unix 主机指标）|
| `prometheus.exporter.windows` | windows_exporter（Windows 主机指标）|
| `prometheus.exporter.cadvisor` | cAdvisor（容器资源指标）|
| `prometheus.exporter.mysql` | mysqld_exporter |
| `prometheus.exporter.postgres` | postgres_exporter |
| `prometheus.exporter.redis` | redis_exporter |
| `prometheus.exporter.mongodb` | mongodb_exporter |
| `prometheus.exporter.mssql` | sql_exporter（MSSQL）|
| `prometheus.exporter.elasticsearch` | elasticsearch_exporter |
| `prometheus.exporter.kafka` | kafka_exporter |
| `prometheus.exporter.memcached` | memcached_exporter |
| `prometheus.exporter.blackbox` | blackbox_exporter |
| `prometheus.exporter.snmp` | snmp_exporter |
| `prometheus.exporter.statsd` | statsd_exporter |
| `prometheus.exporter.apache` | apache_exporter |
| `prometheus.exporter.consul` | consul_exporter |
| `prometheus.exporter.dnsmasq` | dnsmasq_exporter |
| `prometheus.exporter.github` | github_exporter |
| `prometheus.exporter.gcp` | stackdriver_exporter（GCP）|
| `prometheus.exporter.cloudwatch` | cloudwatch_exporter（AWS）|
| `prometheus.exporter.azure` | azure_metrics_exporter |
| `prometheus.exporter.oracledb` | oracledb_exporter |
| `prometheus.exporter.process` | process_exporter |
| `prometheus.exporter.snowflake` | snowflake_exporter |
| `prometheus.exporter.squid` | squid_exporter |
| `prometheus.exporter.databricks` | databricks_exporter |
| `prometheus.exporter.catchpoint` | catchpoint_exporter |
| `prometheus.exporter.self` | —（Alloy 自身指标）|
| `prometheus.exporter.static` | —（静态目标，自定义指标端点）|

**不能取代的情况：**
- **kube-state-metrics**：生成 K8s 对象状态指标，Alloy 无内置替代（见上一条 FAQ）
- **dcgm-exporter**：需要 NVIDIA CUDA 库支持，Alloy 无内置替代
- **rabbitmq_exporter**：无内置，需独立部署后用 `prometheus.scrape` 抓取

对于无内置的 exporter，用 `prometheus.scrape` 直接抓取其 `/metrics` 端点即可，无需修改 Alloy 本身。

---

### 内存占用过高

默认情况下 `prometheus.scrape` 的 `max_shards` 设置较大。可减小 `queue_config.max_shards` 值，或限制 `scrape_interval` 不低于 `15s`。

---

## 10. 参考文档

1. [Grafana Alloy 官方文档](https://grafana.com/docs/alloy/latest/)
2. [River 配置语言参考](https://grafana.com/docs/alloy/latest/reference/)
3. [从 Promtail 迁移到 Alloy](https://grafana.com/docs/alloy/latest/tasks/migrate/from-promtail/)
4. [loki.source.kubernetes 组件文档](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.kubernetes/)
5. [prometheus.exporter.unix 组件文档](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/)

---
