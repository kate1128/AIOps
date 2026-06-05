# 持续部署

持续部署（CD）负责将安全扫描通过的制品**自动部署到目标环境**。因为你们的服务以多种方式运行（K8s Pod、Docker 容器、二进制进程），不同部署方式有不同的工具链和操作规范。

---

## 当前状态

| 部署方式 | 涉及服务 | 当前状态 | 目标状态 |
| --- | --- | --- | --- |
| **K8s + ArgoCD** | AI 推理服务、核心后端 | 🟡 GitLab CI 手动 kubectl | ✅ ArgoCD GitOps |
| **Docker Compose** | 部分过渡期服务 | ✅ 已有脚本，不规范 | 🟡 规范化，逐步迁 K8s |
| **二进制（SSH）** | Java 服务等 | ✅ 已有脚本，不规范 | 🟡 规范化，逐步容器化 |

---

## 四种部署方式对比

| 维度 | K8s（ArgoCD） | Docker Compose | 二进制 | 私有化交付（Ansible） |
| --- | --- | --- | --- | --- |
| 零停机部署 | ✅ 滚动更新 | ❌ 短暂停机 | ❌ 停机 | ❌ 视情况 |
| 自动回滚 | ✅ | 手动 | 手动 | 手动 |
| 资源隔离 | ✅ namespace/quota | 🟡 容器隔离 | ❌ 进程共享 | 视部署结果 |
| GPU 调度 | ✅ HAMI | ❌ | ❌ | ❌ |
| 可观测性 | ✅ 全覆盖 | 🟡 需接入 Loki | ❌ 日志分散 | 视情况 |
| 适合场景 | 高频部署、高可用 | 过渡期 | 旧服务、低频部署 | 向客户交付 |

---

## 部署流程总览

```text
安全扫描通过（03-安全扫描/）
        │
        ▼
判断服务类型
        │
        ├──→ K8s 服务
        │         │
        │         ▼
        │   Git 仓库更新 Helm values（镜像 Tag）
        │         │
        │         ▼
        │   ArgoCD 检测到变更，自动同步
        │         │
        │         ▼
        │   K8s 滚动升级 → readinessProbe 验证 → 完成
        │
        ├──→ Docker Compose 服务
        │         │
        │         ▼
        │   GitLab CI 触发 SSH 部署 Job（when: manual）
        │         │
        │         ▼
        │   目标服务器：docker compose pull + up -d
        │         │
        │         ▼
        │   healthcheck 验证 → 完成
        │
        └──→ 二进制服务
                  │
                  ▼
            GitLab CI 触发 SSH 部署 Job（when: manual）
                  │
                  ▼
            目标服务器：下载新 JAR → 停旧进程 → 启新进程
                  │
                  ▼
            健康检查验证 → 失败自动回滚
```

---

## 环境晋级流程

```text
dev 分支 push
   │ 自动部署到 dev 环境（GitLab CI）
   │
   ▼
开发自测通过
   │ 发起 MR → main
   │ Code Review 通过
   ▼
合并到 main
   │ 自动部署到 pre 环境
   │ QA 测试
   ▼
测试通过
   │ 手动审批（GitLab CI when: manual）
   ▼
部署生产
   │ 观察 10 分钟
  │ 更新飞书知识库服务部署文档
   ▼
完成 / 发现问题 → 立即回滚
```

发布完成后，必须回填飞书知识库中的服务部署文档，至少同步版本号、制品信息、部署步骤差异、配置变更、验证结果和回滚说明。统一模板见 [../05-发布治理/templates/服务部署文档模板.md](../05-发布治理/templates/服务部署文档模板.md)。

---

## 各环境配置差异

| 环境 | 镜像 Tag | 副本数 | 资源 Limit | 部署方式 |
| --- | --- | --- | --- | --- |
| dev | `dev-{sha}`（滚动） | 1 | 小（1c/2G） | 自动 |
| pre | `rc-{semver}` | 1 | 中（2c/8G） | 自动（main 合并触发） |
| prod | `{semver}`（固定版本） | 2 | 正常 | 手动审批 |

---

## 回滚操作

### K8s（ArgoCD）

```bash
# 方式 1：ArgoCD UI 点击 History → 回滚到指定版本
# 方式 2：修改 Git 仓库中的镜像 Tag，ArgoCD 自动同步

# 方式 3：临时快速回滚（绕过 GitOps，用于紧急情况）
kubectl rollout undo deployment/<name> -n <namespace>
# 注意：之后需要同步 Git 仓库，否则 ArgoCD 会重新 apply
```

### Docker Compose

```bash
# 改回旧版本 Tag，重新 up
export IMAGE_TAG=v1.1.0
docker compose up -d <service>
```

### 二进制

```bash
# 自动回滚（deploy.sh 健康检查失败时触发）
bash /opt/scripts/rollback.sh api-service

# 手动回滚
kill $(pgrep -f "api-service-v1.2.0.jar")
nohup java -jar /opt/services/api-service/api-service-v1.1.0.jar &
```

