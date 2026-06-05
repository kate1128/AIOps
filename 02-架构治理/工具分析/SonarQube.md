# SonarQube — 代码质量与技术债静态分析平台

> 通过静态分析持续量化代码中的 Bug、漏洞、异味和技术债，让架构治理有数据依据而非主观感受。

---

## 是什么

SonarQube 是最主流的开源代码质量管理平台，内置超过 5000 条规则，覆盖 Java、Python、JavaScript/TypeScript、Go 等 30+ 语言。分为 Community（免费开源）和 Developer/Enterprise（付费）版本。

---

## 核心能力

| 维度 | 说明 |
|------|------|
| **Bug 检测** | 代码逻辑缺陷、空指针、资源泄漏等静态 Bug |
| **安全漏洞（SAST）** | 注入、XSS、硬编码密钥等 OWASP Top 10 漏洞 |
| **代码异味** | 过长函数、重复代码、圈复杂度过高等可维护性问题 |
| **技术债量化** | 以时间（分钟/天）量化修复所有问题的估算工时 |
| **覆盖率集成** | 接收 JaCoCo/Istanbul 覆盖率数据，与质量门禁联动 |
| **质量门禁（Quality Gate）** | 设置阈值，新增代码不达标则 CI 失败 |

---

## 与 SmartVision 现状的契合

- Java 服务代码质量缺乏客观度量，技术债积累无感知
- AI backend（Python）和 Scheduler 服务缺少统一 SAST 检测
- 架构债没有可视化，消减计划没有量化目标

**SonarQube 可以直接解决**：给出每个服务的技术债小时数、代码异味数，为架构债管理提供客观基线。

---

## 部署步骤（K8s 内网自托管）

### Step 1：准备 PostgreSQL 数据库

```sql
-- 在现有 PostgreSQL 实例执行
CREATE DATABASE sonarqube;
CREATE USER sonarqube WITH PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonarqube;
```

### Step 2：Helm 部署 SonarQube

```yaml
# sonarqube-values.yaml
postgresql:
  enabled: false                 # 不用内置 PG，对接现有实例

jdbcDatabaseType: postgresql
jdbcUrl: "jdbc:postgresql://postgres.smartvision.svc:5432/sonarqube"
jdbcUsername: sonarqube
jdbcPassword: "your-password"   # 生产环境改用 K8s Secret 注入

resources:
  requests:
    memory: "2Gi"
    cpu: "500m"
  limits:
    memory: "4Gi"
    cpu: "2"

service:
  type: NodePort
  nodePort: 30900                # 固定端口，方便记住和配置 CI
```

```bash
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update
helm install sonarqube sonarqube/sonarqube \
  --namespace devtools --create-namespace \
  -f sonarqube-values.yaml
```

部署完成后确认节点 IP 和端口：

```bash
# 查看 NodePort 端口（应该是 30900）
kubectl get svc -n devtools sonarqube-sonarqube

# 查看任意一个 K8s 工作节点的 IP
kubectl get nodes -o wide
```

**访问地址说明**（两种场景，地址不同）：

| 场景 | 地址格式 | 说明 |
|------|---------|------|
| 开发者浏览器访问 | `http://<节点IP>:30900` | 用任意一个 K8s 工作节点的内网 IP |
| GitLab CI 脚本访问 | `http://sonarqube-sonarqube.devtools.svc.cluster.local:9000` | K8s 集群内部 Service DNS，Runner 在集群内才能用 |

> 首次启动约 2-3 分钟。浏览器打开 `http://<节点IP>:30900`，默认账密 `admin/admin`，**登录后立即修改密码**。

---

## 生成 SONAR_TOKEN 并配置到 GitLab

SONAR_TOKEN 是 GitLab CI 访问 SonarQube 的凭证，**全程内网**，不涉及外部服务。

```
1. 浏览器打开 http://<节点IP>:30900，登录 SonarQube
2. 右上角头像 → My Account → Security → Generate Token
   Token Name: gitlab-ci
   Token Type: Global Analysis Token
3. 复制生成的 token（只显示一次）
4. GitLab 项目 → Settings → CI/CD → Variables
   Key:   SONAR_TOKEN
   Value: <刚才的 token>
   勾选 Masked（防止在 CI 日志中显示明文）
```

---

## GitLab CI 接入

**每个仓库根目录**新增 `sonar-project.properties`（提交到 Git，不含密钥）：

```properties
sonar.projectKey=my-service-name
sonar.projectName=My Service
sonar.sources=src/main
sonar.tests=src/test
sonar.java.binaries=target/classes     # Java 项目
# sonar.python.version=3               # Python 项目取消注释
sonar.sourceEncoding=UTF-8
```

