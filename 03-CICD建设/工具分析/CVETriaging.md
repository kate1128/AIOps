# CVE 漏洞智能定级 — 落地实现

> 本文档是 [AI提效计划 - 机会3](../AI提效计划.md) 的内部设计与落地细节。

---

## 设计思路

Trivy 本身只做"有没有这个 CVE"的判断，不考虑当前部署环境——所有 CRITICAL 都标红，导致 ~70% 是实际不可利用的误报。

LLM 补充的是**上下文判断**：
- 这个漏洞的攻击路径需要什么前提条件？
- SmartVision 的 K8s 环境是否满足这些前提？
- 是否有网络隔离/WAF 等缓解措施已经存在？

通过这层过滤，把"需要立即处理"的 CVE 从全集中挑出来。

**安全原则**：LLM 只做降级（把误报降为低风险），不做升级。人工安全工程师有权手动提升任何 CVE 等级，AI 判断仅为参考。

---

## 完整实现

### 定级脚本 `scripts/cve-triage.py`

```python
import os
import json
import requests

VLLM_URL = os.environ.get(
    "VLLM_URL",
    "http://vllm-service.ai-infra.svc.cluster.local:8000/v1/chat/completions"
)
MODEL = os.environ.get("CVE_TRIAGE_MODEL", "Qwen2.5-Coder-32B-Instruct")
TRIVY_REPORT = os.environ.get("TRIVY_REPORT", "trivy-report.json")

# 描述当前部署环境，用于 LLM 上下文判断
# 根据实际情况修改
DEPLOY_CONTEXT = """
- 容器化部署在 K8s 集群（Alibaba Cloud ACK + 自托管）
- 所有服务仅通过 APISIX 网关对外暴露，内部服务不直接对公网开放
- 集群内网络策略：Pod 间通信受 NetworkPolicy 限制
- WAF：APISIX 内置基础 WAF 规则
- 运行用户：非 root 容器（securityContext.runAsNonRoot: true）
"""


def load_trivy_cves(report_path: str) -> list:
    with open(report_path) as f:
        report = json.load(f)
    cves = []
    for result in report.get("Results", []):
        for vuln in result.get("Vulnerabilities", []):
            if vuln.get("Severity") in ("CRITICAL", "HIGH"):
                cves.append({
                    "id": vuln["VulnerabilityID"],
                    "pkg": vuln.get("PkgName", ""),
                    "severity": vuln["Severity"],
                    "score": vuln.get("CVSS", {}).get("nvd", {}).get("V3Score", "N/A"),
                    "description": vuln.get("Description", "")[:300],
                    "attack_vector": vuln.get("CVSS", {}).get("nvd", {}).get("V3Vector", ""),
                })
    return cves


def triage_cve(cve: dict) -> dict:
    resp = requests.post(VLLM_URL, json={
        "model": MODEL,
        "messages": [
            {
                "role": "system",
                "content": "你是一位云原生安全专家，根据部署环境分析 CVE 的实际可利用性。回答简洁，使用中文。"
            },
            {
                "role": "user",
                "content": (
                    f"CVE ID: {cve['id']}\n"
                    f"影响包: {cve['pkg']}\n"
                    f"原始等级: {cve['severity']}\n"
                    f"CVSS 分: {cve['score']}\n"
                    f"攻击向量: {cve['attack_vector']}\n"
                    f"描述: {cve['description']}\n\n"
                    f"当前部署环境:\n{DEPLOY_CONTEXT}\n\n"
                    "请判断：\n"
                    "1. 攻击路径在此环境中是否可达（一句话）\n"
                    "2. 实际风险等级：🔴立即修复 / 🟡计划修复 / ⚪可接受风险\n"
                    "3. 修复建议（一句话，如升级版本号或配置缓解）"
                )
            }
        ]
    }, timeout=60)
    resp.raise_for_status()
    analysis = resp.json()["choices"][0]["message"]["content"]
    return {**cve, "analysis": analysis}


def generate_report(results: list) -> str:
    immediate = [r for r in results if "🔴" in r["analysis"]]
    planned   = [r for r in results if "🟡" in r["analysis"]]
    accepted  = [r for r in results if "⚪" in r["analysis"]]

    lines = [
        "# CVE 智能定级报告\n",
        f"总计 {len(results)} 个 HIGH/CRITICAL CVE，AI 分析结果：\n",
        f"- 🔴 立即修复：{len(immediate)} 个",
        f"- 🟡 计划修复：{len(planned)} 个",
        f"- ⚪ 可接受风险：{len(accepted)} 个\n",
        "> AI 仅做降级判断，安全工程师有权手动提升任何 CVE 等级。\n",
        "---\n",
    ]

    for label, group in [("🔴 立即修复", immediate), ("🟡 计划修复", planned), ("⚪ 可接受风险", accepted)]:
        if group:
            lines.append(f"## {label}\n")
            for r in group:
                lines.append(f"### {r['id']} ({r['pkg']}, 原始:{r['severity']}, CVSS:{r['score']})\n")
                lines.append(r["analysis"] + "\n")

    return "\n".join(lines)


if __name__ == "__main__":
    print(f"加载 Trivy 报告: {TRIVY_REPORT}")
    cves = load_trivy_cves(TRIVY_REPORT)
    print(f"发现 {len(cves)} 个 HIGH/CRITICAL CVE，开始分析...")

    results = []
    for cve in cves:
        print(f"  分析 {cve['id']}...")
        results.append(triage_cve(cve))

    report = generate_report(results)
    with open("cve-triage-report.md", "w") as f:
        f.write(report)
    print("定级完成，报告已写入 cve-triage-report.md")
```

