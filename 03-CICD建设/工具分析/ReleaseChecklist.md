# 发布 Checklist 自动化 — 落地实现

> 本文档是 [AI提效计划 - 机会4](../AI提效计划.md) 的内部设计与落地细节。

---

## 设计思路

发布前检查分两类：

| 类型 | 示例 | 处理方式 |
|------|------|---------|
| **可自动验证** | DB 迁移是否在 pre 跑过、ConfigMap 是否同步、MR 列表 | 脚本自动检查，失败则阻断发布 |
| **需人工判断** | 灰度比例是否合适、业务影响范围 | LLM 生成摘要，人工在飞书确认 |

脚本在 `stage: deploy` 前运行，所有自动检查项通过后才触发飞书审批，审批通过后 ArgoCD 执行实际部署。

---

## 完整实现

### Preflight 检查脚本 `scripts/release-preflight.py`

```python
import os
import sys
import json
import requests

GITLAB_URL   = os.environ["CI_SERVER_URL"]
GITLAB_TOKEN = os.environ["GITLAB_API_TOKEN"]
PROJECT_ID   = os.environ["CI_PROJECT_ID"]
CURRENT_TAG  = os.environ["CI_COMMIT_TAG"]       # 当前发布 tag，如 v2.1.0
PREV_TAG     = os.environ.get("PREV_RELEASE_TAG", "")  # 上次发布 tag，手动配置或脚本获取
FEISHU_WEBHOOK = os.environ["FEISHU_RELEASE_WEBHOOK"]
VLLM_URL = os.environ.get(
    "VLLM_URL",
    "http://vllm-service.ai-infra.svc.cluster.local:8000/v1/chat/completions"
)
MODEL = os.environ.get("RELEASE_MODEL", "Qwen2.5-Coder-32B-Instruct")

gitlab_headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}
checks_passed = []
checks_failed = []


def check(name: str, ok: bool, detail: str = ""):
    if ok:
        checks_passed.append(f"✅ {name}")
    else:
        checks_failed.append(f"❌ {name}" + (f"：{detail}" if detail else ""))


def get_mrs_between_tags() -> list:
    """获取两个 tag 之间合并的 MR 列表"""
    if not PREV_TAG:
        return []
    resp = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/repository/compare",
        params={"from": PREV_TAG, "to": CURRENT_TAG},
        headers=gitlab_headers, timeout=15
    )
    resp.raise_for_status()
    commits = resp.json().get("commits", [])
    # 从 commit message 提取 MR 编号
    import re
    mr_ids = set()
    for c in commits:
        matches = re.findall(r"See merge request.*!(\d+)", c["message"])
        mr_ids.update(matches)
    return list(mr_ids)


def get_mr_titles(mr_ids: list) -> list:
    titles = []
    for mr_id in mr_ids[:20]:  # 最多取 20 个
        resp = requests.get(
            f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/merge_requests/{mr_id}",
            headers=gitlab_headers, timeout=10
        )
        if resp.ok:
            mr = resp.json()
            titles.append(f"MR !{mr_id}: {mr['title']}")
    return titles


def check_db_migration():
    """检查 pre 环境是否已运行 DB 迁移（通过检查特定 CI job 状态）"""
    # 查找 pre 环境最近一次 pipeline 中 db-migrate job 的状态
    resp = requests.get(
        f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/pipelines",
        params={"ref": "pre", "status": "success", "per_page": 1},
        headers=gitlab_headers, timeout=10
    )
    if resp.ok and resp.json():
        pipeline_id = resp.json()[0]["id"]
        jobs_resp = requests.get(
            f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/pipelines/{pipeline_id}/jobs",
            headers=gitlab_headers, timeout=10
        )
        if jobs_resp.ok:
            for job in jobs_resp.json():
                if "migrate" in job["name"].lower() and job["status"] == "success":
                    check("DB 迁移已在 pre 验证", True)
                    return
    check("DB 迁移已在 pre 验证", False, "未找到 pre 环境成功的 migrate job")


def generate_release_summary(mr_titles: list) -> str:
    mr_list = "\n".join(mr_titles) if mr_titles else "（无法获取 MR 列表）"
    resp = requests.post(VLLM_URL, json={
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "你是一位 DevOps 工程师，根据 MR 列表生成发布摘要，供发布审批使用。使用中文，简洁明了。"},
            {"role": "user", "content": (
                f"版本：{CURRENT_TAG}\n"
                f"本次包含的 MR：\n{mr_list}\n\n"
                "请生成发布摘要，包含：\n"
                "1. 本次主要变更（按新功能/Bug修复/其他分类）\n"
                "2. 是否包含破坏性变更（判断依据：MR 标题中是否有 breaking/重构/删除接口等关键词）\n"
                "3. 预计影响评估（高/中/低）及理由\n"
                "4. 建议发布窗口"
            )}
        ]
    }, timeout=60)
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def send_feishu_approval(summary: str, mr_titles: list):
    checks_section = "\n".join(checks_passed + checks_failed)
    mr_section = "\n".join(mr_titles[:10]) if mr_titles else "无"

    requests.post(FEISHU_WEBHOOK, json={
        "msg_type": "interactive",
        "card": {
            "header": {"title": {"tag": "plain_text", "content": f"🚀 发布审批 {CURRENT_TAG}"}},
            "elements": [
                {"tag": "div", "text": {"tag": "lark_md", "content": f"**自动检查结果**\n{checks_section}"}},
                {"tag": "hr"},
                {"tag": "div", "text": {"tag": "lark_md", "content": f"**本次 MR**\n{mr_section}"}},
                {"tag": "hr"},
                {"tag": "div", "text": {"tag": "lark_md", "content": f"**AI 发布摘要**\n{summary}"}},
            ]
        }
    }, timeout=10).raise_for_status()


if __name__ == "__main__":
    # 自动检查项
    check_db_migration()
    # 可继续添加其他检查...
    # check("ConfigMap 已同步", check_configmap_sync())

    mr_ids = get_mrs_between_tags()
    mr_titles = get_mr_titles(mr_ids)
    check("MR 列表获取成功", len(mr_titles) > 0 or not PREV_TAG,
          "未配置 PREV_RELEASE_TAG 环境变量")

    if checks_failed:
        print("❌ 以下检查项未通过，发布中止：")
        for f in checks_failed:
            print(f"  {f}")
        sys.exit(1)

    # 生成摘要并推送飞书审批
    print("✅ 所有检查通过，生成发布摘要...")
    summary = generate_release_summary(mr_titles)
    send_feishu_approval(summary, mr_titles)
    print("飞书审批已发送，等待人工确认")
```

