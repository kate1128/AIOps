# GitLab Releases

> GitLab 内置的 Release 功能，与 CI/CD 深度集成，无需额外工具即可完成版本发布管理。

---

## 适用场景

- 已使用 GitLab 作为代码仓库和 CI 引擎
- 不需要复杂的发布自动化
- 希望减少工具链复杂度

---

## 优劣势

| 优势 | 劣势 |
|------|------|
| 内置功能，无需额外部署 | 功能不如专用工具丰富 |
| 与 GitLab CI 无缝集成 | 版本号需手动或 CI 脚本控制 |
| 支持 Release Note 和附件 | CHANGELOG 自动生成需额外配置 |
| 权限模型和 GitLab 一致 | 无灰度发布等高级功能 |

---

## 配合建议

- GitLab Releases 作为发布记录存储
- 在 CI 脚本中实现版本号自动递增和 CHANGELOG 生成
- ReleasePlease 可作为 CI Job 运行在 GitLab CI 中
