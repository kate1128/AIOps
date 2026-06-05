# Prometheus + Grafana 可观测数据全览

> 一份完整的 Prometheus + Grafana 可监控对象清单，涵盖基础设施、中间件、应用、AI/GPU 等全部维度。

---

## 一、基础设施层

### 1.1 服务器/节点（Node Exporter）

| 指标类别 | 关键指标 | PromQL 示例 |
|---|---|---|
| **CPU** | 使用率、各核利用率、系统/用户/空闲时间 | `100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| **内存** | 使用率、可用内存、缓存、缓冲 | `100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)` |
| **磁盘** | 使用率、读写速率、IOPS、inode 使用率 | `100 - (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100` |
| **网络** | 收发字节数、包数、丢包率、错误率 | `irate(node_network_receive_bytes_total[5m])` |
| **系统** | 负载（1/5/15min）、进程数、文件句柄 | `node_load1` / `node_load5` / `node_load15` |
| **温度/风扇** | 传感器温度、风扇转速 | `node_hwmon_temp_celsius` |
| **时间** | NTP 偏移、时钟同步状态 | `node_timex_offset_seconds` |

**Dashboard 模板**：
- ID: 1860  （Node Exporter Full）
- ID: 8919  （Node Exporter for Prometheus Dashboard）

---

### 1.2 K8s 集群（kube-prometheus-stack 自带）

| 监控对象 | Exporter | 关键指标 |
|---|---|---|
| **K8s API Server** | 内置 | `apiserver_request_duration_seconds`、`apiserver_request_total` |
| **etcd** | 内置 | `etcd_server_has_leader`、`etcd_disk_wal_fsync_duration_seconds` |
| **Controller Manager** | 内置 | 各种控制器指标 |
| **Scheduler** | 内置 | `scheduler_scheduling_duration_seconds` |
| **Kubelet** | 内置 | `kubelet_running_pods`、`kubelet_running_containers` |
| **节点状态** | kube-state-metrics | `node_status_condition`、`node_disk_pressure` |
| **Pod 状态** | kube-state-metrics | `kube_pod_status_phase`、`kube_pod_container_status_restarts_total` |
| **Deployment** | kube-state-metrics | `kube_deployment_status_replicas`、`kube_deployment_status_replicas_unavailable` |
| **Service** | kube-state-metrics | `kube_service_info`、`kube_service_created` |
| **PVC** | kube-state-metrics | `kube_persistentvolumeclaim_status_phase`、`kube_persistentvolumeclaim_access_mode` |
| **HPA** | kube-state-metrics | `kube_horizontalpodautoscaler_status_current_replicas` |
| **容器资源** | cAdvisor | `container_cpu_usage_seconds_total`、`container_memory_usage_bytes` |
| **容器网络** | cAdvisor | `container_network_receive_bytes_total` |
| **容器文件系统** | cAdvisor | `container_fs_usage_bytes`、`container_fs_limit_bytes` |

**Dashboard 模板**：
- ID: 6417  （Kubernetes cluster）
- ID: 315  （Kubernetes Node Exporter）
- ID: 747  （Kubernetes Pod Overview）

---

### 1.3 Docker 容器

| 监控对象 | Exporter | 关键指标 |
|---|---|---|
| **容器基础** | cAdvisor | `container_cpu_usage_seconds_total`、`container_memory_working_set_bytes` |
| **容器网络** | cAdvisor | `container_network_receive_bytes_total`、`container_network_transmit_bytes_total` |
| **Docker 守护进程** | Docker Daemon metrics | `engine_daemon_container_states_containers` |
| **容器事件** | Docker events | 容器创建/删除/重启事件 |

---

## 二、中间件层

### 2.1 数据库

#### PostgreSQL

| 指标类别 | 关键指标 | PromQL 示例 |
|---|---|---|
| **连接** | 活跃连接数、空闲连接数、最大连接数 | `pg_stat_activity_count` |
| **事务** | 提交数、回滚数、TPS | `pg_stat_database_xact_commit` |
| **查询** | 查询数、慢查询、缓存命中率 | `pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)` |
| **锁** | 等待锁的查询数、死锁数 | `pg_stat_database_deadlocks` |
| **复制** | 复制延迟、复制状态 | `pg_replication_lag` |
| **存储** | 数据库大小、表大小、索引大小 | `pg_database_size_bytes` |
| **WAL** | WAL 大小、归档状态 | `pg_stat_archiver_archived_count` |

**Exporter**：`postgres_exporter`
**Dashboard 模板**：ID: 9628

#### MySQL

| 指标类别 | 关键指标 |
|---|---|
| **连接** | Threads_connected、Threads_running、Max_connections |
| **查询** | Queries、Slow_queries、Questions |
| **InnoDB** | Innodb_buffer_pool_reads、Innodb_rows_read |
| **复制** | Slave_SQL_Running、Slave_IO_Running、Seconds_Behind_Master |
| **表** | Table_locks_waited、Table_locks_immediate |
| **缓存** | Qcache_hits、Qcache_inserts |

**Exporter**：`mysqld_exporter`
**Dashboard 模板**：ID: 7362

#### Redis

| 指标类别 | 关键指标 | PromQL 示例 |
|---|---|---|
| **连接** | 连接数、拒绝连接数 | `redis_connected_clients` |
| **内存** | 内存使用量、内存峰值、碎片率 | `redis_memory_used_bytes` |
| **命令** | 每秒命令数、各命令执行次数 | `redis_commands_processed_total` |
| **键** | 键总数、过期键数、键空间命中率 | `redis_keyspace_hits_total` |
| **持久化** | RDB 状态、AOF 状态 | `redis_rdb_last_save_status` |
| **复制** | 复制状态、复制延迟 | `redis_master_repl_offset` |
| **慢查询** | 慢查询数量 | `redis_slowlog_length` |

**Exporter**：`redis_exporter`
**Dashboard 模板**：ID: 763

#### MongoDB

| 指标类别 | 关键指标 |
|---|---|
| **连接** | Connections_current、Connections_available |
| **查询** | Opcounters_query、Opcounters_insert |
| **内存** | Mem_resident、Mem_virtual |
| **复制** | Replset_member_health、Replset_oplog_tail_timestamp |
| **存储** | StorageSize、IndexSize |
| **锁** | Locks_TimeLockedMicros_acquiringCount |

**Exporter**：`mongodb_exporter`
**Dashboard 模板**：ID: 2583

#### ClickHouse

| 指标类别 | 关键指标 |
|---|---|
| **查询** | ClickHouseProfileEvents_Query、ClickHouseProfileEvents_SelectQuery |
| **插入** | ClickHouseProfileEvents_InsertQuery |
| **合并** | ClickHouseProfileEvents_MergedTreeParts |
| **错误** | ClickHouseProfileEvents_Exception |
| **内存** | ClickHouseAsyncMetrics_MemoryTracking |

**Exporter**：内置 HTTP 接口（`/metrics`）

---

### 2.2 消息队列

#### Kafka

| 指标类别 | 关键指标 |
|---|---|
| **Broker** | kafka_server_broker_topics、kafka_server_replica_manager |
| **Topic** | 消息数、字节数、分区数 | kafka_topic_partition_current_offset |
| **消费者** | 消费延迟、消费者组 | kafka_consumer_group_members |
| **延迟** | ConsumerLag、RecordsLagMax |
| **请求** | RequestRate、ErrorRate |

**Exporter**：`kafka_exporter`
**Dashboard 模板**：ID: 7589

#### RabbitMQ

| 指标类别 | 关键指标 |
|---|---|
| **节点** | rabbitmq_nodes、rabbitmq_node_mem_used |
| **队列** | rabbitmq_queue_messages、rabbitmq_queue_messages_ready |
| **连接** | rabbitmq_connections |
| **通道** | rabbitmq_channels |
| **交换机** | rabbitmq_exchanges |

**Exporter**：`rabbitmq_exporter` 或 RabbitMQ 内置 `/metrics`
**Dashboard 模板**：ID: 10991

---

### 2.3 搜索引擎

#### Elasticsearch

| 指标类别 | 关键指标 |
|---|---|
| **集群** | elasticsearch_cluster_health_status、elasticsearch_cluster_health_number_of_nodes |
| **节点** | elasticsearch_jvm_memory_used_bytes、elasticsearch_process_cpu_percent |
| **索引** | elasticsearch_indices_docs_count、elasticsearch_indices_store_size_bytes |
| **查询** | elasticsearch_indices_search_query_time_seconds |
| **存储** | elasticsearch_filesystem_data_size_bytes |

**Exporter**：`elasticsearch_exporter`
**Dashboard 模板**：ID: 6483

---

### 2.4 网关/API

#### Nginx

| 指标类别 | 关键指标 |
|---|---|
| **请求** | nginx_http_requests_total、nginx_http_request_duration_seconds |
| **连接** | nginx_connections_active、nginx_connections_reading |
| **状态码** | nginx_http_requests_total{status="200"} |

**Exporter**：`nginx-prometheus-exporter`
**Dashboard 模板**：ID: 9614

#### APISIX

| 指标类别 | 关键指标 |
|---|---|
| **请求** | apisix_http_requests_total、apisix_http_latency_seconds |
| **连接** | apisix_nginx_http_current_connections |
| **路由** | apisix_http_status |
| **带宽** | apisix_bandwidth |

**Exporter**：内置 `/apisix/prometheus/metrics`

#### Kong

| 指标类别 | 关键指标 |
|---|---|
| **请求** | kong_http_requests_total、kong_latency_ms |
| **状态码** | kong_http_status |
| **带宽** | kong_bandwidth_bytes |

**Exporter**：内置 `/metrics`（需开启）

---

## 三、应用层

### 3.1 HTTP 服务（自定义指标）

| 指标类别 | 指标名称 | 类型 | 说明 |
|---|---|---|---|
| **请求数** | `http_requests_total` | Counter | 总请求数（按 method、status、endpoint 分类） |
| **延迟** | `http_request_duration_seconds` | Histogram | 请求处理时间（P50/P90/P99） |
| **错误率** | `http_requests_total{status=~"5.."}` | Counter | 5xx 错误数 |
| **并发** | `http_active_connections` | Gauge | 当前活跃连接数 |
| **响应大小** | `http_response_size_bytes` | Histogram | 响应体大小 |
| **请求大小** | `http_request_size_bytes` | Histogram | 请求体大小 |

**Python 示例**：
```python
from prometheus_client import Counter, Histogram, Gauge, start_http_server

