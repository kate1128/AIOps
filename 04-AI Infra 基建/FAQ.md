# AI Infra 基建 FAQ

---

**Q1：宿主机直跑的 vLLM 进程和 K8s Pod 内的进程有什么区别？如何识别？**

核心区别是是否经过 K8s 调度器。用以下命令判断：

```bash
# 有输出 = K8s 容器内进程（正常，受 HAMI 管控）
cat /proc/<PID>/cgroup | grep kubepods

# 无输出 = 宿主机直跑进程（问题：HAMI 不可见，显存不受限）
```

宿主机直跑进程的风险：占用 GPU 显存不受任何配额约束，且 K8s 监控中不体现，会出现"HAMI 显示显存充足，实际 OOM"的情况。发现后应迁移到 K8s 管理，或至少记录到 GPU 资产清单中。

---

**Q2：HAMI 能限制宿主机进程吗？**

不能。HAMI 只管控通过 K8s 申请了 `nvidia.com/gpu` 资源的容器。宿主机直跑进程绕过 K8s 调度，HAMI 完全看不见。要管控宿主机进程，需要在宿主机层面设置显存上限（NVIDIA MPS）或强制要求所有推理服务必须通过 K8s 部署。

---

**Q3：多节点 vLLM 版本不一致会有什么问题？**

主要风险：
1. **行为差异**：不同版本对同一模型的推理结果可能略有不同（采样参数、tokenization 差异）
2. **运维复杂**：故障排查时需要确认具体版本，增加排查链路
3. **接口不兼容**：vLLM API 变化较频繁，旧版本可能不支持新参数

建议：用 K8s 统一管理 vLLM 实例后，在 Helm values 中统一锁定版本号，禁止各节点独立升级。

---

**Q4：GPU 驱动四个版本并存（535/550/570/580），需要统一吗？**

短期内不是必须，但需要注意：
- 镜像的 CUDA 版本要兼容最低驱动版本（当前是 535.x，支持 CUDA ≤ 12.2）
- 新模型可能要求 CUDA 12.4+，在 535.x 节点上无法运行
- 建议新节点统一用最新稳定驱动（推荐 550.x），存量节点在维护窗口逐步升级

升级驱动前务必确认：该节点上的 K8s Pod 已迁移，驱动升级需重启节点。

---

**Q5：DCGM Exporter 怎么部署？会影响 GPU 性能吗？**

```bash
# 用 Helm 部署（推荐）
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace observability \
  --set serviceMonitor.enabled=true
```

DCGM Exporter 以 DaemonSet 运行，采集间隔默认 15s，对 GPU 性能影响极小（< 0.1%）。部署后在 Grafana 导入 Dashboard ID 12239 即可看到每张 GPU 的显存、利用率、温度指标。

---

**Q6：如何反馈问题或建议？**

在 GPU 资产清单中补充节点信息，或在 AI Infra 周会中提出。紧急 GPU 故障（OOM、节点 NotReady）走 SRE OnCall 流程。
