# K8s 版本升级规范

> 适用于三套自建/托管集群的版本升级操作，每次升级前必须严格遵守此流程。

---

## 一、升级原则

1. **不允许跨两个大版本升级**：v1.20 → v1.22 → v1.24，不能 v1.20 → v1.24
2. **etcd 备份是前置条件**：升级前必须验证备份文件可用
3. **dev 先行 → pre 验证 → 生产执行**
4. **worker 先于 master 升级**（降低控制面风险）

---

## 二、升级前检查清单

```bash
# 1. 检查当前集群状态
kubectl get nodes
kubectl get cs   # 检查 controller-manager、scheduler、etcd 健康

# 2. 检查 API 版本废弃（使用 pluto 工具）
pluto detect-files -d . --target-versions k8s=v1.22
# 或使用 kubectl-convert 检查 manifest 兼容性

# 3. 备份 etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-pre-upgrade-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 4. 验证备份
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-pre-upgrade-$(date +%Y%m%d).db --write-out=table

# 5. 确认容器运行时版本（v1.24+ 需要 containerd，不支持 dockershim）
kubectl get nodes -o wide | awk '{print $1, $9}'
```

---

## 三、容器运行时迁移（v1.24 前必做）

```bash
# 在每个节点执行

# 1. 安装 containerd
apt-get update
apt-get install -y containerd.io

# 2. 生成默认配置并修改 pause 镜像
containerd config default > /etc/containerd/config.toml
sed -i 's|sandbox_image = "registry.k8s.io/pause:3.6"|sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.9"|' \
  /etc/containerd/config.toml

# 3. 启用 SystemdCgroup（K8s 推荐）
sed -i 's|SystemdCgroup = false|SystemdCgroup = true|' /etc/containerd/config.toml

# 4. 配置 kubelet 使用 containerd
cat > /etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock
EOF

# 5. 重启
systemctl restart containerd
systemctl restart kubelet

# 6. 验证节点状态恢复 Ready
kubectl get node <node-name>
```

---

## 四、Master 节点升级步骤

```bash
# 以从 v1.20 升级到 v1.22 为例

# 1. drain master（允许驱逐 DaemonSet）
kubectl drain <master-node> --ignore-daemonsets --delete-emptydir-data

# 2. 安装目标版本 kubeadm
apt-get install -y kubeadm=1.22.16-00

# 3. 检查升级计划
kubeadm upgrade plan

# 4. 执行升级
kubeadm upgrade apply v1.22.16

# 5. 升级 kubelet 和 kubectl
apt-get install -y kubelet=1.22.16-00 kubectl=1.22.16-00
systemctl daemon-reload
systemctl restart kubelet

# 6. uncordon 节点
kubectl uncordon <master-node>

# 7. 验证
kubectl get nodes
```

---

## 五、Worker 节点升级步骤（逐一执行）

```bash
# 1. 在 master 上 drain worker
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data

# 2. SSH 进入 worker 节点，升级 kubeadm
apt-get install -y kubeadm=1.22.16-00
kubeadm upgrade node

# 3. 升级 kubelet
apt-get install -y kubelet=1.22.16-00 kubectl=1.22.16-00
systemctl daemon-reload
systemctl restart kubelet

# 4. 在 master 上恢复调度
kubectl uncordon <worker-node>

# 5. 等待节点 Ready 后再处理下一个节点（不要批量操作）
kubectl get node <worker-node> -w
```

---

## 六、升级后验证

```bash
# 检查所有节点版本一致
kubectl get nodes

# 检查核心组件健康
kubectl get pods -n kube-system

# 检查 coredns、ingress-nginx 版本兼容性
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get pods -n ingress-nginx

# 跑一个简单的 Pod 验证调度正常
kubectl run test-upgrade --image=nginx --rm -it --restart=Never -- echo "upgrade ok"
```

---

## 七、回滚（etcd 恢复）

> 只有在升级导致集群完全不可用时才执行，正常情况用 kubeadm upgrade 的回滚机制。

```bash
# 停止 kubelet 和 kube-apiserver
systemctl stop kubelet
# 移走 kube-apiserver manifest 文件（静态 Pod 会被停止）
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/

# 恢复 etcd 快照
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-pre-upgrade-20260528.db \
  --data-dir=/var/lib/etcd-restore

# 更新 etcd 数据目录（修改 etcd.yaml 中的 data-dir）
# 重启服务
mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
systemctl start kubelet
```
