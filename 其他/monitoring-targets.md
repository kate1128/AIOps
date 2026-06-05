# 中间件 + 二进制服务 + GPU 监控接入方案

> 基于 Prometheus / Netdata / Zabbix 三个方案，分别覆盖中间件（Redis/Kafka/PostgreSQL）、二进制服务、GPU 资源的监控接入。

---

## 一、一句话结论

| 监控对象 | 能否监控 | 接入方式 | 难度 |
|---|---|---|---|
| **中间件（Redis/Kafka/PostgreSQL）** | 能 | Exporter 暴露指标 → Prometheus 抓取 / Zabbix Agent 采集 | 低 |
| **二进制服务** | 能 | Blackbox Exporter（无侵入）或 Prometheus Client（侵入式） | 中 |
| **GPU 资源** | 能 | DCGM Exporter（NVIDIA GPU）或 node-exporter + nvidia_smi | 低 |

---

## 二、中间件监控接入

### 2.1 Redis 监控

#### 方式 A：Prometheus + redis-exporter（推荐）

```bash
# 部署 redis-exporter
helm install redis-exporter prometheus-community/prometheus-redis-exporter \
  --namespace observability \
  --set redisAddress=redis://redis-master:6379 \
  --set serviceMonitor.enabled=true

# 验证
kubectl get pods -n observability -l app.kubernetes.io/name=prometheus-redis-exporter

# 关键指标
# redis_up                    -- Redis 是否在线
# redis_memory_used_bytes     -- 内存使用量
# redis_connected_clients     -- 连接数
# redis_keyspace_hits_total   -- 命中次数
# redis_keyspace_misses_total -- 未命中次数
# redis_expired_keys_total    -- 过期 key 数
```

#### 方式 B：Netdata 自动发现

```bash
# Netdata 自动发现 Redis（无需额外配置）
# 只要 Redis 运行在本地，Netdata 会自动采集：
# - redis.connections          -- 连接数
# - redis.memory               -- 内存使用
# - redis.operations           -- 操作数
# - redis.keys                 -- Key 数量
# - redis.net                  -- 网络流量

# 查看方式：Netdata UI → Applications → redis
```

#### 方式 C：Zabbix Agent + Template

```bash
# Zabbix Agent 配置 Redis 监控
# 1. 安装 Redis 监控模板（Zabbix Web UI → 配置 → 模板 → 导入）
# 2. 绑定模板到 Redis 主机
# 3. 配置 Redis 连接参数（IP、端口、密码）
# 4. 模板会自动监控：
#    - Redis 进程状态
#    - 内存使用量
#    - 连接数
#    - 命中率
#    - Key 数量
```

---

### 2.2 Kafka 监控

#### 方式 A：Prometheus + kafka-exporter

```bash
# 部署 kafka-exporter
helm install kafka-exporter prometheus-community/prometheus-kafka-exporter \
  --namespace observability \
  --set kafkaServer=kafka:9092 \
  --set serviceMonitor.enabled=true

# 关键指标
# kafka_brokers                         -- Broker 数量
# kafka_consumer_group_members          -- 消费者组成员
# kafka_consumer_lag                    -- 消费延迟
# kafka_topic_partition_current_offset  -- Topic 当前 offset
# kafka_topic_partition_leader        -- Leader 状态
```

#### 方式 B：Netdata 自动发现

```bash
# Netdata 自动发现 Kafka（本地运行）
# Netdata UI → Applications → kafka
# 自动监控：
# - kafka.requests              -- 请求数
# - kafka.messages              -- 消息数
# - kafka.kafka_log             -- 日志大小
# - kafka.kafka_server_broker_topics -- Topic 状态
```

---

### 2.3 PostgreSQL 监控

#### 方式 A：Prometheus + postgres-exporter

```bash
# 部署 postgres-exporter
helm install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --namespace observability \
  --set config.datasource=postgresql://postgres:password@postgres:5432/postgres?sslmode=disable \
  --set serviceMonitor.enabled=true

# 关键指标
# pg_up                       -- PostgreSQL 是否在线
# pg_stat_activity_count      -- 活跃连接数
# pg_stat_database_xact_commit   -- 事务提交数
# pg_stat_database_xact_rollback -- 事务回滚数
# pg_stat_database_blks_hit   -- 缓存命中
# pg_stat_database_blks_read  -- 磁盘读取
# pg_stat_activity_max_tx_duration -- 最长事务时间
```

#### 方式 B：Netdata 自动发现

```bash
# Netdata 自动发现 PostgreSQL（本地运行）
# Netdata UI → Applications → postgres
# 自动监控：
# - postgres.connections        -- 连接数
# - postgres.transactions       -- 事务数
# - postgres.rows_read          -- 读取行数
# - postgres.rows_written       -- 写入行数
# - postgres.database_size      -- 数据库大小
```

---

## 三、二进制服务监控接入

### 3.1 无侵入方式：Blackbox Exporter

**适用场景**：二进制服务已有 HTTP 接口，不想改代码。

