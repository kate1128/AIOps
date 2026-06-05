# GPU 进程级监控与成本归因方案

> 解决"谁跑了多少 GPU"的监控和成本分摊问题。

---

## 一、问题拆解

| 监控维度 | 卡级指标（默认） | 进程级指标（需要配置） |
|---|---|---|
| GPU 利用率 | 整卡利用率 % | **每个进程的利用率** |
| 显存使用 | 整卡显存使用 | **每个进程的显存占用** |
| 功耗 | 整卡功耗 | 不支持 |
| 温度 | 整卡温度 | 不支持 |

---

## 二、命令行查看（最快验证）

### 2.1 查看 GPU 上的进程

```bash
# 查看每个 GPU 上的进程
nvidia-smi

# 输出示例：
# +---------------------------------------------------------------------------------------+
# | NVIDIA-SMI 535.104.05             Driver Version: 535.104.05   CUDA Version: 12.2     |
# |-----------------------------------------+----------------------+----------------------+
# | GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr.ECC  |
# | Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
# |                                         |                      |               MIG M. |
# |=========================================+======================+======================|
# |   0  NVIDIA A100-SXM4-40GB            On  | 00000000:00:04.0 Off |                    0 |
# | N/A   45C    P0             400W / 400W |  38912MiB / 40960MiB |    100%      Default |
# |                                         |                      |             Disabled |
# +-----------------------------------------+----------------------+----------------------+
#
# +---------------------------------------------------------------------------------------+
# | Processes:                                                                            |
# |  GPU   GI   CI        PID   Type   Process name                             GPU Memory |
# |        ID   ID                                                             Usage      |
# |=======================================================================================|
# |    0   N/A  N/A    123456    C   python /app/inference.py                  20480MiB |
# |    0   N/A  N/A    123789    C   python /app/training.py                 18432MiB |
# +---------------------------------------------------------------------------------------+
```

### 2.2 持续监控每个进程的 GPU 使用

```bash
# 实时监控（1秒刷新）
nvidia-smi pmon -s um -d 1

# 输出示例：
# # gpu        pid  type    sm   mem   enc   dec   jpg   ofo  command
# #  Idx          #   C/G     %     %     %     %     %     %
#     0     123456     C    50    40     -     -     -     -  python
#     0     123789     C    30    20     -     -     -     -  python

# 字段说明：
# gpu   -- GPU 卡号
# pid   -- 进程 PID
# type  -- C=Compute(计算), G=Graphics(图形)
# sm    -- SM(SM=Streaming Multiprocessor) 利用率
# mem   -- 显存带宽利用率
# enc   -- 编码器利用率
# dec   -- 解码器利用率
# command -- 进程命令
```

### 2.3 查看进程详细信息

```bash
# 查看每个进程的显存占用
nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory,used_memory --format=csv

# 输出示例：
# pid, process_name, used_gpu_memory [MiB], used_memory [MiB]
# 123456, python, 20480 MiB, 20480 MiB
# 123789, python, 18432 MiB, 18432 MiB
```

---

## 三、Prometheus 进程级 GPU 监控

### 3.1 DCGM Exporter 进程级指标配置

DCGM Exporter 从 v3.0 开始支持进程级指标，但需要配置特定的字段 ID。

```yaml
# dcgm-exporter-config.yaml
# 配置进程级监控字段
apiVersion: v1
kind: ConfigMap
metadata:
  name: dcgm-exporter-custom-config
  namespace: observability
data:
  dcgm-exporter.csv: |
    # GPU 卡级指标
    DCGM_FI_DEV_GPU_UTIL,              gauge, GPU utilization (%)
    DCGM_FI_DEV_MEM_COPY_UTIL,         gauge, Memory utilization (%)
    DCGM_FI_DEV_GPU_TEMP,            gauge, GPU temperature (C)
    DCGM_FI_DEV_POWER_USAGE,           gauge, Power draw (W)
    DCGM_FI_DEV_FB_FREE,             gauge, Frame buffer free (MiB)
    DCGM_FI_DEV_FB_USED,             gauge, Frame buffer used (MiB)
    
    # 进程级指标（关键！）
    DCGM_FI_PROF_GR_ENGINE_ACTIVE,   gauge, GPU engine active (%)
    DCGM_FI_PROF_SM_ACTIVE,          gauge, SM active (%)
    DCGM_FI_PROF_SM_OCCUPANCY,       gauge, SM occupancy (%)
    DCGM_FI_PROF_PIPE_TENSOR_ACTIVE, gauge, Tensor pipe active (%)
    DCGM_FI_PROF_DRAM_ACTIVE,        gauge, DRAM active (%)
    DCGM_FI_PROF_PCIE_TX_BYTES,      counter, PCIe TX bytes
    DCGM_FI_PROF_PCIE_RX_BYTES,      counter, PCIe RX bytes
    DCGM_FI_PROF_NVLINK_TX_BYTES,    counter, NVLink TX bytes
    DCGM_FI_PROF_NVLINK_RX_BYTES,    counter, NVLink RX bytes
```

