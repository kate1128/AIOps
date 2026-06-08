# Micrometer — Java 服务指标采集框架

## 概述

Micrometer 是 Java 应用的指标门面（Metrics Facade），功能类似 SLF4J 之于日志。它提供统一的 API 埋点，底层可将指标导出到 Prometheus、InfluxDB、Datadog 等 20+ 监控系统，无需更换采集后端时修改业务代码。

- GitHub: [micrometer-metrics/micrometer](https://github.com/micrometer-metrics/micrometer) ⭐ ~4.5k
- Spring Boot 2.x+ 默认集成，暴露端点: `/actuator/prometheus`
- 零侵入：Spring Boot 自动注册 JVM / HTTP / 线程池等指标

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **自动仪表化** | Spring Boot Actuator 自动暴露 JVM、GC、线程池、HTTP 请求指标 |
| **RED 指标** | Rate（QPS）、Errors（错误率）、Duration（延迟分布）一套 API |
| **多后端兼容** | 同一套代码可切换 Prometheus / InfluxDB / CloudWatch |
| **自定义指标** | Counter / Gauge / Timer / Summary / DistributionSummary |
| **标签系统** | 与 Prometheus 标签体系无缝对接 |

---

## 核心指标（Spring Boot 自动暴露）

### JVM 指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `jvm_memory_used_bytes{area="heap"}` | 堆内存使用量 | > max × 85% 持续 5m 告警 |
| `jvm_memory_max_bytes{area="heap"}` | 堆内存上限 | — |
| `jvm_gc_pause_seconds_sum` | GC 暂停总时间 | rate > 1s/min 告警 |
| `jvm_gc_pause_seconds_count` | GC 次数 | — |
| `jvm_threads_live_threads` | 活跃线程数 | > 1000 关注 |
| `jvm_threads_daemon_threads` | 守护线程数 | — |
| `jvm_threads_states_threads{state="blocked"}` | 阻塞线程数 | > 0 持续增长告警 |
| `jvm_classes_loaded_classes` | 已加载类数 | — |

### HTTP 请求指标

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `http_server_requests_seconds_count{status="5xx"}` | 5xx 错误请求数 | rate > 0 持续 2m 告警 |
| `http_server_requests_seconds_sum` | 请求总延迟 | — |
| `http_server_requests_seconds_bucket` | 延迟分布（Histogram）| P99 > 2s 告警 |
| `http_server_requests_seconds_max` | 最大延迟 | > 5s 告警 |

### 连接池（HikariCP）

| 指标 | 含义 | 告警建议 |
|------|------|---------|
| `hikaricp_connections_active` | 活跃连接数 | > pool_size × 90% 告警 |
| `hikaricp_connections_pending` | 等待连接数 | > 0 持续 1m 告警 |
| `hikaricp_connections_timeout_total` | 获取连接超时次数 | > 0 告警 |
| `hikaricp_connections_acquire_seconds_sum` | 获取连接耗时 | P99 > 100ms 告警 |

---

## 在本项目中的使用

### Spring Boot 接入（推荐，零代码侵入）

```xml
<!-- pom.xml -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: prometheus, health, info
  endpoint:
    prometheus:
      enabled: true
  metrics:
    export:
      prometheus:
        enabled: true
    tags:
      # 所有指标附加公共标签
      application: ${spring.application.name}
      env: ${spring.profiles.active}
```

### 自定义业务指标埋点

```java
import io.micrometer.core.instrument.*;

@Service
public class InferenceService {

    private final Counter requestCounter;
    private final Timer requestTimer;
    private final Gauge queueDepth;

    public InferenceService(MeterRegistry registry) {
        this.requestCounter = Counter.builder("inference_requests_total")
            .description("AI 推理请求总数")
            .tags("model", "qwen2-7b")
            .register(registry);

        this.requestTimer = Timer.builder("inference_duration_seconds")
            .description("AI 推理耗时分布")
            .publishPercentiles(0.5, 0.9, 0.99)
            .register(registry);

        this.queueDepth = Gauge.builder("inference_queue_depth",
            requestQueue, Queue::size)
            .description("当前推理队列深度")
            .register(registry);
    }

    public String infer(String prompt) {
        requestCounter.increment();
        return requestTimer.record(() -> {
            // 实际推理逻辑
            return callLLM(prompt);
        });
    }
}
```

### Prometheus 采集配置

```yaml
# Prometheus static_configs（Java 服务部署在 K8s 外时）
scrape_configs:
  - job_name: java_services
    metrics_path: /actuator/prometheus
    static_configs:
      - targets:
          - "ai-backend:8080"
        labels:
          service: ai-backend
          env: prod

# K8s ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: java-services
  namespace: observability
spec:
  selector:
    matchLabels:
      metrics: enabled   # Java Pod 需要有此标签
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 15s
```

---

## 非 Spring Boot 项目接入（纯 Java）

```java
// 不依赖 Spring，手动配置
import io.micrometer.prometheus.PrometheusRegistry;
import io.prometheus.client.exporter.HTTPServer;

PrometheusMeterRegistry registry = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
// 注册 JVM 指标
new JvmMemoryMetrics().bindTo(registry);
new JvmGcMetrics().bindTo(registry);
new ProcessorMetrics().bindTo(registry);
new JvmThreadMetrics().bindTo(registry);

// 启动 HTTP 端点
HTTPServer server = new HTTPServer(9090);
```

---

## Grafana Dashboard

| Dashboard | ID | 说明 |
|-----------|-----|------|
| JVM Micrometer | 4701 | 最常用的 Spring Boot JVM 面板 |
| Spring Boot Statistics | 6756 | HTTP + JVM 综合面板 |
