# 二进制服务部署规范

> 当前状态：✅ 已采用（Java 服务等以 JAR 包形式直接运行在服务器上）

---

## 适用场景

- Java Spring Boot 服务（fat jar）
- Go 单二进制服务
- 其他不依赖容器的独立可执行程序
- 过渡期尚未容器化的旧服务

---

## GitLab CI 触发二进制部署流程

```
开发者 push 代码
      │
      ▼
GitLab CI
  ├── build: mvn package / go build → 生成制品
  ├── upload: 推送 JAR 到 Harbor（Generic Package）或 Nexus
  └── deploy（when: manual）
        │ SSH 连接目标服务器
        ▼
      目标服务器
        ├── 下载新版本 JAR
        ├── 停止旧进程
        ├── 启动新进程
        └── 健康检查
```

### GitLab CI 配置示例

```yaml
# .gitlab-ci.yml
stages:
  - build
  - upload
  - deploy

build:
  stage: build
  image: maven:3.8-openjdk-17
  script:
    - mvn clean package -DskipTests
  artifacts:
    paths:
      - target/*.jar
    expire_in: 1 week

upload:
  stage: upload
  script:
    # 推送到 Harbor Generic Package
    - |
      curl -u "$HARBOR_USER:$HARBOR_PASS" \
        -X POST "https://harbor.internal/api/v2.0/projects/platform/repositories" \
        -F "file=@target/api-service-*.jar" \
        -F "filename=api-service-${CI_COMMIT_SHORT_SHA}.jar"

deploy-pre:
  stage: deploy
  script:
    - ssh deploy@192.168.1.10 "
        /opt/scripts/deploy.sh api-service ${CI_COMMIT_SHORT_SHA}
      "
  when: manual
  environment:
    name: pre
```

---

## 服务器端部署脚本

```bash
#!/bin/bash
# /opt/scripts/deploy.sh
# 用法: deploy.sh <service-name> <version>

SERVICE=$1
VERSION=$2
DEPLOY_DIR="/opt/services/${SERVICE}"
HARBOR_URL="https://harbor.internal"

echo "[$(date)] 开始部署 ${SERVICE}:${VERSION}"

# 1. 下载新版本
mkdir -p ${DEPLOY_DIR}
curl -u "${HARBOR_USER}:${HARBOR_PASS}" \
  "${HARBOR_URL}/packages/${SERVICE}-${VERSION}.jar" \
  -o "${DEPLOY_DIR}/${SERVICE}-${VERSION}.jar"

# 2. 停止旧进程（保留旧 JAR 用于回滚）
OLD_PID=$(pgrep -f "${SERVICE}-.*.jar")
if [ -n "$OLD_PID" ]; then
  echo "停止旧进程 PID: ${OLD_PID}"
  kill $OLD_PID
  sleep 5
fi

# 3. 启动新进程
nohup java -jar \
  -Xms512m -Xmx2g \
  -Dspring.profiles.active=pre \
  ${DEPLOY_DIR}/${SERVICE}-${VERSION}.jar \
  > ${DEPLOY_DIR}/app.log 2>&1 &

NEW_PID=$!
echo "新进程 PID: ${NEW_PID}"

# 4. 健康检查（等待最多 60 秒）
for i in $(seq 1 12); do
  sleep 5
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health)
  if [ "$HTTP_CODE" = "200" ]; then
    echo "[$(date)] 部署成功，服务健康"
    # 记录当前版本（用于回滚）
    echo $VERSION > ${DEPLOY_DIR}/current_version
    exit 0
  fi
  echo "等待服务启动... ($i/12)"
done

echo "[$(date)] 健康检查失败，自动回滚"
bash /opt/scripts/rollback.sh ${SERVICE}
exit 1
```

### 回滚脚本

```bash
#!/bin/bash
# /opt/scripts/rollback.sh
SERVICE=$1
DEPLOY_DIR="/opt/services/${SERVICE}"

CURRENT=$(cat ${DEPLOY_DIR}/current_version)
echo "当前版本: ${CURRENT}，执行回滚..."

# 找上一个版本的 JAR
PREV_JAR=$(ls -t ${DEPLOY_DIR}/*.jar | sed -n '2p')
if [ -z "$PREV_JAR" ]; then
  echo "没有可回滚的版本"
  exit 1
fi

# 停止当前进程并启动上一版本
kill $(pgrep -f "${SERVICE}-.*.jar")
sleep 3
nohup java -jar $PREV_JAR -Dspring.profiles.active=pre > ${DEPLOY_DIR}/app.log 2>&1 &
echo "回滚完成，运行: $PREV_JAR"
```

---

## 服务目录规范

```
/opt/services/
  api-service/
    api-service-v1.1.0.jar    # 上一版本（保留用于回滚）
    api-service-v1.2.0.jar    # 当前版本
    current_version           # 记录当前运行版本
    app.log                   # 运行日志（建议用 logrotate 轮转）
    .env                      # 环境变量（不放 Git）
```

---

## 当前问题与改进方向

| 问题 | 说明 | 改进方向 |
|---|---|---|
| 进程管理不规范 | nohup 后台运行，重启后不自动拉起 | 使用 systemd 管理服务 |
| 日志难以集中 | 散落在各服务器 app.log | 接入 Loki / Filebeat |
| 无零停机 | 停旧起新期间有停机 | 迁移到 K8s 或使用 nginx upstream 切换 |
| 依赖手动参数 | JVM 参数、配置文件手动维护 | 统一到 Ansible inventory vars |

### 用 systemd 管理（推荐替代 nohup）

```ini
# /etc/systemd/system/api-service.service
[Unit]
Description=API Service
After=network.target

[Service]
User=deploy
WorkingDirectory=/opt/services/api-service
ExecStart=/usr/bin/java -jar -Xms512m -Xmx2g api-service-current.jar
ExecStop=/bin/kill -SIGTERM $MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
# 部署时更新软链接而不是直接替换
ln -sf api-service-v1.2.0.jar api-service-current.jar
systemctl restart api-service
```

---

## 迁移到容器化的判断标准

满足以下任一条件，建议容器化该服务：

- [ ] 依赖 JDK 版本与系统版本冲突
- [ ] 需要在多台服务器部署（容器化后统一镜像）
- [ ] 部署频率高（每天多次，脚本维护成本高）
- [ ] 需要和其他服务统一监控和日志采集
