package com.example.virtualthreadsdemo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.util.concurrent.Semaphore;

@RestController
public class CallController {

    private final RestClient restClient;
    private final String wiremockUrl;
    private final Semaphore semaphore;

    public CallController(RestClient.Builder builder,
                          @Value("${wiremock.url:http://wiremock:8080}") String wiremockUrl,
                          @Value("${downstream.concurrency.limit:0}") int concurrencyLimit) {
        this.restClient = builder.build();
        this.wiremockUrl = wiremockUrl;
        this.semaphore = concurrencyLimit > 0 ? new Semaphore(concurrencyLimit) : null;
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
}
