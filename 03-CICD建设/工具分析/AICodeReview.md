# AI Code Review 辅助 — 落地实现

> 本文档是 [AI提效计划 - 机会2](../AI提效计划.md) 的内部设计与落地细节。

---

## 设计决策

**工具选型：自建 vs GitLab Duo**

| 方式 | 优点 | 缺点 |
|------|------|------|
| **GitLab Duo**（付费）| 原生集成，1天接入，无需维护 | $19/人/月，需联网，代码发送 GitLab 云端 |
| **自建（内网 vLLM）** | 代码不出内网，复用已有模型，零额外费用 | 需开发维护脚本（约1周）|

考虑到代码安全性（内网项目代码不出公网）和已有 vLLM 基础设施，**推荐自建方案**。

---

## 完整实现

### 分析脚本 `scripts/ai-code-review.py`

```python
import os
import requests

GITLAB_URL    = os.environ["CI_SERVER_URL"]
GITLAB_TOKEN  = os.environ["GITLAB_API_TOKEN"]
PROJECT_ID    = os.environ["CI_PROJECT_ID"]
MR_IID        = os.environ["CI_MERGE_REQUEST_IID"]
VLLM_URL      = os.environ.get(
    "VLLM_URL",
    "http://vllm-service.ai-infra.svc.cluster.local:8000/v1/chat/completions"
)
MODEL = os.environ.get("CODE_REVIEW_MODEL", "Qwen2.5-Coder-32B-Instruct")
MAX_COMMENTS  = int(os.environ.get("MAX_REVIEW_COMMENTS", "5"))  # 防止噪音过多

gitlab_headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}


def get_mr_diff() -> str:
    resp = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/merge_requests/{MR_IID}/diffs",
        headers=gitlab_headers, timeout=15
    )
    resp.raise_for_status()
    diffs = resp.json()
    # 只取前 300 行 diff，避免超出 context window
    all_diff = "\n".join(d.get("diff", "") for d in diffs)
    return "\n".join(all_diff.splitlines()[:300])


def get_mr_title() -> str:
    resp = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/merge_requests/{MR_IID}",
        headers=gitlab_headers, timeout=10
    )
    resp.raise_for_status()
    return resp.json().get("title", "")


def review(title: str, diff: str) -> str:
    resp = requests.post(VLLM_URL, json={
        "model": MODEL,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是一位严格但友善的 Code Reviewer，负责审查代码变更。\n"
                    "只指出真正重要的问题，不做无意义的吹毛求疵。\n"
                    "最多给出 5 条评论，按优先级排序。使用中文。"
                )
            },
            {
                "role": "user",
                "content": (
                    f"MR 标题：{title}\n\n"
                    f"代码变更（diff）：\n```\n{diff}\n```\n\n"
                    "请检查以下方面，只在发现问题时输出：\n"
                    "1. 硬编码的密钥/密码/Token（安全）\n"
                    "2. SQL 拼接注入风险（安全）\n"
                    "3. 未关闭的资源（文件/连接/流）\n"
                    "4. 明显的空指针/越界风险\n"
                    "5. 新增功能缺少对应测试\n\n"
                    "同时生成一行 MR 摘要（变更了什么）。\n\n"
                    "输出格式：\n"
                    "**MR 摘要**：xxx\n\n"
                    "**问题列表**（无问题则写"未发现明显问题"）：\n"
                    "- [优先级:高/中/低] 问题描述（文件名:行号）"
                )
            }
        ]
    }, timeout=90)
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def post_comment(body: str):
    requests.post(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/merge_requests/{MR_IID}/notes",
        headers=gitlab_headers,
        json={"body": f"## 🤖 AI Code Review\n\n> 由内网 vLLM 生成，仅供参考，Reviewer 请以实际代码为准。\n\n{body}"},
        timeout=10
    ).raise_for_status()


if __name__ == "__main__":
    title = get_mr_title()
    diff = get_mr_diff()
    review_result = review(title, diff)
    post_comment(review_result)
    print("AI Code Review 完成")
```

### GitLab CI 配置

```yaml
ai-code-review:
  stage: test
  image: python:3.11-slim
  script:
    - pip install requests -q
    - python scripts/ai-code-review.py
  variables:
    GITLAB_API_TOKEN: $GITLAB_API_TOKEN
  rules:
    - if: $CI_MERGE_REQUEST_IID   # 只对 MR pipeline 触发
  allow_failure: true             # Review 失败不阻塞 MR 合并
```

### CI/CD Variable 配置

| 变量名 | 说明 |
|--------|------|
| `GITLAB_API_TOKEN` | 有 `api` 权限的 Project Access Token，Masked |
| `MAX_REVIEW_COMMENTS` | 可选，默认 5，控制评论数量防止噪音 |

---

## 评论效果示例

```
🤖 AI Code Review

> 由内网 vLLM 生成，仅供参考，Reviewer 请以实际代码为准。

**MR 摘要**：新增用户邀请功能，包含邮件发送逻辑和数据库写入。

**问题列表**：
- [优先级:高] `UserInviteService.java:42` 中 SQL 使用字符串拼接，存在注入风险，建议改为 PreparedStatement
- [优先级:中] `EmailSender.java:78` 中 SMTP 密码硬编码为字符串字面量，应从环境变量读取
- [优先级:低] `InviteController.java` 新增了 POST /api/invite 接口，未见对应的单元测试
```

---

## 注意事项

**防止评论疲劳**：`MAX_REVIEW_COMMENTS` 限制为 5 条，确保 Reviewer 不会因 AI 噪音而忽略所有评论。

**diff 长度限制**：脚本取前 300 行 diff，超大 MR 建议拆分提交；若需完整审查可调整参数，但注意模型 context window 限制（32K tokens）。

**人工优先原则**：AI Review 在 `stage: test` 运行，与其他 CI job 并行，不阻塞人工 Review 开始。

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [AI提效计划.md](../AI提效计划.md) | 整体方案和实施路径 |
| [CIFailureAnalysis.md](./CIFailureAnalysis.md) | CI 失败分析，复用同一套 vLLM |
