# Spring Boot Virtual Threads Benchmark

Controlled comparison of Spring Boot with and without virtual threads under IO-bound load. Two identical app instances run side by side — the only difference is one property flag. WireMock simulates a slow downstream dependency. Prometheus + Grafana + cAdvisor provide observability throughout.

---

## Architecture

```
k6 (load generator)
    │
    ├──▶ app-no-vt :8080  (platform threads, Tomcat pool = 200)
    │         │
    └──▶ app-vt    :8081  (virtual threads, semaphore = 500)
              │
              └──▶ wiremock :8080  (200ms fixed delay, 2000 threads)

Prometheus ──scrapes──▶ app-no-vt /actuator/prometheus
           ──scrapes──▶ app-vt    /actuator/prometheus
           ──scrapes──▶ cadvisor  (container CPU/memory)

Grafana ──reads──▶ Prometheus  (JVM Micrometer dashboard, pre-loaded)
```

The endpoint under test: `GET /api/call` → calls WireMock → returns after 200ms.

---

## Current Settings

| Setting | Value |
|---|---|
| k6 VUs | 1500 (ramp 30s, hold 60s, ramp down 10s) |
| WireMock delay | 200ms |
| WireMock threads (`--container-threads`) | 2000 |
| Tomcat thread pool (no-VT) | 200 (Spring Boot default) |
| Virtual threads (VT instance) | `SPRING_THREADS_VIRTUAL_ENABLED=true` |
| Downstream semaphore (VT instance) | 500 concurrent calls |

---

## How to Run

```bash
./run-comparison.sh
```

This builds images, starts all containers, runs k6 against each app in sequence, and prints a comparison table. Grafana is available at `http://localhost:3000` during the test — the JVM dashboard shows thread count diverge between the two instances in real time.

Tear down when done:

```bash
docker compose down
```

---

## Results (current settings)

```
Metric             No VT          VT             Delta
─────────────────────────────────────────────────────
Requests/sec       966 req/s      2315 req/s     +140%
p50 latency        1503 ms        629 ms         -58%
p95 latency        1549 ms        691 ms         -55%
p99 latency        1571 ms        722 ms         -54%
Error rate         0.00%          0.00%
```

**Why these numbers make sense:**

- No-VT has 200 Tomcat threads. At 1500 VUs with 200ms IO, 1300 VUs are queuing for a thread at any moment. Throughput caps at ~1000 req/s. Latency is flat from p50→p99 because every request experiences the same queue — textbook M/D/1 queuing behaviour.

- VT + semaphore(500) allows 500 concurrent WireMock calls. The other 1000 VUs park as cheap virtual threads waiting for a semaphore permit. Queue wait ≈ 1000 / 2315 ≈ 430ms + 200ms service = ~630ms, which matches measured p50 almost exactly.

---

## What Happens When You Tinker

### WireMock thread count (`--container-threads` in docker-compose.yml)

The downstream thread pool. Set too low, WireMock becomes the bottleneck even for VT.

| WireMock threads | Effect |
|---|---|
| 500 (default) | At 1500 VUs VT overwhelms WireMock; no-VT accidentally wins on throughput because its 200-thread limit naturally rate-limits downstream calls |
| 2000 (current) | WireMock handles the load; VT advantage is visible |

**Try:** Drop back to 500 and remove the semaphore — you'll see VT produce worse results than no-VT despite being architecturally superior. This illustrates why unbounded concurrency without downstream protection is dangerous.

---

### Tomcat thread pool size (`server.tomcat.threads.max` in application.properties, no-VT instance)

Increase it and the no-VT app improves — up to a point.

| Threads | Effect |
|---|---|
| 200 (default) | Saturates at ~300 VUs |
| 500 | Handles more load but ~500MB extra stack memory |
| 1000 | ~1GB stack memory; context-switching overhead starts showing on the Grafana CPU panel |
| 2000+ | OS may refuse thread creation; JVM heap pressure; GC pauses increase |

