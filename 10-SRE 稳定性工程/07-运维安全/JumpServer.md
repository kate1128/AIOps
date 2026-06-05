# JumpServer — 统一运维审计堡垒机

> 所有服务器、数据库、K8s 的统一登录入口，支持权限管控、操作审计、会话录像。

---

## 是什么

JumpServer 是开源的堡垒机（Bastion Host）系统，提供统一的运维入口和操作审计平台。运维人员不再直接 SSH 到服务器，而是通过 JumpServer 登录，系统记录所有操作命令和会话视频，满足安全合规要求。

---

## 核心能力

| 能力 | 说明 |
|---|---|
| **统一登录入口** | SSH/RDP/SFTP/数据库/K8s 全部走 JumpServer |
| **资产管理** | 树形结构管理所有服务器、数据库、网络设备 |
| **权限控制** | 按用户组、资产组、时间段精细授权 |
| **操作审计** | 命令记录、会话录像、支持回放 |
| **命令过滤** | 高危命令（`rm -rf`、`DROP TABLE`）自动拦截或告警 |
| **数据库代理** | MySQL、PostgreSQL、Redis、MongoDB 通过 JumpServer 连接 |
| **K8s 接入** | 直接在 JumpServer 中 `kubectl exec` 进入容器 |
| **多因素认证** | 支持 TOTP、短信、LDAP 集成 |
| **批量命令** | 一条命令批量在多台主机执行 |

---

## 适用场景

- **合规审计**：等保 2.0、SOC2 要求的操作留痕
- **最小权限原则**：开发只能访问测试环境，DBA 才能访问生产数据库
- **外包/临时人员管控**：临时授权，有效期后自动收回
- **数据库统一管控**：DBA 不直接持有数据库密码，通过 JumpServer 连接
- **离职员工权限回收**：一键禁用账号，所有资产权限同步失效

---

## 与本项目的关系

```
运维人员 / 开发人员
    │
    └── JumpServer（统一入口）
            │
            ├── Linux 服务器（SSH）── 生产 / 预发 / 开发
            ├── Windows 服务器（RDP）
            ├── 数据库（MySQL / PostgreSQL / Redis）
            ├── K8s（kubectl）── 集群操作
            └── 网络设备（SSH / Telnet）
                    │
                    └── 所有操作 ──→ 审计日志 + 会话录像
```

---

## Docker Compose 快速部署

```bash
# 官方一键安装脚本
curl -sSL https://github.com/jumpserver/jumpserver/releases/latest/download/quick_start.sh | bash

# 或 Docker Compose
git clone --depth=1 https://github.com/jumpserver/Dockerfile.git
cd Dockerfile
cp config_example.conf .env
# 编辑 .env，修改 SECRET_KEY 和 BOOTSTRAP_TOKEN
docker compose up -d

# 默认访问 http://localhost
# 默认账号：admin / ChangeMe
```

### 生产环境关键配置（.env）

```bash
# .env
SECRET_KEY=<随机32位字符串，务必修改>
BOOTSTRAP_TOKEN=<随机16位字符串，务必修改>
DB_HOST=postgres-host
DB_PORT=5432
DB_USER=jumpserver
DB_PASSWORD=<强密码>
DB_NAME=jumpserver
REDIS_HOST=redis-host
```

---

## 资产接入示例

### 批量导入服务器（CSV）

```csv
hostname,ip,port,protocol,platform,username,password,comment
prod-web-01,192.168.1.10,22,ssh,Linux,root,,生产 Web 服务器
prod-db-01,192.168.1.20,3306,mysql,MySQL,admin,,生产数据库
```

### 命令过滤（高危命令拦截）

```yaml
# 在 JumpServer 后台配置命令过滤规则
危险命令示例：
  - rm -rf /
  - DROP DATABASE
  - TRUNCATE TABLE
  - shutdown
  - reboot
动作：拒绝 / 告警 / 审批
```

---

## 权限矩阵设计

| 角色 | 可访问资产 | 权限 |
|---|---|---|
| 开发工程师 | 开发/测试服务器 | SSH 只读，禁止 root |
| 运维工程师 | 全部服务器 | SSH 完整权限 |
| DBA | 所有数据库 | 数据库连接，禁止 DROP |
| 外包人员 | 特定资产 | 限时授权（N 天内有效） |
| 安全审计 | 无操作权限 | 只读审计日志和录像 |

---

## 与其他工具的集成

| 集成点 | 说明 |
|---|---|
| LDAP / AD | 统一账号认证，离职自动失效 |
| Zabbix | 资产信息同步（JumpServer 作为 CMDB 来源） |
| Prometheus | JumpServer 暴露 `/metrics`，监控在线会话数 |
| 钉钉/飞书 | 登录通知、高危命令告警 |
| Vault（HashiCorp） | 动态密码，JumpServer 不存储明文密码 |

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/jumpserver/jumpserver
- Star：30.5k（统计日期：2026-05-27）

