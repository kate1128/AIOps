# 发布治理落地行动清单

> 对应 03-CICD 建设后半段，前置条件是 CI、制品仓库、基础部署链路已跑通。

## 第一步：确定版本策略

```text
# 推荐策略：GitFlow + SemVer

# 分支
- develop：日常开发
- release/x.y.z：发布准备
- main：正式发布
- hotfix/*：线上修复

# 版本规则
- dev：dev-{sha}
- 预发：rc-{semver}
- 正式：{semver}
- 热修复：{semver}-hotfix.{n}
```

## 第二步：建立发布清单模板

```markdown
# 文件：release-manifest.yaml

version: 1.2.3
git_tag: v1.2.3
commit: abcdef1
artifacts:
  - name: api-service
    type: docker
    ref: harbor.internal/platform/api-service:1.2.3
  - name: platform-chart
    type: helm
    ref: harbor.internal/helm/platform-api:1.2.3
changes:
  features: []
  fixes: []
  known_issues: []
verification:
  smoke_test: passed
documentation:
  feishu_kb_page: https://feishu.example/wiki/service-api
  deployment_doc_updated: true
rollback:
  target_version: 1.2.2
  owner: sre-oncall
```

## 第三步：建立 Release Notes 模板

```markdown
# Release Notes - v1.2.3

## Features
- 

## Bug Fixes
- 

## Improvements
- 

## Known Issues
- 

## Upgrade Notes
- 
```

## 第四步：建立飞书知识库更新模板

```markdown
# 飞书知识库服务部署文档

## 服务信息
- 服务名称：
- 当前版本：
- 最近更新时间：
- 负责人：

## 部署制品
- 镜像地址：
- Helm Chart / 包版本：

## 部署步骤
1. 
2. 
3. 

## 配置与依赖
- 环境变量：
- 外部依赖：
- 密钥说明：

## 验证与回滚
- 验证命令：
- 回滚步骤：
- 常见故障排查：
```

统一模板文件：

- [templates/服务部署文档模板.md](./templates/服务部署文档模板.md)

## 第五步：配置发布审批流程

```text
# 建议组合
- GitLab MR Approval：代码审批
- 飞书或 Jira 审批流：变更单审批
- GitLab Protected Environments：生产发布权限控制

# 最小审批要求
- 技术 Lead 审批
- QA 验证完成
- 运维确认窗口
- 回滚方案已填写
- 飞书知识库更新责任人已明确
```

## 第六步：把发布清单纳入 CI 产物

```yaml
# Git Tag 触发时自动归档发布清单
archive-release-manifest:
  stage: archive
  script:
    - test -f release-manifest.yaml
    - mc cp release-manifest.yaml smartvision-archive/$CI_PROJECT_NAME/$CI_COMMIT_TAG/
    - mc cp RELEASE_NOTES.md smartvision-archive/$CI_PROJECT_NAME/$CI_COMMIT_TAG/
  rules:
    - if: $CI_COMMIT_TAG
```

## 第七步：把知识库更新纳入发布后动作

```text
# 发布完成后的固定动作
1. 更新飞书知识库中的服务部署文档
2. 补充本次版本号、制品信息、配置变更、回滚步骤
3. 在发布群或变更单中附上飞书知识库链接
4. 如果部署方式发生变化，通知 SRE / 运维同步值班手册
```

## 第八步：建立月度发布复盘机制

```markdown
# 每月发布复盘会（1 小时）

## 数据输入
- 生产发布次数
- 发布失败次数
- 回滚次数
- 平均审批耗时
- DORA 四项指标趋势

## 输出
- 本月最大流程瓶颈
- 下月要自动化的 1-2 个动作
- 高风险服务发布特别治理清单
```

## 验收 Checklist

- [ ] 版本命名规则已统一
- [ ] 发布清单模板已纳入仓库
- [ ] Release Notes 模板已固定
- [ ] 飞书知识库服务部署文档模板已固定
- [ ] 生产发布审批链路已建立
- [ ] Git Tag 发布可自动归档交付清单
- [ ] 发布后已要求同步更新飞书知识库和服务部署文档
- [ ] 月度发布复盘已开始执行
