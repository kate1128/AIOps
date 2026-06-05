# AI 代码审核机器人接入方案

> 在 GitLab CI 流程中引入 AI 自动代码审核，提升代码质量和安全性。

---

## 一、可选方案对比

| 方案 | 类型 | 费用 | GitLab 支持 | 特点 |
|---|---|---|---|---|
| **GitLab Duo** | GitLab 官方 | 付费（Ultimate 版） | 原生集成 | 最自然，但贵 |
| **PR-Agent** | 开源 | 免费 | 支持 | 功能全，可自托管 |
| **CodeRabbit.ai** | SaaS | 按量付费 | 支持 | 体验好，但依赖外部 |
| **自研（Claude API）** | 自建 | API 费用 | 支持 | 完全可控，需开发 |
| **SonarQube + AI** | 工具+插件 | 社区版免费 | 支持 | 偏静态分析，AI 辅助有限 |

---

## 二、推荐方案

### 方案 A：PR-Agent（开源免费，推荐）

PR-Agent 是由 Codium 开源的 AI 代码审核工具，支持 GitLab、GitHub、Bitbucket。

#### 功能特性

- **自动代码审核**：分析 MR diff，给出修改建议
- **自动生成描述**：根据代码变更自动生成 MR 描述
- **问答模式**：在 MR 评论区 @机器人提问
- **增量审查**：只审查新增的变更
- **安全检查**：识别潜在的安全漏洞

#### 部署方式（GitLab CI）

```yaml
# .gitlab-ci.yml 中增加 AI 审核阶段
stages:
  - lint
  - test
  - ai-review     # 新增 AI 审核阶段
  - build
  - scan
  - deploy

# AI 代码审核 Job
ai-code-review:
  stage: ai-review
  image: codiumai/pr-agent:latest
  variables:
    # GitLab 配置
    GITLAB_TOKEN: $CI_JOB_TOKEN           # 或专用 Token
    GITLAB_URL: $CI_SERVER_URL
    
    # AI 提供商（可选 OpenAI / Anthropic / Azure）
    OPENAI_KEY: $OPENAI_API_KEY             # 或 ANTHROPIC_API_KEY
    
    # PR-Agent 配置
    PR_REVIEWER.EXTRA_INSTRUCTIONS: "请重点关注安全性和性能问题"
    PR_DESCRIPTION.EXTRA_INSTRUCTIONS: "请用中文生成描述"
  script:
    - |
      # 运行代码审核
      python -m pr_agent.cli \
        --url "$CI_MERGE_REQUEST_IID" \
        --pr_url "$CI_MERGE_REQUEST_SOURCE_BRANCH_SHA" \
        review
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  allow_failure: true   # AI 审核失败不阻塞流水线
```

#### 配置说明

```bash
# 1. 在 GitLab 中创建专用 Token
# Settings → CI/CD → Variables → Add Variable
#   Key: OPENAI_API_KEY
#   Value: sk-xxxxxxxxxx
#   Protected: true
#   Masked: true

# 2. 配置 PR-Agent 行为（可选）
# 在项目根目录创建 .pr_agent.toml

[pr_reviewer]
# 审查要求
extra_instructions = """
请重点关注以下方面：
1. 安全性问题（SQL注入、XSS、敏感信息泄露）
2. 性能问题（N+1查询、内存泄漏、无效循环）
3. 代码规范（命名、注释、异常处理）
4. 架构合理性（耦合度、可维护性）
"""

# 自动审查的文件类型
files_to_ignore = ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"]

[pr_description]
# 自动生成 MR 描述
publish_description_as_comment = true

[pr_questions]
# 问答模式
enable_help_text = true
```

#### PR-Agent 审查效果示例

