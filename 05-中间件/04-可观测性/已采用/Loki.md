# Loki - 日志采集

> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| 日志集中存储 |
| 部署方式 | 待确认 |
| 版本 | - |
| 接入范围 | Java 二进制、ai-backend 容器、scheduler 均未接入 |

---

## 日志接入现状

| 服务 | 部署 | 日志位置 | 接入 | 方式 |
|------|------|----------|------|------|
| java-service | 二进制 | 本地文件 | 无 | Promtail file_sd |
| ai-backend | Docker | 容器标准输出 | 无 | Promtail + docker driver |
| scheduler | K8s | 容器标准输出 | 无 | Promtail DaemonSet |
| Nginx | Docker | access.log | 无 | Promtail |

---

## Promtail 配置

```yaml
scrape_configs:
  # K8s Pod 日志
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    pipeline_stages:
      - cri: {}
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace

  # 二进制服务本地日?  - job_name: binary-services
    static_configs:
      - targets: [localhost]
        labels:
          job: java-service
          __path__: /var/log/smartvision/*.log
    pipeline_stages:
      - multiline:
          firstline: '^\d{4}-\d{2}-\d{2}'
```

---

## K8s 部署

```bash
helm upgrade --install loki grafana/loki-stack \
  --namespace observability \
  --set grafana.enabled=false \
  --set prometheus.enabled=false \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=50Gi
```

---

## 常用 LogQL

```logql
{app="ai-backend", namespace="prod"} |= "ERROR"
rate({namespace="prod"} |= "ERROR" [5m])
{app="nginx"} | json | request_time > 5
```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | Java 二进制日??Promtail file_sd 采集 |
| P0 | Docker 容器日志 ?采集 /var/lib/docker 或使?Loki Driver |
| P0 | K8s Pod 日志 ?Promtail DaemonSet 自动采集 |
| P1 | 日志 Retention 策略?-30 天）|
| P1 | 应用日志结构化（JSON 格式）|
