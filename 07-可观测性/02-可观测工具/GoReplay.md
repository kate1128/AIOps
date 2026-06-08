# GoReplay — 流量录制与回放

## 概述

GoReplay 是开源的生产流量录制和回放工具，无需修改代码即可捕获 HTTP 流量并回放到测试环境。使用 Go 编写，性能极高，适用于上线前的回归测试和压力测试。

## 核心能力

- **流量录制**: 从指定端口或网络接口捕获 HTTP 请求
- **流量回放**: 将录制的流量发送到目标环境，支持速率控制
- **请求过滤**: 按 URL、Header、HTTP Method 等条件过滤请求
- **请求修改**: 支持修改请求内容（替换 header、重写路径、脱敏数据）

## 使用场景

### 1. 压力测试

```bash
# 录制生产流量到文件
gor --input-raw :8080 --output-file requests.gor

# 在 staging 环境中回放，保留原始速率
gor --input-file requests.gor --output-http "http://staging:8080"
```

### 2. 回放测试

```bash
# 实时录制并转发到 staging（不保存文件）
gor --input-raw :8080 --output-http "http://staging:8080"

# 限制回放速率，不压垮 staging（100% 录制，50% 回放）
gor --input-raw :8080 --output-http "http://staging:8080|50%"
```

### 3. 请求过滤

```bash
# 只回放 GET 请求
gor --input-raw :8080 --output-http "http://staging:8080" \
  --http-allow-method GET

# 只回放指定路径（排除健康检查）
gor --input-raw :8080 --output-http "http://staging:8080" \
  --http-allow-url /api/v1
```

## 推荐场景

- **回归测试**: 每次上线前用最近 1 小时的生产流量回放 staging，验证系统行为一致
- **容量评估**: 使用生产流量模式对 staging 做负载测试，评估新架构的吞吐极限
- **功能验证**: 用真实数据验证新功能逻辑是否正确

## 注意事项

- 回放时只发送请求，不校验响应（GoReplay 默认不比对返回结果）
- 写请求（POST/PUT/DELETE）回放可能导致测试环境数据污染，建议只回放 GET 请求或在 staging 使用隔离数据库
- 生产环境录制建议只在外网流量入口（Nginx/Ingress）上录制，避免内部调用放大
