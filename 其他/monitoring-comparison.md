# Zabbix vs Prometheus vs Netdata 对比与部署方案

> 基于已有 K8s + GitLab CI + Nginx + 飞书/Jira 基础，三个监控方案的详细对比和可落地的部署脚本。

---

## 一、三句话总结

| 工具 | 一句话定位 | 适合谁 |
|---|---|---|
| **Zabbix** | 传统 IT 监控的"瑞士军刀"，功能全但配置重 | 运维老炮，习惯 GUI 管理，监控物理机和 VM 为主 |
| **Prometheus** | 云原生监控的事实标准，和 K8s 天生一对 | 有 K8s，愿意投入学习成本，追求可扩展性 |
| **Netdata** | 开箱即用的"监控速览"，安装即见 Dashboard | 想快速看到监控效果，不想折腾配置，小团队起步 |

---

## 二、详细对比

### 2.1 功能对比

| 维度 | Zabbix | Prometheus | Netdata |
|---|---|---|---|
| **部署方式** | Agent + Server（集中式） | Pull 模式，Exporter 暴露端点 | Agent 模式，本地部署 |
| **配置复杂度** | 高（GUI 点选 + 模板 + 触发器 + 动作分离） | **更高**（YAML + PromQL + Alertmanager + Grafana） | **极低**（自动发现，开箱即用） |
| **学习曲线** | 中等（GUI 友好，但概念多） | **陡峭**（PromQL 需专门学习） | **几乎没有**（安装完就能用） |
| **Dashboard** | 内置，但 UI 老旧 | 无，需 Grafana（另配） | **自动生成，现代 UI** |
| **K8s 集成** | 弱（需额外配置，非原生） | **原生支持**（ServiceMonitor 自动发现） | 中等（有 Helm Chart，但非原生） |
| **告警能力** | 内置完整（触发器 + 动作 + 媒介） | 需 Alertmanager（额外配置） | 基础，够用但不够灵活 |
| **存储** | MySQL/PostgreSQL（长期存储） | TSDB（默认 15 天，需 Thanos/VictoriaMetrics 扩展） | 内存 + 本地磁盘（默认几天，长期存储弱） |
| **扩展性** | 中等（自定义脚本、模板） | **极强**（PromQL + Exporter 生态丰富） | 较弱（自定义指标麻烦） |
| **社区生态** | 成熟但偏传统 | **云原生生态中心** | 活跃但相对小众 |

### 2.2 配置复杂度拆解

#### Zabbix 的配置链路

```
安装 Zabbix Server（MySQL + PHP + Web）
    ↓
安装 Zabbix Agent（每个被监控节点）
    ↓
在 Web UI 中配置：
    ├── Host（添加被监控主机）
    ├── Template（绑定监控模板：Linux、MySQL、Nginx 等）
    ├── Trigger（定义触发条件：CPU > 80%）
    ├── Action（定义动作：发送邮件/短信）
    └── Media（配置告警媒介：SMTP、Webhook）
```

**痛点：**
- 每新增一个监控项，要在 Web UI 里点选多次
- 模板和 Host 分离，容易遗漏
- Trigger 的表达式语法不直观：`{Linux:system.cpu.util[,user].last()}>80`
- 告警媒介配置分散（SMTP、Webhook、短信分别配置）

#### Prometheus 的配置链路

```
安装 Prometheus Server
    ↓
配置 prometheus.yml（抓取目标、告警规则）
    ↓
安装 Exporter（node-exporter、kube-state-metrics 等）
    ↓
配置 Alert Rules（YAML 定义告警条件）
    ↓
安装 Alertmanager（告警路由和通知）
    ↓
配置 alertmanager.yml（路由、接收人、通知渠道）
    ↓
安装 Grafana（可视化）
    ↓
配置 Grafana Dashboard（导入模板或自定义）
```

**痛点：**
- YAML 配置容易写错（缩进、格式）
- PromQL 查询语言需要专门学习：`rate(http_requests_total[5m]) > 0.05`
- 组件多：Prometheus + Exporter + Alertmanager + Grafana，每个都要配
- 告警链路长：触发 → Alertmanager → 路由 → Webhook → 飞书，任何环节断了都不知道

#### Netdata 的配置链路

```
安装 Netdata Agent
    ↓
自动发现所有服务和指标
    ↓
Dashboard 自动生成
    ↓
配置告警通知（Webhook 到飞书）
```

**优势：**
- 安装完就能看到所有服务的 CPU、内存、网络、磁盘图
- 不需要配置监控项，自动发现
- 不需要配 Dashboard，自动生成
- 内置常见告警规则（磁盘满、CPU 高、内存不足）

