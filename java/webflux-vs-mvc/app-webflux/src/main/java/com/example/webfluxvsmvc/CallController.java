package com.example.webfluxvsmvc;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import reactor.netty.http.client.HttpClient;
import reactor.netty.resources.ConnectionProvider;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

@RestController
public class CallController {

    private final WebClient webClient;
    private final int cpuIterations;

    public CallController(WebClient.Builder builder,
                          @Value("${wiremock.url:http://wiremock:8080}") String wiremockUrl,
                          @Value("${cpu.iterations:500000}") int cpuIterations) {
        // Limit concurrent downstream connections to match the semaphore used in MVC+VT,
        // so WireMock isn't the bottleneck across the three-way comparison.
        ConnectionProvider provider = ConnectionProvider.builder("webflux")
                .maxConnections(500)
                .build();
        this.webClient = builder
                .baseUrl(wiremockUrl)
                .clientConnector(new ReactorClientHttpConnector(HttpClient.create(provider)))
                .build();
        this.cpuIterations = cpuIterations;
    }

    @GetMapping("/api/call")
    public Mono<String> call() {
        return webClient.get()
                .uri("/api/downstream")
                .retrieve()
                .bodyToMono(String.class);
    }

    // Runs the hash synchronously on the Netty event loop thread.
    // While this thread is busy, no other requests can be accepted or processed.
    @GetMapping("/api/cpu")
    public Mono<String> cpu() {
        return Mono.just(computeHash());
    }

    // Offloads the hash onto boundedElastic, freeing the event loop immediately.
    @GetMapping("/api/cpu-offloaded")
    public Mono<String> cpuOffloaded() {
        return Mono.fromCallable(this::computeHash)
                .subscribeOn(Schedulers.boundedElastic());
    }

    private String computeHash() {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] data = "perf-test".getBytes(StandardCharsets.UTF_8);
            for (int i = 0; i < cpuIterations; i++) {
                data = md.digest(data);
            }
            return HexFormat.of().formatHex(data);
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }
}
