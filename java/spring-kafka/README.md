# Apache Kafka & Spring Cloud Stream

> Status: not yet implemented

Kafka's performance characteristics are largely determined by two knobs: producer batching (throughput vs latency tradeoff) and consumer group topology (parallelism is bounded by partition count). This experiment makes both concrete, and adds Spring Cloud Stream abstraction overhead as a third dimension.

---

## Planned Experiments

### A. Producer batch size vs latency tradeoff (the main benchmark)
Send 1 million messages through a topic. Vary `linger.ms` (0, 5, 50ms) and `batch.size` across runs.

- `linger.ms=0`: every record sent immediately — lowest latency, lowest throughput
- `linger.ms=50`: records batched for 50ms before sending — highest throughput, higher latency

Metric: messages/sec and end-to-end latency (timestamp embedded in message payload, delta measured on consumer side).

Demonstrates that Kafka is not "low latency by default" — it's a deliberate tuning decision that trades one for the other.

### B. Consumer group scaling
Topic with 12 partitions. Start a producer at a rate that builds lag (more messages than 1 consumer can process). Add consumers one at a time up to 12; watch lag decrease linearly. Add a 13th consumer — it sits idle, demonstrating the partition count ceiling.

Metric: consumer group lag (via Kafka JMX → Prometheus, visualised in Grafana).

### C. At-least-once vs exactly-once delivery overhead
Same pipeline, two configurations:
- Default (at-least-once): no idempotence, no transactions
- Exactly-once: `enable.idempotence=true` + producer transactions + `isolation.level=read_committed` on consumer

Metrics: throughput drop and latency increase. The overhead is real but often smaller than people expect.

### D. Spring Cloud Stream abstraction overhead
Same producer/consumer logic implemented twice: raw `KafkaTemplate` / `@KafkaListener` vs Spring Cloud Stream functional bindings. Measures the cost of the abstraction layer (usually <5%, but worth having the number).

### E. Dead letter queue + retry pattern (POC)
Consumer that throws on ~10% of messages. Configure Spring Cloud Stream's built-in DLQ with exponential backoff retry. Demonstrates: failed messages don't block the partition, retries are bounded, DLQ captures unrecoverable messages for inspection. Not benchmarked — just the pattern with instrumented counters.

---

## Key Metrics
- Messages/sec (producer and consumer throughput)
- End-to-end latency (producer send → consumer process, embedded timestamp)
- Consumer group lag (Grafana)
- DLQ message count (experiment E)

---

## Stack
```
java/spring-kafka/
  producer/         ← Spring Boot app, sends configurable message rate
  consumer/         ← Spring Boot app, Spring Cloud Stream functional consumer
  docker-compose.yml  ← Kafka (KRaft mode, no Zookeeper), Kafka UI, Prometheus, Grafana
```

Uses Kafka in KRaft mode (no Zookeeper dependency, available since Kafka 3.3). Kafka UI (`provectuslabs/kafka-ui`) for topic/consumer group inspection.