request_count = Counter('http_requests_total', 'Total requests', ['method', 'status', 'endpoint'])
request_duration = Histogram('http_request_duration_seconds', 'Request duration', ['endpoint'])
active_connections = Gauge('http_active_connections', 'Active connections')

start_http_server(9090)
```

---

### 3.2 gRPC 服务

| 指标类别 | 指标名称 | 类型 |
|---|---|---|
| **请求数** | `grpc_server_started_total` | Counter |
| **请求延迟** | `grpc_server_handling_seconds` | Histogram |
| **消息** | `grpc_server_msg_received_total` / `grpc_server_msg_sent_total` | Counter |
| **错误** | `grpc_server_handled_total{grpc_code!="OK"}` | Counter |

**Exporter**：`grpc-prometheus` 客户端库

---

### 3.3 队列/任务

| 指标类别 | 指标名称 | 类型 |
|---|---|---|
| **队列深度** | `queue_messages_ready` | Gauge |
| **处理速率** | `queue_messages_processed_total` | Counter |
| **失败数** | `queue_messages_failed_total` | Counter |
| **处理时间** | `queue_task_duration_seconds` | Histogram |
| **重试次数** | `queue_task_retries_total` | Counter |

---

## 四、AI/GPU 层

### 4.1 NVIDIA GPU（DCGM Exporter）

| 指标类别 | 指标名称 | 说明 |
|---|---|---|
| **利用率** | `DCGM_FI_DEV_GPU_UTIL` | GPU 利用率 % |
| **显存** | `DCGM_FI_DEV_FB_USED` / `DCGM_FI_DEV_FB_FREE` | 显存使用/空闲 |
| **温度** | `DCGM_FI_DEV_GPU_TEMP` | GPU 温度 °C |
| **功耗** | `DCGM_FI_DEV_POWER_USAGE` | GPU 功耗 W |
| **时钟频率** | `DCGM_FI_DEV_SM_CLOCK` / `DCGM_FI_DEV_MEM_CLOCK` | SM/显存时钟频率 |
| **ECC 错误** | `DCGM_FI_DEV_ECC_SBE_VOLATILE_TOTAL` | 单比特纠错错误 |
| **XID 错误** | `DCGM_FI_DEV_XID_ERRORS` | XID 错误次数 |
| **PCIe** | `DCGM_FI_DEV_PCIE_TX_THROUGHPUT` | PCIe 吞吐量 |
| **进程** | `DCGM_FI_DEV_VGPU_PROCESS_PER_VGPU` | 进程数 |

**Dashboard 模板**：ID: 12239

---

### 4.2 AI 推理服务

| 指标类别 | 指标名称 | 类型 |
|---|---|---|
| **请求数** | `inference_requests_total` | Counter |
| **延迟** | `inference_latency_seconds` | Histogram |
| **Token 数** | `inference_tokens_total` | Counter |
| **队列深度** | `inference_queue_length` | Gauge |
| **模型加载** | `model_load_duration_seconds` | Histogram |
| **模型版本** | `model_version_info` | Gauge |

---

## 五、网络层

### 5.1 网络设备

| 监控对象 | Exporter | 关键指标 |
|---|---|---|
| **交换机** | SNMP Exporter | 端口状态、流量、错误包 |
| **路由器** | SNMP Exporter | 路由表、BGP 状态、接口流量 |
| **防火墙** | SNMP Exporter | 连接数、丢包率、规则命中 |

### 5.2 DNS

| 指标类别 | 关键指标 |
|---|---|
| **查询** | `dns_query_count`、`dns_query_duration_seconds` |
| **缓存** | `dns_cache_hits`、`dns_cache_misses` |
| **错误** | `dns_query_failures` |

### 5.3 证书

| 指标类别 | 关键指标 |
|---|---|
| **到期时间** | `ssl_certificate_expiry_seconds` |
| **证书状态** | `ssl_certificate_valid` |

---

## 六、业务层（自定义）

### 6.1 通用业务指标

| 指标类别 | 指标名称 | 类型 | 说明 |
|---|---|---|---|
| **活跃用户数** | `business_active_users` | Gauge | 当前在线用户数 |
| **注册用户数** | `business_registered_users_total` | Counter | 累计注册用户数 |
| **订单数** | `business_orders_total` | Counter | 累计订单数 |
| **订单金额** | `business_order_amount` | Counter | 累计订单金额 |
| **支付成功率** | `business_payment_success_rate` | Gauge | 支付成功率 |
| **API 调用** | `business_api_calls_total` | Counter | API 调用次数 |
| **错误数** | `business_errors_total` | Counter | 业务错误数 |

### 6.2 AI 业务指标

| 指标类别 | 指标名称 | 类型 |
|---|---|---|
| **Token 消耗** | `ai_tokens_consumed_total` | Counter |
| **推理延迟** | `ai_inference_latency_seconds` | Histogram |
| **模型版本** | `ai_model_version` | Gauge |
| **队列长度** | `ai_queue_length` | Gauge |
| **并发数** | `ai_concurrent_requests` | Gauge |
| **错误率** | `ai_error_rate` | Gauge |
| **成本** | `ai_cost_usd` | Counter |

---

## 七、日志（Loki + Promtail）

虽然 Loki 不是 Prometheus 指标，但可以与 Grafana 集成：

| 日志来源 | 采集方式 | 查询示例 |
|---|---|---|
| **K8s Pod 日志** | Promtail | `{namespace="prod", app="my-app"}` |
| **系统日志** | Promtail | `{job="syslog"}` |
| **应用日志** | Promtail | `{app="api", level="error"}` |
| **Nginx 日志** | Promtail | `{job="nginx"}` |
| **Docker 日志** | Docker Driver | `{container_name="my-app"}` |

---

## 八、链路追踪（Tempo + OpenTelemetry）

| 追踪维度 | 关键指标 |
|---|---|
| **请求链路** | 调用链、Span 耗时、错误分布 |
| **服务依赖** | 服务间调用关系图 |
| **延迟分布** | P50/P90/P99 链路延迟 |
| **错误追踪** | 错误链路、根因定位 |

---

## 九、汇总表

| 层级 | 监控对象 | Exporter | Dashboard ID |
|---|---|---|---|
| **基础设施** | Node | node_exporter | 1860, 8919 |
| | K8s 集群 | kube-prometheus-stack 自带 | 6417, 315 |
| | Docker | cAdvisor | 内置 |
| **中间件** | PostgreSQL | postgres_exporter | 9628 |
| | MySQL | mysqld_exporter | 7362 |
| | Redis | redis_exporter | 763 |
| | MongoDB | mongodb_exporter | 2583 |
| | Kafka | kafka_exporter | 7589 |
| | RabbitMQ | rabbitmq_exporter | 10991 |
| | Elasticsearch | elasticsearch_exporter | 6483 |
| | Nginx | nginx-prometheus-exporter | 9614 |
| | APISIX | 内置 | 自建 |
| **应用** | HTTP 服务 | 自定义 / Prometheus Client | 自建 |
| | gRPC 服务 | grpc-prometheus | 自建 |
| **AI/GPU** | NVIDIA GPU | dcgm-exporter | 12239 |
| | AI 推理 | 自定义 | 自建 |
| **网络** | 交换机/路由器 | snmp_exporter | 自建 |
| | DNS | 自定义 | 自建 |
| | 证书 | 自定义 | 自建 |
| **日志** | 所有日志 | Promtail + Loki | 内置 |
| **链路** | 调用链 | Tempo + OpenTelemetry | 内置 |

---

## 十、下一步建议

**Phase 1：基础设施（Week 1）**
- [ ] 部署 Prometheus + Grafana
- [ ] 接入 node_exporter（服务器监控）
- [ ] 接入 kube-prometheus-stack（K8s 监控）
- [ ] 接入 dcgm-exporter（GPU 监控）
- [ ] 导入 Dashboard 模板

**Phase 2：中间件（Week 2）**
- [ ] 接入 PostgreSQL Exporter
- [ ] 接入 Redis Exporter
- [ ] 接入 Kafka Exporter
- [ ] 接入 Nginx Exporter

**Phase 3：应用 + 业务（Week 3）**
- [ ] 在应用中埋点 Prometheus Client
- [ ] 暴露业务指标（活跃用户数、订单数等）
- [ ] 配置自定义 Dashboard

**Phase 4：日志 + 链路（Week 4）**
- [ ] 部署 Loki + Promtail
- [ ] 部署 Tempo + OpenTelemetry
- [ ] 配置日志告警

试完告诉我哪些指标最有价值，哪些需要调整。
