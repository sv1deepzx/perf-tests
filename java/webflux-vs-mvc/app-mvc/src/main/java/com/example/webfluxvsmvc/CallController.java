package com.example.webfluxvsmvc;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.concurrent.Semaphore;

@RestController
public class CallController {

    private final RestClient restClient;
    private final String wiremockUrl;
    private final Semaphore semaphore;
    private final int cpuIterations;

    public CallController(RestClient.Builder builder,
                          @Value("${wiremock.url:http://wiremock:8080}") String wiremockUrl,
                          @Value("${downstream.concurrency.limit:0}") int concurrencyLimit,
                          @Value("${cpu.iterations:500000}") int cpuIterations) {
        this.restClient = builder.build();
        this.wiremockUrl = wiremockUrl;
        this.semaphore = concurrencyLimit > 0 ? new Semaphore(concurrencyLimit) : null;
        this.cpuIterations = cpuIterations;
    }

    @GetMapping("/api/call")
    public String call() throws InterruptedException {
        if (semaphore != null) semaphore.acquire();
        try {
            return restClient.get()
                    .uri(wiremockUrl + "/api/downstream")
                    .retrieve()
                    .body(String.class);
        } finally {
            if (semaphore != null) semaphore.release();
        }
    }

    @GetMapping("/api/cpu")
    public String cpu() throws NoSuchAlgorithmException {
        return computeHash();
    }

    private String computeHash() throws NoSuchAlgorithmException {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        byte[] data = "perf-test".getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i < cpuIterations; i++) {
            data = md.digest(data);
        }
        return HexFormat.of().formatHex(data);
    }
}
