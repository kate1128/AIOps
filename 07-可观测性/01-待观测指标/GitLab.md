# GitLab 可观测性调研

**更新日期：** 2026年06月09日
**信息来源：** 官方文档、GitHub 仓库、Grafana Alloy 官方回答、社区实践
**参考地址：**

1. GitLab Monitoring：[GitLab Prometheus](https://docs.gitlab.com/administration/monitoring/prometheus/)
2. GitLab metrics：[GitLab application metrics](https://docs.gitlab.com/administration/monitoring/prometheus/gitlab_metrics/)
3. GitLab Runner metrics：[Runner monitoring](https://docs.gitlab.com/runner/monitoring/)
4. Alloy 抓取配置：[prometheus.scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)

---

## 1. 结论摘要

GitLab 由 Rails、Sidekiq、Gitaly、Workhorse、Runner、PostgreSQL、Redis 等组件组成。GitLab EE 15.3.3+ 可通过 Grafana Cloud 官方 GitLab 集成使用 Alloy 采集指标和日志；自建 Prometheus/Alloy 场景下，核心方式是抓取 GitLab `/-/metrics`、Gitaly `:9236/metrics`、Runner `:9252/metrics`，并采集 GitLab 日志。

| 关键信息 | 值 |
| --- | --- |
| 应用指标 | GitLab Rails / Sidekiq `/-/metrics` |
| Gitaly 指标 | TCP `9236` `/metrics` |
| Runner 指标 | TCP `9252` `/metrics` |
| Alloy 集成 | `prometheus.scrape` + `loki.source.file` |
| 官方 Grafana Cloud 限制 | GitLab EE 15.3.3+ |

---

## 2. 产品概况

| 组件 | 指标内容 | 暴露方式 |
| --- | --- | --- |
| Rails / Workhorse | HTTP 请求、DB、Redis、错误 | `/-/metrics` |
| Sidekiq | 后台任务、队列延迟、失败数 | `/-/metrics` |
| Gitaly | Git clone/push/fetch 操作 | `:9236/metrics` |
| GitLab Runner | CI 作业、排队、失败率 | `:9252/metrics` |
| PostgreSQL / Redis | GitLab 依赖中间件 | 对应 exporter / Alloy 集成 |

---

## 3. 核心指标

| 指标 | 含义 | 告警建议 |
| --- | --- | --- |
| `http_requests_total` | HTTP 请求总数 | 错误率分母 |
| `http_request_duration_seconds_bucket` | HTTP 延迟分布 | P99 > 2s 告警 |
| `rails_db_main_pool_connections` | DB 连接池使用 | > 80% 告警 |
| `sidekiq_queue_latency` | Sidekiq 队列延迟 | > 60s 告警 |
| `sidekiq_queue_size` | Sidekiq 队列积压 | > 1000 关注 |
| `sidekiq_jobs_failed_total` | 后台任务失败 | 增长告警 |
| `gitaly_command_duration_seconds` | Git 命令耗时 | P99 > 5s 告警 |
| `ci_runner_jobs_failed_total` | Runner 作业失败 | 失败率 > 5% 告警 |
| `ci_runner_jobs_queued_duration_seconds` | CI 排队耗时 | > 300s 说明 Runner 不足 |

---

## 4. 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
| --- | --- | --- | --- | --- |
| GitLab 内置 metrics | 内置端点 | Rails / Sidekiq / Workhorse | 无 | 标准方案 |
| Gitaly metrics | 内置端点 | Git 操作 | 无 | Gitaly 专项 |
| Runner metrics | Runner 内置 | CI 作业 | 无 | Runner 专项 |
| **Grafana Alloy** | `prometheus.scrape` | 多端点统一采集 | `loki.source.file` | **本项目首选** |
| Netdata | Agent | 主机/应用部分指标 | 内置 | 快速验证 |

---

## 5. Alloy 集成方案（推荐）

### 5.1 GitLab 应用指标

```alloy
discovery.relabel "gitlab" {
  targets = [{ __address__ = "gitlab.devops.svc.cluster.local:80" }]
  rule { target_label = "instance" replacement = "gitlab-main" }
}

prometheus.scrape "gitlab" {
  targets      = discovery.relabel.gitlab.output
  metrics_path = "/-/metrics"
  job_name     = "integrations/gitlab"
  forward_to   = [prometheus.remote_write.central.receiver]
}
```

### 5.2 Gitaly 与 Runner

```alloy
prometheus.scrape "gitlab_gitaly" {
  targets = [{ __address__ = "gitlab-gitaly.gitlab.svc:9236", component = "gitaly" }]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.scrape "gitlab_runner" {
  targets = [{ __address__ = "gitlab-runner.gitlab.svc:9252", component = "runner" }]
  forward_to = [prometheus.remote_write.central.receiver]
}
```

### 5.3 Linux 日志采集

```alloy
local.file_match "gitlab_logs" {
  path_targets = [{ __path__ = "/var/log/gitlab/gitlab-rails/exceptions_json.log", job = "integrations/gitlab" }]
}

loki.source.file "gitlab_logs" {
  targets = local.file_match.gitlab_logs.targets
  forward_to = [loki.write.default.receiver]
}
```

### 5.4 Kubernetes 自动发现

```alloy
discovery.kubernetes "gitlab" {
  role = "pod"
  selectors { role = "pod" label = "app=gitlab" }
}

prometheus.scrape "gitlab_k8s" {
  targets = discovery.kubernetes.gitlab.targets
  metrics_path = "/-/metrics"
  forward_to = [prometheus.remote_write.central.receiver]
}
```

---

## 6. GitLab 配置要点

```ruby
# /etc/gitlab/gitlab.rb
gitlab_rails['prometheus_enable'] = true
gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '10.0.0.0/8']
sidekiq['metrics_enabled'] = true
gitaly['prometheus_listen_addr'] = '0.0.0.0:9236'
```

```bash
sudo gitlab-ctl reconfigure
sudo gitlab-ctl restart
```

---

## 7. 告警规则

```yaml
groups:
- name: gitlab.rules
  rules:
  - alert: GitLabRailsLatencyHigh
    expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "GitLab Rails P99 延迟超过 2s" }

  - alert: GitLabSidekiqQueueLatencyHigh
    expr: sidekiq_queue_latency > 60
    for: 5m
    labels: { severity: warning }
    annotations: { summary: "GitLab Sidekiq 队列延迟过高" }

  - alert: GitLabRunnerQueueHigh
    expr: ci_runner_jobs_queued_duration_seconds > 300
    for: 10m
    labels: { severity: warning }
    annotations: { summary: "GitLab CI 作业排队超过 300s" }
```

---

## 8. Grafana Dashboard

Grafana Cloud GitLab 集成提供 1 个预置 Dashboard 和 4 个预置告警规则，可在 Connections → GitLab 中安装。自建场景建议按 Rails、Sidekiq、Gitaly、Runner 四类拆分 Dashboard。

---

## 9. KAgent 集成（GitLab 运维 Agent）

推荐绑定 PrometheusServer 查询 GitLab 指标，并用 Skills 注入 CI 排队、Sidekiq 积压、Gitaly 慢操作排查 SOP。

---

## 10. 常见问题

### Grafana Alloy 能采集 GitLab 指标吗？

**可以。** Grafana Cloud 提供 GitLab 集成，使用 Alloy 采集 GitLab EE 实例指标和日志。自建环境可用 `prometheus.scrape` 抓取 `/-/metrics`、Gitaly 和 Runner 端点。

### 为什么需要配置 monitoring_whitelist？

GitLab metrics 默认只允许白名单 IP 访问。Alloy 所在节点或集群网段必须加入 `gitlab_rails['monitoring_whitelist']`，否则 scrape 会被拒绝。

### GitLab CE 能用吗？

自建 Prometheus scrape 可采集 CE 暴露的指标；但 Grafana Cloud 官方 GitLab 集成说明仅支持 GitLab EE 15.3.3+，需以实际版本验证。