```markdown
## AI 代码审查报告

### 🔍 审查概览
- **审查范围**: 新增 3 个文件，修改 150 行
- **风险等级**: 低
- **建议数量**: 5 条

### 🛡️ 安全性检查
- [x] 无 SQL 注入风险
- [x] 无 XSS 风险
- [⚠️] 发现潜在敏感信息泄露：
  `utils/config.py:15` 硬编码了数据库密码，建议使用环境变量

### ⚡ 性能优化
- `services/user.py:42` 存在 N+1 查询问题，建议使用 `select_related`
- `tasks/async_job.py:88` 循环内重复创建数据库连接，建议移到循环外

### 📝 代码规范
- `models/order.py:23` 函数名 `getData` 不符合 snake_case 规范，建议改为 `get_data`
- 缺少异常处理：`api/views.py:56` 的 API 接口未处理 `KeyError`

### 💡 建议
建议在合并前处理上述标记为 [⚠️] 的问题。
```

---

### 方案 B：自研 Claude API 审核（完全可控）

如果你希望完全控制审核逻辑，可以自研脚本调用 Claude API。

#### 实现脚本

```python
#!/usr/bin/env python3
"""
ai_code_review.py
调用 Claude API 审核 GitLab MR 的代码变更
"""

import os
import requests
import json
import re

# 配置
GITLAB_URL = os.getenv("CI_SERVER_URL", "https://gitlab.com")
PROJECT_ID = os.getenv("CI_PROJECT_ID")
MERGE_REQUEST_IID = os.getenv("CI_MERGE_REQUEST_IID")
GITLAB_TOKEN = os.getenv("AI_REVIEW_TOKEN")  # 专用 Token，需要 api 权限
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")

def get_mr_diff():
    """获取 MR 的代码 diff"""
    url = f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/merge_requests/{MERGE_REQUEST_IID}/changes"
    headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}
    
    response = requests.get(url, headers=headers)
    response.raise_for_status()
    
    changes = response.json()
    return changes.get("changes", [])

def review_with_claude(diff_content: str) -> str:
    """调用 Claude API 审核代码"""
    
    prompt = f"""你是一位资深代码审查专家。请审查以下代码变更，并给出详细的审查报告。

请重点关注：
1. 安全性问题（SQL注入、XSS、CSRF、敏感信息泄露、不安全的反序列化等）
2. 性能问题（N+1查询、内存泄漏、无效循环、大O复杂度问题等）
3. 代码质量（命名规范、注释、异常处理、日志记录等）
4. 架构设计（耦合度、可维护性、可测试性等）
5. 最佳实践（是否遵循语言/框架的惯用法）

请以中文输出，格式如下：
- 问题等级：[严重]/[警告]/[建议]
- 问题位置：文件和行号
- 问题描述
- 修复建议

代码变更：
```diff
{diff_content}
```
"""
    
    response = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": ANTHROPIC_API_KEY,
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01"
        },
        json={
            "model": "claude-3-5-sonnet-20240620",
            "max_tokens": 4096,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        }
    )
    
    response.raise_for_status()
    return response.json()["content"][0]["text"]

def post_review_comment(comment: str):
    """将审查结果作为评论发布到 MR"""
    url = f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/merge_requests/{MERGE_REQUEST_IID}/notes"
    headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}
    
    # 截断过长的评论
    if len(comment) > 1000000:  # GitLab 评论最大 1MB
        comment = comment[:900000] + "\n\n...（评论过长，已截断）"
    
    data = {
        "body": f"## 🤖 AI 代码审查报告\n\n{comment}\n\n---\n*由 Claude AI 自动生成*"
    }
    
    response = requests.post(url, headers=headers, json=data)
    response.raise_for_status()
    return response.json()

def main():
    try:
        # 获取代码 diff
        changes = get_mr_diff()
        
        if not changes:
            print("没有需要审查的代码变更")
            return
        
        # 构建 diff 文本（限制大小，避免超出 Claude 上下文）
        diff_text = ""
        total_lines = 0
        max_lines = 500  # 限制最大行数
        
        for change in changes:
            if total_lines >= max_lines:
                diff_text += "\n...（还有更多文件，已截断）"
                break
            
            diff = change.get("diff", "")
            if len(diff.splitlines()) + total_lines > max_lines:
                lines = diff.splitlines()
                diff = "\n".join(lines[:max_lines - total_lines])
                diff_text += f"\n--- {change['new_path']} ---\n{diff}\n...（已截断）"
                break
            
            diff_text += f"\n--- {change['new_path']} ---\n{diff}"
            total_lines += len(diff.splitlines())
        
        print(f"正在审查 {len(changes)} 个文件的变更...")
        
        # 调用 Claude API
        review_result = review_with_claude(diff_text)
        
        # 发布审查结果
        post_review_comment(review_result)
        
        print("AI 代码审查完成，结果已发布到 MR")
        
    except Exception as e:
        print(f"AI 代码审查失败: {e}")
        # 失败不阻塞流水线
        exit(0)

if __name__ == "__main__":
    main()
```

