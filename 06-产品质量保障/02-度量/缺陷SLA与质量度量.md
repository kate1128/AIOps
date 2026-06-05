# 缺陷 SLA 与质量度量

> 用数据回答"我们的 Bug 管理做得怎么样"，驱动持续改进。

---

## 一、SLA 定义

| 优先级 | 响应时限（确认）| 修复时限（Closed）| 超期定义 |
|---|---|---|---|
| P0 - 致命 | 15 分钟 | 4 小时 | 超过修复时限未关闭 |
| P1 - 严重 | 1 小时 | 24 小时 | 同上 |
| P2 - 一般 | 4 小时 | 当前迭代结束 | 跨迭代未关闭 |
| P3 - 轻微 | 下个迭代开始 | 下下个迭代结束 | 积压超 3 个迭代 |

**时限从状态变为 `Confirmed` 开始计时**（确认是 Bug 才算 SLA 开始）。

---

## 二、核心度量指标

| 指标 | 计算方式 | 健康目标 |
|---|---|---|
| **P0/P1 SLA 达标率** | 在时限内关闭的 P0/P1 数 / 总 P0/P1 数 | > 95% |
| **Bug 逃逸率** | 生产环境发现的 Bug / 总 Bug 数 | < 10% |
| **平均修复时间（MTTR）** | 所有 Bug 的（Closed 时间 - Confirmed 时间）均值 | P0 < 2h，P1 < 12h |
| **Reopen 率** | 被重新打开的 Bug / 总关闭 Bug 数 | < 5% |
| **Bug 积压趋势** | 当前 Open Bug 数（按周统计）| 趋势向下 |
| **新增 vs 关闭** | 周期内新增数 / 关闭数比值 | ≤ 1（不能积压）|

---

## 三、数据采集方式

当前使用 GitLab Issues，通过 GitLab API 采集：

```bash
# 获取过去 30 天内所有 P0 Bug 的响应时间
curl "https://gitlab.com/api/v4/projects/{PROJECT_ID}/issues" \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -G \
  --data-urlencode "labels=P0-critical" \
  --data-urlencode "created_after=$(date -d '30 days ago' +%Y-%m-%d)" \
  --data-urlencode "state=all"
```

使用 GitLab 内置的 Issue Analytics 看板（路径：项目 → Analyze → Issue analytics）可直接查看趋势图。

---

## 四、Grafana 看板（推荐配置）

通过 GitLab API → Prometheus Pushgateway → Grafana 实现实时看板。

### 定时采集脚本（每小时执行）

```bash
#!/bin/bash
# collect-bug-metrics.sh — 采集 GitLab Issues 指标推送到 Prometheus

PROJECT_ID="your-project-id"
TOKEN="$GITLAB_TOKEN"
PUSHGW="http://prometheus-pushgateway:9091"

# 当前 Open 的 P0 数量
P0_OPEN=$(curl -s "https://gitlab.com/api/v4/projects/$PROJECT_ID/issues?labels=P0-critical,status::confirmed&state=opened&per_page=1" \
  -H "PRIVATE-TOKEN: $TOKEN" -I | grep "X-Total:" | awk '{print $2}' | tr -d '\r')

# 当前 Open 的 P1 数量
P1_OPEN=$(curl -s "https://gitlab.com/api/v4/projects/$PROJECT_ID/issues?labels=P1-severe&state=opened&per_page=1" \
  -H "PRIVATE-TOKEN: $TOKEN" -I | grep "X-Total:" | awk '{print $2}' | tr -d '\r')

# 推送到 Pushgateway
cat <<EOF | curl --data-binary @- "$PUSHGW/metrics/job/bug_metrics"
bug_open_total{priority="P0"} ${P0_OPEN:-0}
bug_open_total{priority="P1"} ${P1_OPEN:-0}
EOF
```

### 推荐 Panel 配置

| Panel | 指标 | 图表类型 |
|---|---|---|
| 当前 Open P0/P1 数量 | `bug_open_total` | Stat（数字大屏）|
| Bug 积压趋势（4 周）| Open Bug 数按周统计 | 折线图 |
| 本周新增 vs 关闭 | 新增数 / 关闭数 | 柱状图（双色）|
| Bug 逃逸率（月）| source::customer / 总数 | Gauge |
| P0 SLA 达标率 | 达标数 / 总数 | Gauge（目标线 95%）|
| 按模块分布 | module 标签分组 | 饼图 |

---

## 五、双周质量报告模板

每两周发给技术团队和产品团队：

```markdown
## 缺陷质量报告 {日期范围}

### 本周期概览
- 新增 Bug：{n} 个（P0: {n}，P1: {n}，P2: {n}，P3: {n}）
- 关闭 Bug：{n} 个
- 当前积压：{n} 个

### SLA 达标情况
| 优先级 | 目标 | 实际 | 状态 |
|---|---|---|---|
| P0 | > 95% | {n}% | ✅/❌ |
| P1 | > 95% | {n}% | ✅/❌ |

### Bug 逃逸率
- 本周期逃逸：{n} 个（{n}%），目标 < 10%

### 本周期高频根因 TOP3
1. {根因 1}：{n} 个 Bug
2. {根因 2}：{n} 个 Bug
3. {根因 3}：{n} 个 Bug

### 改进行动
- [ ] {Action 1}（负责人：{name}，截止：{date}）
```
