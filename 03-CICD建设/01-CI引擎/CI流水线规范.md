# CI 引擎

持续集成（CI）负责在代码提交后自动完成**构建、测试、质量检查**，产出可部署的制品（JAR / Docker 镜像 / Helm Chart），是整个 CI/CD 流水线的起点。

---

## 当前状态

| 项目 | 状态 | 说明 |
|---|---|---|
| CI 引擎 | ✅ GitLab CI | 已在用，流水线已运行 |
| Runner | 🟡 待规范 | Runner 配置和 Executor 类型需统一 |
| 分支策略 | 🟡 待规范 | dev/pre/main 分支触发规则需明确 |
| 测试覆盖率门禁 | ❌ 未配置 | 无最低覆盖率要求 |
| 代码质量门禁 | ❌ 未配置 | 无 SAST/Lint 硬性拦截 |

---

## 流水线触发规则

| 触发条件 | 运行阶段 | 说明 |
|---|---|---|
| push 到任意分支 | lint + test | 快速反馈，不构建镜像 |
| push 到 `dev` 分支 | lint + test + build + push | 自动构建 dev 镜像 |
| push 到 `main` 分支 | lint + test + build + push + 触发 CD | 完整流水线 |
| MR 创建/更新 | lint + test | 合并前必须通过 |
| 手动触发 | 全部 | 用于临时构建 |

---

## 标准流水线阶段

```
代码 push / MR 创建
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│  Stage 1: lint                                           │
│  ├── 代码风格检查（ESLint / Checkstyle / golangci-lint） │
│  └── 失败 → 阻断，不进入下一阶段                         │
└──────────────────────────────────────────────────────────┘
        │ ✅
        ▼
┌──────────────────────────────────────────────────────────┐
│  Stage 2: test                                           │
│  ├── 单元测试                                            │
│  ├── 测试覆盖率报告（目标 > 60%）                         │
│  └── 失败 → 阻断，测试报告上传 GitLab Artifacts          │
└──────────────────────────────────────────────────────────┘
        │ ✅（仅 dev/main 分支继续）
        ▼
┌──────────────────────────────────────────────────────────┐
│  Stage 3: build                                          │
│  ├── Java: mvn package → 生成 JAR                        │
│  ├── 容器服务: docker build → 生成镜像                   │
│  └── 镜像 Tag：dev-{commit_sha} / {semver}               │
└──────────────────────────────────────────────────────────┘
        │ ✅
        ▼
┌──────────────────────────────────────────────────────────┐
│  Stage 4: push                                           │
│  ├── docker push → Harbor                               │
│  └── JAR → Harbor Generic Package / MinIO               │
└──────────────────────────────────────────────────────────┘
        │ ✅（进入安全扫描，见 03-安全扫描/）
        ▼
     制品就绪，等待 CD 部署
```

---

## Runner 规划

| Runner 类型 | 用途 | Executor | 说明 |
|---|---|---|---|
| 通用 Runner | lint / test / build | Docker | 每个 Job 独立容器，环境干净 |
| GPU Runner | AI 模型测试 / 推理验证 | Shell | 需要访问 GPU 设备，暂用 Shell |
| K8s Runner | 弹性扩缩（未来）| Kubernetes | Job 以 K8s Pod 运行，按需创建 |

```yaml
# .gitlab-ci.yml Runner 绑定示例
build-java:
  tags:
    - docker          # 指定用 Docker Executor 的 Runner
  image: maven:3.8-openjdk-17

build-gpu:
  tags:
    - gpu-runner      # 指定有 GPU 的 Runner
```

---

## 分支策略与流水线关系

```
feature/*  →  push  →  lint + test（快速反馈）
               │
               ▼ MR → dev
dev        →  push  →  lint + test + build + push harbor（dev-{sha}）
               │
               ▼ MR → main（需 Code Review 通过）
main       →  push  →  完整流水线 + 触发 CD 部署 pre 环境
               │
               ▼ 手动打 Tag（vX.Y.Z）
tag        →  push  →  构建正式版本镜像，部署生产
```

