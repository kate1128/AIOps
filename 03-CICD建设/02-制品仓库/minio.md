# MinIO — 内部制品对象存储

> 用于存储 CI 构建产出的 JAR 包、镜像 tar、SBOM 等制品，供内部归档和审计使用。
> 当前状态：🔲 规划中（当前无对象存储，制品散落各处）

---

## 是什么

MinIO 是兼容 AWS S3 API 的高性能开源对象存储，可完全私有化部署。在制品管理体系中，MinIO 承担**内部制品归档**职责：CI 构建完成后，将 JAR 包、镜像离线包（docker save）、SBOM 文件等上传到 MinIO 长期保存，供审计、回滚和客户交付打包使用。

> 与 FTP 的分工：MinIO 面向**内部系统**（CI 自动上传、脚本查询），FTP 面向**外部客户**（手动下载）。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **S3 兼容 API** | 所有 S3 生态工具（mc、aws cli、Terraform）直接可用 |
| **Bucket 策略** | 精细控制读写权限，CI 账号只写，CD 账号只读 |
| **生命周期规则** | 自动删除/转冷 dev 构建物，无需人工清理 |
| **版本控制** | 同 Key 多版本并存，误删可恢复 |
| **事件通知** | 文件上传后触发 Webhook，可自动通知下游系统 |
| **私有化部署** | 完全内网，无需公网，数据不出内网 |

---

## 与替代方案对比

| 维度 | MinIO | NFS 共享目录 | 阿里云 OSS | Harbor Generic |
|---|---|---|---|---|
| 私有化部署 | ✅ | ✅ | ❌ 公有云 | ✅ |
| S3 兼容 API | ✅ | ❌ | ✅ | ❌ |
| 生命周期管理 | ✅ 自动 | ❌ 手动脚本 | ✅ | ❌ |
| 高可用 | ✅ 分布式模式 | ❌ 单点 | ✅ | 依赖 Harbor |
| 性能 | 高（并发读写）| 受网络限制 | 高 | 中 |
| 运维成本 | 低 | 低 | 极低（托管）| 与 Harbor 共用 |
| **适用场景** | **内部制品归档首选** | 简单文件共享 | 公有云项目 | 镜像仓库附带存储 |

> **选型结论**：自建环境下 MinIO 是内部制品归档的最优选择，S3 兼容 API 让 CI 脚本通用，生命周期规则自动清理 dev 构建物，运维成本低。

---

## Bucket 规划

| Bucket | 用途 | 保留策略 |
|---|---|---|
| `smartvision-archive` | JAR 包、镜像 tar、SBOM | dev: 90天；rc: 365天；正式: 永久 |
| `smartvision-models` | AI 模型权重文件 | 永久（手动管理）|
| `smartvision-logs` | CI 构建日志归档 | 30 天后删除 |

---

## 目录结构（`smartvision-archive`）

```
smartvision-archive/
├── {project-name}/
│   └── {version}/
│       ├── {project-name}-{version}.jar       # Java 二进制
│       ├── {project-name}-{version}.tar        # docker save 产物
│       ├── sbom-{version}.cyclonedx.json       # SBOM（Syft 生成）
│       ├── manifest.json                       # 版本元信息
│       └── checksums.sha256                    # 所有文件校验和
│
# 示例：
smartvision-archive/
├── api-service/
│   ├── 1.2.0/
│   │   ├── api-service-1.2.0.jar
│   │   ├── manifest.json
│   │   └── checksums.sha256
│   └── dev-a3f8c21/
│       └── api-service-dev-a3f8c21.jar
└── ai-backend/
    └── 1.2.0/
        ├── ai-backend-1.2.0.tar
        └── sbom-1.2.0.cyclonedx.json
```

---

## CI 接入（`mc` 客户端）

```yaml
# .gitlab-ci.yml 片段
archive-to-minio:
  stage: archive
  image: minio/mc
  script:
    # 配置 MinIO 连接
    - mc alias set smartvision ${MINIO_ENDPOINT} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}
    # JAR 上传
    - mc cp ./target/${CI_PROJECT_NAME}-${CI_COMMIT_TAG}.jar \
        smartvision/smartvision-archive/${CI_PROJECT_NAME}/${CI_COMMIT_TAG}/
    # 生成并上传 SHA256
    - sha256sum ./target/${CI_PROJECT_NAME}-${CI_COMMIT_TAG}.jar > checksums.sha256
    - mc cp checksums.sha256 \
        smartvision/smartvision-archive/${CI_PROJECT_NAME}/${CI_COMMIT_TAG}/
  rules:
    - if: '$CI_COMMIT_TAG'
    - if: '$CI_COMMIT_BRANCH == "main"'
```

所需 CI 变量：

| 变量名 | 说明 |
|---|---|
| `MINIO_ENDPOINT` | MinIO 地址，如 `http://minio.internal:9000` |
| `MINIO_ACCESS_KEY` | 访问密钥（Protected Variable）|
| `MINIO_SECRET_KEY` | 密钥（Protected Variable）|

---

## 生命周期规则配置

```bash
# 使用 mc 配置自动清理规则

# dev 构建物 90 天后删除
mc ilm add smartvision/smartvision-archive \
  --prefix "*/dev-*/" \
  --expiry-days 90

# rc 构建物 365 天后删除
mc ilm add smartvision/smartvision-archive \
  --prefix "*/rc-*/" \
  --expiry-days 365

# 查看规则
mc ilm ls smartvision/smartvision-archive
```

---

## 日常运维命令

```bash
# 查看 Bucket 使用量
mc du smartvision/smartvision-archive

# 列出某版本的所有制品
mc ls smartvision/smartvision-archive/api-service/1.2.0/

# 下载指定版本（用于回滚或客户交付打包）
mc cp smartvision/smartvision-archive/api-service/1.2.0/api-service-1.2.0.jar ./

# 手动删除某个 dev 构建
mc rm --recursive smartvision/smartvision-archive/api-service/dev-a3f8c21/
```

---

## 相关文档

| 文档 | 说明 |
|---|---|
| [制品管理规范.md](./制品管理规范.md) | 各类制品的存储位置与生命周期规范 |
| [ftp.md](./ftp.md) | 对外客户交付通道 |
