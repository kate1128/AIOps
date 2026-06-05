# 成本管理 FAQ

---

**Q1：GPU 节点成本很高，但不知道钱花在哪个模型/服务上，怎么办？**

需要两个数据源结合：
1. **DCGM Exporter**：采集每张 GPU 的显存使用量，按 Pod 归因
2. **K8s 标签**：每个 vLLM Pod 打 `model=qwen-7b` 标签

两者结合在 Grafana 看板上可以看到：哪个模型占了多少 GPU 成本。

前置条件：先完成 GPU 监控接入，见 [02-AI Infra 基建/优化方案.md](../02-AI\ Infra\ 基建/优化方案.md)。

---

**Q2：Kubecost 免费版和付费版有什么区别？需要付费吗？**

对于当前规模，免费版（开源版）完全够用：

| 功能 | 免费版 | 付费版 |
|---|---|---|
| Namespace/Workload 成本 | ✅ | ✅ |
| 多集群汇总 | ❌ | ✅ |
| 历史数据保留 | 15 天 | 无限 |
| 成本预测 | ❌ | ✅ |

15 天历史数据对于月度复盘够用。多集群汇总（生产+pre+dev 一起看）需要付费版，暂时可以分别部署三套免费版。

---

**Q3：dev 环境是否需要做成本管理？**

dev 环境不需要精细化管理，但至少要做：
- 下班自动关机（GPU 节点成本高，晚上不用时关掉）
- 设置 ResourceQuota 防止误操作大量申请资源

dev GPU 节点（RTX4090）关机命令参考：

```bash
# 定时关机（例如每天 22:00 关机，8:00 开机）
# 在阿里云 ECS 控制台配置定时开关机，或用阿里云定时任务
```

---

**Q4：发现某个服务的成本突然增加了很多，如何排查？**

```bash
# 1. 查看该服务的 Pod 资源使用变化
kubectl top pods -n <namespace> --sort-by=memory

# 2. 查看 Kubecost 该 Namespace 成本趋势（Kubecost UI）

# 3. 查看 HPA 是否触发了扩容
kubectl get hpa -n <namespace>

# 4. 查看是否有新的 Pod 被调度到了 GPU 节点
kubectl get pods -n <namespace> -o wide | grep <gpu-node>
```

---

**Q5：资源 request 和 limit 应该怎么设置才合理？**

经验原则：
- `request` = 服务正常负载下的 P95 使用量
- `limit` = request × 2（留峰值 buffer）
- **不要把 request 和 limit 设成一样**（会导致调度器过于保守）

使用 Goldilocks 或 VPA（Vertical Pod Autoscaler）自动给出建议值，比手动估算准确。

```bash
# 查看 VPA 建议
kubectl get vpa -n ai-infra
```
