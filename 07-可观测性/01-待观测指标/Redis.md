# Redis 可观测性

> 通过 redis_exporter 采集 Redis 缓存运行时指标。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| redis_exporter | Redis 指标采集器，直连 Redis 实例读取 INFO/STATS | TCP 9121 /metrics |

支持单机、Sentinel、Cluster 三种模式，启动时指定 `--redis.addr` 即可。

---

## 核心指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `redis_memory_used_bytes` | 已用内存 | > 80% maxmemory 告警 |
| `redis_memory_max_bytes` | 配置的最大内存 | — |
| `redis_keyspace_hits_total` / `redis_keyspace_misses_total` | 缓存命中率 | < 90% 需排查 |
| `redis_connected_clients` | 当前连接数 | > 2000 关注 |
| `redis_replication_lag` | 主从复制延迟 | > 1s 告警 |
| `redis_uptime_in_seconds` | 运行时间 | < 60s 说明重启了 |
| `redis_db_keys` | 各 DB 的 Key 数量 | 单 DB > 1000 万需规划 |
| `redis_slowlog_length` | 慢查询队列长度 | > 0 持续增长需排查 |

---

## 采集集成

```yaml
# Prometheus static_configs（二进制/Docker）
- job_name: redis
  static_configs:
    - targets:
        - "redis-host:9121"
      labels:
        service: redis
        env: prod

# K8s ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis
  namespace: observability
spec:
  selector:
    matchLabels:
      app: redis-exporter
  endpoints:
    - port: metrics
      interval: 15s
```

---

## 告警规则

```yaml
- alert: RedisMemoryHigh
  expr: redis_memory_used_bytes / redis_memory_max_bytes * 100 > 80
  for: 5m
  annotations:
    summary: "Redis 内存使用率 {{ $value | humanizePercentage }}"

- alert: RedisCacheHitRateLow
  expr: rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100 < 90
  for: 10m
  annotations:
    summary: "Redis 缓存命中率低于 90%"

- alert: RedisReplicationLag
  expr: redis_replication_lag > 1
  for: 2m
  annotations:
    summary: "Redis 主从延迟 {{ $value }}s"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 Redis | 宿主机起 redis_exporter，`--redis.addr=localhost:6379` |
| Docker Redis | redis_exporter 容器化，同 network 或 `--redis.addr=host.docker.internal:6379` |
| K8s Redis | ServiceMonitor 自动发现 |
| Sentinel/Cluster | redis_exporter 支持 `--redis.addr=sentinel://...` 自动发现主从 |

Cluster 模式建议每个节点分别部署 exporter，或使用一个 exporter 带 `--check-keys` 参数扫描全部节点。