```bash
# 部署 Blackbox Exporter
helm install blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  --namespace observability \
  --set config.modules.http_2xx.prober=http \
  --set config.modules.http_2xx.http.validStatusCodes=[200]

# 配置 Prometheus 抓取
# 在 ServiceMonitor 或 prometheus.yml 中添加：
- job_name: 'binary-services'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - http://binary-service-1:8080/health
      - http://binary-service-2:8080/health
      - http://binary-service-3:9090/ping

# 关键指标
# probe_success          -- 探测是否成功（1=成功，0=失败）
# probe_duration_seconds -- 探测耗时
# probe_http_status_code -- HTTP 状态码
# probe_ssl_earliest_cert_expiry -- SSL 证书过期时间
```

### 3.2 侵入式方式：Prometheus Client

**适用场景**：你想获取更详细的业务指标（请求数、延迟、错误率）。

**Python 示例：**

```python
from prometheus_client import start_http_server, Counter, Histogram, Gauge
import time
import random

# 创建指标
request_count = Counter('http_requests_total', 'Total requests', ['method', 'endpoint', 'status'])
request_duration = Histogram('http_request_duration_seconds', 'Request duration', ['endpoint'])
active_connections = Gauge('http_active_connections', 'Active connections')

# 启动 metrics 服务（暴露 /metrics 端点）
start_http_server(9090)

# 在请求处理中记录指标
@request_duration.time()
def handle_request():
    active_connections.inc()
    
    # 模拟业务处理
    time.sleep(random.uniform(0.1, 0.5))
    
    # 记录请求
    status = random.choice(['200', '500'])
    request_count.labels(method='GET', endpoint='/api', status=status).inc()
    
    active_connections.dec()
    return status

# 模拟服务运行
while True:
    handle_request()
    time.sleep(1)
```

**Go 示例：**

```go
package main

import (
    "net/http"
    "time"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    requestCount = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total requests",
        },
        []string{"method", "endpoint", "status"},
    )
    
    requestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "http_request_duration_seconds",
            Help: "Request duration",
        },
        []string{"endpoint"},
    )
)

func init() {
    prometheus.MustRegister(requestCount)
    prometheus.MustRegister(requestDuration)
}

func main() {
    http.Handle("/metrics", promhttp.Handler())
    
    http.HandleFunc("/api", func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        
        // 模拟业务处理
        time.Sleep(100 * time.Millisecond)
        
        requestCount.WithLabelValues("GET", "/api", "200").Inc()
        requestDuration.WithLabelValues("/api").Observe(time.Since(start).Seconds())
        
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("OK"))
    })
    
    http.ListenAndServe(":8080", nil)
}
```

### 3.3 进程级监控：node-exporter + process-exporter

**适用场景**：二进制服务没有 HTTP 接口，只能监控进程状态。

```bash
# 部署 process-exporter
helm install process-exporter prometheus-community/prometheus-process-exporter \
  --namespace observability \
  --set config.processes=[{name=\"my-binary-service\",cmdline=\"my-binary-service\"}]

# 关键指标
# namedprocess_namegroup_num_procs       -- 进程数量
# namedprocess_namegroup_cpu_seconds_total -- CPU 使用时间
# namedprocess_namegroup_memory_bytes    -- 内存使用
# namedprocess_namegroup_threads         -- 线程数
# namedprocess_namegroup_open_filedesc   -- 打开文件描述符数
```

---

## 四、GPU 资源监控接入

### 4.1 NVIDIA GPU 监控：DCGM Exporter

**适用场景**：NVIDIA GPU（ecs.gn7i 等实例）。

```bash
# 方式 A：Helm 部署（推荐）
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace observability \
  --set serviceMonitor.enabled=true

# 方式 B：Docker 部署
docker run -d --rm \
  --gpus all \
  --name dcgm-exporter \
  -p 9400:9400 \
  nvcr.io/nvidia/k8s/dcgm-exporter:latest

# 关键指标
# DCGM_FI_DEV_GPU_UTIL            -- GPU 利用率
# DCGM_FI_DEV_MEM_COPY_UTIL       -- 显存复制利用率
# DCGM_FI_DEV_GPU_TEMP            -- GPU 温度
# DCGM_FI_DEV_POWER_USAGE         -- GPU 功耗
# DCGM_FI_DEV_ECC_SBE_VOLATILE_TOTAL -- ECC 单比特错误
# DCGM_FI_DEV_ECC_DBE_VOLATILE_TOTAL -- ECC 双比特错误（致命）
# DCGM_FI_DEV_FB_FREE             -- 显存空闲
# DCGM_FI_DEV_FB_USED             -- 显存使用
```

### 4.2 非 NVIDIA GPU 监控

```bash
# AMD GPU
helm install amd-gpu-exporter prometheus-community/prometheus-amd-gpu-exporter \
  --namespace observability

# 通用 GPU（无 NVIDIA/AMD 驱动）
# 使用 node-exporter + nvidia-smi 脚本
# 或自定义脚本暴露指标
```

