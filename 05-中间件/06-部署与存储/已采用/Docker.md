# Docker - 容器运行时
> 现状参考：`00-产品分析/产品分析.md`
> 当前状态：- 已使用
---

## 现状

| 项目 | 内容 |
|------|------|
| 用途| ai-backend 容器化运行 |
| 部署方式 | docker run / docker compose |
| 版本 | - |

---

## 存在问题

- 日志在容器内，未集中采集?Loki
- 部署靠手动执行命令，未自动化
- 缺少统一编排文件版本管理

---

## 优化建议

- 统一使用 `docker compose` 编排替代?`docker run`
- 接入 Loki logging driver ?Promtail sidecar 采集日志
- 编排文件（docker-compose.yaml / docker-run.sh）纳?Git 版本管理 + 制品归档

> 参考：`05-cicd/制品管理方案.md` ?4.3 ?