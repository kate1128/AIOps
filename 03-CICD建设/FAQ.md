# CI/CD 常见问题

---

**Q：为什么选 GitLab CI 而不是 Jenkins？**

代码仓库已在 GitLab，使用 GitLab CI 无需额外运维 CI 服务器，`.gitlab-ci.yml` 与代码同仓库版本化管理。Jenkins 运维成本高（插件升级、Groovy 流水线维护），在代码已托管 GitLab 的前提下引入 Jenkins 属于重复建设。详见 [01-CI引擎/CI流水线规范.md](01-CI引擎/CI流水线规范.md)。

---

**Q：ArgoCD 和 Helm 是什么关系，为什么要同时用？**

两者是不同层次的工具：

- **Helm**：K8s 资源的配置模板引擎，解决"一套配置适配多环境"的问题
- **ArgoCD**：GitOps 部署控制器，监听 Git 仓库变更并自动同步到 K8s，解决"谁来部署、何时部署、部署什么版本"的问题

实际工作流：CI 更新 Git 配置仓库中的 `values.yaml`（改镜像 Tag）→ ArgoCD 检测到变更 → 调用 Helm 渲染模板 → 同步到 K8s。两者配合使用，不是二选一。

---

**Q：现在用 kubectl 推模式，有什么安全风险？什么时候必须迁移到 GitOps？**

主要风险：CI Runner 持有 `kubeconfig`，一旦 Runner 被入侵或 CI 变量泄露，攻击者可直接操作 K8s 集群。建议：

- 短期（当前可接受）：限制 `kubeconfig` 权限为 `deployment/patch`，不给 `cluster-admin`
- 中期（接入 ArgoCD 后）：CI 只写配置仓库，Runner 不再需要 K8s 凭证，风险彻底消除
- 时机：当生产部署频率 > 每周 5 次，或出现因 Runner 凭证问题导致的安全事件时，立刻迁移

---

**Q：测试覆盖率门禁从 0% 直接设到 60%，现有项目 CI 会全部挂掉吗？**

会。建议分步推进：

1. 先在流水线中加测试并**收集现有覆盖率数据**（`--cov-report=xml`，不设 `--cov-fail-under`）
2. 观察 1-2 周，了解各服务真实覆盖率基线
3. 设初始门禁为**基线值 - 5%**（比如现有 35%，就设 30%，防止降低）
4. 每个迭代提升 5-10%，逐步收紧到 60%

关键原则：**门禁只防倒退，不强制一步到位。**

---

**Q：Cosign 签名密钥放在哪里？CI 怎么用？**

不要把私钥明文放在 GitLab 变量中。推荐方案：

- **短期**：使用 GitLab CI Protected Variable 存储 Cosign 私钥（加密存储，仅 Protected branch/tag 可见）
- **中期**：使用 KMS（阿里云 KMS 或 HashiCorp Vault）管理密钥，Cosign 支持 `--key gcpkms://...` / `--key hashivault://...` 格式
- 公钥存入 Harbor 项目配置和 K8s Secret，部署前验证

```bash
# CI 中签名（使用 KMS）
cosign sign --key hashivault://cosign-key $IMAGE_NAME:$TAG

# 部署前验证（Kyverno Policy 中配置，自动执行）
cosign verify --key /etc/cosign/pub.key $IMAGE_NAME:$TAG
```

---

**Q：生产 ACK 集群是 K8s v1.20，ArgoCD 支持吗？**

ArgoCD v2.6+ 要求 K8s >= 1.21。需要：

- 使用 ArgoCD v2.5.x（最后支持 v1.20 的版本）
- 或推动阿里云 ACK 集群升级到 v1.24+（ACK 支持在线升级，建议在 dev → pre → prod 顺序验证）

建议优先升级集群，v1.20 已超出官方维护期，存在未修复的安全漏洞。

---

**Q：Harbor 清理策略会不会误删正在运行的镜像？**

Harbor 的 Tag Retention 只删除 Tag 记录，如果有 `imagePullPolicy: IfNotPresent`，已运行的 Pod 不受影响（镜像已在节点 cache）。但若节点重建或 Pod 漂移到新节点，可能拉不到已删除 Tag 的镜像，导致启动失败。

规避方法：
- 正式发布版本（semver Tag）设置永久保留，永远不删
- 生产运行的镜像确保使用 semver Tag，不使用 `dev-*` / `rc-*`
- 清理前用 `kubectl get pods --all-namespaces -o=jsonpath='{..image}'` 核查在用镜像

---

**Q：GPU Runner 能不能用 Docker Executor？**

能，但需要额外配置。Docker Executor 默认无 GPU 访问权限，需在 Runner `config.toml` 中传入 GPU 设备：

```toml
[[runners]]
  name = "gpu-runner"
  executor = "docker"
  [runners.docker]
    runtime = "nvidia"
    gpus = "all"
    # 或指定设备
    devices = ["/dev/nvidia0", "/dev/nvidiactl", "/dev/nvidia-uvm"]
```

要求宿主机安装 `nvidia-container-runtime`，并配置 Docker daemon 默认 runtime 为 nvidia。若 GPU 共享调度由 HAMI 管理，需确认 HAMI 与 Docker Executor 的兼容性，否则保留 Shell Executor 更稳妥。

---

**Q：Ansible（私有化交付）和 ArgoCD（内部 CD）有功能重叠吗？**

没有重叠，两者面向不同场景：

