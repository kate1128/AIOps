# DORA 指标自动采集与分析 — 落地实现

> 本文档是 [AI提效计划 - 机会5](../AI提效计划.md) 的内部设计与落地细节。

---

## DORA 四项指标采集方案

| 指标 | 数据来源 | 采集方式 |
|------|---------|---------|
| 部署频率 | GitLab deployment events | GitLab API → Prometheus Pushgateway |
| 变更前置时间 | MR 创建时间 → 生产部署时间 | GitLab API 计算差值 → Prometheus |
| 变更失败率 | 发布后 1h 内是否回滚 | GitLab Tag + Alertmanager 事件关联 |
| 服务恢复时间 | P0/P1 告警触发到 resolved 时间差 | Alertmanager webhook → 自定义采集器 |

---

## 实现步骤

### Step 1：DORA 指标采集脚本

脚本以 K8s CronJob 运行，每天凌晨拉取 GitLab 数据推送到 Prometheus Pushgateway：

```python
# scripts/dora-collector.py
import os
import time
import requests
from datetime import datetime, timedelta, timezone

GITLAB_URL   = os.environ["GITLAB_URL"]
GITLAB_TOKEN = os.environ["GITLAB_API_TOKEN"]
PROJECT_ID   = os.environ["GITLAB_PROJECT_ID"]
PUSHGATEWAY  = os.environ.get("PUSHGATEWAY_URL", "http://prometheus-pushgateway.monitoring.svc:9091")

gitlab_headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}


def get_deployments_last_30days() -> int:
    """部署频率：过去 30 天生产部署次数"""
    since = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    resp = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/deployments",
        params={"environment": "production", "status": "success",
                "updated_after": since, "per_page": 100},
        headers=gitlab_headers, timeout=15
    )
    resp.raise_for_status()
    return len(resp.json())


def get_avg_lead_time_days() -> float:
    """变更前置时间：过去 30 天 MR 从创建到部署的平均天数"""
    since = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    deployments = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/deployments",
        params={"environment": "production", "status": "success",
                "updated_after": since, "per_page": 20},
        headers=gitlab_headers, timeout=15
    ).json()

    lead_times = []
    for dep in deployments:
        deployed_at = datetime.fromisoformat(dep["created_at"].replace("Z", "+00:00"))
        # 获取该部署关联的 MR
        mr_resp = requests.get(
            f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/deployments/{dep['id']}/merge_requests",
            headers=gitlab_headers, timeout=10
        )
        if mr_resp.ok:
            for mr in mr_resp.json():
                created_at = datetime.fromisoformat(mr["created_at"].replace("Z", "+00:00"))
                lead_times.append((deployed_at - created_at).total_seconds() / 86400)

    return sum(lead_times) / len(lead_times) if lead_times else 0


def push_to_prometheus(metrics: dict):
    """推送指标到 Prometheus Pushgateway"""
    lines = []
    for name, value in metrics.items():
        lines.append(f"# TYPE {name} gauge")
        lines.append(f"{name} {value}")
    payload = "\n".join(lines) + "\n"
    requests.post(
        f"{PUSHGATEWAY}/metrics/job/dora_collector",
        data=payload,
        headers={"Content-Type": "text/plain"},
        timeout=10
    ).raise_for_status()


if __name__ == "__main__":
    metrics = {
        "dora_deployment_frequency_30d":  get_deployments_last_30days(),
        "dora_lead_time_avg_days":        get_avg_lead_time_days(),
        # 变更失败率和恢复时间需结合 Alertmanager 数据，见下方说明
    }
    push_to_prometheus(metrics)
    print(f"DORA 指标已推送: {metrics}")
```

### Step 2：Prometheus 告警关联（变更失败率 + 恢复时间）

**变更失败率**：在 Alertmanager 配置 webhook，当生产告警触发后 1 小时内有回滚 Tag（如 `rollback-v2.1.0`）则计为失败发布：

```yaml
# alertmanager.yml - 额外 webhook 接收器
receivers:
  - name: dora-webhook
    webhook_configs:
      - url: 'http://dora-collector.devtools.svc:8080/alert'
        send_resolved: true

route:
  receiver: dora-webhook
  group_by: [alertname, severity]
```

**恢复时间**：Alertmanager resolved webhook 触发时间 - firing webhook 触发时间，由 `dora-collector` 服务计算后推送 Prometheus。

### Step 3：Grafana Dashboard

导入社区 DORA Dashboard（ID: `10530`）或自建，配置 4 个面板：

```yaml
# grafana/dora-dashboard.json（关键 panel 配置）
panels:
  - title: "部署频率（次/月）"
    expr: "dora_deployment_frequency_30d"
    thresholds:
      - value: 1    color: red     # Low
      - value: 4    color: yellow  # Medium
      - value: 20   color: green   # High → Elite

  - title: "变更前置时间（天）"
    expr: "dora_lead_time_avg_days"
    thresholds:
      - value: 7    color: green   # Elite: < 1 天显示为优秀
      - value: 30   color: yellow
      - value: 999  color: red

  - title: "变更失败率（%）"
    expr: "dora_change_failure_rate_percent"

  - title: "服务恢复时间（小时）"
    expr: "dora_mttr_hours"
```

