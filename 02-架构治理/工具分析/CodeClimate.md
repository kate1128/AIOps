# CodeClimate Quality — 可维护性评分与架构债可视化

> 用字母评分（A-F）直观量化每个文件/模块的可维护性，开发者友好，适合快速建立代码质量文化。

---

## 是什么

CodeClimate Quality 是一个代码质量分析平台，通过分析圈复杂度、重复代码、函数长度等维度，对每个文件给出 A-F 的可维护性评分，并以「技术债时间」量化修复成本。核心分析引擎（`codeclimate` CLI）完全开源（MIT），支持在 CI 中本地运行，无需购买 SaaS 订阅。

---

## 核心能力

| 维度 | 说明 |
|------|------|
| **可维护性评分** | 每个文件/函数 A-F 评级，直观反映代码健康度 |
| **技术债时间** | 量化修复所有问题需要的估算时间（分钟/小时）|
| **圈复杂度检测** | 函数逻辑分支过多时告警，驱动重构 |
| **重复代码检测** | 跨文件重复代码块识别，推动抽象复用 |
| **趋势分析** | 按 PR/时间轴展示质量变化趋势，防止债务悄悄积累 |
| **GitLab MR 集成** | 在 Merge Request 中直接展示新增问题 |

---

## 与 SmartVision 现状的契合

- 架构债无量化，修复优先级靠主观判断
- 不知道哪些模块最难维护，新成员改动时没有任何复杂度提示
- 需要一种能向非技术 stakeholder 解释技术债的可视化方式

**CodeClimate 可以直接解决**：用 A-F 评分让"架构债"变得可视化，让 PM 也能理解哪个模块需要重构排期。

---

## GitLab CI 集成示例

```yaml
code-quality:
  stage: analysis
  image: docker:stable
  services:
    - docker:dind
  variables:
    DOCKER_DRIVER: overlay2
  script:
    - docker run
        --env CODECLIMATE_CODE="$PWD"
        --volume "$PWD":/code
        --volume /var/run/docker.sock:/var/run/docker.sock
        --volume /tmp/cc:/tmp/cc
        codeclimate/codeclimate analyze -f json > gl-code-quality-report.json
  artifacts:
    reports:
      codequality: gl-code-quality-report.json  # GitLab 原生支持在 MR 中展示
    paths:
      - gl-code-quality-report.json
    expire_in: 1 week
```

> GitLab Ultimate 可在 MR 界面直接展示 Code Quality 差异；CE/EE 版可通过下载 Artifact 查阅，或对接 SonarQube 的 GitLab 集成。

---

## 本地快速扫描

```bash
# 使用 Docker，无需安装任何额外工具
docker run --interactive --tty --rm \
  --env CODECLIMATE_CODE="$PWD" \
  --volume "$PWD":/code \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume /tmp/cc:/tmp/cc \
  codeclimate/codeclimate analyze
```

---

## 与 SonarQube 对比

| 对比项 | CodeClimate | SonarQube |
|--------|-------------|-----------|
| 部署方式 | CLI 本地运行（开源）/ 云 SaaS | 自托管（推荐）|
| 上手成本 | ⚡ 极低，无需服务器 | ⚠️ 需配置服务器 + PostgreSQL |
| 开发者友好度 | ✅ A-F 评分直观易懂 | 需要了解各类指标含义 |
| 安全扫描（SAST）| ⚠️ 非核心，基础支持 | ✅ 核心能力 |
| 技术债细粒度 | ✅ 文件/函数级别 | ✅ 更细，支持行级别 |
| 向非技术展示 | ✅ 字母评分一目了然 | ⚠️ 需要定制报表 |
| **推荐场景** | 补充 SonarQube，提升开发者感知 | 主力质量和安全分析 |

---

## 实践建议

1. **作为 SonarQube 的补充而非替代**：SonarQube 做深度分析，CodeClimate 提供轻量级 MR 反馈
2. **关注趋势不关注绝对值**：初次接入时出现大量 D/F 级文件是正常的，关键是每个迭代趋势向好
3. **驱动重构排期**：将「F 级文件列表」作为架构债管理文档中的具体条目，逐季度消减
4. **资源有限时跳过**：只有一个人力投入工具体系时，优先上 SonarQube，CodeClimate 可后期补充

---

## 推荐决策

**作为 SonarQube 的开发者体验补充层**，不作为独立主工具：
- 在 CI 输出 `gl-code-quality-report.json`，让开发者在 MR 界面感知复杂度变化
- 用字母评分向管理层、产品经理解释技术债优先级

---

## GitHub 信息

- 开源状态：CLI 开源（MIT），SaaS 商业
- 仓库地址：https://github.com/codeclimate/codeclimate
- Star：2.8k（统计日期：2026-05-29）
