# 私有化交付 FAQ

---

**Q1：客户服务器在完全内网，无法访问 Harbor 拉镜像怎么办？**

使用离线安装包方案。在有网络的环境预先打包所有镜像：

```bash
# 构建离线包（在有网络的机器上执行）
bash build-offline-package.sh v2.1.0

# 将生成的 wenxue-2.1.0-offline.tar.gz 传给客户（FTP 或 U 盘）

# 客户在内网解压执行
tar -xzf wenxue-2.1.0-offline.tar.gz
bash install.sh
```

详见 [优化方案.md Phase 3](./优化方案.md)。

---

**Q2：客户已有自己的 MySQL/Redis，不想我们重装怎么办？**

在 `inventory.yml` 中设置跳过标志，并填写客户已有数据库连接信息：

```yaml
# inventory/customer-a.yml
all:
  vars:
    install_mysql: false      # 不安装 MySQL
    install_redis: false      # 不安装 Redis
    mysql_host: 10.0.0.5      # 客户已有 MySQL 地址
    mysql_port: 3306
    redis_host: 10.0.0.6
    redis_port: 6379
```

部署前需确认客户 MySQL 版本 ≥ 8.0，Redis ≥ 6.0。

---

**Q3：preflight 检查发现端口 80 被占用怎么处理？**

两种方案选一个：

1. **要求客户停用占用端口的服务**：先用 `ss -tlnp | grep :80` 找到是哪个进程，请客户停用或迁移
2. **改变我们的端口**：在 `inventory.yml` 中修改 `app_port: 8080`，通知客户访问 `:8080`

不允许强行覆盖端口，会导致客户现有服务中断。

---

**Q4：部署中途失败了，能重新执行 Playbook 吗？**

可以，Ansible Playbook 设计为幂等的，重复执行不会造成重复安装。直接重新执行：

```bash
ansible-playbook -i inventory/{customer-name}.yml playbooks/site.yml
```

如果某个 Role 持续失败，加 `--start-at-task` 从失败处开始：

```bash
ansible-playbook -i inventory/{customer-name}.yml playbooks/site.yml \
  --start-at-task "启动应用服务"
```

---

**Q5：客户 OS 是 CentOS 7 能部署吗？**

可以，但有限制：
- CentOS 7 内核 3.10 不支持部分 Docker 新特性，建议 Docker 版本使用 24.x 而非最新
- CentOS 7 已于 2024-06-30 EOL，建议客户升级到 Ubuntu 22.04
- `vm.max_map_count` 参数需要手动持久化到 `/etc/sysctl.conf`，否则重启后失效

---

**Q6：AI 版部署后模型加载很慢（超过 10 分钟）是正常的吗？**

取决于模型大小和存储速度：
- 7B 模型约 14 GB，从 NFS 加载可能需要 5-10 分钟
- 如果存储在本地 SSD 上，通常 2-3 分钟

判断是否异常：执行 `docker logs vllm-service --tail=50` 查看是否在正常加载日志还是报错。

正常日志示例：`Loading weights took XX seconds`、`Model is ready`

---

**Q7：部署完成后客户要求修改域名怎么办？**

```bash
# 修改 inventory 中的域名
vim inventory/{customer-name}.yml
# 修改 app_domain 值

# 只重新执行 Nginx 相关 Role
ansible-playbook -i inventory/{customer-name}.yml playbooks/site.yml \
  --tags "nginx,cert"
```

注意：如果使用了 SSL 证书，需要先申请新域名的证书再执行。

---

**Q8：如何给客户追加 GPU 节点（AI 版扩容）？**

```bash
# 在 inventory 中新增 gpu-server2
vim inventory/{customer-name}.yml
# 新增：
#   gpu-server2:
#     ansible_host: 10.0.0.4

# 只对新节点执行 GPU 相关 Role
ansible-playbook -i inventory/{customer-name}.yml playbooks/site.yml \
  --limit gpu-server2 --tags "docker,nvidia,vllm"
```
