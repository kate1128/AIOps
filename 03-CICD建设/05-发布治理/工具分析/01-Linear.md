# Linear — 现代研发项目管理

> 为工程师设计的项目管理工具，简洁高效，与 GitLab 深度集成，是 Jira 的轻量替代。

---

## 是什么

Linear 是新一代研发项目管理工具，专为工程团队设计，强调极简操作和快速响应。与 Jira 相比，Linear 的 UI 更简洁，键盘操作流畅，与 GitHub/GitLab 集成后能自动关联代码变更，是越来越多中小型研发团队的首选。

---

## 核心能力

| 能力 | 说明 |
| --- | --- |
| Issue 管理 | 需求、任务、Bug 统一管理，状态流转清晰 |
| Cycle（迭代） | 两周 Sprint 管理，自动追踪完成进度 |
| Project | 跨 Cycle 的大功能版本规划 |
| Roadmap | 产品路线图时间线视图 |
| GitLab 集成 | MR 自动关联 Issue，合并后自动完成 Issue |
| 快捷键驱动 | 几乎所有操作都有快捷键，不用鼠标 |
| 命令面板 | `Cmd+K` 快速搜索和操作 |
| Slack / 钉钉通知 | Issue 变更实时通知 |

---

## 与本项目的关系

```text
产品需求（PRD）
    │
    └── Linear Project（版本计划）
            │
            ├── Feature Issues ──→ 开发分支（feature/LIN-123-xxx）
            ├── Bug Issues ──→ GitLab MR（提交信息引用 LIN-XXX）
            └── Cycle（两周迭代）
                    │
                    └── 自动统计完成率 / 速度
```

---

## 与 GitLab 集成

```yaml
# GitLab 提交信息规范（自动关联 Linear Issue）
# 格式：<type>(<LIN-ID>): <description>
feat(LIN-234): 实现用户 Token 配额管理
fix(LIN-567): 修复推理超时未正确返回错误码
chore(LIN-891): 更新 vLLM 至 0.4.2

# MR 合并后，Linear Issue 自动流转到 Done 状态
# 前提：在 Linear 设置中配置 GitLab 集成 + 打开自动完成开关
```

---

## 核心工作流

```text
1. 产品：在 Linear 创建 Issue，写清楚需求描述、验收标准
2. 开发：领取 Issue，创建分支（Linear 自动建议分支名）
3. 开发：提交代码，Commit 消息引用 Issue ID
4. 开发：创建 MR，描述中引用 Linear Issue 链接
5. Review：GitLab MR Review + Approve
6. 合并：MR 合并，Linear Issue 自动完成
7. 迭代：每两周 Cycle Review，看速度和完成率
```

---

## 与其他工具的选型

详见 [../../../06-产品质量保障/工具分析/01-TAPD.md](../../../06-产品质量保障/工具分析/01-TAPD.md) 中的完整三方选型对比（Linear vs TAPD vs Jira）。

快速结论：团队 < 50 人、数据无合规要求 -> Linear；需要数据在国内或内置测试管理 -> TAPD。

---

## GitHub 信息

- 开源状态：非开源 / 不对应单一开源仓库
- 说明：Linear 为商业 SaaS，暂无官方开源主仓库
- Star：不适用
