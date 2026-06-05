# FTP — 客户交付制品传输通道

> 用于向客户提供正式版本离线安装包的文件传输服务。
> 当前状态：🔲 规划中（配合私有化部署场景）

---

## 是什么

FTP（File Transfer Protocol）是历史最久、兼容性最好的文件传输协议，几乎所有操作系统和网络环境均原生支持。在制品管理体系中，FTP **不负责存储构建制品**，而是作为正式版本的**对外交付通道**——客户从 FTP 下载离线安装包，在内网环境中完成私有化部署，无需访问公司内网的 Harbor 或 MinIO。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **离线包交付** | 客户在完全隔离的内网也能下载完整安装包 |
| **断点续传** | 大包（数 GB）传输中断后可从断点继续，不用重传 |
| **目录浏览** | 客户可直观看到各版本目录，自助下载历史版本 |
| **账号隔离** | 按客户创建独立 FTP 账号，互不可见 |
| **零依赖** | 客户侧无需安装任何额外工具，`ftp` / `curl` / FileZilla 均可使用 |

---

## 与替代方案对比

| 维度 | FTP/FTPS | SFTP | OSS/S3 公网下载 | 邮件发送 |
|---|---|---|---|---|
| 客户侧要求 | 极低（系统自带）| 需 SSH 客户端 | 需公网访问 | 附件大小受限 |
| 传输安全 | ❌ 明文（FTPS 加密）| ✅ 全程加密 | ✅（HTTPS）| ❌ 不可控 |
| 断点续传 | ✅ | ✅ | ✅ | ❌ |
| 版本自助浏览 | ✅ 目录结构 | ✅ | ✅ | ❌ |
| 部署复杂度 | 低 | 低 | 中（需云账号）| 无 |
| **适用场景** | **离线内网客户交付** | 安全要求高的交付 | 公网客户自助下载 | 紧急小文件传输 |

> **选型结论**：FTP 是面向私有化部署客户的最低门槛交付方式。生产上应使用 FTPS（FTP over TLS）或替换为 SFTP，禁止使用明文 FTP 传输安装包。

---

## 适用场景

| 场景 | 使用 FTP | 不使用 FTP |
|---|---|---|
| 客户私有化部署，完全内网隔离 | ✅ | |
| 正式版本（semver Tag）交付包 | ✅ | |
| dev / rc 构建物 | | ❌（仅限 Harbor/MinIO 内部流转）|
| 包含镜像的完整离线包（数 GB）| ✅ | |
| 敏感配置文件（含密码）| | ❌（通过安全渠道单独交付）|

---

## 目录规范

```
/releases/
└── smartvision/
    ├── latest -> 1.2.0/           # 软链指向最新稳定版
    ├── 1.2.0/
    │   ├── smartvision-1.2.0.tar.gz        # 完整离线包
    │   ├── smartvision-1.2.0.tar.gz.sha256  # 完整性校验
    │   ├── manifest.json                    # 组件版本清单
    │   ├── CHANGELOG.md                     # 本版本变更说明
    │   └── install/
    │       ├── install.sh                   # 一键安装脚本
    │       ├── .env.template                # 环境变量模板（无真实密码）
    │       └── docker-compose.yaml
    └── 1.1.0/
        └── ...
```

---

## 账号权限规范

| 账号类型 | 权限 | 说明 |
|---|---|---|
| CI 上传账号 | 写（限 `/releases/` 目录）| 仅用于 GitLab CI 上传，不对外暴露 |
| 客户账号 | 只读（限客户自己目录）| 每客户独立账号，不能访问其他客户目录 |
| 运维账号 | 读写全目录 | 用于管理和清理历史版本 |

> CI 上传密码必须存为 GitLab **Protected Variable**，不能写在 `.gitlab-ci.yml` 明文中。

---

## CI 上传示例

```yaml
upload-ftp:
  stage: release
  script:
    - sha256sum smartvision-${CI_COMMIT_TAG}.tar.gz > smartvision-${CI_COMMIT_TAG}.tar.gz.sha256
    - |
      curl --ftp-create-dirs --ftp-ssl \
        -T smartvision-${CI_COMMIT_TAG}.tar.gz \
        ftps://${FTP_HOST}/releases/smartvision/${CI_COMMIT_TAG}/ \
        --user ${FTP_USER}:${FTP_PASS}
    - |
      curl --ftp-create-dirs --ftp-ssl \
        -T smartvision-${CI_COMMIT_TAG}.tar.gz.sha256 \
        ftps://${FTP_HOST}/releases/smartvision/${CI_COMMIT_TAG}/ \
        --user ${FTP_USER}:${FTP_PASS}
    - |
      curl --ftp-create-dirs --ftp-ssl \
        -T manifest.json \
        ftps://${FTP_HOST}/releases/smartvision/${CI_COMMIT_TAG}/ \
        --user ${FTP_USER}:${FTP_PASS}
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/'
      when: manual    # 正式上传需人工确认
```

---

## 客户下载示例

```bash
# 命令行下载（支持断点续传）
curl -C - -O ftps://releases.example.com/releases/smartvision/1.2.0/smartvision-1.2.0.tar.gz \
  --user customer-a:PASSWORD

# 验证完整性
sha256sum -c smartvision-1.2.0.tar.gz.sha256

# 解压并安装
tar -xzf smartvision-1.2.0.tar.gz
cd smartvision-1.2.0/install
cp .env.template .env && vi .env   # 填写客户自己的环境配置
bash install.sh
```

---

## 相关文档

| 文档 | 说明 |
|---|---|
| [制品管理规范.md](./制品管理规范.md) | 各类制品的存储位置与生命周期规范 |
| [minio.md](./minio.md) | 内部制品归档存储（JAR / 镜像 tar）|
