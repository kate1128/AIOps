# Kubecost — Kubernetes 成本可视化

> 按 Namespace/Workload/Label 拆解 K8s 成本，回答“钱花在哪里”。

---

## 是什么

Kubecost 是云原生成本分析平台，基于集群资源使用与云账单价格模型计算成本。

---

## 核心能力

- 成本按团队/服务/环境归因
- 预算与阈值告警
- 闲置资源识别（idle cost）
- 成本优化建议（right-sizing）

---

## 关键视图

- Namespace 成本 TopN
- GPU 成本占比
- 闲置成本趋势
- 预测下月成本

---

## 实践建议

- 统一标签体系（team/service/env/owner）
- 与周报机制绑定，按团队追责到 owner
- 预算告警必须进飞书群

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/kubecost/cost-analyzer
- Star：54（统计日期：2026-05-27）

