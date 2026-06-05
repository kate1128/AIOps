# CI 失败自动根因分析 — 落地实现

> 本文档是 [AI提效计划 - 机会1](../AI提效计划.md) 的内部设计与落地细节。

---

## 设计决策

**为什么不用 Webhook 监听服务？**

常规思路是：GitLab 推 Webhook → 外部 HTTP 服务接收 → 分析 → 回写评论。这需要额外部署一个常驻服务，增加运维负担。

更简单的方案：利用 GitLab CI 内置的 `.post` stage + `when: on_failure`，pipeline 失败时自动触发分析 job，该 job 内调用 GitLab API 拿日志，发给内网 vLLM，结果回写 MR 评论。**无需额外基础设施，pipeline 本身即触发器。**

**为什么用内网 vLLM 而不是 Claude API？**

CI 日志可能包含内部服务名、环境变量、代码片段等敏感信息，不应发往外网。内网 vLLM（Qwen2.5-Coder）与架构治理 Agent 复用同一套服务，额外成本为零。

---

## 完整实现

### 分析脚本 `scripts/ci-failure-analysis.py`

```python
import os
import requests

GITLAB_URL   = os.environ["CI_SERVER_URL"]         # GitLab CI 自动注入
GITLAB_TOKEN = os.environ["GITLAB_API_TOKEN"]      # CI/CD Variable（Masked）
PROJECT_ID   = os.environ["CI_PROJECT_ID"]         # GitLab CI 自动注入
PIPELINE_ID  = os.environ["CI_PIPELINE_ID"]        # GitLab CI 自动注入
MR_IID       = os.environ.get("CI_MERGE_REQUEST_IID")  # 仅 MR pipeline 有值

VLLM_URL = os.environ.get(
    "VLLM_URL",
    "http://vllm-service.ai-infra.svc.cluster.local:8000/v1/chat/completions"
)
MODEL = os.environ.get("CI_ANALYSIS_MODEL", "Qwen2.5-Coder-32B-Instruct")

gitlab_headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}


def get_failed_jobs() -> list:
    resp = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/pipelines/{PIPELINE_ID}/jobs",
        headers=gitlab_headers, timeout=10
    )
    resp.raise_for_status()
    return [j for j in resp.json() if j["status"] == "failed"]


def get_job_log(job_id: int) -> str:
    resp = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/jobs/{job_id}/trace",
        headers=gitlab_headers, timeout=15
    )
    resp.raise_for_status()
    lines = resp.text.splitlines()
    return "\n".join(lines[-200:])  # 只取最后 200 行，避免 token 超限


def analyze(job_name: str, log_tail: str) -> str:
    resp = requests.post(VLLM_URL, json={
        "model": MODEL,
        "messages": [
            {
                "role": "system",
                "content": "你是一位经验丰富的 DevOps 工程师，专门分析 GitLab CI 失败原因。回答简洁，面向开发者，使用中文。"
            },
            {
                "role": "user",
                "content": (
                    f"以下是 GitLab CI Job「{job_name}」的失败日志（最后 200 行）：\n\n"
                    f"```\n{log_tail}\n```\n\n"
                    "请给出：\n"
                    "1. **根因**（一句话）\n"
                    "2. **失败类型**（编译错误 / 测试失败 / 环境问题 / 超时 / 其他）\n"
                    "3. **修复建议**（不超过 3 步，给出具体命令或操作）"
                )
            }
        ]
    }, timeout=60)
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def post_mr_comment(body: str):
    if not MR_IID:
        print("非 MR pipeline，跳过评论")
        return
    requests.post(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/merge_requests/{MR_IID}/notes",
        headers=gitlab_headers,
        json={"body": body},
        timeout=10
    ).raise_for_status()


if __name__ == "__main__":
    failed_jobs = get_failed_jobs()
    if not failed_jobs:
        print("未发现失败 Job")
        exit(0)

    parts = [
        "## 🤖 CI 失败自动分析\n\n"
        "> 由内网 vLLM 生成，仅供参考，请结合实际日志判断。\n"
    ]
    for job in failed_jobs:
        log = get_job_log(job["id"])
        analysis = analyze(job["name"], log)
        job_url = job.get("web_url", "")
        parts.append(f"### ❌ Job: [`{job['name']}`]({job_url})\n\n{analysis}\n\n---")

    post_mr_comment("\n".join(parts))
    print("分析完成，已发 MR 评论")
```

### GitLab CI 配置

在各仓库的 `.gitlab-ci.yml` 末尾追加，或提取到公共 CI 模板通过 `include` 复用：

```yaml
ci-failure-analysis:
  stage: .post          # GitLab 内置最后阶段，无需声明
  when: on_failure      # 只在有 job 失败时触发
  image: python:3.11-slim
  script:
    - pip install requests -q
    - python scripts/ci-failure-analysis.py
  variables:
    GITLAB_API_TOKEN: $GITLAB_API_TOKEN
  rules:
    - if: $CI_MERGE_REQUEST_IID   # 只对 MR pipeline 生效
      when: on_failure
```

> `rules` 中限定 `CI_MERGE_REQUEST_IID` 存在，避免 main/develop 分支 pipeline 失败时因无 MR 目标而报错。

### CI/CD Variable 配置

在 GitLab 项目 → Settings → CI/CD → Variables 中添加：

| 变量名 | 类型 | 说明 |
|--------|------|------|
| `GITLAB_API_TOKEN` | Masked | 有 `api` 权限的 Project Access Token |
| `VLLM_URL` | 可选 | 默认已写入脚本，覆盖时填写 |
| `CI_ANALYSIS_MODEL` | 可选 | 默认 `Qwen2.5-Coder-32B-Instruct`，资源紧张时改为 7B |

---

## MR 评论效果示例

```
🤖 CI 失败自动分析

> 由内网 vLLM 生成，仅供参考，请结合实际日志判断。

❌ Job: unit-test

**根因**：UserServiceTest.testCreateUser 断言失败，期望 HTTP 201 但实际返回 400。

**失败类型**：测试失败

**修复建议**：
1. 检查 `UserController.createUser` 的参数校验，`email` 字段新增了格式校验
2. 更新测试请求体，补充合法 email：`"email": "test@example.com"`
3. 本地执行 `./mvnw test -Dtest=UserServiceTest` 验证
```

---

## 复用到多仓库

如果有多个仓库需要接入，推荐在 GitLab 创建一个公共 CI 模板仓库，通过 `include` 引用：

```yaml
# 各仓库的 .gitlab-ci.yml
include:
  - project: 'devops/ci-templates'
    ref: main
    file: '/templates/ci-failure-analysis.yml'
```

模板仓库统一维护脚本和 job 定义，各业务仓库只需一行 `include`。

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [AI提效计划.md](../AI提效计划.md) | 整体方案和实施路径 |
| [02-架构治理/工具分析/TechDebtAgent.md](../../02-架构治理/工具分析/TechDebtAgent.md) | 复用同一套 vLLM 的 Agent 实现参考 |
