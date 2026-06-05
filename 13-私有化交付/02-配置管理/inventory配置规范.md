# inventory 配置规范

> `inventory.yml` 是私有化交付的唯一配置入口，所有客户差异均通过此文件体现，Playbook 本身不含硬编码值。

---

## 一、字段说明

### 通用字段（所有版本必填）

| 字段 | 类型 | 说明 | 示例 |
|---|---|---|---|
| `product_version` | string | 部署的产品版本号 | `2.1.0` |
| `harbor_image_prefix` | string | 镜像仓库前缀 | `harbor.internal/platform` |
| `app_domain` | string | 客户访问域名 | `wenxue.customer-a.com` |
| `data_root` | string | 数据持久化根目录 | `/data/wenxue` |
| `mysql_root_password` | vault | MySQL root 密码（Vault 加密）| `{{ vault_mysql_root_password }}` |
| `mysql_db_name` | string | 数据库名 | `wenxue` |
| `redis_password` | vault | Redis 密码（Vault 加密）| `{{ vault_redis_password }}` |
| `enable_https` | bool | 是否启用 HTTPS | `true` |
| `install_mysql` | bool | 是否安装 MySQL（客户自备时设 false）| `true` |
| `install_redis` | bool | 是否安装 Redis | `true` |

### AI 版专用字段（`enable_ai: true` 时必填）

| 字段 | 类型 | 说明 | 示例 |
|---|---|---|---|
| `enable_ai` | bool | 是否部署 AI 推理服务 | `true` |
| `vllm_model_path` | string | 模型文件在服务器上的路径 | `/data/models/Qwen2-7B` |
| `vllm_model_name` | string | 模型服务名（API 调用用）| `qwen2-7b` |
| `vllm_gpu_memory_limit` | int | 显存限制（MiB）| `20000` |
| `vllm_tensor_parallel` | int | 张量并行数（多卡时填 > 1）| `1` |

### 客户已有中间件（跳过安装时填写）

| 字段 | 说明 |
|---|---|
| `mysql_host` / `mysql_port` | 客户自备 MySQL 的连接地址 |
| `redis_host` / `redis_port` | 客户自备 Redis 的连接地址 |
| `es_host` / `es_port` | 客户自备 Elasticsearch |

---

## 二、主机组规范

| 组名 | 说明 | 必须 |
|---|---|---|
| `app-server` | 部署应用服务的节点 | ✅ |
| `db-server` | 部署 MySQL / Redis / ES 的节点 | ✅（或客户自备）|
| `gpu-server` | 部署 vLLM 推理服务的 GPU 节点 | AI 版必须 |

单节点部署时，所有组可以指向同一台服务器。

---

## 三、配置模板

### 标准版（单节点，不含 AI）

```yaml
# inventory/template-standard.yml
all:
  vars:
    product_version: "2.1.0"
    harbor_image_prefix: "harbor.internal/platform"
    app_domain: "wenxue.example.com"
    data_root: "/data/wenxue"
    enable_https: true
    enable_ai: false
    install_mysql: true
    install_redis: true
    install_elasticsearch: true
    mysql_db_name: "wenxue"
    mysql_root_password: "{{ vault_mysql_root_password }}"
    redis_password: "{{ vault_redis_password }}"

  hosts:
    app-server:
      ansible_host: 10.0.0.1
      ansible_user: ubuntu
      ansible_ssh_private_key_file: ~/.ssh/customer_key
    db-server:
      ansible_host: 10.0.0.1    # 单节点时与 app-server 相同
      ansible_user: ubuntu
      ansible_ssh_private_key_file: ~/.ssh/customer_key
```

### AI 版（多节点）

```yaml
# inventory/template-ai.yml
all:
  vars:
    product_version: "2.1.0"
    harbor_image_prefix: "harbor.internal/platform"
    app_domain: "wenxue.example.com"
    data_root: "/data/wenxue"
    enable_https: true
    enable_ai: true
    install_mysql: true
    install_redis: true
    install_elasticsearch: true
    mysql_db_name: "wenxue"
    mysql_root_password: "{{ vault_mysql_root_password }}"
    redis_password: "{{ vault_redis_password }}"
    # AI 专用配置
    vllm_model_path: "/data/models/Qwen2-7B"
    vllm_model_name: "qwen2-7b"
    vllm_gpu_memory_limit: 20000
    vllm_tensor_parallel: 1

  hosts:
    app-server:
      ansible_host: 10.0.0.1
      ansible_user: ubuntu
      ansible_ssh_private_key_file: ~/.ssh/customer_key
    db-server:
      ansible_host: 10.0.0.2
      ansible_user: ubuntu
      ansible_ssh_private_key_file: ~/.ssh/customer_key
    gpu-server:
      ansible_host: 10.0.0.3
      ansible_user: ubuntu
      ansible_ssh_private_key_file: ~/.ssh/customer_key
```

### 客户自备数据库

```yaml
# 在 vars 中添加，并设置 install_* 为 false
all:
  vars:
    install_mysql: false
    install_redis: false
    mysql_host: "10.0.0.5"
    mysql_port: 3306
    redis_host: "10.0.0.6"
    redis_port: 6379
    # mysql_root_password 仍需填写，用于初始化数据库和账号
    mysql_root_password: "{{ vault_mysql_root_password }}"
```

---

## 四、敏感变量加密

所有密码类字段必须用 Ansible Vault 加密，禁止明文存放：

```bash
# 加密单个变量值
ansible-vault encrypt_string 'StrongPassword123!' --name 'vault_mysql_root_password'

# 输出如下，粘贴到 inventory.yml 的对应字段
vault_mysql_root_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  38363137353834303339...

# 执行 Playbook 时解密
ansible-playbook site.yml -i inventory/customer-a.yml --ask-vault-pass

# 或用 vault 密码文件（推荐 CI/CD 场景）
ansible-playbook site.yml -i inventory/customer-a.yml --vault-password-file .vault_pass
```

**`.vault_pass` 文件禁止提交到代码仓库**，加入 `.gitignore`。

---

## 五、文件命名规范

| 场景 | 文件名 | 说明 |
|---|---|---|
| 新客户模板 | `template-standard.yml` / `template-ai.yml` | 不直接修改，复制后改 |
| 具体客户 | `{customer-id}.yml` | 如 `customer-a.yml` |
| 存档（已交付）| `{customer-id}-{version}-{date}.yml` | 如 `customer-a-2.1.0-20260528.yml` |

每次交付完成后，将 `{customer-id}.yml`（脱敏版，密码替换为 `***`）作为交付物归档到制品管理系统。
