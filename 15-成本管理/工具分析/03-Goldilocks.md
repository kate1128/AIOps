# Goldilocks — 资源配额优化助手

> 基于 VPA 推荐值，帮助你给 Pod 设置合理的 request/limit。

---

## 是什么

Goldilocks 是一款轻量工具，用 VPA 推荐值告诉你“资源给多了还是给少了”，用于 right-sizing。

---

## 核心能力

- 查看每个 Deployment 的 CPU/内存建议值
- 快速识别过度配置和配置不足
- 与 VPA 联动进行持续优化

---

## 适用场景

- 资源 request 常年凭感觉填写
- 集群利用率低，成本偏高
- 希望每周做一次资源优化

---

## 实践建议

- 每两周拉一次推荐值
- 先在 staging 调整，再推广生产
- 调整后观察 7 天稳定性和成本变化

---

## GitHub 信息

- 开源状态：开源
- 仓库地址：https://github.com/FairwindsOps/goldilocks
- Star：3.2k（统计日期：2026-05-27）

