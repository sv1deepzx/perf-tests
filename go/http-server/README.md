# Java vs Go HTTP Server Benchmark

> Status: not yet implemented

Go goroutines and Java virtual threads are conceptually identical — both are cheap, user-space concurrent units that park on IO and resume when ready. This experiment benchmarks them head-to-head and explores where each language has a genuine edge.

---

## What's Being Compared

| Instance | Language | Concurrency model |
|---|---|---|
| `app-java` | Java 21 + Spring Boot 3.x | Virtual threads (Tomcat) |
| `app-go` | Go 1.22+ | Goroutines (`net/http` or Fiber) |

Both implement the same endpoint: `GET /api/call` → downstream HTTP call to WireMock (200ms delay). Same WireMock instance, same k6 load profile as the VT experiment.

---

## Planned Experiments

### A. IO-bound throughput
Direct apples-to-apples at 1500 VUs with WireMock delay. Expected outcome:
- Comparable throughput (both handle concurrent IO efficiently)
- Go wins on memory RSS (no JVM baseline overhead)
- Java wins after JIT warmup (~30s); Go is more consistent from cold start

### B. CPU-bound throughput
Endpoint computes SHA-256 over a random payload — no IO, no parking. Tests raw execution speed: JIT-compiled Java vs Go's ahead-of-time compiler. Expected: Java pulls ahead after warmup; Go more predictable.

### C. Memory footprint at scale
Hold 10,000 concurrent idle connections open to each server. Measure RSS via cAdvisor.
- Go goroutine stack: starts at 8KB, grows as needed
- Java virtual thread: starts at ~1KB (smaller initial stack)
- But Java has JVM overhead (~100MB baseline) that Go doesn't

Reveals at what concurrency level each is more memory-efficient overall.

### D. Cold start / startup time
Measure time from container start to first successful health check response.
- Go binary: typically <50ms
- Spring Boot: typically 2–4s

Optional extension: compare Spring Boot native image (GraalVM) to close the startup gap.

---

## Key Metrics
- Requests/sec, p50/p99 latency (k6)
- Container RSS memory at peak load (cAdvisor)
- Startup time (`time curl /health` after container start)

---

## Stack
```
go/http-server/
  app/              ← Go HTTP server (mirrors CallController from the Java experiment)
  docker-compose.yml  ← runs Go server alongside reused WireMock/k6/Prometheus/Grafana
```

The Go app is a minimal `net/http` server with a single handler that calls WireMock via `http.Get`. No framework needed to match the simplicity of the Spring Boot endpoint.
