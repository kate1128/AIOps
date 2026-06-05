# Docker 可观测性

> Docker Daemon 内置 metrics 端点，配合 cAdvisor 实现容器级资源监控。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| Docker Daemon metrics | Daemon 内置 Prometheus 端点 | TCP 9323 /metrics |
| cAdvisor | 容器资源使用（CPU/内存/网络/磁盘）| TCP 8080 /metrics |
| Container logs | Docker json-file log driver → Promtail 采集 | 宿主机 /var/lib/docker/containers/\*/\*-json.log |

---

## 核心指标

### Docker Daemon

| 指标 | 含义 |
|------|------|
| `engine_daemon_container_states_containers` | 容器状态分布（running/paused/stopped）|
| `engine_daemon_events_total` | Docker 事件计数（start/destroy/restart）|
| `engine_daemon_engine_memory_bytes` | Docker Daemon 自身内存 |

### cAdvisor（容器级别）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `container_cpu_usage_seconds_total` | 容器 CPU 使用 | — |
| `container_memory_usage_bytes` | 容器内存使用 | > 90% limit 告警 |
| `container_network_receive_bytes_total` | 容器网络入流量 | — |
| `container_network_transmit_bytes_total` | 容器网络出流量 | — |
| `container_fs_usage_bytes` | 容器磁盘使用 | — |
| `container_restarts_total` | 容器重启次数 | > 3 次/10min 告警 |

---

## 采集集成

```yaml
# Docker Daemon 开启 metrics（daemon.json）
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}

# cAdvisor 容器化启动
docker run -d \
  --name=cadvisor \
  --restart=always \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker/:/var/lib/docker:ro \
  --publish=8080:8080 \
  gcr.io/cadvisor/cadvisor

# Prometheus scrape
- job_name: docker-daemon
  static_configs:
    - targets:
        - "docker-host:9323"
      labels:
        service: docker
        env: prod

- job_name: cadvisor
  static_configs:
    - targets:
        - "docker-host:8080"
      labels:
        service: cadvisor
        env: prod
```

---

## 告警规则

```yaml
- alert: ContainerRestarting
  expr: rate(container_restarts_total[10m]) > 0.3
  for: 5m
  annotations:
    summary: "容器 {{ $labels.name }} 频繁重启"

- alert: ContainerMemoryNearLimit
  expr: container_memory_usage_bytes{container_label_com_docker_compose_service!=""} / on(container_label_com_docker_compose_service) container_spec_memory_limit_bytes > 0.9
  for: 3m
  annotations:
    summary: "容器内存使用超过 90% limit"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| 二进制 + Docker 混合 | 宿主机起 cAdvisor 容器 + Daemon metrics，统一给 Prometheus |
| 纯 Docker 环境 | cAdvisor 和 node-exporter 覆盖全部 |
| Docker → K8s 迁移过渡 | cAdvisor 和 kubelet metrics 重复采集无妨，逐步移除 cAdvisor |

Docker Daemon 默认不开启 metrics，需显式配置并重启 dockerd。生产建议限制 metrics 端口访问来源。
