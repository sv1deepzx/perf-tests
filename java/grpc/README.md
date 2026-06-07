# gRPC vs REST Benchmark

> Status: not yet implemented

gRPC vs REST isn't purely a performance question — it's also about contract-first design, streaming, and payload efficiency. This experiment covers all three, with a Java server and optional Go server using the same `.proto` definition.

---

## What's Being Compared

| Server | Protocol | Serialisation |
|---|---|---|
| REST endpoint | HTTP/1.1 | JSON |
| gRPC endpoint | HTTP/2 | Protobuf binary |

Same logical operation (`GetProduct(id)`) implemented both ways on the same Spring Boot app (using `grpc-spring-boot-starter`).

---

## Planned Experiments

### A. Unary call: gRPC vs REST+JSON (the main benchmark)
Same endpoint, three payload sizes:
- Small: product with a few string fields (~100 bytes JSON / ~40 bytes Protobuf)
- Medium: product with nested objects and arrays (~2KB JSON / ~800 bytes Protobuf)
- Large: product with many fields and a base64 image (~100KB JSON / ~80KB Protobuf)

Expected: gRPC wins clearly on small/medium (binary encoding + HTTP/2 framing overhead amortised over many requests); gap narrows on large payloads where encoding efficiency matters less than raw throughput.

Metrics: req/s, p99 latency, bytes on wire (network I/O from cAdvisor).

### B. gRPC streaming vs REST polling
Use case: real-time counter that updates every 100ms. Two implementations:
- REST: k6 VUs poll `GET /api/counter` every 100ms
- gRPC: server-side streaming `WatchCounter()` — single connection, server pushes updates

Metrics: total bandwidth consumed, number of open connections, server CPU.

Streaming wins on connection count and bandwidth; demonstrates the right use case for server-streaming (real-time feeds, live dashboards).

### C. High-concurrency: HTTP/2 multiplexing advantage
1500 VUs, both endpoints. gRPC uses HTTP/2 which multiplexes many requests over a single TCP connection. REST typically uses HTTP/1.1 with connection-per-request (or a small pool).

Expect: gRPC handles more concurrent requests with fewer open connections and less TCP handshake overhead at scale.

k6 supports gRPC natively via `k6/net/grpc` — same load profile as all other experiments.

### D. Java gRPC vs Go gRPC (ties back to the Java vs Go experiment)
Same `.proto` file, two server implementations: `grpc-java` and `google.golang.org/grpc`. Compares the runtime overhead of each gRPC implementation rather than language performance in isolation.

---

## Key Metrics
- Requests/sec, p50/p99 latency (k6)
- Bytes transferred per request (cAdvisor network I/O)
- Open TCP connections at peak load

---

## Stack
```
java/grpc/
  proto/
    product.proto     ← shared contract for all implementations
  app/                ← Spring Boot with grpc-spring-boot-starter (REST + gRPC on same app)
  go/                 ← optional Go gRPC server for experiment D
  docker-compose.yml
```

`grpcurl` used for manual endpoint testing (equivalent of `curl` for gRPC).