在 `.gitlab-ci.yml` 新增扫描 job：

```yaml
sonarqube-scan:
  stage: analysis
  image: sonarsource/sonar-scanner-cli:latest
  variables:
    # GitLab Runner 在 K8s 集群内部，用 Service 内部 DNS，不用 IP+端口
    SONAR_HOST_URL: "http://sonarqube-sonarqube.devtools.svc.cluster.local:9000"
    SONAR_TOKEN: $SONAR_TOKEN          # 从 GitLab Variables 读取
  script:
    - sonar-scanner
  only:
    - main
    - merge_requests
  allow_failure: true    # 初期建议 true，观察 2 周基线后改为 false 启用门禁
```

---

## Quality Gate 建议配置

在 SonarQube 管理界面配置，只检查**新增代码**（避免历史债务淹没团队）：

| 条件 | 阈值 |
|------|------|
| 新增代码覆盖率 | < 60% 则 Fail |
| 新增 Bug 数 | > 0 则 Fail |
| 新增 Critical 漏洞 | > 0 则 Fail |
| 新增重复代码率 | > 5% 则 Warn |

---

## 实践建议

1. **先扫不挡 CI**：`allow_failure: true` 运行 2 周，摸清各服务技术债基线，再开质量门禁
2. **只管新增代码**：Quality Gate 配置 `new_code` 范围，历史债务单独排期消减
3. **月报驱动消减**：每月导出技术债 Top 10，作为架构债管理 backlog 的具体条目

---

## REST API：查询扫描结果

SonarQube 所有数据都通过 REST API 可查，认证方式为 Basic Auth（用户名填 SONAR_TOKEN，密码留空）。

**本地调试时**先用 port-forward，不需要记 NodePort：

```bash
kubectl port-forward svc/sonarqube-sonarqube -n devtools 9000:9000
# 另开终端，此时 localhost:9000 即 SonarQube
```

**月报脚本在 K8s Job 中运行时**，直接用 Service 内部 DNS：`http://sonarqube-sonarqube.devtools.svc.cluster.local:9000`

### 查询单个项目的当前指标

```bash
# 本地调试（port-forward 后）
curl -u "$SONAR_TOKEN:" \
  "http://localhost:9000/api/measures/component?\
component=java-backend&\
metricKeys=complexity,duplicated_lines_density,coverage,code_smells,bugs,vulnerabilities,sqale_index"
```

**示例返回**：

```json
{
  "component": {
    "key": "java-backend",
    "name": "Java Backend",
    "measures": [
      { "metric": "complexity",               "value": "1842"  },
      { "metric": "duplicated_lines_density", "value": "8.3"   },
      { "metric": "coverage",                 "value": "31.2"  },
      { "metric": "code_smells",              "value": "247"   },
      { "metric": "bugs",                     "value": "12"    },
      { "metric": "vulnerabilities",          "value": "3"     },
      { "metric": "sqale_index",              "value": "2880"  }
    ]
  }
}
```

> `sqale_index` 单位是**分钟**，2880 = 48 小时修复成本。

---

### 查询历史趋势（用于月报对比）

```bash
curl -u "$SONAR_TOKEN:" \
  "http://localhost:9000/api/measures/search_history?\
component=java-backend&\
metrics=bugs,code_smells,coverage,sqale_index&\
from=2026-04-01&to=2026-05-01&ps=30"
```

**示例返回**：

```json
{
  "measures": [
    {
      "metric": "bugs",
      "history": [
        { "date": "2026-04-05T10:00:00+0000", "value": "9"  },
        { "date": "2026-04-20T14:30:00+0000", "value": "11" },
        { "date": "2026-05-03T09:15:00+0000", "value": "12" }
      ]
    },
    {
      "metric": "sqale_index",
      "history": [
        { "date": "2026-04-05T10:00:00+0000", "value": "2400" },
        { "date": "2026-05-03T09:15:00+0000", "value": "2880" }
      ]
    }
  ]
}
```

> 用这个接口计算环比：上月末 value vs 本月末 value，即可得出"Bug 数环比 +33%"。

---

### 查询问题明细（具体到文件和行号）

```bash
# 查询 java-backend 的所有 Critical 以上 Bug，按严重程度排序
curl -u "$SONAR_TOKEN:" \
  "http://localhost:9000/api/issues/search?\
componentKeys=java-backend&\
types=BUG&\
severities=CRITICAL,BLOCKER&\
resolved=false&\
ps=20"
```

**示例返回**（精简）：

