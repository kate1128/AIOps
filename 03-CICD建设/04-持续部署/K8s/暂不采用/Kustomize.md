# Kustomize — 暂不采用

> 当前状态：❌ 暂不采用（Helm 已足够，两者不建议混用）

---

## 是什么

Kustomize 是 K8s 官方内置的配置管理工具（`kubectl apply -k`），通过 **overlay** 机制在原始 YAML 上叠加差异，不引入模板语法，所有文件都是合法的 K8s YAML。

---

## 核心机制

```
base/                    # 基础配置（通用）
  deployment.yaml
  service.yaml
  kustomization.yaml

overlays/
  dev/
    kustomization.yaml   # 只写差异：副本数 1，镜像 tag dev
  prod/
    kustomization.yaml   # 差异：副本数 2，镜像 tag v1.2.0
```

```bash
# 部署 prod 环境
kubectl apply -k overlays/prod/
```

---

## 不采用原因

1. **Helm 已选型**：Helm 和 Harbor Chart 仓库配合更好，有打包和版本管理能力，满足当前需求
2. **两者混用增加复杂度**：Helm 和 Kustomize 都支持 ArgoCD，混用会让团队困惑
3. **无打包能力**：Kustomize 无法像 Helm Chart 一样打包分发给客户（私有化交付场景）

---

## 适合引入的场景

- 项目 K8s YAML 很简单，不需要打包分发
- 团队抗拒 Go 模板语法，更喜欢纯 YAML
- 只需要简单的 dev/prod 差异管理