### GitLab CI 配置

```yaml
trivy-scan:
  stage: test
  image: aquasec/trivy:latest
  script:
    - trivy image --format json --output trivy-report.json $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  artifacts:
    paths:
      - trivy-report.json

cve-triage:
  stage: test
  needs: [trivy-scan]           # 等 Trivy 扫完再分析
  image: python:3.11-slim
  script:
    - pip install requests -q
    - python scripts/cve-triage.py
  artifacts:
    paths:
      - cve-triage-report.md    # 可在 GitLab Pipeline 页面下载
  allow_failure: true
```

---

## 报告效果示例

```markdown
# CVE 智能定级报告

总计 18 个 HIGH/CRITICAL CVE，AI 分析结果：
- 🔴 立即修复：2 个
- 🟡 计划修复：5 个
- ⚪ 可接受风险：11 个

---

## 🔴 立即修复

### CVE-2021-44228 (log4j-core, 原始:CRITICAL, CVSS:10.0)
攻击路径可达：java-backend 使用 log4j 2.14.0，JNDI lookup 在 HTTP 请求头中可触发，APISIX 未过滤 `${jndi:` 前缀。
🔴 立即修复
升级 log4j-core 至 2.17.1+，或添加 JVM 参数 `-Dlog4j2.formatMsgNoLookups=true`。

## ⚪ 可接受风险

### CVE-2023-44487 (nghttp2, 原始:HIGH, CVSS:7.5)
攻击路径不可达：HTTP/2 Rapid Reset 攻击需要直接访问 HTTP/2 端点，SmartVision 所有流量经 APISIX 终止 TLS，内部服务不对外暴露 HTTP/2。
⚪ 可接受风险
可在下次依赖升级时顺带更新，无需立即处理。
```

---

## 调整部署环境描述

脚本中 `DEPLOY_CONTEXT` 变量是 LLM 判断可达性的关键依据，需根据实际情况维护：

```python
DEPLOY_CONTEXT = """
- 容器化部署在 K8s 集群...
- 对外暴露的端口：...
- WAF 规则覆盖：...
- 特殊网络限制：...
"""
```

建议将此信息维护在一个单独文件（如 `deploy-context.txt`），脚本从文件读取，方便后续更新。

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [AI提效计划.md](../AI提效计划.md) | 整体方案和实施路径 |
| [03-安全扫描/](../03-安全扫描/) | Trivy 接入规范 |