### 4.3 Netdata GPU 监控

```bash
# Netdata 自动发现 GPU（需安装 NVIDIA 驱动和 nvidia-smi）
# Netdata UI → Hardware → nvidia_smi
# 自动监控：
# - nvidia_smi.gpu_utilization     -- GPU 利用率
# - nvidia_smi.memory_utilization  -- 显存利用率
# - nvidia_smi.temperature         -- GPU 温度
# - nvidia_smi.power_draw          -- GPU 功耗
# - nvidia_smi.clocks_sm           -- GPU 时钟频率
# - nvidia_smi.ecc_errors          -- ECC 错误
```

### 4.4 Zabbix GPU 监控

```bash
# Zabbix Agent 配置 GPU 监控
# 1. 编写自定义监控脚本（nvidia-smi 解析）
# 2. 配置 UserParameter
# 3. 创建监控项和触发器

# 示例脚本（nvidia-smi 解析）
cat > /usr/local/bin/zabbix_gpu_monitor.sh <<'EOF'
#!/bin/bash
# 获取 GPU 利用率
nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits
EOF
chmod +x /usr/local/bin/zabbix_gpu_monitor.sh

# Zabbix Agent 配置
echo "UserParameter=gpu.utilization,/usr/local/bin/zabbix_gpu_monitor.sh" >> /etc/zabbix/zabbix_agent2.conf
systemctl restart zabbix-agent2
```

---

## 五、一键部署脚本（全部监控对象）

### Prometheus 完整监控栈（中间件 + 二进制 + GPU）

```bash
#!/bin/bash
# deploy-monitoring.sh
# 一键部署 Prometheus + 所有 Exporter

NAMESPACE="observability"

# 1. 创建命名空间
kubectl create namespace $NAMESPACE 2>/dev/null || true

# 2. 添加 Helm 仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# 3. 部署 kube-prometheus-stack（Prometheus + Alertmanager + Grafana）
echo "部署 kube-prometheus-stack..."
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --set grafana.enabled=true \
  --set grafana.adminPassword=admin123

# 4. 部署 redis-exporter
echo "部署 redis-exporter..."
helm install redis-exporter prometheus-community/prometheus-redis-exporter \
  --namespace $NAMESPACE \
  --set redisAddress=redis://redis-master:6379 \
  --set serviceMonitor.enabled=true

# 5. 部署 postgres-exporter
echo "部署 postgres-exporter..."
helm install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --namespace $NAMESPACE \
  --set config.datasource=postgresql://postgres:password@postgres:5432/postgres?sslmode=disable \
  --set serviceMonitor.enabled=true

# 6. 部署 kafka-exporter
echo "部署 kafka-exporter..."
helm install kafka-exporter prometheus-community/prometheus-kafka-exporter \
  --namespace $NAMESPACE \
  --set kafkaServer=kafka:9092 \
  --set serviceMonitor.enabled=true

# 7. 部署 blackbox-exporter（二进制服务探测）
echo "部署 blackbox-exporter..."
helm install blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  --namespace $NAMESPACE

# 8. 部署 dcgm-exporter（GPU 监控）
echo "部署 dcgm-exporter..."
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace $NAMESPACE \
  --set serviceMonitor.enabled=true

echo "部署完成！"
echo ""
echo "访问方式："
echo "  Grafana:    kubectl port-forward -n $NAMESPACE svc/kube-prometheus-grafana 3000:80"
echo "  Prometheus: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-prometheus 9090:9090"
echo "  Alertmanager: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-alertmanager 9093:9093"
```

---

## 六、监控对象覆盖清单

| 监控对象 | Prometheus | Netdata | Zabbix |
|---|---|---|---|
| **K8s 集群** | 原生支持（kube-state-metrics） | 自动发现 | 模板支持 |
| **容器/Pod** | 原生支持（cAdvisor） | 自动发现 | Agent 采集 |
| **节点/主机** | node-exporter | 自动发现 | Agent 采集 |
| **Redis** | redis-exporter | 自动发现 | 模板支持 |
| **Kafka** | kafka-exporter | 自动发现 | 模板支持 |
| **PostgreSQL** | postgres-exporter | 自动发现 | 模板支持 |
| **二进制服务（HTTP）** | Blackbox Exporter | 不支持 | 不支持 |
| **二进制服务（进程）** | process-exporter | 自动发现 | Agent 采集 |
| **NVIDIA GPU** | dcgm-exporter | 自动发现 | 自定义脚本 |

---

## 七、下一步建议

1. **先部署 Prometheus + 所有 Exporter**（一键脚本 5 分钟跑完）
2. **配置飞书告警**（Alertmanager Webhook）
3. **导入 Grafana Dashboard**（Redis/Kafka/PostgreSQL/GPU 都有现成模板）
4. **验证二进制服务监控**（Blackbox Exporter 探测 + 进程监控）

试完后告诉我：
- 哪些中间件监控正常？
- 二进制服务能不能看到？
- GPU 指标有没有数据？
