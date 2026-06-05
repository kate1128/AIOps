# Redis - 缓存

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 缓存、会话存储、分布式锁 |
| 部署方式 | 待确认 |
| 版本 | - |
| 高可用| 待确认 |

---

## 部署模式选型

| 模式 | 高可用| 扩展 | 场景 |
|------|--------|------|------|
| 单机 | 否 | 否 | 开发测试 |
| Sentinel | 是 自动主从切换 | 是 | 生产中小规模 |
| Cluster | 是 | 是 分片 | 大数据量 |
| Redis Operator | 是 | 是 | K8s 生产 |

---

## K8s 部署（Redis Operator）
```bash
helm repo add redis-operator https://spotahome.github.io/redis-operator
helm install redis-operator redis-operator/redis-operator \
  --namespace redis --create-namespace

# 创建 Redis 高可用集群
kubectl apply -f - <<EOF
apiVersion: databases.spotahome.com/v1
kind: RedisFailover
metadata:
  name: redis-ha
  namespace: redis
spec:
  sentinel:
    replicas: 3
    resources:
      requests:
        cpu: 100m
        memory: 100Mi
  redis:
    replicas: 3
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
    storage:
      persistentVolumeClaim:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 10Gi
EOF
```

---

## 关键配置

```conf
maxmemory 4gb
maxmemory-policy allkeys-lru      # 缓存场景 LRU 淘汰
save ""                            # 纯缓存关闭 RDB
appendonly yes                     # 需要持久化时开启
appendfsync everysec               # 每秒刷盘
slowlog-log-slower-than 10000      # 慢命令阈值 10ms
```

---

## 监控

```promql
# 内存使用率
redis_memory_used_bytes / redis_memory_max_bytes * 100

# 缓存命中率（低于 90% 需排查）
rate(redis_keyspace_hits_total[5m]) /
(rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100

# 连接数
redis_connected_clients

# 主从复制延迟 > 1s 告警
redis_replication_lag
```

---

## 常见运维

```bash
redis-cli INFO memory              # 内存详情
redis-cli --bigkeys                # 查找大Key
redis-cli SLOWLOG GET 10           # 慢日志
redis-cli BGREWRITEAOF             # 触发 AOF 重写
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | 确认高可用方案（Sentinel / Cluster / Operator）|
| P0 | 配置 maxmemory-policy 防止 OOM |
| P1 | 缓存命中率监控告警 |
| P1 | 大Key 定期扫描治理 |
| P2 | AOF 重写策略调优 |

> 参考：`工具分析/04-Redis.md`