### 3.2 部署支持进程级监控的 DCGM Exporter

```bash
# 方式 A：Helm 部署（自定义字段）
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# 下载默认配置并修改
helm show values nvidia/dcgm-exporter > dcgm-values.yaml

# 编辑 dcgm-values.yaml，添加进程级字段
# 关键配置：
cudaVersion: 12.2
arguments:
  -f /etc/dcgm-exporter/dcp-metrics-included.csv  # 使用包含进程级指标的配置文件

# 部署
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace observability \
  --set serviceMonitor.enabled=true \
  --set arguments="-f,/etc/dcgm-exporter/custom-config.csv" \
  --set-file configMap.data.custom-config.csv=./dcgm-exporter.csv
```

### 3.3 进程级指标详解

```promql
# 查看每个 GPU 上各进程的 SM 利用率
dcgm_prof_sm_active

# 查看每个 GPU 上各进程的显存占用（通过 DCGM_FI_DEV_FB_USED 结合进程信息）
# 注意：DCGM Exporter 本身不直接暴露进程 PID，需要通过 nv-hostengine 获取
```

**注意**：DCGM Exporter 的进程级指标是**采样级别**的，不是实时的 PID 级。要获取**实时的进程-GPU 映射**，需要结合 NVIDIA 的 nv-hostengine 或者自定义脚本。

---

## 四、自定义 Exporter：精确到进程和用户的 GPU 监控

如果你需要**精确的"谁跑了多少 GPU"**，建议写一个自定义 Exporter，通过 `nvidia-smi` 获取进程信息并暴露为 Prometheus 指标。

### 4.1 自定义 GPU 进程 Exporter（Python）

