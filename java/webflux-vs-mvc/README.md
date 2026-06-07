# WebFlux vs MVC Benchmark

> Status: not yet implemented

Three-way comparison of Spring Boot's concurrency models under IO-bound load — the natural sequel to the virtual threads experiment.

---

## What's Being Compared

| Instance | Model | Config |
|---|---|---|
| `app-mvc` | Spring MVC + platform threads | Tomcat, default 200-thread pool |
| `app-mvc-vt` | Spring MVC + virtual threads | `spring.threads.virtual.enabled=true` |
| `app-webflux` | Spring WebFlux | Netty event loop, non-blocking IO |

All three hit the same WireMock downstream (200ms fixed delay). Same k6 load profile.

This answers the most common question after enabling virtual threads: *"do I still need WebFlux?"*

---

## Planned Experiments

### A. IO-bound throughput (the main comparison)
Three-way benchmark at 1500 VUs. Expected outcome:
- MVC + platform threads: saturates at ~200 threads, high latency tail
- MVC + virtual threads: matches WebFlux on throughput; slightly higher memory (carrier threads)
- WebFlux: fewest OS threads, lowest memory; similar throughput to VT

### B. CPU-bound: WebFlux is the wrong tool
Add an endpoint that does heavy computation (no IO). WebFlux will starve other requests because the computation blocks the event loop. MVC + VT handles it fine — virtual threads yield cooperatively on IO but not on CPU, so they don't interfere with each other.

Fix: `subscribeOn(Schedulers.boundedElastic())` to offload from the event loop. Rerun to show recovery.

### C. Backpressure (WebFlux only)
Virtual threads have no backpressure mechanism — if the producer outpaces the consumer, requests queue as parked threads until memory runs out. WebFlux's `Flux` supports `onBackpressureBuffer` / `onBackpressureDrop` for controlled degradation.

Demonstration: producer generates events faster than the consumer can process; show buffer overflow without backpressure, controlled drop rate with it.

---

## Key Metrics
- Requests/sec, p50/p95/p99 latency (k6)
- Live thread count and heap (Grafana JVM dashboard)
- Container RSS memory (cAdvisor) — the most telling difference between WebFlux and VT

---

## Stack
Extends the `spring-boot-virtual-threads` setup. Adds a third `app-webflux` container. WireMock, Prometheus, Grafana, cAdvisor, k6 reused as-is.
