# Redis Caching Benchmark

> Status: not yet implemented

Measures the latency and throughput impact of Redis caching in front of a Postgres database, and stress-tests failure modes that only appear under load.

---

## What's Being Compared

| Endpoint | Path |
|---|---|
| Uncached | `GET /api/product/{id}` → Postgres query (~20ms) |
| Cached (Redis) | Same endpoint, Redis cache hit (~1ms network RTT) |
| Cached (Caffeine) | Same endpoint, in-JVM cache hit (sub-microsecond) |

---

## Planned Experiments

### A. Cached vs uncached latency (the baseline)
k6 with a Zipf key distribution (20% of keys get 80% of traffic — realistic for product catalogues). Watch the cache warm up over the first 30s; Grafana shows Postgres query rate dropping as hit rate climbs.

Metrics: p50/p95 latency, cache hit rate (Redis `INFO stats`), Postgres query rate (pg_stat_activity).

### B. Cache stampede
Warm the cache with 1000 keys (TTL = 10s). Run k6 at 500 VUs. At peak load, execute `FLUSHALL` — all keys expire simultaneously. Every concurrent request misses and slams Postgres at once, exhausting the HikariCP connection pool.

Then implement a fix (probabilistic early expiration or single-flight / `@Cacheable` with a mutex) and rerun to show controlled degradation instead of a spike.

### C. In-process (Caffeine) vs network cache (Redis)
Same endpoint, swap cache backends:
- Caffeine: no network hop, sub-microsecond hit latency
- Redis: ~0.5–1ms Docker network RTT per hit

Shows when the Redis network cost matters (very high RPS, latency-sensitive paths) vs when it's irrelevant (infrequent access, need shared state across instances).

### D. Write-through vs cache-aside (POC)
Code walkthrough of both patterns using Spring's `@Cacheable`, `@CachePut`, `@CacheEvict`. Not benchmarked — demonstrates consistency tradeoffs: cache-aside can serve stale data between write and eviction; write-through keeps cache consistent but couples write latency to both DB and Redis.

---

## Key Metrics
- p50/p95/p99 latency per endpoint (k6)
- Cache hit rate (Redis INFO)
- Postgres query rate (Prometheus pg exporter)
- Latency distribution during and after cache flush (stampede test)

---

## Stack
```
java/redis-caching/
  app/              ← Spring Boot with spring-data-redis + spring-data-jpa
  docker-compose.yml  ← app, Postgres, Redis, Prometheus, Grafana, k6
  init/
    schema.sql      ← products table + 100k row seed data
```