| 工具 | 面向 | 触发方 | 目标环境 |
|---|---|---|---|
| ArgoCD | 内部研发 CI/CD | GitLab CI | 公司内部 dev/pre/生产 K8s |
| Ansible | 私有化交付 | 交付工程师 | 客户本地服务器（无 K8s 或异构环境）|

两者并存，不冲突。详见 [../../14-私有化交付/README.md](../../14-私有化交付/README.md)。

---

**Q：AI Code Review 会不会把代码发出去？**

不会。AI Code Review 使用内网 vLLM 服务（`vllm-service.ai-infra.svc.cluster.local`），只在 K8s 集群内部网络通信，代码 diff 不经过任何外网。如果团队后续考虑接入 GitLab Duo，需评估其数据政策，因为 GitLab Duo 会将代码发送到 GitLab 的云端 AI 服务。

---

**Q：AI Code Review 误报率高怎么办？团队会不会对它失去信任？**

这是推广初期的核心风险。建议：
- 初期只做**代码规范 + 硬编码 Secret** 两类检查，准确率高，误报少；逐步扩展到其他类别
- 每条评论末尾注明"AI 生成，仅供参考，如有误判请忽略"，降低心理负担
- 设置最多 5 条评论的限制，宁可漏报也不刷屏
- 3 个月后收集团队反馈，统计"有用评论 vs 误报评论"比例，决定是否调整 Prompt

---

**Q：gitleaks 扫出 Secret 了，但那是个测试用的假 key，怎么处理？**

两种方案：

1. **推荐**：把测试 key 改成明显的占位符（如 `FAKE_KEY_FOR_TESTING`），gitleaks 不会误报
2. **备选**：在项目根目录添加 `.gitleaks.toml`，配置允许特定 pattern 的例外：

```toml
[[allowlist]]
description = "测试用假 key，不是真实凭据"
paths = ["tests/fixtures/"]
regexes = ["FAKE_.*"]
```

**不要**把真实 key 提交进去再走例外流程——例外配置一旦存在就容易被滥用，扩大攻击面。

---

**Q：oasdiff 检测到 Breaking Change，但这次变更就是故意要改接口，怎么处理？**

两种情况：

- **新接口版本（推荐）**：新增 `/v2/xxx` 路径，旧 `/v1/xxx` 保留至少 2 个版本，消费方有时间迁移。oasdiff 不会报错，因为没有删除旧路径。
- **强制破坏性变更**：在 `.oasdiff-ignore` 文件中登记，注明原因和时间，CI 会跳过该条：

```
# 2026-06-01 故意删除废弃字段 user.legacy_id，消费方已确认无使用
GET /api/v1/users/{id} response-property-removed legacy_id
```

`.oasdiff-ignore` 必须在 MR 中审批，确保破坏性变更有据可查。

---

**Q：Trivy 扫描很慢，每次 CI 要等 5-10 分钟，怎么优化？**

主要优化方向：

1. **本地缓存 DB**：Trivy 每次运行会下载漏洞数据库（约 50MB），配置 GitLab CI cache 缓存到 Runner 本地：
   ```yaml
   cache:
     paths:
       - .trivy-cache/
   variables:
     TRIVY_CACHE_DIR: .trivy-cache
   ```
2. **只扫增量层**：`--skip-files` 跳过不变的基础镜像层（如果基础镜像已单独扫过）
3. **并行执行**：将 Trivy 扫描与其他非依赖 job 并行（`needs: [build]` 不等 test 完成）
4. **分级触发**：MR 阶段只扫 `CRITICAL`，main 分支才扫 `HIGH+CRITICAL`

---

**Q：DORA 指标的"变更失败率"怎么界定？灰度回滚算失败吗？**

建议定义：**发布后 1 小时内，触发了人工回滚或自动回滚则计为失败**。灰度阶段（金丝雀流量 < 10%）中止视为失败，但影响权重可以降低。

具体实现：在 GitLab Webhook 中监听 `deployment` 事件，当同一服务的发布版本在 1h 内被新版本覆盖（版本号降低），记为变更失败。边界情况可以在团队内对齐一次，比 DORA 的精确定义更重要。

---

**Q：现在手动 kubectl apply，怎么临时查某个环境部署的是哪个版本？**

```bash
# 查看当前运行的镜像 Tag
kubectl get deployment <service-name> -n <namespace> \
  -o=jsonpath='{.spec.template.spec.containers[0].image}'

# 查看镜像的构建信息（镜像注入了 Label）
docker inspect <image>:<tag> | grep -A 20 '"Labels"'

# 或通过 Harbor UI → 镜像详情 → Labels 查看 git.commit
```

接入 ArgoCD 后，直接在 ArgoCD Dashboard 查看每个应用当前部署版本、最后同步时间、与 Git 的差异。

---

**Q：CI Runner 挂了，整个团队的流水线都卡住，有高可用方案吗？**

短期：至少注册 2 个 Runner（可以是不同机器），GitLab 会自动负载均衡。Runner 注册时用同一个 Registration Token 即可。

```bash
# 第二台机器注册 Runner
gitlab-runner register \
  --url https://gitlab.internal \
  --registration-token <token> \
  --name "runner-backup-01" \
  --executor docker
```

中期：将 Runner 以 K8s Pod 形式部署（`gitlab-runner` Helm chart），配置 `replicas: 2`，Kubernetes Executor 按需启动 Job Pod，天然高可用且资源利用率更高。
