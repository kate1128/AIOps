# K8s 运维 FAQ

---

**Q1: 生产集群 K8s v1.20 已经 EOL 很久了，升级风险大吗？有什么前置条件？**

是的，v1.20 于 2021-12 EOL，现已超期约 4 年。升级的主要风险点：

1. **跨版本 API 废弃**：v1.20→v1.28 跨度大，部分 API 被移除（如 `extensions/v1beta1` Ingress 在 v1.22 移除）。升级前需用 `kubectl-convert` 检查 manifest 兼容性。
2. **dockershim 移除**：v1.24 正式移除，需先迁移到 containerd，详见 [优化方案.md](./优化方案.md) 第三节。
3. **HAMI 版本兼容**：升级前确认 HAMI 版本支持目标 K8s 版本，避免 GPU 调度失效。

前置条件：etcd 备份 → 容器运行时迁移 → 逐节点滚动升级。

---

**Q2: 生产 master 节点在 CentOS 7 上，能直接升级 K8s 吗？**

不建议，有两重风险：
- CentOS 7 内核（3.10.0）不支持 K8s v1.24+ 的部分特性（如 `cgroups v2`）
- CentOS 7 已于 2024-06-30 EOL，系统本身存在未修复漏洞

建议：先替换 master 节点到 Ubuntu 22.04（新节点加入集群 → 迁移 etcd 数据 → 摘除旧节点），再做 K8s 版本升级。

---

**Q3: etcd 备份后，如何验证备份文件是否可用？**

```bash
# 验证快照完整性（不会触发任何集群操作）
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-20260528.db --write-out=table
```

输出应包含：`Hash`、`Revision`、`Total Keys`、`Total Size`。若返回错误，备份文件损坏。

建议：每次备份后自动验证，并将验证结果发到告警通道。

---

**Q4: 一个节点 NotReady 对现有服务有多大影响？**

如果该节点上没有 Running Pod，影响仅是减少了一个调度槽位。但需要注意：
- NotReady 节点上的 Pod 会在 5 分钟后被标记为 `Unknown`，随后被 evict 到其他节点
- 如果集群资源已满，evict 后可能无法重新调度，导致服务中断

处理步骤见 [优化方案.md](./优化方案.md) 第 2.1 节。

---

**Q5: 从 NFS 迁移到块存储，PostgreSQL 需要停机吗？**

需要短暂停机（通常 10-30 分钟）。步骤：

1. 停写（应用层切维护模式或停止写入）
2. `pg_dump` 导出数据
3. 创建新的块存储 PVC，启动新 PostgreSQL 实例
4. `pg_restore` 导入数据
5. 验证数据一致性
6. 切换应用连接地址

如果需要更短停机时间，可以先用逻辑复制（pg_logical）做在线迁移，但配置更复杂。

---

**Q6: Flannel 不支持 NetworkPolicy，短期内怎么做命名空间隔离？**

Flannel 本身不处理 NetworkPolicy，但 Calico 的网络策略引擎可以独立于 CNI 运行（Calico 策略引擎 + Flannel 网络）。这样可以不换 CNI 前提下启用 NetworkPolicy。

不过更推荐的中期方案是在 dev/pre 环境直接替换为 Cilium：
- 支持 NetworkPolicy
- 提供 Hubble 网络流量观测
- 基于 eBPF，性能更好

---

**Q7: 多个 namespace 拆分后，运维复杂度会不会显著增加？**

初期会增加一些操作成本（切换 namespace、查看跨 ns 资源），但工具可以补偿：

- 使用 `kubens`（kubectx 套件）快速切换 namespace
- k9s 默认显示所有 namespace 的资源，切换成本低
- `kubectl get pods -A` 仍可一次查看全部

长期来看，隔离带来的安全性和可观测收益远大于操作成本。

---

**Q8: 客户私有化部署的 Ansible Playbook 怎么改进？**

当前问题：配置分散、无环境预检、无部署后验收。

最小改进方案：
1. 统一 `group_vars/all.yml` 作为中心配置文件
2. 增加 `roles/preflight/tasks/main.yml`（检查 OS 版本、内核、端口、依赖）
3. 增加 `roles/healthcheck/tasks/main.yml`（部署后验证各服务端点响应 200）

不需要重写，在现有 Playbook 基础上补充这两个 role 即可。
