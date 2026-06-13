# WebFlux vs MVC Benchmark

> Status: Experiments A and B implemented. Experiment C planned.

Three-way comparison of Spring Boot's concurrency models — the natural sequel to the virtual threads experiment.

---

## What's Being Compared

| Instance | Model | Config |
|---|---|---|
| `app-mvc` | Spring MVC + platform threads | Tomcat, default 200-thread pool |
| `app-mvc-vt` | Spring MVC + virtual threads | `spring.threads.virtual.enabled=true` |
| `app-webflux` | Spring WebFlux | Netty event loop, non-blocking IO |

---

## Experiment A — IO-bound throughput

**Run:** `./run-comparison.sh`
**Setup:** 1500 VUs, 200ms WireMock downstream delay, 30s ramp / 60s hold / 10s ramp-down.
MVC+VT uses a `Semaphore(500)` to cap downstream concurrency (same config as the VT experiment). WebFlux caps its Reactor Netty connection pool at 500 for the same reason.

### Results

| Metric | MVC (baseline) | MVC + VT | WebFlux | VT vs MVC | WF vs MVC |
|---|---|---|---|---|---|
| Requests/sec | 966.6 | 2315.1 | 2311.2 | +139.5% | +139.1% |
| Total requests | 96,833 | 231,931 | 231,376 | +139.5% | +138.9% |
| p50 latency | 1503.0 ms | 635.0 ms | 601.9 ms | -57.8% | -60.0% |
| p95 latency | 1551.1 ms | 669.6 ms | 614.8 ms | -56.8% | -60.4% |
| p99 latency | 1568.9 ms | 682.7 ms | 633.0 ms | -56.5% | -59.7% |
| Error rate | 0.00% | 0.00% | 0.00% | | |

### What the numbers show

**MVC platform threads** saturates at 200 Tomcat threads. With 1500 VUs and a 200ms downstream delay, each request waits behind ~7.5 others: `7.5 × 200ms = 1500ms` — the p50 matches queuing theory exactly.

**MVC+VT and WebFlux are statistically identical on throughput** (2315 vs 2311 req/s, within noise). This is the direct answer to *"do I still need WebFlux if I enable virtual threads?"* — for IO-bound work: no.

**WebFlux has a consistent ~5–8% latency edge at p99** (633ms vs 683ms). Netty runs on `~CPU-count` event loop threads with zero thread scheduling overhead. VT carrier threads still incur a small scheduling cost. The difference is negligible for most applications.

### Grafana observations

- `app-mvc`: live thread count pins at ~200 under load
- `app-mvc-vt`: live thread count stays at ~28 throughout (carrier threads + JVM system threads) regardless of 1500 concurrent requests
- `app-webflux`: similar to VT, ~15–20 threads flat

---

## Experiment B — CPU-bound: WebFlux event loop starvation

**Run:** `./run-cpu-comparison.sh`
**Setup:** 200 VUs, SHA-256 chained 500k times per request (~50ms CPU per request), 20s ramp / 60s hold / 10s ramp-down. WebFlux tested twice: naive (blocks event loop) and fixed (`subscribeOn(Schedulers.boundedElastic())`).

### Results

| Metric | MVC (baseline) | MVC + VT | WebFlux naive | WebFlux offloaded |
|---|---|---|---|---|
| Requests/sec | 160.0 | 154.6 | 158.9 | 163.1 |
| Total requests | 14,403 | 13,916 | 14,298 | 14,684 |
| vs MVC baseline | — | -3.4% | -0.7% | +1.9% |
| p50 latency | 1180.7 ms | 73.2 ms | 1197.4 ms | 913.1 ms |
| p99 latency | 1570.9 ms | 9264.2 ms | 1446.2 ms | 1820.1 ms |
| Error rate | 0.00% | 0.00% | 0.00% | 0.00% |

### What the numbers show

**Throughput is identical across all four** (~160 req/s). CPU cores are the bottleneck; the threading model is irrelevant for throughput on CPU-bound work.

**MVC+VT shows a pathological latency distribution** — p50 of 73ms but p99 of 9264ms. The carrier thread pool (sized to CPU count) runs VTs to completion without yielding; there is no IO to park on. Early VTs complete quickly after JIT warmup; later VTs starve behind them. Virtual threads give no benefit for CPU-bound work and actively worsen tail latency.

**WebFlux naive is not catastrophic at 200 VUs hitting one endpoint** — throughput and latency match platform threads. The event loop starvation failure mode appears when *other* endpoints (health checks, different routes) are called concurrently — those see timeouts while the event loop is blocked. At single-endpoint load the event loop threads just behave like a small thread pool.

**WebFlux offloaded** (`subscribeOn(Schedulers.boundedElastic())`) behaves similarly to platform threads once the elastic pool grows to match demand.

### Grafana observations

- `app-mvc`: live thread count stays at ~200 flat throughout
- `app-mvc-vt`: live thread count **drops from ~28 to ~17 during the load test**, then recovers. See note below.
- `app-webflux` (naive): similar thread drop expected during its run
- `app-webflux` (offloaded): thread count climbs as `boundedElastic` grows to handle offloaded tasks

---

## Investigation: JIT thread termination under VT CPU load

**Observed:** During experiment B, `app-mvc-vt` Grafana thread count dropped from ~28 to ~17 during the k6 run, then recovered afterward. Daemon thread count dropped from 24 to 13.

**Hypothesis:** The virtual thread carrier pool is sized to exactly `availableProcessors()`, filling every core with no slack. The JVM detects zero available CPU for JIT compiler threads (which are daemon threads) and proactively terminates them. Tomcat's 200-thread pool produces constant context switching that creates gaps for JIT; the ForkJoinPool-based carrier pool does not.

**Side effect:** JIT compiling the SHA-256 loop early in the run (before termination) produces a bimodal latency distribution — requests served after JIT compilation completes are fast (p50=73ms), while requests queued during the pre-JIT phase are slow (p99=9264ms).

**To investigate further:**
- Run experiment B with `-XX:+PrintCompilation` or JFR to confirm JIT thread termination timing
- Compare thread count drop on `app-mvc` (platform threads) vs `app-mvc-vt` during the same run — does the platform thread variant show the same dip?
- Try `-XX:CICompilerCount=1` to reduce JIT thread count and see if the drop is less dramatic
- Try a pre-warmed run (hit `/api/cpu` a few times before k6 starts) — should eliminate the bimodal distribution

---

## Experiment C — Backpressure (planned)

Virtual threads have no backpressure mechanism. WebFlux's `Flux` supports `onBackpressureBuffer` / `onBackpressureDrop` for controlled degradation when a producer outpaces a consumer.

---

## Stack

```
java/webflux-vs-mvc/
  app-mvc/          ← Spring MVC (used for both platform and VT containers)
  app-webflux/      ← Spring WebFlux (Netty); exposes /api/call, /api/cpu, /api/cpu-offloaded
  docker-compose.yml
  run-comparison.sh       ← experiment A (IO-bound, 3 runs)
  compare-results.sh
  run-cpu-comparison.sh   ← experiment B (CPU-bound, 4 runs)
  compare-cpu-results.sh
  k6/scripts/
    load-test.js          ← experiment A script
    load-test-cpu.js      ← experiment B script
  monitoring/             ← Prometheus + Grafana (JVM dashboard pre-loaded)
  wiremock/               ← 200ms fixed-delay downstream stub
```