---

## 发布后文档回填要求

部署执行完成不代表流程结束，以下动作属于 CD 闭环的一部分：

1. 在飞书知识库更新对应服务的部署文档。
2. 回填本次部署的版本号、镜像 Tag 或部署包版本。
3. 记录本次部署涉及的配置变更、迁移脚本、验证结论。
4. 如果存在回滚或临时处置，必须同步更新回滚说明和故障处理记录。

如果部署方式、操作步骤、依赖项没有变化，也至少要更新“当前生产版本”和“最近发布时间”。

---

## GitLab CI 驱动 CD（推模式完整配置）

GitLab CI 通过 `environment`、`when: manual`、Protected Environments 可独立完成 CD 全流程，不依赖 ArgoCD。适合当前过渡阶段，或 ArgoCD 尚未接入的服务。

### 核心机制

| 机制 | 说明 |
| --- | --- |
| `environment: name` | 声明 Deployment 归属环境，GitLab UI 可追踪每个环境当前版本 |
| Protected Environments | 在 Settings → CI/CD → Protected environments 中限制谁可以触发生产部署 |
| `when: manual` | Job 需要人工点击才执行，配合 Protected Environments 实现审批 |
| `needs:` | 指定前置 Job，确保 CD Job 在 CI 全部通过后才可触发 |
| `on_stop` | 配套清理 Job，支持销毁预发环境 |

### 完整 .gitlab-ci.yml（三种部署方式）

```yaml
stages:
  - lint
  - test
  - build
  - scan
  - deploy-dev
  - deploy-pre
  - deploy-prod

variables:
  HARBOR_URL: harbor.internal
  IMAGE_NAME: $HARBOR_URL/platform/$CI_PROJECT_NAME

# ===== K8s 服务 CD =====
# dev：push 到 dev 分支自动部署
deploy-k8s-dev:
  stage: deploy-dev
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/$CI_PROJECT_NAME
        $CI_PROJECT_NAME=$IMAGE_NAME:$CI_COMMIT_SHORT_SHA
        -n dev
    - kubectl rollout status deployment/$CI_PROJECT_NAME -n dev --timeout=300s
  environment:
    name: dev
    url: https://dev.smartvision.internal
  needs: [scan]
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"

# pre：合并到 main 后自动部署
deploy-k8s-pre:
  stage: deploy-pre
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/$CI_PROJECT_NAME
        $CI_PROJECT_NAME=$IMAGE_NAME:rc-$CI_COMMIT_SHORT_SHA
        -n pre
    - kubectl rollout status deployment/$CI_PROJECT_NAME -n pre --timeout=300s
  environment:
    name: pre
    url: https://pre.smartvision.internal
  needs: [scan]
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

# prod：手动审批（需在 Protected Environments 中配置 Approvers）
deploy-k8s-prod:
  stage: deploy-prod
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/$CI_PROJECT_NAME
        $CI_PROJECT_NAME=$IMAGE_NAME:$CI_COMMIT_TAG
        -n prod
    - kubectl rollout status deployment/$CI_PROJECT_NAME -n prod --timeout=600s
  environment:
    name: production
    url: https://smartvision.internal
  needs: [scan]
  rules:
    - if: $CI_COMMIT_TAG   # 仅 Git Tag 触发
  when: manual

# ===== Docker Compose 服务 CD =====
deploy-docker-pre:
  stage: deploy-pre
  image: alpine:latest
  before_script:
    - apk add --no-cache openssh-client
    - eval $(ssh-agent -s)
    - echo "$SSH_PRIVATE_KEY" | ssh-add -       # GitLab CI Variable（Protected）
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - ssh-keyscan $DEPLOY_HOST >> ~/.ssh/known_hosts
  script:
    - |
      ssh $DEPLOY_USER@$DEPLOY_HOST "
        export IMAGE_TAG=$CI_COMMIT_SHORT_SHA
        cd /opt/smartvision/ai-backend
        docker compose pull
        docker compose up -d --remove-orphans
        sleep 5
        docker compose ps | grep -q 'Up' || exit 1
      "
  environment:
    name: pre/docker
  needs: [scan]
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy-docker-prod:
  stage: deploy-prod
  image: alpine:latest
  before_script:
    - apk add --no-cache openssh-client
    - eval $(ssh-agent -s)
    - echo "$SSH_PRIVATE_KEY" | ssh-add -
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - ssh-keyscan $PROD_DEPLOY_HOST >> ~/.ssh/known_hosts
  script:
    - |
      ssh $DEPLOY_USER@$PROD_DEPLOY_HOST "
        export IMAGE_TAG=$CI_COMMIT_TAG
        cd /opt/smartvision/ai-backend
        docker compose pull
        docker compose up -d --remove-orphans
        sleep 5
        docker compose ps | grep -q 'Up' || (docker compose logs --tail 50; exit 1)
      "
  environment:
    name: production/docker
  needs: [scan]
  rules:
    - if: $CI_COMMIT_TAG
  when: manual

# ===== 二进制服务 CD =====
deploy-binary-prod:
  stage: deploy-prod
  image: alpine:latest
  before_script:
    - apk add --no-cache openssh-client curl
    - eval $(ssh-agent -s)
    - echo "$SSH_PRIVATE_KEY" | ssh-add -
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - ssh-keyscan $PROD_JAVA_HOST >> ~/.ssh/known_hosts
  script:
    - |
      ssh $DEPLOY_USER@$PROD_JAVA_HOST bash << 'EOF'
        set -euo pipefail
        SERVICE=api-service
        VERSION=$CI_COMMIT_TAG
        DEPLOY_DIR=/opt/smartvision/$SERVICE
        JAR_URL=https://harbor.internal/api/v2.0/projects/platform/repositories/${SERVICE}/artifacts/${VERSION}/download

        # 备份当前运行版本
        CURRENT=$(readlink $DEPLOY_DIR/current.jar 2>/dev/null || echo "none")

        # 下载新版本
        curl -u $HARBOR_USER:$HARBOR_PASS -o $DEPLOY_DIR/${SERVICE}-${VERSION}.jar $JAR_URL

        # 切换并重启
        ln -sf $DEPLOY_DIR/${SERVICE}-${VERSION}.jar $DEPLOY_DIR/current.jar
        systemctl restart $SERVICE

        # 健康检查（最多等 60s）
        for i in $(seq 1 12); do
          sleep 5
          if curl -sf http://localhost:8080/actuator/health | grep -q '"status":"UP"'; then
            echo "✅ $SERVICE 启动成功"
            exit 0
          fi
        done

        # 失败回滚
        echo "❌ 健康检查失败，回滚到 $CURRENT"
        ln -sf $CURRENT $DEPLOY_DIR/current.jar
        systemctl restart $SERVICE
        exit 1
      EOF
  environment:
    name: production/java
  needs: [scan]
  rules:
    - if: $CI_COMMIT_TAG
  when: manual
```