---

## 关键 `.gitlab-ci.yml` 片段

```yaml
stages:
  - lint
  - test
  - build
  - push

variables:
  HARBOR_URL: harbor.internal
  IMAGE_NAME: $HARBOR_URL/platform/$CI_PROJECT_NAME

lint:
  stage: lint
  image: python:3.11
  script:
    - pip install flake8 && flake8 .
  only:
    - merge_requests
    - dev
    - main

test:
  stage: test
  script:
    - pytest --cov=. --cov-report=xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

build:
  stage: build
  script:
    - docker build -t $IMAGE_NAME:$CI_COMMIT_SHORT_SHA .
  only:
    - dev
    - main
    - tags

push:
  stage: push
  script:
    - docker login $HARBOR_URL -u $HARBOR_USER -p $HARBOR_PASS
    - docker push $IMAGE_NAME:$CI_COMMIT_SHORT_SHA
    # main 分支额外打 latest
    - |
      if [ "$CI_COMMIT_BRANCH" = "main" ]; then
        docker tag $IMAGE_NAME:$CI_COMMIT_SHORT_SHA $IMAGE_NAME:latest
        docker push $IMAGE_NAME:latest
      fi
  only:
    - dev
    - main
    - tags
```

## 工具对比

| 维度 | GitLab CI ✅ | Jenkins | GitHub Actions | Tekton |
|---|---|---|---|---|
| **代码仓库** | 一体化（自带）| 独立，需集成 | GitHub 一体化 | 独立 |
| **配置方式** | YAML（`.gitlab-ci.yml`）| Groovy / Declarative | YAML | YAML（K8s CRD）|
| **Runner/Agent** | GitLab Runner | Jenkins Agent | GitHub 托管 / 自托管 | K8s Pod |
| **云原生** | Runner on K8s | Agent on K8s | 托管 | ✅ K8s 原生 |
| **插件生态** | 内置功能为主 | ✅ 1800+ 插件 | Actions 市场 | 社区 Catalog |
| **复杂流水线** | 中（DAG stages）| ✅ 强（共享库）| 中 | ✅ 强（Task/Pipeline DAG）|
| **私有化部署** | ✅ 支持 | ✅ 支持 | ❌ 需自托管 | ✅ 支持 |
| **运维成本** | 低 | 高（升级/插件维护）| 零（托管）| 中（K8s 依赖）|
| **学习曲线** | 低 | 高 | 低 | 高 |
| **国内使用** | ✅ 广泛 | ✅ 广泛 | 🟡 需翻墙 | 🟡 较少 |

### 选型结论

| 工具 | 结论 | 原因 |
|---|---|---|
| **GitLab CI** | ✅ 已采用，继续深化 | 代码仓库已在 GitLab，一体化成本最低 |
| **Jenkins** | ❌ 不引入 | 运维成本高，Groovy 流水线维护难，GitLab CI 已满足需求 |
| **GitHub Actions** | ❌ 不引入 | 代码不在 GitHub，迁移成本高且网络访问受限 |
| **Tekton** | ❌ 暂不引入 | K8s 原生但复杂度高，团队规模不匹配，当前 GitLab CI 够用 |

---

## 相关文档

| 文档 | 说明 |
|---|---|
| [GitLabCI.md](GitLabCI.md) | GitLab CI 详细功能和配置说明 |
| [Jenkins.md](Jenkins.md) | Jenkins 分析（不采用原因）|
| [GitHubActions.md](GitHubActions.md) | GitHub Actions 分析（不采用原因）|
| [Tekton.md](Tekton.md) | Tekton 分析（不采用原因）|
| [../02-制品仓库/制品管理规范.md](../02-制品仓库/制品管理规范.md) | 制品存储规范（CI 产出物的去处）|
| [../03-安全扫描/安全扫描规范.md](../03-安全扫描/安全扫描规范.md) | 安全扫描流程（CI 完成后的下一步）|