```python
#!/usr/bin/env python3
"""
gpu-process-exporter.py
通过 nvidia-smi 获取进程级 GPU 占用，暴露为 Prometheus 指标
"""

from prometheus_client import start_http_server, Gauge, Info
import subprocess
import json
import time
import re

# 定义指标
gpu_process_memory = Gauge(
    'gpu_process_memory_mib',
    'GPU memory used by process (MiB)',
    ['gpu', 'pid', 'user', 'command']
)

gpu_process_utilization = Gauge(
    'gpu_process_utilization_percent',
    'GPU SM utilization by process (%)',
    ['gpu', 'pid', 'user', 'command']
)

gpu_process_count = Gauge(
    'gpu_process_count',
    'Number of processes per GPU',
    ['gpu']
)

def get_gpu_processes():
    """通过 nvidia-smi 获取 GPU 进程信息"""
    try:
        # 获取进程信息（JSON 格式）
        result = subprocess.run(
            ['nvidia-smi', '--query-compute-apps=pid,process_name,used_gpu_memory,gpu_name,gpu_bus_id',
             '--format=csv,noheader'],
            capture_output=True, text=True, check=True
        )
        
        processes = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            # 解析：pid, process_name, used_gpu_memory, gpu_name, gpu_bus_id
            parts = [p.strip() for p in line.split(',')]
            if len(parts) >= 3:
                pid = parts[0]
                process_name = parts[1]
                memory_str = parts[2]
                
                # 解析显存（去掉 "MiB"）
                memory = 0
                if 'MiB' in memory_str:
                    memory = float(memory_str.replace('MiB', '').strip())
                elif 'GiB' in memory_str:
                    memory = float(memory_str.replace('GiB', '').strip()) * 1024
                
                # 获取进程用户信息（通过 ps 命令）
                try:
                    user_result = subprocess.run(
                        ['ps', '-p', pid, '-o', 'user=', '--no-headers'],
                        capture_output=True, text=True
                    )
                    user = user_result.stdout.strip() or 'unknown'
                except:
                    user = 'unknown'
                
                processes.append({
                    'gpu': '0',  # 简化处理，实际应解析 GPU 索引
                    'pid': pid,
                    'user': user,
                    'command': process_name,
                    'memory_mib': memory
                })
        
        return processes
    except subprocess.CalledProcessError as e:
        print(f"Error running nvidia-smi: {e}")
        return []

def get_gpu_process_utilization():
    """获取每个进程的 GPU SM 利用率"""
    try:
        result = subprocess.run(
            ['nvidia-smi', 'pmon', '-s', 'um', '-c', '1'],
            capture_output=True, text=True, check=True
        )
        
        utilization = {}
        for line in result.stdout.strip().split('\n')[2:]:  # 跳过表头
            parts = line.split()
            if len(parts) >= 3:
                gpu = parts[0]
                pid = parts[1]
                sm = parts[2] if parts[2] != '-' else '0'
                utilization[pid] = {
                    'gpu': gpu,
                    'sm': float(sm)
                }
        return utilization
    except:
        return {}

def update_metrics():
    """更新 Prometheus 指标"""
    # 清空旧指标（避免进程退出后指标残留）
    gpu_process_memory.clear()
    gpu_process_utilization.clear()
    
    # 获取进程信息
    processes = get_gpu_processes()
    utilizations = get_gpu_process_utilization()
    
    # 统计每个 GPU 的进程数
    gpu_counts = {}
    for proc in processes:
        gpu = proc['gpu']
        gpu_counts[gpu] = gpu_counts.get(gpu, 0) + 1
        
        # 设置显存指标
        gpu_process_memory.labels(
            gpu=gpu,
            pid=proc['pid'],
            user=proc['user'],
            command=proc['command']
        ).set(proc['memory_mib'])
        
        # 设置 SM 利用率
        sm_util = utilizations.get(proc['pid'], {}).get('sm', 0)
        gpu_process_utilization.labels(
            gpu=gpu,
            pid=proc['pid'],
            user=proc['user'],
            command=proc['command']
        ).set(sm_util)
    
    # 设置每个 GPU 的进程数
    gpu_process_count.clear()
    for gpu, count in gpu_counts.items():
        gpu_process_count.labels(gpu=gpu).set(count)

if __name__ == '__main__':
    # 启动 HTTP 服务
    start_http_server(9090)
    print("GPU Process Exporter started on port 9090")
    
    # 定期更新指标
    while True:
        update_metrics()
        time.sleep(15)  # 15秒更新一次
```

### 4.2 部署自定义 Exporter

```yaml
# gpu-process-exporter-deployment.yaml
apiVersion: apps/v1
kind: DaemonSet  # 每个 GPU 节点都跑一个
metadata:
  name: gpu-process-exporter
  namespace: observability
spec:
  selector:
    matchLabels:
      app: gpu-process-exporter
  template:
    metadata:
      labels:
        app: gpu-process-exporter
    spec:
      hostPID: true  # 必须！需要访问宿主机的 nvidia-smi
      containers:
      - name: exporter
        image: python:3.11-slim
        command:
        - /bin/sh
        - -c
        - |
          pip install prometheus_client &&
          python /app/gpu-process-exporter.py
        volumeMounts:
        - name: exporter-script
          mountPath: /app
        - name: nvidia-smi
          mountPath: /usr/bin/nvidia-smi
        resources:
          limits:
            memory: "256Mi"
            cpu: "100m"
      volumes:
      - name: exporter-script
        configMap:
          name: gpu-process-exporter-script
      - name: nvidia-smi
        hostPath:
          path: /usr/bin/nvidia-smi
      nodeSelector:
        nvidia.com/gpu.present: "true"  # 只在 GPU 节点运行
---
apiVersion: v1
kind: Service
metadata:
  name: gpu-process-exporter
  namespace: observability
  labels:
    app: gpu-process-exporter
spec:
  selector:
    app: gpu-process-exporter
  ports:
  - name: metrics
    port: 9090
    targetPort: 9090
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gpu-process-exporter
  namespace: observability
spec:
  selector:
    matchLabels:
      app: gpu-process-exporter
  endpoints:
  - port: metrics
    interval: 15s
```