**劣势：**
- 自定义监控项困难（要写自定义 collector）
- 告警路由不够灵活（不能做 P0→电话、P1→飞书这种分级）
- 历史数据存储弱（默认几天，长期趋势看不了）

### 2.3 飞书告警接入对比

| 工具 | 接入方式 | 难度 | 灵活性 |
|---|---|---|---|
| **Zabbix** | Webhook → 飞书 Bot | 中等（需写脚本或配置 Webhook 媒介） | 中（支持告警分级、去重、升级） |
| **Prometheus** | Alertmanager Webhook → 飞书 Bot | 中等（需配置 Alertmanager + 飞书 Webhook） | **高**（支持复杂路由、静默、抑制） |
| **Netdata** | 内置 Webhook → 飞书 Bot | **简单**（UI 配置或配置文件） | **低**（基础通知，不支持复杂路由） |

---

## 三、三个方案部署脚本

### 方案 A：Zabbix 部署

#### 适用场景
- 你习惯 GUI 管理监控
- 监控对象以物理机/VM 为主，K8s 为辅
- 需要长期存储历史数据
- 团队有运维人员维护

#### 部署脚本（Docker Compose）

```yaml
# docker-compose.yml
version: '3.8'

services:
  zabbix-db:
    image: mysql:8.0
    container_name: zabbix-db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: zabbix_root_pass
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pass
    volumes:
      - zabbix-db-data:/var/lib/mysql
    networks:
      - zabbix-net

  zabbix-server:
    image: zabbix/zabbix-server-mysql:alpine-7.0-latest
    container_name: zabbix-server
    restart: always
    environment:
      DB_SERVER_HOST: zabbix-db
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pass
      MYSQL_ROOT_PASSWORD: zabbix_root_pass
    ports:
      - "10051:10051"
    depends_on:
      - zabbix-db
    networks:
      - zabbix-net

  zabbix-web:
    image: zabbix/zabbix-web-nginx-mysql:alpine-7.0-latest
    container_name: zabbix-web
    restart: always
    environment:
      ZBX_SERVER_HOST: zabbix-server
      DB_SERVER_HOST: zabbix-db
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pass
      MYSQL_ROOT_PASSWORD: zabbix_root_pass
      PHP_TZ: Asia/Shanghai
    ports:
      - "8080:8080"
    depends_on:
      - zabbix-db
      - zabbix-server
    networks:
      - zabbix-net

  zabbix-agent:
    image: zabbix/zabbix-agent:alpine-7.0-latest
    container_name: zabbix-agent
    restart: always
    environment:
      ZBX_HOSTNAME: "zabbix-server"
      ZBX_SERVER_HOST: "zabbix-server"
    networks:
      - zabbix-net

volumes:
  zabbix-db-data:

networks:
  zabbix-net:
    driver: bridge
```

#### 部署步骤

```bash
# 1. 创建目录
mkdir -p /opt/zabbix && cd /opt/zabbix

# 2. 写入 docker-compose.yml（上面的内容）
cat > docker-compose.yml <<'EOF'
# ... 上面的 docker-compose.yml 内容 ...
EOF

# 3. 启动
sudo docker-compose up -d

# 4. 访问 Web UI
# http://<your-server-ip>:8080
# 默认账号：Admin / zabbix

# 5. 配置飞书告警
# 进入 Zabbix Web UI → 管理 → 报警媒介类型 → 创建媒体类型
# 类型：Webhook
# 参数：
#   URL: https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_WEBHOOK_TOKEN
#   Message: {ALERT.MESSAGE}
```

#### Zabbix Agent 安装（被监控节点）

```bash
# Debian/Ubuntu
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu22.04_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu22.04_all.deb
sudo apt update
sudo apt install -y zabbix-agent2
sudo systemctl enable --now zabbix-agent2

# 配置 Agent
sudo sed -i 's/Server=127.0.0.1/Server=<zabbix-server-ip>/' /etc/zabbix/zabbix_agent2.conf
sudo sed -i 's/ServerActive=127.0.0.1/ServerActive=<zabbix-server-ip>/' /etc/zabbix/zabbix_agent2.conf
sudo systemctl restart zabbix-agent2
```

---

### 方案 B：Prometheus + Grafana 部署

#### 适用场景
- 你有 K8s，想监控 Pod、Service、Ingress
- 愿意投入学习成本，追求可扩展性
- 需要自定义复杂的监控指标和告警
- 团队有 DevOps/SRE 人员维护