### Step 4：LLM 月度分析（K8s CronJob，每月第一个工作日）

```python
# scripts/dora-monthly-report.py
import os, requests

PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "http://prometheus.monitoring.svc:9090")
VLLM_URL       = os.environ.get("VLLM_URL", "http://vllm-service.ai-infra.svc.cluster.local:8000/v1/chat/completions")
FEISHU_WEBHOOK = os.environ["FEISHU_DORA_WEBHOOK"]
MODEL          = os.environ.get("DORA_MODEL", "Qwen2.5-Coder-32B-Instruct")

# 行业基准（DORA 2023 报告 High 档）
BENCHMARKS = {
    "deployment_frequency": "每周 1 次以上",
    "lead_time": "1天-1周",
    "change_failure_rate": "5-10%",
    "mttr": "< 1天"
}


def query_prometheus(expr: str) -> float:
    resp = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={"query": expr}, timeout=10)
    result = resp.json()["data"]["result"]
    return float(result[0]["value"][1]) if result else 0


def collect_metrics() -> dict:
    return {
        "deployment_frequency_30d": query_prometheus("dora_deployment_frequency_30d"),
        "lead_time_avg_days":       query_prometheus("dora_lead_time_avg_days"),
        "change_failure_rate_pct":  query_prometheus("dora_change_failure_rate_percent"),
        "mttr_hours":               query_prometheus("dora_mttr_hours"),
    }


def generate_report(metrics: dict) -> str:
    resp = requests.post(VLLM_URL, json={
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "你是一位 DevOps 效能分析专家，根据 DORA 指标数据生成月度分析报告。使用中文，简洁务实。"},
            {"role": "user", "content": (
                f"本月 DORA 指标数据：\n{metrics}\n\n"
                f"行业基准（High 档）：\n{BENCHMARKS}\n\n"
                "请生成：\n"
                "1. 各指标与基准的对比（达标/待改进）\n"
                "2. 当前最需改进的 Top 2 指标及原因分析\n"
                "3. 每个待改进指标给出一条具体可执行的改进建议\n"
                "4. 一句话总结本月研发效能状态"
            )}
        ]
    }, timeout=60)
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def send_feishu(report: str, metrics: dict):
    requests.post(FEISHU_WEBHOOK, json={
        "msg_type": "text",
        "content": {
            "text": (
                f"📊 DORA 效能月报\n\n"
                f"部署频率：{metrics['deployment_frequency_30d']:.0f} 次/月\n"
                f"变更前置时间：{metrics['lead_time_avg_days']:.1f} 天\n"
                f"变更失败率：{metrics['change_failure_rate_pct']:.1f}%\n"
                f"服务恢复时间：{metrics['mttr_hours']:.1f} 小时\n\n"
                f"{report}"
            )
        }
    }, timeout=10).raise_for_status()


if __name__ == "__main__":
    metrics = collect_metrics()
    report = generate_report(metrics)
    send_feishu(report, metrics)
    print("DORA 月报已推送飞书")
```

### K8s CronJob 部署

```yaml
# k8s/dora-monthly-report-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: dora-monthly-report
  namespace: devtools
spec:
  schedule: "0 9 1 * *"   # 每月 1 日 09:00
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: reporter
              image: harbor.internal/devtools/dora-reporter:latest
              env:
                - name: GITLAB_API_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: gitlab-token
                      key: token
                - name: FEISHU_DORA_WEBHOOK
                  valueFrom:
                    secretKeyRef:
                      name: feishu-webhook
                      key: dora-url
```

---

## 飞书月报示例

```
📊 DORA 效能月报

部署频率：12 次/月
变更前置时间：3.2 天
变更失败率：8.3%
服务恢复时间：4.1 小时

各指标与基准对比：
✅ 部署频率：12次/月，达 High 档（基准≥4次）
⚠️ 变更前置时间：3.2天，处于 Medium 档（基准 1天-1周的中段）
✅ 变更失败率：8.3%，处于 High 档范围（基准 5-10%）
⚠️ 服务恢复时间：4.1小时，略超 High 档（基准<24小时，但优化空间大）

Top 2 待改进项：
1. 变更前置时间：Code Review 周期平均 2.1 天，是前置时间的主要组成部分
   → 建议：AI Code Review 接入后跟踪 Review 周期变化，目标降至 1.5 天内
2. 服务恢复时间：P1 告警平均 2.8 小时才有人响应（OnCall 覆盖时段外）
   → 建议：完善 OnCall 轮值表，非工作时间 P1 告警 15 分钟内必须响应

本月总结：研发效能处于 High 档水平，整体健康，核心瓶颈在 Review 速度和夜间响应。
```

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [AI提效计划.md](../AI提效计划.md) | 整体方案和实施路径 |
| [07-可观测性/体系建设总览.md](../../07-可观测性/体系建设总览.md) | Prometheus + Grafana 基础设施 |
| [10-SRE 稳定性工程/体系建设总览.md](../../10-SRE%20稳定性工程/体系建设总览.md) | MTTR 与 OnCall 体系 |
