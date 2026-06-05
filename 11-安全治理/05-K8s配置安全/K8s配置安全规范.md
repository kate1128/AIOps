# K8s 配置安全规范

## 1. 目标

防止因 K8s 配置不当引入的安全风险，包括：

- 特权容器/hostPID/hostNetwork 滥用
- 容器以 root 身份运行
- 敏感 Secret 被非预期 Pod 挂载
- 无资源限制导致资源耗尽

## 2. 控制项

| ID | 控制项 | 严重度 | 执行阶段 |
| --- | --- | --- | --- |
| C-01 | 生产容器禁止使用 `privileged: true` | 高 | CI lint + OPA |
| C-02 | 容器必须以非 root 用户运行（`runAsNonRoot: true`） | 高 | CI lint |
| C-03 | 禁止挂载 hostPath 到生产 Pod | 高 | CI lint |
| C-04 | 所有 Pod 必须配置 CPU/Memory limits | 中 | CI lint |
| C-05 | Secret 只挂载到需要的 Pod，不全局挂载 | 中 | CR |
| C-06 | 使用 Network Policy 限制 Pod 间通信 | 中 | 架构规范 |

## 3. 执行流程

### 3.1 CI 阶段 Helm/YAML 静态检查

```yaml
k8s-security-lint:
  stage: scan
  image: zegl/kube-score:latest
  script:
    - kube-score score helm/templates/*.yaml
  allow_failure: false
```

或使用 `trivy config`：

```bash
trivy config ./helm --exit-code 1 --severity HIGH,CRITICAL
```

检查项目包括：

- `securityContext.runAsNonRoot`
- `resources.limits` 存在
- `privileged` 为 false
- `readOnlyRootFilesystem` 建议为 true

### 3.2 准入控制（Kyverno）

中期目标，通过 Kyverno 策略在集群侧拦截不合规部署：

```yaml
# 禁止特权容器策略示例
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-privileged
      match:
        resources:
          kinds: [Pod]
      validate:
        message: "Privileged containers are not allowed"
        pattern:
          spec:
            containers:
              - securityContext:
                  privileged: "false | nil"
```

### 3.3 存量集群安全基线审计

```bash
# 使用 kube-bench 检查 CIS 基线
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench
```

定期（每季度）执行，结果与基线对比。

## 4. 工具推荐

| 场景 | 工具 | 备注 |
| --- | --- | --- |
| YAML 静态检查 | kube-score / trivy config | CI 集成 |
| 运行时准入控制 | Kyverno | 中期目标 |
| 基线合规审计 | kube-bench | 季度执行 |
| 网络策略可视化 | Cilium / Hubble | 与 07-可观测性 联动 |

## 5. KPI

| 指标 | 目标值 |
| --- | --- |
| CI 配置安全检查覆盖率 | 100% K8s 应用 |
| 特权容器数量 | 0 |
| 无 resource limits 的 Pod | 0 |
| CIS Benchmark 合规评分 | 大于等于 80%（季度审计） |

## 6. 验收标准

- [ ] 所有 Helm Chart CI 中包含 kube-score 或 trivy config 检查
- [ ] 生产集群中特权容器已清零
- [ ] 所有生产 Pod 配置了 CPU/Memory limits
- [ ] 已完成一次 kube-bench 基线审计并建立 baseline 记录