#### GitLab CI 配置

```yaml
# .gitlab-ci.yml
stages:
  - lint
  - ai-review     # AI 代码审核
  - test
  - build
  - scan
  - deploy

# AI 代码审核 Job
ai-code-review:
  stage: ai-review
  image: python:3.11-slim
  variables:
    # GitLab 配置
    CI_SERVER_URL: $CI_SERVER_URL
    CI_PROJECT_ID: $CI_PROJECT_ID
    CI_MERGE_REQUEST_IID: $CI_MERGE_REQUEST_IID
    
    # AI 配置
    ANTHROPIC_API_KEY: $ANTHROPIC_API_KEY
    AI_REVIEW_TOKEN: $AI_REVIEW_TOKEN  # 需要 api 权限的 GitLab Token
  script:
    - pip install requests
    - python scripts/ai_code_review.py
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: always
  allow_failure: true   # AI 审核失败不阻塞流水线
  timeout: 5m          # 限制执行时间，避免 API 超时阻塞
```

#### 效果示例

```markdown
## 🤖 AI 代码审查报告

### 审查结果

#### [严重] utils/db.py:45 - SQL 注入风险
**问题**：`cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")` 使用 f-string 拼接 SQL
**修复建议**：
```python
# 错误
# cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")

# 正确
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

#### [警告] services/order.py:78 - N+1 查询
**问题**：循环内查询数据库
```python
for order in orders:
    user = User.query.get(order.user_id)  # 每次循环都查 DB
```
**修复建议**：
```python
# 使用 joinedload 或批量查询
from sqlalchemy.orm import joinedload
orders = Order.query.options(joinedload(Order.user)).all()
```

#### [建议] models/user.py:23 - 缺少类型提示
**问题**：函数参数和返回值缺少类型注解
**修复建议**：
```python
def get_user(user_id: int) -> Optional[User]:
    ...
```

---
*由 Claude AI 自动生成*
```

---

### 方案 C：CodeRabbit.ai（SaaS，开箱即用）

如果你不想自己部署，可以用 CodeRabbit.ai。

#### 接入方式

1. 访问 https://coderabbit.ai
2. 用 GitLab 账号登录并授权
3. 选择需要监控的仓库
4. 配置审查规则（中文、审查深度等）

#### 特点

- **优点**：零部署，配置简单，支持中文，审查质量高
- **缺点**：按量付费，代码会传到第三方服务器
- **费用**：免费版每月 200 次审查，Pro 版 $15/月

---

## 三、GitLab CI 中的完整集成

### 推荐的流水线配置