### 4.3 Prometheus 查询示例

```promql
# 1. 查看每个用户占用了多少 GPU 显存
sum by (user) (gpu_process_memory_mib)

# 2. 查看每个 GPU 上各进程的显存占用
gpu_process_memory_mib

# 3. 查看占用 GPU 显存最多的 Top 10 进程
topk(10, gpu_process_memory_mib)

# 4. 查看每个 GPU 的进程数
gpu_process_count

# 5. 查看每个用户的 GPU SM 利用率
sum by (user) (gpu_process_utilization_percent)
```

---

## 五、Kubernetes Pod 级别 GPU 监控

如果你在 K8s 上跑 AI 任务，更需要的是**Pod 级别的 GPU 监控**（而不是进程级别）。

### 5.1 使用 NVIDIA Device Plugin + DCGM Exporter

```bash
# NVIDIA Device Plugin 会自动注入 GPU 信息到 Pod 环境变量
# Pod 内可以通过以下环境变量获取 GPU 信息：
# - NVIDIA_VISIBLE_DEVICES
# - NVIDIA_DRIVER_CAPABILITIES

# DCGM Exporter 通过 Pod Label 关联 GPU 指标
# 关键：需要配置 ServiceMonitor 抓取 Pod 级别的指标
```

### 5.2 Pod 级别 GPU 监控（推荐）

```yaml
# 在 Prometheus 中使用 kubelet cadvisor 指标
cadvisor 指标路径：/metrics/cadvisor

# 关键指标：
# container_gpu_usage_seconds_total    -- Pod 使用 GPU 的时间
# container_gpu_memory_usage_bytes     -- Pod 使用 GPU 显存（字节）

# 注意：需要 kubelet 开启 GPU 指标采集
# 在 kubelet 配置中开启：
# --enable-cadvisor-json-apis=true
```

### 5.3 使用 KubeGPU 或 GPU Operator

```bash
# NVIDIA GPU Operator（推荐，已包含 DCGM Exporter）
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --set dcgmExporter.enabled=true \
  --set dcgmExporter.serviceMonitor.enabled=true

# GPU Operator 会自动：
# 1. 安装 NVIDIA Driver
# 2. 安装 NVIDIA Container Toolkit
# 3. 安装 Device Plugin
# 4. 安装 DCGM Exporter（带 Pod 级别指标）
```

### 5.4 Pod 级别 GPU 查询

```promql
# 查看每个 Pod 使用的 GPU 显存
dcgmi_gpu_memory_used_bytes / 1024 / 1024  # 转换为 MiB

# 查看每个 Namespace 的 GPU 使用量
sum by (namespace) (dcgmi_gpu_memory_used_bytes)

# 查看每个 Pod 的 GPU 利用率
sum by (namespace, pod) (dcgmi_gpu_utilization)
```

---

## 六、成本归因方案

### 6.1 按用户/项目分摊 GPU 成本

```python
#!/usr/bin/env python3
"""
gpu-cost-attribution.py
按用户和项目统计 GPU 使用量，用于成本分摊
"""

import requests
import json
from datetime import datetime, timedelta

PROMETHEUS_URL = "http://prometheus:9090"

def get_gpu_usage_by_user(start_time, end_time):
    """
    查询指定时间段内每个用户的 GPU 使用量
    """
    query = """
    sum by (user) (
        avg_over_time(gpu_process_memory_mib[1h])
    )
    """
    
    response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={
        "query": query,
        "time": end_time
    })
    
    return response.json()

def generate_cost_report(start_time, end_time, gpu_hourly_cost=10.0):
    """
    生成 GPU 成本报告
    
    Args:
        start_time: 开始时间
        end_time: 结束时间
        gpu_hourly_cost: GPU 每小时成本（元）
    """
    usage = get_gpu_usage_by_user(start_time, end_time)
    
    print("=" * 60)
    print(f"GPU 成本归因报告 ({start_time} - {end_time})")
    print("=" * 60)
    
    total_cost = 0
    for item in usage.get('data', {}).get('result', []):
        user = item['metric'].get('user', 'unknown')
        memory_mib = float(item['value'][1])
        
        # 简化的成本计算（实际应基于时间积分）
        cost = memory_mib / 40960 * gpu_hourly_cost  # 假设单卡 40GB
        total_cost += cost
        
        print(f"用户: {user}")
        print(f"  GPU 显存占用: {memory_mib:.2f} MiB")
        print(f"  预估成本: {cost:.2f} 元")
        print()
    
    print(f"总计: {total_cost:.2f} 元")

# 生成昨日报告
if __name__ == '__main__':
    end_time = datetime.now()
    start_time = end_time - timedelta(days=1)
    
    generate_cost_report(
        start_time.isoformat(),
        end_time.isoformat()
    )
```

