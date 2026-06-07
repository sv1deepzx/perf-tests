# Postgres & Database Transactions

> Status: not yet implemented

Connection pool sizing has exactly the same shape as the thread pool problem from the virtual threads experiment — too few connections causes queuing, too many creates database overhead. This experiment makes that concrete, then explores locking strategies under concurrent writes.

---

## Planned Experiments

### A. HikariCP connection pool sizing (the main benchmark)
Fix k6 at 500 VUs. Vary `spring.datasource.hikari.maximum-pool-size` across runs: 5 → 10 → 25 → 50 → 200.

Expected: throughput increases and latency drops as pool size grows, until you hit diminishing returns (DB CPU / context-switching overhead). The curve mirrors the Tomcat thread pool experiment.

Validate HikariCP's own recommendation: pool size = `(core_count * 2) + effective_spindle_count`. For a 4-core machine with SSD: ~9 connections is often optimal — far fewer than most people configure.

### B. Index vs sequential scan
Table of 1M user rows. Two endpoints: `GET /api/user/by-email/{email}` (no index) and `GET /api/user/{id}` (primary key). k6 hammers both.

Latency cliff between the two will be dramatic. `EXPLAIN ANALYZE` output logged to show the query plan difference. Shows why adding an index matters more than any connection pool tuning.

### C. Optimistic vs pessimistic locking under concurrent writes
`POST /api/account/transfer` — move balance between two accounts. Both approaches must prevent double-spend.

- **Pessimistic:** `SELECT FOR UPDATE` — locks the row, serialises writes
- **Optimistic:** `@Version` column — allows concurrent reads, detects conflict on write, retries

k6 at 200 VUs all hitting the same account pair. Metrics: throughput, error rate (optimistic conflict exceptions), retry count, deadlock rate.

Shows the concurrency/consistency tradeoff concretely: pessimistic is safer but serialises; optimistic scales better under low contention, degrades under high contention.

### D. Batch insert vs row-by-row (POC)
Insert 10,000 rows two ways: a loop of individual `save()` calls vs `saveAll()` with JDBC batching enabled (`hibernate.jdbc.batch_size=100`).

Measures the cost of N round-trips to Postgres vs 1. Not a load test — a single-run timing comparison. Demonstrates why bulk operations should always use batching.

---

## Key Metrics
- Requests/sec, p50/p95/p99 (k6)
- HikariCP pool active/idle/wait metrics (Micrometer → Prometheus)
- Postgres `pg_stat_activity` active connections
- Lock wait time and deadlock count (pg_locks)

---

## Stack
```
java/postgres-transactions/
  app/              ← Spring Boot with spring-data-jpa + HikariCP
  docker-compose.yml  ← app, Postgres 16, Prometheus, Grafana, k6
  init/
    schema.sql      ← users table (1M rows), accounts table
    seed.sql
```

Postgres exporter (`prometheuscommunity/postgres-exporter`) added to scrape DB-level metrics into Prometheus.