**Try:** Set `server.tomcat.threads.max=500` on no-VT and rerun at 1500 VUs. You'll see it close the gap somewhat but never match VT's efficiency. Check cAdvisor memory usage in Grafana — the no-VT container will consume significantly more RAM.

---

### Semaphore limit (`DOWNSTREAM_CONCURRENCY_LIMIT` in docker-compose.yml, VT instance)

Controls how many concurrent WireMock calls VT allows. The right value is roughly equal to WireMock's thread count.

| Semaphore | Effect |
|---|---|
| 0 (disabled) | All 1500 VUs hit WireMock simultaneously; WireMock saturates; errors and timeouts |
| 200 | Matches no-VT's effective downstream concurrency — similar throughput, but VT queues cheaply in-JVM rather than at TCP layer |
| 500 (current) | Balanced — WireMock handles load, VT queues excess requests as parked virtual threads |
| 1500 | Effectively no limit; same as disabled at current VU count |

**Try:** Set `DOWNSTREAM_CONCURRENCY_LIMIT=0` and run at 1500 VUs. VT will flood WireMock, producing high error rates and worse throughput than no-VT — demonstrating that virtual threads require explicit concurrency control for downstream resources.

---

### WireMock delay (`fixedDelayMilliseconds` in wiremock/mappings/slow-endpoint.json)

The IO wait time per request. Virtual threads benefit scales with how long threads are blocked.

| Delay | Effect |
|---|---|
| 20ms | Low IO time; thread pool exhaustion happens at much higher VU counts; VT advantage narrower |
| 200ms (current) | Clear separation between the two instances |
| 1000ms | No-VT becomes almost unusable at 1500 VUs; VT + semaphore handles it gracefully |

**Try:** Set delay to `1000` and rerun. No-VT latency will reach 7-8 seconds at p50 (1300 queued × 1000ms / 200 threads). VT p50 will be ~1000ms + queue wait. The relative advantage widens significantly with slower IO.

---

### k6 VU count (`target` in k6/scripts/load-test.js)

The number of concurrent users.

| VUs | Effect |
|---|---|
| 150 | Below Tomcat's thread limit; both apps perform similarly (~200ms); no meaningful difference |
| 300 | No-VT starts queuing; p50 diverges; VT wins cleanly |
| 1500 (current) | Strong separation; semaphore effect visible |
| 3000+ | Both apps under extreme pressure; interesting to see where VT + semaphore breaks |

**Try:** Drop to 150 VUs — you'll see near-identical results. This is a useful sanity check: virtual threads only help when you're IO-bound *and* concurrency exceeds the thread pool limit.

---

## Other Interesting Experiments

### CPU-bound workload
Add a second endpoint that does pure computation (e.g. calculating primes) with no IO. Run k6 against that endpoint on both instances. Virtual threads will show **no advantage** — carrier threads are never parked, so you have the same number of active threads as platform threads. This illustrates that virtual threads are not a universal performance upgrade; they only help with IO-bound blocking.

### Thread pinning
Virtual threads get "pinned" to their carrier thread when they enter a `synchronized` block or call certain native methods — the carrier thread is blocked instead of freed. Add a `synchronized` block around the WireMock call and rerun. You'll see VT performance degrade toward no-VT levels, demonstrating one of VT's known pitfalls. The fix is to use `ReentrantLock` instead of `synchronized`.

### Multiple chained IO calls
Change the endpoint to make two sequential WireMock calls per request (two 200ms delays = 400ms total). The VT advantage compounds because each virtual thread parks twice per request, freeing carrier threads twice as often. No-VT's effective throughput halves since each thread is blocked twice as long.

### Memory pressure
Set a JVM heap limit on both containers (`-Xmx512m`) and run at high VU counts. No-VT will OOM or GC thrash first because platform thread stacks (~1MB each) sit outside the heap but consume native memory. VT stacks are tiny and managed by the JVM. Watch cAdvisor's memory panel in Grafana.
