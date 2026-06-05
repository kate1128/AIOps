# Docker Compose — Docker 服务部署规范

> 当前状态：✅ 已采用（部分服务以 Docker Compose 形式部署在服务器上）

---

## 适用场景

Docker Compose 部署适合以下情况：
- 服务尚未迁移到 K8s（过渡期）
- 单机或少数几台服务器，不值得用 K8s 管理
- 依赖组合较复杂但规模不大的服务组合

---

## GitLab CI 触发 Docker 部署流程

```
开发者 push 代码
      │
      ▼
GitLab CI
  ├── build: docker build + push to Harbor
  └── deploy（when: manual 或 main 分支自动）
        │ SSH 连接目标服务器
        ▼
      目标服务器
        ├── docker pull harbor.internal/xxx:tag
        └── docker compose up -d
```

### GitLab CI 配置示例

```yaml
# .gitlab-ci.yml
stages:
  - build
  - deploy

build:
  stage: build
  script:
    - docker build -t harbor.internal/platform/api-service:$CI_COMMIT_SHORT_SHA .
    - docker push harbor.internal/platform/api-service:$CI_COMMIT_SHORT_SHA

deploy-pre:
  stage: deploy
  script:
    # SSH 到目标服务器执行部署
    - ssh deploy@192.168.1.10 "
        cd /opt/platform &&
        export IMAGE_TAG=$CI_COMMIT_SHORT_SHA &&
        docker compose pull &&
        docker compose up -d --remove-orphans
      "
  environment:
    name: pre
  only:
    - main
```

---

## docker-compose.yml 规范

### 基本规范

```yaml
# /opt/platform/docker-compose.yml
version: "3.8"

services:
  api-service:
    image: harbor.internal/platform/api-service:${IMAGE_TAG:-latest}
    container_name: api-service
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=pre
      - DB_HOST=mysql
      - REDIS_HOST=redis
    volumes:
      - ./logs/api:/app/logs
      - ./config/api:/app/config
    networks:
      - platform-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"

networks:
  platform-net:
    driver: bridge
```

### 环境变量管理

```bash
# /opt/platform/.env（不提交到 Git，只在服务器上维护）
IMAGE_TAG=v1.2.0
DB_PASSWORD=xxx
REDIS_PASSWORD=xxx
```

```yaml
# docker-compose.yml 中引用
environment:
  - DB_PASSWORD=${DB_PASSWORD}
```

---

## 部署操作规范

```bash
# 升级服务（标准流程）
cd /opt/platform
export IMAGE_TAG=v1.2.0

# 1. 拉新镜像
docker compose pull api-service

# 2. 滚动更新（单容器无法真正滚动，但可以控制停机时间）
docker compose up -d api-service

# 3. 检查容器状态
docker compose ps
docker compose logs api-service --tail=50

# 回滚（改回旧版本号重新 up）
export IMAGE_TAG=v1.1.0
docker compose up -d api-service
```

---

## 当前问题与改进方向

| 问题 | 说明 | 改进方案 |
|---|---|---|
| 无零停机部署 | `docker compose up` 期间有短暂停机 | 迁移到 K8s 滚动升级 |
| 版本管理靠人工 | IMAGE_TAG 手动指定，容易出错 | GitLab CI 自动注入 |
| 无健康检查自动摘除 | 容器异常需手动重启 | 已有 `restart: unless-stopped`，补充 healthcheck |
| 日志分散 | 每台机器独立日志 | 接入 Loki（参考 07-可观测性）|

---

## 迁移到 K8s 的判断标准

满足以下任一条件，建议迁移该服务到 K8s：

- [ ] 需要多副本高可用
- [ ] 需要自动伸缩（HPA）
- [ ] 部署频率高（每天多次）
- [ ] 依赖 GPU 资源（必须走 HAMI 调度）