#### 部署脚本（K8s + Helm）

```bash
# 1. 添加 Helm 仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 2. 创建命名空间
kubectl create namespace observability

# 3. 部署 kube-prometheus-stack（一键部署 Prometheus + Alertmanager + Grafana）
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --set grafana.enabled=true \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.retention=30d \
  --set alertmanager.alertmanagerSpec.replicas=1

# 4. 查看部署状态
kubectl get pods -n observability

# 5. 暴露 Grafana 端口（临时访问）
kubectl port-forward -n observability svc/kube-prometheus-grafana 3000:80

# 6. 访问 Grafana
# http://localhost:3000
# 账号：admin / admin123
```

#### 配置 Prometheus 告警规则

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: service-health-rules
  namespace: observability
spec:
  groups:
    - name: service-health
      rules:
        - alert: ServiceDown
          expr: up == 0
          for: 1m
          labels:
            severity: P0
          annotations:
            summary: "服务 {{ $labels.instance }} 不可达"
            
        - alert: HighErrorRate
          expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
          for: 2m
          labels:
            severity: P1
          annotations:
            summary: "服务 {{ $labels.instance }} 错误率超过 5%"
            
        - alert: HighLatency
          expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
          for: 3m
          labels:
            severity: P1
          annotations:
            summary: "服务 {{ $labels.instance }} P99 延迟超过 2s"
```

#### 配置 Alertmanager 飞书通知

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: observability
stringData:
  alertmanager.yml: |
    global:
      smtp_smarthost: 'localhost:25'
    
    route:
      receiver: 'feishu-webhook'
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
    
    receivers:
      - name: 'feishu-webhook'
        webhook_configs:
          - url: 'https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_WEBHOOK_TOKEN'
            send_resolved: true
            http_config:
              headers:
                Content-Type: application/json
```

#### 二进制服务接入 Prometheus

```yaml
# 方式 A：Blackbox Exporter（无侵入）
# 部署 blackbox-exporter
helm install blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  --namespace observability

# 配置 Prometheus 抓取
# 在 prometheus.yml 或 ServiceMonitor 中添加：
- job_name: 'binary-services'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - http://binary-service-1:8080/health
      - http://binary-service-2:8080/health

# 方式 B：Prometheus Client（侵入式，但信息更丰富）
# 在二进制服务代码中加入 Prometheus client 库
# Python 示例：
from prometheus_client import start_http_server, Counter, Histogram
import time

# 创建指标
request_count = Counter('http_requests_total', 'Total requests', ['method', 'endpoint'])
request_duration = Histogram('http_request_duration_seconds', 'Request duration')

# 启动 metrics 服务
start_http_server(9090)

# 在请求处理中记录指标
@request_duration.time()
def handle_request():
    request_count.labels(method='GET', endpoint='/api').inc()
    # ... 业务逻辑 ...
```

---

### 方案 C：Netdata 部署

#### 适用场景
- 想快速看到监控效果，不想折腾配置
- 小团队，没有专职运维
- 监控需求简单（CPU、内存、磁盘、网络、基础服务）
- 不需要复杂的告警路由

#### 部署脚本（K8s + Helm）

```bash
# 1. 添加 Helm 仓库
helm repo add netdata https://netdata.github.io/helmchart/
helm repo update

# 2. 创建命名空间
kubectl create namespace observability

# 3. 部署 Netdata
helm install netdata netdata/netdata \
  --namespace observability \
  --set parent.configs.notifications.slack.enabled=true \
  --set parent.configs.notifications.slack.webhook="https://open.feishu.cn/open-apis/bot/v2/hook/3eeade21-583d-4fa8-9f0c-6d0bf8a86278"

# 4. 查看部署状态
kubectl get pods -n observability

# 5. 暴露 Netdata UI
kubectl port-forward -n observability svc/netdata-parent 19999:19999

# 6. 访问 Netdata
# http://localhost:19999
```

#### Netdata 飞书告警配置

```yaml
# 编辑 Netdata 告警配置文件
# 路径：/etc/netdata/health_alarm_notify.conf

# 1. 配置 Webhook 通知
SEND_Feishu="YES"
FEISHU_WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_WEBHOOK_TOKEN"

# 2. 重启 Netdata
sudo systemctl restart netdata
```

#### Netdata 自定义告警规则