```yaml
stages:
  - lint
  - ai-review        # AI 代码审核
  - test
  - build
  - scan
  - deploy-staging
  - deploy-prod

# ========== Lint ==========
lint:
  stage: lint
  image: python:3.11-slim
  script:
    - pip install ruff
    - ruff check .
  rules:
    - if: $CI_MERGE_REQUEST_ID

# ========== AI 代码审核（新增）==========
ai-code-review:
  stage: ai-review
  image: python:3.11-slim
  variables:
    # GitLab 配置
    CI_SERVER_URL: $CI_SERVER_URL
    CI_PROJECT_ID: $CI_PROJECT_ID
    CI_MERGE_REQUEST_IID: $CI_MERGE_REQUEST_IID
    
    # AI 配置（方案 B：自研 Claude API）
    ANTHROPIC_API_KEY: $ANTHROPIC_API_KEY
    AI_REVIEW_TOKEN: $AI_REVIEW_TOKEN
  script:
    - pip install requests
    - python scripts/ai_code_review.py
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: always
  allow_failure: true
  timeout: 5m

# ========== Test ==========
test:
  stage: test
  image: python:3.11-slim
  script:
    - pip install pytest pytest-cov
    - pytest --cov=. --cov-report=term --cov-fail-under=60
  rules:
    - if: $CI_MERGE_REQUEST_ID
    - if: $CI_COMMIT_BRANCH == "develop"

# ========== Build ==========
build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t $IMAGE_NAME:$CI_COMMIT_SHA .
    - docker push $IMAGE_NAME:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
    - if: $CI_COMMIT_BRANCH == "main"

# ========== Scan ==========
scan-image:
  stage: scan
  image: aquasec/trivy:latest
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE_NAME:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
    - if: $CI_COMMIT_BRANCH == "main"

# ========== Deploy ==========
deploy-dev:
  stage: deploy-staging
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/$CI_PROJECT_NAME $CI_PROJECT_NAME=$IMAGE_NAME:$CI_COMMIT_SHA -n dev
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"

deploy-prod:
  stage: deploy-prod
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/$CI_PROJECT_NAME $CI_PROJECT_NAME=$IMAGE_NAME:$CI_COMMIT_SHA -n prod
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  when: manual
```

---

## 四、关键注意事项

### 1. AI 审核的定位

| 定位 | 说明 |
|---|---|
| **辅助工具，非替代** | AI 审核不能替代人工 Review，只能发现 "明显的问题" |
| **允许失败** | `allow_failure: true`，AI 审核失败不阻塞流水线 |
| **可选执行** | 只在 MR 触发时执行，不阻塞日常提交 |

### 2. 数据安全

| 方案 | 代码是否出域 | 风险 |
|---|---|---|
| PR-Agent 自托管 | 不出域 | 低 |
| 自研 Claude API | 出域到 Anthropic | 中（代码片段上传） |
| CodeRabbit.ai | 出域到 CodeRabbit | 高（完整 diff 上传） |
| GitLab Duo | 不出域（企业版） | 低 |

**建议**：
- 敏感代码用 **PR-Agent 自托管** 或 **GitLab Duo**
- 开源项目或不敏感代码可以用 **CodeRabbit.ai** 或 **Claude API**

### 3. 成本控制

| 方案 | 成本 | 控制方式 |
|---|---|---|
| PR-Agent | 免费（自托管） | 无 |
| Claude API | $0.008/1K tokens（Sonnet） | 限制 diff 大小、最大 token 数 |
| CodeRabbit | $15/月（Pro） | 按 MR 数量计费 |

**成本优化技巧**：
- 限制 diff 大小（只审查前 500 行）
- 过滤无关文件（`.md`、`.txt`、配置文件不审查）
- 设置超时（`timeout: 5m`）

### 4. 与人工 Review 的配合

```
开发提交 MR
    ↓
GitLab CI 触发
    ├── Lint（代码风格检查）
    ├── AI 审核（发现明显问题）
    └── 单元测试
        ↓
    AI 审核结果发布到 MR 评论区
    人工 Reviewer 查看 AI 建议
        ↓
    人工 Review + AI 建议结合
        ↓
    合并到 main
```

**建议流程：**
1. AI 审核作为 **第一道防线**，发现明显问题（安全、性能）
2. 人工 Reviewer 关注 **架构设计** 和 **业务逻辑**
3. AI 审核通过的 MR，人工 Reviewer 可以 **更快通过**
4. AI 发现的问题，开发在合并前 **必须修复**

---

## 五、下一步行动

**本周可以做的 3 件事：**

1. **试用 PR-Agent**（30 分钟）
   ```bash
   docker run codiumai/pr-agent:latest
   ```

2. **试用 Claude API 审核**（1 小时）
   - 写一个 `ai_code_review.py` 脚本
   - 在测试 MR 上跑一遍
   - 看效果是否满意

3. **评估 CodeRabbit.ai**（30 分钟）
   - 注册账号
   - 接入一个测试仓库
   - 看审查质量

**试完后告诉我：**
- 哪个方案的审查质量最好？
- 审查结果中有多少是真正有意义的？
- 是否愿意引入到正式流程中？
