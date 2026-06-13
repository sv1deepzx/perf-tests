#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/k6/results"

if docker compose version &>/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose &>/dev/null; then
  DC="docker-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' found." >&2
  exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

wait_healthy() {
  local name=$1 url=$2 max_wait=${3:-90}
  log "Waiting for $name to be healthy..."
  local elapsed=0
  until curl -sf "$url" > /dev/null 2>&1; do
    if (( elapsed >= max_wait )); then
      echo "ERROR: $name did not become healthy within ${max_wait}s" >&2
      exit 1
    fi
    sleep 3
    (( elapsed += 3 ))
  done
  log "$name is healthy."
}

cd "$SCRIPT_DIR"

log "Building images..."
$DC build

log "Starting infrastructure..."
$DC up -d wiremock prometheus grafana cadvisor
wait_healthy "WireMock" "http://localhost:9090/__admin/health"

log "Starting app-mvc, app-mvc-vt, and app-webflux..."
$DC up -d --force-recreate app-mvc app-mvc-vt app-webflux
wait_healthy "app-mvc"      "http://localhost:8080/actuator/health"
wait_healthy "app-mvc-vt"   "http://localhost:8081/actuator/health"
wait_healthy "app-webflux"  "http://localhost:8082/actuator/health"

log "Grafana is available at http://localhost:3000"
log ""

mkdir -p "$RESULTS_DIR"
chmod 777 "$RESULTS_DIR"

# ── Run 1: MVC platform threads ───────────────────────────────────────────────
log "=== Running k6 against app-mvc (MVC, platform threads) ==="
$DC --profile k6 run --rm \
  -e TARGET_URL=http://app-mvc:8080 \
  -e ENDPOINT=/api/cpu \
  -e OUTPUT_FILE=/results/cpu-mvc.json \
  k6 run /scripts/load-test-cpu.js

log "Waiting 10s for metrics to settle..."
sleep 10

# ── Run 2: MVC virtual threads ────────────────────────────────────────────────
log "=== Running k6 against app-mvc-vt (MVC, virtual threads) ==="
$DC --profile k6 run --rm \
  -e TARGET_URL=http://app-mvc-vt:8080 \
  -e ENDPOINT=/api/cpu \
  -e OUTPUT_FILE=/results/cpu-mvc-vt.json \
  k6 run /scripts/load-test-cpu.js

log "Waiting 10s for metrics to settle..."
sleep 10

# ── Run 3: WebFlux — event loop blocked (the wrong way) ───────────────────────
log "=== Running k6 against app-webflux /api/cpu (event loop blocked — expect bad results) ==="
$DC --profile k6 run --rm \
  -e TARGET_URL=http://app-webflux:8080 \
  -e ENDPOINT=/api/cpu \
  -e OUTPUT_FILE=/results/cpu-webflux-naive.json \
  k6 run /scripts/load-test-cpu.js || true   # allow non-zero exit if errors spike

log "Waiting 15s for event loop to recover before next run..."
sleep 15

# ── Run 4: WebFlux — offloaded to boundedElastic (the fix) ───────────────────
log "=== Running k6 against app-webflux /api/cpu-offloaded (fixed) ==="
$DC --profile k6 run --rm \
  -e TARGET_URL=http://app-webflux:8080 \
  -e ENDPOINT=/api/cpu-offloaded \
  -e OUTPUT_FILE=/results/cpu-webflux-offloaded.json \
  k6 run /scripts/load-test-cpu.js

log ""
log "=== Comparison ==="
"$SCRIPT_DIR/compare-cpu-results.sh" \
  "$RESULTS_DIR/cpu-mvc.json" \
  "$RESULTS_DIR/cpu-mvc-vt.json" \
  "$RESULTS_DIR/cpu-webflux-naive.json" \
  "$RESULTS_DIR/cpu-webflux-offloaded.json"

log ""
log "Grafana: http://localhost:3000  |  Prometheus: http://localhost:9091"
log "Done. Run '$DC down' to tear down."