```yaml
# 路径：/etc/netdata/health.d/my_custom_alarm.conf

# CPU 使用率告警
alarm: high_cpu_usage
    on: system.cpu
lookup: average -3m unaligned of user,system,softirq,irq,guest
  units: %
  every: 10s
   warn: $this > 80
   crit: $this > 95
   info: CPU utilization is high
     to: sysadmin

# 磁盘使用率告警
alarm: high_disk_usage
    on: disk_space._
lookup: maximum -3m unaligned of used
  units: %
  every: 10s
   warn: $this > 80
   crit: $this > 95
   info: Disk space is running low
     to: sysadmin
```

---

## 四、三个方案快速上手对比

### 4.1 看到第一个 Dashboard 需要多久

| 方案 | 时间 | 步骤 |
|---|---|---|
| **Zabbix** | ~15 分钟 | `docker-compose up -d` → 访问 8080 → 账号 Admin/zabbix → 点"监测" → "主机" → 等 Agent 上报 |
| **Prometheus + Grafana** | ~10 分钟 | `helm install` → `kubectl port-forward` → 账号 admin/admin123 → 导入 Dashboard 模板 → 看到 K8s 集群指标 |
| **Netdata** | **~5 分钟** | `helm install` → `kubectl port-forward` → 直接看到自动生成的 Dashboard |

### 4.2 配置第一个告警需要多久

| 方案 | 时间 | 复杂度 |
|---|---|---|
| **Zabbix** | ~30 分钟 | 中（Web UI 点选：配置 → 主机 → 触发器 → 动作 → 媒介） |
| **Prometheus** | ~1 小时 | **高**（写 YAML → 应用规则 → 配置 Alertmanager → 配置 Webhook） |
| **Netdata** | **~10 分钟** | **低**（修改配置文件 → 重启服务，内置规则已生效） |

### 4.3 接入飞书告警需要多久

| 方案 | 时间 | 复杂度 |
|---|---|---|
| **Zabbix** | ~20 分钟 | 中（创建 Webhook 媒介 → 配置动作 → 测试） |
| **Prometheus** | ~30 分钟 | **高**（写 Alertmanager YAML → 配置 Webhook → 测试告警链路） |
| **Netdata** | **~10 分钟** | **低**（修改 health_alarm_notify.conf → 重启服务） |

---

## 五、我的建议

### 如果你时间紧迫（这周就要出效果）

**选 Netdata**。
- 5 分钟出 Dashboard
- 10 分钟配置好飞书告警
- 不需要学 PromQL
- 缺点：长期存储弱、告警路由不灵活（但小团队够用）

```bash
# 一键部署
helm install netdata netdata/netdata --namespace observability --create-namespace
kubectl port-forward -n observability svc/netdata-parent 19999:19999
# 访问 http://localhost:19999
```

### 如果你追求长期治理（愿意投入时间）

**选 Prometheus + Grafana**。
- 和 K8s 天生一对
- PromQL 强大，可以写复杂查询
- 生态丰富，Exporter 很多
- 缺点：配置复杂，需要学习成本

```bash
# 一键部署
helm install kube-prometheus prometheus-community/kube-prometheus-stack --namespace observability --create-namespace --set grafana.adminPassword=admin123
kubectl port-forward -n observability svc/kube-prometheus-grafana 3000:80
# 访问 http://localhost:3000 (admin/admin123)
```

### 如果你习惯传统运维

**选 Zabbix**。
- GUI 管理友好
- 功能全面（监控、告警、资产管理、网络发现）
- 适合物理机和 VM 为主的场景
- 缺点：K8s 支持弱，配置繁琐

```bash
# Docker Compose 一键部署
docker-compose up -d
# 访问 http://localhost:8080 (Admin/zabbix)
```

---

## 六、混合方案（我的推荐）

如果你不想选，可以**先用 Netdata 应急，再逐步迁移到 Prometheus**：

```
Week 1：部署 Netdata
  → 快速看到监控效果
  → 配置飞书告警（CPU、内存、磁盘）
  → 团队先习惯"有监控看"

Week 2-3：并行部署 Prometheus + Grafana
  → 只监控 K8s 核心服务
  → 学习 PromQL
  → 配置复杂告警（错误率、延迟）

Week 4+：逐步替代
  → Netdata 保留做"快速查看"
  → Prometheus 做"长期趋势和复杂告警"
  → 团队熟悉后，Netdata 可以下线
```

这样你既能在短期内出效果，又能为长期治理打基础。

---

## 七、下一步

建议你**三个都试一遍**（每个 30 分钟足够），然后告诉我：
- 哪个部署最顺利？
- 哪个 Dashboard 看起来最舒服？
- 哪个告警配置你觉得最顺手？

我可以根据你的实际体验，帮你敲定最终的监控方案。
