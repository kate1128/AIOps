
## Nodes Tab 主要能看到什么、能配置什么

根据 [官方 nodes-tab.md 文档](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/nodes-tab.md)，Nodes Tab 分为 **3 大块区域**（中央视图 / 行级操作 / 右侧边栏）。下面把"能看到什么"和"能配置什么"分开讲。

---

## 🖥️ 你能看到什么

### 1. 中央视图（每节点一行）

- 你的 Room 里**所有节点**（单机部署 = 1 个；Parent 架构 = 父 + 全部子节点）
- 节点名（点击 `(i)` 图标 → 右侧 Info 子 Tab 显示详细元数据）
- 你**自选**的 quick reference charts（默认通常显示 CPU / RAM / Disk / Network，但可改）

### 2. 行级菜单（每个节点 9 个操作）

| 操作 | 你能看到/得到什么 | 是否需要登录 |
|---|---|:---:|
| **View status** | 节点连接状态（live/stale/reachable）| 无需 |
| **Open the single node dashboard** | 进入该节点的单节点 Metrics 视图 | 无需 |
| **Access node details via the sidebar** | 右侧边栏显示该节点详细信息 | 无需 |
| **View active alerts** | 该节点当前告警列表 | 无需 |
| **Check Machine Learning status** | ML 是否在跑、训练进度 | 无需 |
| **Check Functions capability status** | Live/Logs Functions 是否可用 | 无需 |
| **View key collected attributes** | 节点关键元数据 | 无需 |
| **Add configuration (beta)** | 给该节点写配置（动态配置）| 需 Community+ |
| **Add alert silencing rules** | 静默该节点告警 | 需 Community+ |

### 3. 右侧边栏

| 子 Tab | 内容 |
|---|---|
| **Node hierarchy** | 按当前排序方式显示节点层级树，方便按名字定位 |
| **Filters** | 4 类过滤（见下方）|
| **Alerts** | 当前 Room 的所有告警 + 每条告警详情 |
| **Info** | 点击节点 `(i)` 后显示该节点的详细元数据 |

---

## ⚙️ 你能配置什么

### A. 顶部右上角的两项配置

| 配置项 | 可选值 | 说明 |
|---|---|---|
| **节点排序** | `status` 或 `alert status` | 决定节点列表顺序 |
| **Quick reference charts** | 从所有可用 Netdata charts 中多选 | 决定每行显示哪些"快速参考图表"（CPU、RAM、Load、Disk、Network 等可自由组合）|

### B. 右侧 Filters 子 Tab（4 类过滤）

| 过滤维度 | 用途 |
|---|---|
| **Host labels** | 按节点标签（如 `role=db`、`region=cn-east`）过滤 |
| **Node status** | 按节点连接状态过滤（live / stale / unreachable 等）|
| **Netdata version** | 按 Agent 版本号过滤（用于滚动升级、版本管理）|
| **Individual nodes** | 手动勾选/取消特定节点 |

### C. 对单个节点的操作

- **Add configuration (beta)**：动态给该节点下发配置（需 Community+）
- **Add alert silencing rules**：给该节点设置告警静默规则（需 Community+）

---

## ⚠️ 重要细节

### 配置是"Room 级共享"的

文档明确说：

> "All configurations on this page are **persistent and visible to all users in the Room**."

意思是：
- 你在 Nodes Tab 选定的 quick charts / 排序 / 过滤**对同一 Room 内所有用户生效**
- 这些配置**持久保存**（不会刷新就丢）
- 其他人登录进来会看到你配的视图（但他们自己改后也会被其他所有人看到）

### 登录要求汇总

| 操作 | Anonymous | Community | Paid |
|---|:---:|:---:|:---:|
| 查看节点列表/状态/告警/ML/Functions | ✅ | ✅ | ✅ |
| 单节点 dashboard | ✅ | ✅ | ✅ |
| 节点行级操作（查看类 7 项）| ✅ | ✅ | ✅ |
| Add configuration (beta) | ❌ | ✅ | ✅ |
| Add alert silencing rules | ❌ | ✅ | ✅ |

