# ArgoCD - K8s GitOps 持续部署

> 推荐原因：SmartVision 当前部署方式依赖手动 kubectl apply 或 GitLab CI 直接操作集群，缺乏状态同步和回滚能力。ArgoCD 实现 Git 为 Single Source of Truth，所有生产变更可审计、可回滚，与现有 GitLab CI 流程互补。
> 当前状态：❌ 未部署，计划在 pre 环境先验证，再推广到 prod（参见 03-CICD建设）。

---

## 现状与问题

| 项目 | 现状 |
|------|------|
| 生产部署方式 | GitLab CI runner 直接 kubectl apply |
| 配置漂移检测 | ❌ 无，手动修改集群无法被发现 |
| 部署状态可视化 | ❌ 无，只能看 CI/CD 日志 |
| 多环境同步 | 手动操作，pre/prod 配置经常不一致 |
| 回滚 | kubectl rollout undo（只能回滚最近一次）|
| 部署审批 | ❌ 无内置审批流 |

---

## ArgoCD 是什么

ArgoCD 是 CNCF 毕业的 GitOps 持续部署工具，它：
- **持续同步**：监听 Git 仓库，自动/手动将集群状态与 Git 保持一致
- **漂移检测**：有人手动改了集群？ArgoCD 立即告警
- **可视化 Dashboard**：每个应用的 Pod/Service/Deployment 状态一目了然
- **回滚到任意历史版本**：直接回滚到某个 Git commit
- **多集群管理**：一个 ArgoCD 实例管理 prod/pre/dev 三套集群

---

## 与当前流程的关系

```
现有流程（保留）：
  开发 push → GitLab CI → 构建镜像 → push Harbor → 更新 values.yaml tag

新增流程（ArgoCD 接管部署）：
  values.yaml tag 更新 → ArgoCD 检测到 → （可选：人工确认）→ 自动 Apply → 同步状态
```

---

## K8s 部署

```bash
# 安装 ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 暴露 UI（生产建议用 Ingress）
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort"}}'

# 获取初始 admin 密码
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 注册外部集群（pre/dev 集群）
argocd cluster add <pre-cluster-context>
argocd cluster add <dev-cluster-context>
```

---

## 应用定义示例

```yaml
# smartvision-app.yaml - 在 ArgoCD 中注册一个应用
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: smartvision-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.smartvision.internal/devops/k8s-configs
    targetRevision: main
    path: prod/smartvision-api  # Helm chart 或 K8s manifest 路径
  destination:
    server: https://kubernetes.default.svc  # prod 集群
    namespace: prod
  syncPolicy:
    automated:
      prune: true      # 自动删除 Git 中不再存在的资源
      selfHeal: true   # 手动修改集群会被自动纠正
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 3
      backoff:
        duration: 10s
        maxDuration: 3m
```

---

## 生产发布流程（与 GitLab CI 协作）

```yaml
# GitLab CI 只负责构建，ArgoCD 负责部署
deploy-to-prod:
  stage: deploy
  script:
    # 更新镜像 tag（通过修改 Git 仓库中的 values.yaml）
    - git clone https://gitlab.smartvision.internal/devops/k8s-configs
    - cd k8s-configs
    - |
      yq e '.image.tag = "${CI_COMMIT_SHA:0:7}"' \
        -i prod/smartvision-api/values.yaml
    - git commit -am "ci: update smartvision-api to ${CI_COMMIT_SHA:0:7}"
    - git push
    # ArgoCD 自动检测到变更，触发同步
    # 如果需要手动确认，在 ArgoCD Dashboard 操作
  only:
    - main
```

---

## 多环境配置管理

```
k8s-configs/
├── dev/
│   └── smartvision-api/
│       └── values.yaml   # dev 环境配置（低资源规格，自动同步）
├── pre/
│   └── smartvision-api/
│       └── values.yaml   # pre 环境配置（接近生产，自动同步）
└── prod/
    └── smartvision-api/
        └── values.yaml   # 生产配置（手动触发同步，需审批）
```

---

## 关键功能：Sync Wave（控制部署顺序）

```yaml
# 确保先部署数据库 Migration，再部署 API 服务
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # 先执行（DB migration Job）

# API Deployment
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"   # 后执行
```

---

## 告警与通知

```yaml
# ArgoCD 同步失败时通知飞书
# 通过 ArgoCD Notifications 插件
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.feishu: |
    url: https://open.feishu.cn/open-apis/bot/v2/hook/xxx
    headers:
    - name: Content-Type
      value: application/json
  template.app-sync-failed: |
    webhook:
      feishu:
        method: POST
        body: |
          {"msg_type":"text","content":{"text":"🚨 ArgoCD: {{.app.metadata.name}} 同步失败\n原因: {{.app.status.operationState.message}}"}}
```

---

## 引入优先级

| 优先级 | 理由 |
|--------|------|
| 🟡 中优（pre 环境先验证）| CI/CD 体系建设 Phase 2 中的核心目标之一 |

---

## 参考

- 官方文档：https://argo-cd.readthedocs.io/
- 最佳实践：https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/
- Notifications：https://argocd-notifications.readthedocs.io/