```json
{
  "total": 5,
  "issues": [
    {
      "key": "AYx1234",
      "rule": "java:S2259",
      "severity": "CRITICAL",
      "component": "java-backend:src/main/java/com/smartvision/OrderService.java",
      "line": 87,
      "message": "A \"NullPointerException\" could be thrown; \"order\" is nullable here.",
      "effort": "10min",
      "creationDate": "2026-05-03T09:15:22+0000"
    }
  ]
}
```

> `effort` 是 SonarQube 估算的修复时间，`rule` 是触发的规则 ID，可在界面查规则说明。

---

### 常用 Metrics Key 速查

| Metric Key | 含义 | 单位 |
|------------|------|------|
| `bugs` | Bug 数量 | 个 |
| `vulnerabilities` | 安全漏洞数 | 个 |
| `code_smells` | 代码异味数 | 个 |
| `sqale_index` | 技术债总量 | 分钟 |
| `sqale_debt_ratio` | 技术债率（债/开发成本）| % |
| `coverage` | 测试覆盖率 | % |
| `duplicated_lines_density` | 重复代码率 | % |
| `complexity` | 圈复杂度总和 | - |
| `cognitive_complexity` | 认知复杂度（更贴近可读性）| - |
| `ncloc` | 非注释代码行数 | 行 |

---

## Dashboard 使用指南

浏览器访问 `http://<节点IP>:30900`，登录后各页面内容如下：

### 项目概览页

进入某个项目后，首页展示四象限健康状态：

```
┌─────────────────────────────────────────────────┐
│  Reliability     Security      Maintainability  │
│  🔴 12 Bugs      🟡 3 Vulns    🟡 247 Smells    │
│  Rating: D       Rating: C     Rating: C        │
│                                                  │
│  Coverage: 31.2%              Duplications: 8.3%│
│  ──────────────               ─────────────     │
│  Quality Gate: ❌ FAILED      技术债: 48h       │
└─────────────────────────────────────────────────┘
```

- **Rating A-E**：SonarQube 给每个维度打分，A 最好，E 最差
- **Quality Gate 状态**：红色 = 本次 MR 未达标，对应 CI 中的 Block

### 问题列表页（Issues）

可按以下维度筛选，定位具体问题：

| 筛选维度 | 可选值 |
|---------|--------|
| 类型 | Bug / Vulnerability / Code Smell / Security Hotspot |
| 严重级别 | Blocker / Critical / Major / Minor / Info |
| 状态 | Open / Confirmed / Resolved / Won't Fix |
| 文件 | 支持路径前缀搜索 |
| 创建时间 | 可筛选"本周新增"、"本月新增" |

每条问题点进去可以看到：代码高亮标注、违反的规则说明、修复建议示例、估算修复时间。

### 趋势图页（Activity）

项目页顶部 **Activity** 标签，展示：

- **各指标随时间变化的折线图**（Bug 数、覆盖率、技术债）
- **每次扫描的版本标记**（可以和发布版本对应）
- **Quality Gate 通过/失败历史**

> 折线图是向管理层汇报"技术债在变好还是变差"的直接素材。

### 全局项目列表页

首页展示所有项目的汇总视图：

```
项目名称          Quality Gate   Bugs   Coverage   技术债
──────────────────────────────────────────────────────
java-backend      ❌ Failed      12     31.2%      48h
ai-backend        ✅ Passed       2     67.4%       6h
scheduler         ✅ Passed       0     72.1%       2h
```

> 这个视图直接复制粘贴就能作为月报的数据表格基础。

---

| 对比项 | SonarQube | CodeClimate |
|--------|-----------|-------------|
| 部署方式 | 自托管 | 云 SaaS / CLI 本地 |
| 免费版 | Community Edition 功能完整 | 限制仓库数量 |
| 语言覆盖 | 30+ | 10+ |
| 安全扫描（SAST）| ✅ 完整 | ⚠️ 基础 |
| 技术债可视化 | ✅ 精细（行级别）| ✅ 直观（字母评分）|
| 私有化友好 | ✅ 首选 | ✅ CLI 可本地运行 |
| **推荐场景** | 安全合规 + 深度质量分析 | 快速上手 + 开发者友好 |

---

## 推荐决策

**推荐在 SmartVision 优先采用 SonarQube Community Edition**：
- 自托管符合私有化产品的安全要求
- 免费且覆盖 Java/Python/JS/TS 全栈
- GitLab CI 原生集成，接入成本低
- 与架构债管理（03-架构债管理）直接联动

---

## GitHub 信息

- 开源状态：Community Edition 开源（LGPL）
- 仓库地址：https://github.com/SonarSource/sonarqube
- Star：9.9k（统计日期：2026-05-29）
