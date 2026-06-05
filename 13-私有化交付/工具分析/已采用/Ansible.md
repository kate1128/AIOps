# Ansible — IT 自动化编排引擎

> 二进制/Docker 部署的标准化编排工具，无需 Agent，YAML 编写。
> 当前状态：✅ 已采用（待加强）

---

## 是什么

Ansible 是 Red Hat 开源的 IT 自动化平台，通过 SSH（Linux）/ WinRM（Windows）连接目标机器，使用 YAML Playbook 描述配置、部署和编排任务。最大优势是**无 Agent 架构**——目标机器只需要 Python 运行环境。

---

## 与替代方案对比

| 维度 | Ansible | Terraform |
|------|---------|-----------|
| **定位** | 配置管理 + 应用部署 | 基础设施即代码（IaC）|
| **状态管理** | 幂等，无状态文件 | 状态文件（.tfstate）|
| **语言** | YAML Playbook | HCL |
| **适用范围** | 服务器配置/应用部署/网络 | 云资源/基础设施管理 |
| **K8s** | ⚠️ 通过 shell 模块 | ✅ 原生 Provider |
| **Agent** | ❌ 无 Agent（SSH）| ❌ 无 Agent（API）|

---

## 当前用法

- Java 服务二进制部署 Playbook
- Docker 服务部署 Playbook（拉镜像 + docker compose up）
- 一键部署脚本，但配置需手动修改参数

> 见 `制品管理方案.md` 中的 Playbook 示例

---

## 引入 Ansible 加强你能得到什么

| 收益 | 说明 |
|------|------|
| ✅ 配置参数化 | 用 vars 和 inventory 替代手动改脚本 |
| ✅ 幂等执行 | 多次执行结果一致，不会重复部署 |
| ✅ 运维标准化 | Playbook 版本化，所有操作有记录 |

## 当前不足

| 不足 | 说明 |
|------|------|
| ❌ 配置分散 | 部署参数分散在多个 vars 文件中，无配置中心 |
| ❌ 缺乏 AWX | 没有 AWX/Tower 提供 Web UI 和调度能力 |
| ❌ 可视化弱 | 执行结果靠 CLI 输出，无 Dashboard |