---

## 一句话总结

> **能看**：节点列表 + 状态 + 自选 quick charts + 节点元数据 + 节点告警 + Room 告警 + 节点层级。
> **能配**：排序方式（status/alert status）+ quick reference charts 选哪些 + 4 类过滤（labels/status/version/individual）+ 动态下配置（Community+）+ 静默规则（Community+）。所有配置 Room 级共享。

---

## 进一步阅读

- [Nodes Tab 官方文档](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/nodes-tab.md)
- [Netdata Access Control and Feature Availability](https://github.com/netdata/netdata/blob/master/docs/netdata-oss-limitations.md)
- [Node States and Transitions](https://github.com/netdata/netdata/blob/master/docs/netdata-cloud/node-states-and-transitions.md)
- [Alert Silencing Rules](https://github.com/netdata/netdata/blob/master/docs/alerts-and-notifications/notifications/centralized-cloud-notifications/manage-alert-notification-silencing-rules.md)


----------------
我先查一下官方对 Metrics tab 的定义。
The user is asking about the Metrics tab. Let me look it up. Actually, looking at the previous turns, I should check whether there is an official "Metrics tab" doc or if it's the same as "Netdata Charts" in the dashboard. Let me research.
## Metrics Tab 主要监控项与配置

根据 [metrics-tab-and-single-node-tabs.md](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/metrics-tab-and-single-node-tabs.md) 和 [netdata-charts.md](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/netdata-charts.md) 官方文档，Metrics Tab **没有一个固定的"监控项清单"**——它的内容是动态的，由你的 Agent 上跑了哪些 collectors 决定。

下面分两部分讲：**官方明确提到的结构**，以及 **实际部署中你大概率会看到的几大类**。

---

## 一、官方明确说明的 Metrics Tab 结构

### 1. 这个 tab 是什么

> "The **Metrics tab** provides real-time, per-second time series charts for all nodes in a Room."
> "You can also view **single-node dashboards**, which offer the same charts but are focused on a single node."

- 多节点视图：显示**整个 Room** 所有节点的指标
- 单节点视图：只显示一个节点（点击节点名进入）
- 内容是**每秒钟刷新**的实时时间序列图

### 2. 指标是怎么组织的

> "The dashboard displays various charts organized by their **context**. At the beginning of each section, there is a predefined arrangement of charts that provides an overview for that particular group of metrics."

- 指标按 **context（上下文）** 分组
- 每个 section 开头有**预定义的图表排列**作为该组指标的概览
- Context 命名规则：`类型.细分`，例如 `system.cpu`、`mem.available`、`disk.io`

### 3. 你能看到的核心图表元素

每个 Netdata chart 包含：

| 元素 | 说明 |
|---|---|
| **Title bar** | 图表标题、状态图标、6 个快速操作（管理告警、图表信息、图表类型、全屏、用户设置、拖拽到 Dashboard）|
| **Anomaly Rate ribbon** | 顶部 ML 异常率条带（机器学习实时检测）|
| **Definition bar** | NIDL 过滤选项（Node / Instance / Dimension / Label）|
| **Chart area** | 图表主体 |
| **Dimensions legend** | 各维度图例 |

### 4. 右侧 Chart Navigation Menu（固定存在的功能区）

| 功能 | 作用 |
|---|---|
| **Section Navigation** | 快速跳转到各 section |
| **Chart Filtering Options** | 4 类过滤：Host labels / Node status / Netdata version / Individual nodes |
| **Active Alerts Display** | 当前 Room 活跃告警 |
| **AR% Button** | 每节最大异常率（点一下能马上看出哪里有问题）|

### 5. Metrics Tab 还能跳到的地方

- **Integrations tab**（看接入的 collectors）
- **Metric Correlations**（高亮一段曲线，自动找行为相似的其他指标）
- **Single Node Tabs**（点节点名 → 单节点 dashboard）

---

## 二、实际部署中你大概率会看到的"主要监控大类"

> ⚠️ 以下**不是官方硬编码的固定列表**，而是从 Netdata 的 collector 架构（[product description](https://github.com/netdata/netdata)、[collectors list](https://github.com/netdata/netdata/blob/master/src/collectors/README.md)）能合理推断出的标准分组。是否显示取决于你的环境和启用的 collectors。

### 通用系统类（proc.plugin / apps.plugin / cgroups.plugin，几乎永远在）

| Section | 典型 contexts | 监控什么 |
|---|---|---|
| **System Overview** | `system.cpu`、`system.load`、`system.uptime`、`system.idlejitter` | CPU 整体使用率、负载、运行时长 |
| **CPU** | `cpu.cpu0...cpuN`（按核）、`system.cpu` | 每颗核心的使用率、用户态/内核态/iowait/irq/softirq 拆分 |
| **Memory** | `mem.available`、`mem.free`、`mem.cached`、`mem.committed`、`swap.io` | RAM、缓存、可用内存、swap 流量 |
| **Disks** | `disk.io`、`disk.ops`、`disk.backlog`、`disk.util`、`disk.await`、`disk.space` | 每块盘的 IOPS、吞吐量、等待时间、利用率、剩余空间 |
| **Network** | `net.net`、`net.packets`、`net.drops`、`net.errors`、`net.sockets` | 每张网卡的吞吐、包量、丢包、TCP/UDP 连接状态 |
| **Apps / Processes** | `apps.cpu`、`apps.mem`、`apps.io`、`apps.net` | 按进程/服务/容器分组的资源使用（apps.plugin 自动归类）|
| **Containers / cgroups** | `cgroup.cpu`、`cgroup.mem`、`cgroup.io`、`cgroup.throttle` | Docker、Podman、LXC、K8s pod、systemd service 资源 |
| **Filesystems** | `disk_space._filesystem_path` | 每个挂载点使用率 |

### 硬件类（启用相关 collector 后出现）

| Section | 来源 | 监控什么 |
|---|---|---|
| **IPMI Sensors** | `freeipmi.plugin` | 温度、电压、风扇、电源、PSU 状态 |
| **lm-sensors** | `sensors` | CPU/主板温度与电压 |
| **NVMe / SMART** | `smartctl`、`nvme` | 磁盘健康度、温度、SMART 属性 |
| **RAID** | `megacli`、`hpssa`、`adaptecraid`、`storcli`、`scaleio` | RAID 控制器、电池、磁盘 |
| **Network interfaces detail** | `ethtool` | 网卡驱动级统计、CRC 错误、协商速度 |
| **Power / Thermal** | IPMI + sensors | 服务器整机功耗与温度趋势 |

### 操作系统内核类

| Section | 监控什么 |
|---|---|
| **Interrupts / Contexts** | 中断与上下文切换 |
| **Softnet / Soft IRQs** | 网络软中断分布 |
| **Kernel same-page merging (KSMD)** | 内核内存合并 |
| **Entropy** | `/dev/urandom` 熵池 |
| **slabinfo** | 内核 slab 分配器 |
| **Numa** | `numa.nodes`、`numa.cpu`（跨 NUMA 内存访问）|
| **tc / QoS** | Linux 流量控制队列 |
| **perf** | 内核软硬件性能计数器 |
| **idletjitter** | CPU 空闲抖动（CPU 隔离配置诊断）|
| **timex** | 系统时钟同步状态 |

### 应用/服务类（启用对应 collector 后才会出现）

下面是**几个常用**的，实际还支持 800+ 集成（[集成列表](https://github.com/netdata/netdata/blob/master/src/collectors/README.md)）：

| 类别 | 典型 collectors | 监控什么 |
|---|---|---|
| **Web 服务器** | `nginx`、`apache`、`lighttpd`、`traefik`、`haproxy` | 请求数、连接、状态码、延迟 |
| **数据库** | `mysql`、`mariadb`、`postgres`、`mssql`、`mongodb`、`redis`、`clickhouse`、`oracle`、`cockroachdb`、`yugabytedb` | QPS、慢查询、连接池、复制延迟、锁、Top Queries（部分支持）|
| **缓存 / 队列** | `memcached`、`rabbitmq`、`kafka`、`nats`、`beanstalk`、`pulsar` | hit rate、内存、消费者滞后 |
| **容器编排** | `k8s_kubelet`、`k8s_state`、`k8s_apiserver`、`k8s_kubeproxy`、`coredns` | Pod 状态、节点压力、API Server QPS |
| **日志/搜索** | `elasticsearch`、`logstash`、`fluentd` | 索引速率、shard 状态、JVM |
| **消息/邮件** | `postfix`、`dovecot`、`exim` | 队列、信封处理速率 |
| **DNS** | `bind`、`dnsdist`、`dnsmasq`、`powerdns`、`unbound`、`coredns` | 查询、缓存命中率、zone 传输 |
| **监控本身** | `prometheus`（抓取外部 Prom exporter）、`snmp` | 拉取第三方 Prom 指标、SNMP 设备 |
| **证书/网站** | `x509check`、`httpcheck`、`portcheck`、`ping`、`whoisquery` | 证书过期、HTTP 可用性、端口、延迟 |
| **Windows 特有** | `windows.plugin` | AD、IIS、Hyper-V、Exchange、SQL Server、Print Server 等 |
| **虚拟化** | `proxmox`、`vmware/vsphere`、KVM/LXC | 宿主机/虚机资源 |

### 第三方桥接（无法直接 collector 的）

| 方式 | 走什么 collector |
|---|---|
| **Prometheus 兼容 Exporter** | `go.d/prometheus` 抓取 |
| **OpenTelemetry 指标/日志** | `otelcol.plugin` → `otel-plugin` |
| **StatsD** | `statsd` 接收 UDP |
| **Nagios 插件** | `scripts.d.plugin` 调度 |
| **任何 HTTP/JSON API** | `go.d/httpcheck` / 自定义 |
| **SNMP 设备** | `go.d/snmp`（vnode 形式）|

---

## 三、Metrics Tab 能配置什么

| 配置项 | 用途 | 作用域 |
|---|---|---|
| **Section 顺序** | 调整各 section 出现顺序 | 仪表板保存后对所有用户可见 |
| **单 chart 的过滤**（Definition bar）| 选节点、实例、维度、标签 | 临时或保存到 Personal/Room/Space |
| **单 chart 的图表类型** | line / stacked / area / bar / multi-bar | 同上 |
| **维度排序** | 按名称、值、异常率排序 | 同上 |
| **维度显示/隐藏** | 隔离特定维度 | 同上 |
| **图表高度** | 拖拽调整 | 同上 |
| **节点过滤**（右侧菜单）| 按 host labels / node status / version / individual 过滤 | 跨整个 tab |
| **AR% 开关** | 顶部异常率条带 | 跨整个 tab |
| **图表用户设置** | 持久保存个人偏好 | 三级优先级：**Personal > Room > Space** |
| **时间范围 / 播放控制** | Pan / Highlight / Zoom / Pause | 临时 |
| **拖拽到 Dashboard** | 把任意图表加到 Custom Dashboards | 跨 tab |

---

## 四、一句话总结

> Metrics Tab **不是固定监控项清单**，而是一个**按 context 自动组织的实时图表集合**。你实际看到的 section 数量和内容由你机器上装了哪些 collectors 决定——单机 Linux 系统大致会看到 10+ 个 section（CPU/Memory/Disk/Network/Apps/cgroups/IPMI/Sensors/Net 等），每加一个 collector（如 MySQL、Redis、SNMP）就会多一个对应的 section。

---

## 进一步阅读

- [Metrics Tab and Single Node Tabs 官方文档](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/metrics-tab-and-single-node-tabs.md)
- [Netdata Charts 完整文档（每张图的解剖）](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/netdata-charts.md)
- [NIDL Framework 解释](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/nidl.md)
- [Collectors 总目录（800+ 集成）](https://github.com/netdata/netdata/blob/master/src/collectors/README.md)
- [Netdata Charts 简介（学习中心）](https://learn.netdata.cloud/docs/dashboards-and-charts/charts)
- [Single Node vs Multi-node 视图](https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/README.md)

