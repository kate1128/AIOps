# Vector — 高性能日志/指标管道

## 概述

Vector 是 DataDog 旗下开源的高性能可观测性数据管道，以 Rust 编写，专注于日志、指标、事件的采集、转换（Transform）和路由。以极低内存占用（~20 MB）和近乎零丢包率著称，并内置强大的 VRL（Vector Remap Language）用于日志清洗和脱敏。

- GitHub: [vectordotdev/vector](https://github.com/vectordotdev/vector) ⭐ ~18k
- CNCF 状态: 非 CNCF 项目（DataDog 主导）
- 适用场景: 需要复杂日志转换、脱敏处理，或日志量极大（> 1 TB/天）的场景

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **VRL 转换语言** | 内置专用日志转换/脱敏语言，支持复杂字段提取、JSON 改写、PII 脱敏 |
| **极低内存** | ~20 MB RSS，适合资源受限节点 |
| **零丢包** | 内置持久化缓冲区（磁盘），网络中断时不丢数据 |
| **多输入多输出** | 从文件/Kafka/Syslog 读取，同时写入 Loki + S3 + Elasticsearch |
| **背压机制** | 下游慢时自动限速，不会打爆下游 |
| **内置指标** | 暴露自身管道指标（处理速率、丢包数、缓冲区大小）|

---

## 与 Fluent Bit / Alloy / Filebeat 对比

| 维度 | Vector | Fluent Bit | Grafana Alloy | Filebeat |
|------|--------|-----------|--------------|---------|
| 开发语言 | **Rust** | C | Go | Go |
| 内存占用 | ~20 MB | **~15 MB** | ~100 MB | ~50 MB |
| 日志转换能力 | ✅ 极强（VRL）| ⚠️ 中等（Lua 脚本）| ⚠️ 中等 | ⚠️ 有限 |
| 指标采集 | ⚠️ 支持但弱 | ❌ | ✅ 强（内置 node-exporter）| ❌ |
| 链路追踪 | ❌ | ❌ | ✅ | ❌ |
| CNCF 标准 | ❌ | ✅ Graduated | ❌ | ❌ |
| 日志脱敏 | **✅ 原生** | ⚠️ 需 Lua | ⚠️ 有限 | ❌ |
| 持久化缓冲 | ✅ 磁盘级 | ⚠️ 内存 | ⚠️ 有限 | ✅ |
| **适用场景** | 复杂转换/脱敏/高吞吐 | 资源受限节点 | Grafana 全家桶 | ELK 生态 |

---

## 在本项目中的评估

### 推荐使用场景

- 日志中含有 **敏感数据**（用户 ID、API Key、手机号）需要脱敏后再发送 Loki
- 日志格式非常混乱（多种格式混合），需要复杂解析重组
- 日志量超大（> 100 GB/天），需要在采集侧进行聚合压缩

### 与方案一的关系

> 方案一选择 Grafana Alloy，原因是需要同时处理日志和指标（替代 node-exporter）。如果日志处理需求复杂，可以 **Alloy 做指标采集 + Vector 做日志处理管道** 混合部署。

```
K8s Pod 日志
    ↓
  Vector (DaemonSet)
    ├── 日志清洗、字段提取、PII 脱敏（VRL）
    └──→ Loki

主机系统指标
    ↓
  Alloy (DaemonSet)
    ├── prometheus.exporter.unix（替代 node-exporter）
    └──→ Prometheus
```

---

## 配置示例

### 基础配置（K8s 容器日志 → Loki）

```toml
# vector.toml

[sources.k8s_logs]
type = "kubernetes_logs"

[transforms.parse_json]
type   = "remap"
inputs = ["k8s_logs"]
source = '''
  . = merge(., parse_json!(.message)) ?? .
  # 脱敏：移除含 key/token 的字段
  del(.password, .api_key, .token)
  # 标准化 level 字段
  .level = downcase(get!(.level, ["level"]) ?? "info")
'''

[sinks.loki]
type    = "loki"
inputs  = ["parse_json"]
endpoint = "http://loki.observability.svc:3100"
encoding.codec = "json"

  [sinks.loki.labels]
  namespace = "{{ kubernetes.pod_namespace }}"
  pod       = "{{ kubernetes.pod_name }}"
  container = "{{ kubernetes.container_name }}"
  level     = "{{ level }}"
```

### PII 脱敏示例（VRL）

```coffeescript
# 脱敏规则：替换手机号和邮箱
.message = replace(.message, r'\d{11}', "***phone***")
.message = replace(.message, r'[\w.-]+@[\w.-]+\.\w+', "***email***")

# 删除敏感 JSON 字段
if exists(.user_token) { del(.user_token) }
if exists(.password)   { del(.password) }
```

### DaemonSet 部署

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: vector
  namespace: observability
spec:
  template:
    spec:
      containers:
        - name: vector
          image: timberio/vector:0.39.0-distroless-libc
          volumeMounts:
            - name: config
              mountPath: /etc/vector
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: varlibdocker
              mountPath: /var/lib/docker/containers
              readOnly: true
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
        - name: varlibdocker
          hostPath:
            path: /var/lib/docker/containers
```

---

## 不选原因（方案一场景下）

> **结论：方案一不选 Vector 作为主力采集器**，原因如下：
>
> 1. **无法替代 node-exporter**：Vector 的指标采集能力弱，无法采集主机系统指标
> 2. **无 OTel Traces 支持**：不能作为链路追踪采集端
> 3. **Grafana 生态集成弱**：不如 Alloy 与 Loki / Tempo 无缝联动
>
> 如果项目需要严格的日志脱敏合规，可以**在 Alloy 上游插入 Vector 作为日志处理层**。