### GitLab CI 配置

```yaml
release-preflight:
  stage: pre-deploy
  image: python:3.11-slim
  script:
    - pip install requests -q
    - python scripts/release-preflight.py
  variables:
    GITLAB_API_TOKEN: $GITLAB_API_TOKEN
    FEISHU_RELEASE_WEBHOOK: $FEISHU_RELEASE_WEBHOOK
    PREV_RELEASE_TAG: $PREV_RELEASE_TAG   # 在 Pipeline 触发时手动填写，或从 API 自动获取
  rules:
    - if: $CI_COMMIT_TAG    # 只在打 Tag 时触发

deploy-production:
  stage: deploy
  needs: [release-preflight]  # 依赖 preflight 通过
  script:
    - argocd app sync smartvision-prod --revision $CI_COMMIT_TAG
  rules:
    - if: $CI_COMMIT_TAG
      when: manual          # 人工在飞书确认后手动触发
```

### CI/CD Variable 配置

| 变量名 | 说明 |
|--------|------|
| `GITLAB_API_TOKEN` | 有 `api` 权限的 Token，Masked |
| `FEISHU_RELEASE_WEBHOOK` | 发布审批飞书群的 Bot Webhook，Masked |
| `PREV_RELEASE_TAG` | 上次发布的 Tag，用于对比 MR 列表（可在 Pipeline 触发时填写）|

---

## 飞书审批消息示例

```
🚀 发布审批 v2.1.0

自动检查结果
✅ DB 迁移已在 pre 验证
✅ MR 列表获取成功

本次 MR
MR !234: feat: AI 知识库检索优化
MR !235: fix: 文档上传超时问题
MR !236: chore: 升级 Spring Boot 3.2.1

AI 发布摘要
本次主要变更：
- 新功能：AI 知识库向量检索改用 HNSW 索引，检索速度提升约 40%
- Bug 修复：修复大文件上传时 multipart 超时问题
- 其他：Spring Boot 升级，无 breaking change

破坏性变更：无
预计影响：低（无核心接口变更，功能为优化型）
建议发布窗口：工作日 10:00-16:00
```

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [AI提效计划.md](../AI提效计划.md) | 整体方案和实施路径 |
| [05-发布治理/](../05-发布治理/) | 发布流程规范 |