### 6.2 Grafana Dashboard 配置

```json
{
  "dashboard": {
    "title": "GPU 进程级监控与成本归因",
    "panels": [
      {
        "title": "各用户 GPU 显存占用",
        "type": "piechart",
        "targets": [
          {
            "expr": "sum by (user) (gpu_process_memory_mib)",
            "legendFormat": "{{ user }}"
          }
        ]
      },
      {
        "title": "各进程 GPU 显存占用 Top 10",
        "type": "table",
        "targets": [
          {
            "expr": "topk(10, gpu_process_memory_mib)",
            "format": "table",
            "instant": true
          }
        ]
      },
      {
        "title": "GPU 进程数趋势",
        "type": "graph",
        "targets": [
          {
            "expr": "sum by (gpu) (gpu_process_count)",
            "legendFormat": "GPU {{ gpu }}"
          }
        ]
      }
    ]
  }
}
```

---

## 七、完整方案总结

| 监控需求 | 方案 | 部署难度 | 精确度 |
|---|---|---|---|
| **快速查看 GPU 进程** | `nvidia-smi pmon` | 无 | 实时 PID 级 |
| **Prometheus 卡级指标** | DCGM Exporter 默认配置 | 低 | 卡级 |
| **Prometheus 进程级指标** | 自定义 GPU Process Exporter | 中 | PID 级 |
| **K8s Pod 级别 GPU** | GPU Operator + DCGM Exporter | 低 | Pod 级 |
| **成本归因** | 自定义脚本 + Prometheus 查询 | 中 | 用户/项目级 |

### 推荐部署顺序

```
Step 1: 部署 DCGM Exporter（卡级指标）
    ↓
Step 2: 部署 GPU Process Exporter（进程级指标）
    ↓
Step 3: 配置 Grafana Dashboard（进程 + 用户 + 成本）
    ↓
Step 4: 接入飞书告警（高 GPU 占用告警）
    ↓
Step 5: 成本归因脚本（每日/每周自动生成报告）
```

### 关键告警规则

```yaml
# gpu-alerts.yaml
groups:
  - name: gpu-process
    rules:
      - alert: GPUHighMemoryUsage
        expr: gpu_process_memory_mib > 30000  # 单个进程占用超过 30GB
        for: 5m
        labels:
          severity: P1
        annotations:
          summary: "进程 {{ $labels.command }}(PID: {{ $labels.pid }}) 占用 GPU 显存过高"
          
      - alert: GPUTooManyProcesses
        expr: gpu_process_count > 10  # 单个 GPU 进程数过多
        for: 10m
        labels:
          severity: P2
        annotations:
          summary: "GPU {{ $labels.gpu }} 进程数过多，可能影响性能"
          
      - alert: GPUProcessHung
        expr: gpu_process_memory_mib > 1000 and gpu_process_utilization_percent == 0
        for: 30m
        labels:
          severity: P2
        annotations:
          summary: "进程 {{ $labels.command }} 占用 GPU 但无计算活动，可能已卡死"
```

---

## 八、下一步行动

1. **先验证 nvidia-smi 进程监控**（5 分钟）：
   ```bash
   nvidia-smi pmon -s um -d 1
   ```

2. **部署自定义 GPU Process Exporter**（30 分钟）：
   ```bash
   kubectl apply -f gpu-process-exporter-deployment.yaml
   ```

3. **配置 Prometheus 抓取和 Grafana Dashboard**（1 小时）

4. **接入飞书告警**（30 分钟）

试完后告诉我：
- `nvidia-smi pmon` 能看到进程信息吗？
- 需要我把自定义 Exporter 打包成 Docker 镜像吗？
- GPU 成本归因的粒度要到什么级别（用户/项目/团队）？
