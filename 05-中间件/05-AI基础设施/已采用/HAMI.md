# HAMI - GPU 调度器
> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| GPU 资源调度与管无 |
| 部署方式 | 待确认 |
| 版本 | - |
| 功能 | GPU 显存/算力动态分割、多任务共享、优先级调度 |

---

## 部署

```bash
helm repo add hami https://hami.github.io/charts
helm install hami hami/hami --namespace gpu-operator --create-namespace
```

---

## 监控

```promql
DCGM_FI_DEV_GPU_UTIL       # GPU 利用?DCGM_FI_DEV_FB_USED        # 显存使用
DCGM_FI_DEV_GPU_TEMP       # GPU 温度
DCGM_FI_DEV_POWER_USAGE    # 功率
hami_scheduled_jobs_total  # 调度任务?```

---

## 优先级
| 重要性| 事项 |
|--------|------|
| P0 | GPU 利用率监控（避免空转/争抢）|
| P0 | 显存碎片管理 |
| P1 | 调度策略调优（任务优先级 QoS）|
