# GitLab 可观测性

> GitLab 多组件暴露 Prometheus 指标，覆盖 Rails、Sidekiq、Gitaly 和 CI Runner。

---

## 可观测性组件

| 组件 | 说明 | 暴露方式 |
|------|------|---------|
| GitLab Rails | Web 请求指标、数据库查询、Redis 调用 | /-/metrics |
| Sidekiq | 后台任务队列、任务执行时长 | /-/metrics |
| Gitaly | Git 操作指标（clone/push/fetch）| TCP 9236 /metrics |
| Workhorse | 反向代理指标 | /-/metrics |
| GitLab Runner | CI 作业执行指标 | TCP 9252 /metrics |
| PostgreSQL | GitLab 底层数据库 | 由 PostgreSQL exporter 覆盖 |
| Redis | GitLab 缓存 | 由 Redis exporter 覆盖 |

---

## 核心指标

### Rails（应用层）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `http_requests_total` | HTTP 请求总数 | — |
| `http_request_duration_seconds_bucket` | 请求延迟分布 | P99 > 2s 告警 |
| `rails_db_main_pool_connections` | 数据库连接池使用 | > 80% 告警 |
| `ruby_gc_duration_seconds` | GC 耗时 | 突增说明内存压力 |
| `sidekiq_jobs_failed_total` | 任务失败数 | > 0 告警 |
| `sidekiq_queue_latency` | 队列等待延迟 | > 60s 告警 |
| `sidekiq_queue_size` | 队列积压 | > 1000 关注 |

### Gitaly（Git 操作）

| 指标 | 含义 |
|------|------|
| `gitaly_commands_total` | Git 命令执行次数 |
| `gitaly_command_duration_seconds` | Git 命令执行时长 |
| `gitaly_connections_total` | 连接数 |

### Runner（CI）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `ci_runner_jobs_total` | 已执行作业数 | — |
| `ci_runner_jobs_duration_seconds` | 作业执行时长 | — |
| `ci_runner_jobs_failed_total` | 作业失败数 | 失败率 > 5% 告警 |
| `ci_runner_jobs_queued_duration_seconds` | 作业排队时长 | > 300s 说明 Runner 不足 |

---

## 采集集成

```yaml
# Prometheus static_configs（Omnibus/源码部署）
- job_name: gitlab-rails
  metrics_path: /-/metrics
  static_configs:
    - targets:
        - "gitlab-host:80"
      labels:
        service: gitlab
        component: rails

- job_name: gitlab-sidekiq
  metrics_path: /-/metrics
  static_configs:
    - targets:
        - "gitlab-host:80"
      labels:
        service: gitlab
        component: sidekiq

- job_name: gitlab-gitaly
  static_configs:
    - targets:
        - "gitlab-gitaly:9236"
      labels:
        service: gitlab
        component: gitaly

- job_name: gitlab-runner
  static_configs:
    - targets:
        - "runner-host:9252"
      labels:
        service: gitlab-runner
```

Omnibus 部署需在 `/etc/gitlab/gitlab.rb` 中启用：
```ruby
gitlab_rails['prometheus_enable'] = true
sidekiq['metrics_enabled'] = true
gitaly['prometheus_listen_addr'] = '0.0.0.0:9236'
```

---

## 告警规则

```yaml
- alert: GitlabSidekiqQueueLatencyHigh
  expr: sidekiq_queue_latency > 60
  for: 5m
  annotations:
    summary: "GitLab Sidekiq 队列延迟 {{ $value }}s"

- alert: GitlabDatabaseConnHigh
  expr: rails_db_main_pool_connections / rails_db_main_pool_size * 100 > 80
  for: 3m
  annotations:
    summary: "GitLab 数据库连接使用率 {{ $value | humanizePercentage }}"

- alert: GitlabRailsLatencyHigh
  expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
  for: 3m
  annotations:
    summary: "GitLab Rails P99 延迟 > 2s"
```

---

## 部署注意事项（混合部署适配）

| 部署方式 | 采集方式 |
|---------|---------|
| Omnibus 部署 | `/etc/gitlab/gitlab.rb` 启用 prometheus，默认端口 9168（单机统一）|
| Docker GitLab | 各组件容器分别暴露 metrics 端口 |
| GitLab Helm Chart | Cloud Native 模式，ServiceMonitor 自动发现 |

Omnibus 部署默认在 `gitlab_exporter` 中聚合所有组件指标（9168/metrics），建议按组件分开采集以便更精细的告警路由。

---

## 采集器方案对比

| 采集器 | 部署方式 | 指标覆盖 | 日志支持 | 适用场景 |
|--------|---------|---------|---------|---------|
| GitLab 内置 /-/metrics | 内置端点 | Rails/Sidekiq/Workhorse | 无 | 标准方案（需认证配置） |
| GitLab Gitaly | TCP 9236 | Git 操作指标 | 无 | Gitaly 专项 |
| GitLab Runner | TCP 9252 | CI 作业指标 | 无 | Runner 专项 |
| Grafana Alloy | 抓取各端口 | 同上 | 内置 loki.source | Grafana 全栈 |
| Netdata | 一键安装 | 内置 gitlab collector（社区） | 内置日志查看 | 快速部署 |

---

## Alloy 采集配置

```alloy
// GitLab Rails + Sidekiq（需 Bearer Token）
prometheus.scrape "gitlab_rails" {
  targets = [{ __address__ = "gitlab.devops.svc:80", __metrics_path__ = "/-/metrics" }]
  authorization {
    type        = "Bearer"
    credentials = env("GITLAB_METRICS_TOKEN")
  }
  forward_to = [prometheus.remote_write.central.receiver]
}

// Gitaly
prometheus.scrape "gitlab_gitaly" {
  targets = [{ __address__ = "gitlab-gitaly.gitlab.svc:9236", service = "gitlab-gitaly" }]
  forward_to = [prometheus.remote_write.central.receiver]
}

// Runner
prometheus.scrape "gitlab_runner" {
  targets = [{ __address__ = "gitlab-runner.gitlab.svc:9252", service = "gitlab-runner" }]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint { url = "http://prometheus.observability.svc:9090/api/v1/write" }
}
```

---

## 方案对比

| 维度 | GitLab 内置 + Prometheus | Alloy | Netdata |
|------|------------------------|-------|---------|
| 部署复杂度 | 中（需认证配置） | 中 | 低 |
| 认证/白名单 | 必须配置 | 必须配置 | 需配置 |
| 多组件覆盖 | 需多个 scrape job | ✅ 统一配置 | 自动发现 |
| Grafana 兼容 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 推荐场景 | 已有 Prometheus 栈 | Grafana 全栈 | 快速验证 |