### GitLab Protected Environments 配置

在 **Settings → CI/CD → Protected environments** 中配置：

| 环境名 | Allowed to deploy | Approvers |
| --- | --- | --- |
| `production` | Maintainer | 指定审批人（如技术负责人） |
| `production/docker` | Maintainer | 同上 |
| `production/java` | Maintainer | 同上 |
| `pre` | Developer+ | 不设审批，自动 |
| `dev` | Developer+ | 不设审批，自动 |

配置 Approvers 后，`when: manual` 的 Job 需要指定人员点击才能运行，满足生产审批要求。

### 需要在 GitLab CI/CD Variables 中配置的变量

| 变量 | 说明 | 是否 Protected | 是否 Masked |
| --- | --- | --- | --- |
| `SSH_PRIVATE_KEY` | 部署服务器 SSH 私钥 | ✅ | ✅ |
| `DEPLOY_HOST` | Pre 部署主机 IP | ✅ | ❌ |
| `PROD_DEPLOY_HOST` | 生产部署主机 IP | ✅ | ❌ |
| `PROD_JAVA_HOST` | Java 服务生产主机 IP | ✅ | ❌ |
| `DEPLOY_USER` | SSH 登录用户 | ✅ | ❌ |
| `HARBOR_USER` / `HARBOR_PASS` | Harbor 拉包凭证 | ✅ | ✅ |

### GitLab CI CD vs ArgoCD 对比

| 维度 | GitLab CI 推模式 | ArgoCD GitOps |
| --- | --- | --- |
| 配置复杂度 | 低，`.gitlab-ci.yml` 一文件 | 中，需独立部署 ArgoCD |
| K8s 凭证管理 | CI Runner 持有 kubeconfig，**风险** | ArgoCD 在 K8s 内部，CI 不需要凭证 |
| 漂移检测 | ❌ 无法检测手动操作导致的配置漂移 | ✅ 自动检测并修正 |
| 多集群管理 | 每个集群配一套 kubeconfig | ✅ ArgoCD 统一管理多集群 |
| 回滚 | `kubectl rollout undo`（临时）+ 改 CI 变量 | ArgoCD UI 一键回滚到任意历史版本 |
| 适用阶段 | **当前**（快速接入，已有 GitLab CI） | **目标**（K8s 服务达到一定规模后） |

---

## 相关文档

| 文档 | 说明 |
| --- | --- |
| [K8s/推荐采用/ArgoCD.md](K8s/推荐采用/ArgoCD.md) | GitOps 部署方案详解 |
| [K8s/推荐采用/Helm.md](K8s/推荐采用/Helm.md) | K8s 配置模板和多环境管理 |
| [Docker/已采用/DockerCompose.md](Docker/已采用/DockerCompose.md) | Docker Compose 部署规范和 CI 集成 |
| [二进制/已采用/Shell部署规范.md](二进制/已采用/Shell部署规范.md) | 二进制服务部署和回滚脚本 |
| [../../14-私有化交付/README.md](../../14-私有化交付/README.md) | 客户私有化部署方案（Ansible） |
