# perf-tests

A collection of performance benchmarks and proof-of-concept experiments across languages, frameworks, and infrastructure technologies. Each experiment lives in its own directory and is fully self-contained (Docker Compose, load scripts, observability stack).

---

## Experiments

### Java

| Directory | Type | What it tests |
|---|---|---|
| [`java/spring-boot-virtual-threads`](java/spring-boot-virtual-threads) | Benchmark | Platform threads vs virtual threads under IO-bound load |
| [`java/webflux-vs-mvc`](java/webflux-vs-mvc) | Benchmark | Spring MVC (platform) vs MVC (virtual threads) vs WebFlux |
| [`java/redis-caching`](java/redis-caching) | Benchmark + POC | Redis cache impact on latency; stampede, Caffeine vs Redis |
| [`java/postgres-transactions`](java/postgres-transactions) | Benchmark + POC | HikariCP pool sizing, index scans, optimistic vs pessimistic locking |
| [`java/spring-kafka`](java/spring-kafka) | POC + Benchmark | Kafka producer batching, consumer group scaling, delivery guarantees |
| [`java/grpc`](java/grpc) | Benchmark + POC | gRPC vs REST: throughput, payload size, streaming vs polling |

### Go

| Directory | Type | What it tests |
|---|---|---|
| [`go/http-server`](go/http-server) | Benchmark | Go goroutines vs Java virtual threads: IO, CPU, memory, startup time |

---

## Common Stack

All experiments share the same observability approach:

- **k6** — load generation; results saved as JSON, compared via `compare-results.sh`
- **Prometheus** — metrics scraping (Spring Actuator `/actuator/prometheus`, cAdvisor)
- **Grafana** — pre-provisioned dashboards (JVM Micrometer dashboard loaded automatically)
- **cAdvisor** — container-level CPU and memory metrics
- **WireMock** — simulates IO-bound downstream dependencies where needed

Each experiment has a `run-comparison.sh` that handles build, startup, load test, and teardown.

---

## Suggested Order

1. `java/spring-boot-virtual-threads` ✅ — start here; foundational concepts used throughout
2. `java/webflux-vs-mvc` — direct sequel; answers "VT vs WebFlux?"
3. `go/http-server` — reuses the VT setup; low setup cost
4. `java/postgres-transactions` — same queuing concept applied to DB connections
5. `java/redis-caching` — builds on Postgres experiment
6. `java/grpc` — self-contained; introduces a new protocol dimension
7. `java/spring-kafka` — most new infrastructure; best tackled last
