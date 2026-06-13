#!/usr/bin/env bash
# Parses four k6 handleSummary JSON files and prints a CPU-experiment comparison table.
set -euo pipefail

MVC_FILE=${1:-k6/results/cpu-mvc.json}
VT_FILE=${2:-k6/results/cpu-mvc-vt.json}
WFN_FILE=${3:-k6/results/cpu-webflux-naive.json}
WFO_FILE=${4:-k6/results/cpu-webflux-offloaded.json}

for f in "$MVC_FILE" "$VT_FILE" "$WFN_FILE" "$WFO_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "Usage: $0 <cpu-mvc.json> <cpu-mvc-vt.json> <cpu-webflux-naive.json> <cpu-webflux-offloaded.json>" >&2
    exit 1
  fi
done

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for this script." >&2
  exit 1
fi

extract() {
  local file=$1 key=$2
  jq -r "$key // \"N/A\"" "$file"
}

fmt_ms() {
  local val=$1
  [[ "$val" == "N/A" ]] && echo "N/A" && return
  printf "%.1f ms" "$val"
}

fmt_rps() {
  local val=$1
  [[ "$val" == "N/A" ]] && echo "N/A" && return
  printf "%.1f req/s" "$val"
}

fmt_pct() {
  local val=$1
  [[ "$val" == "N/A" ]] && echo "N/A" && return
  awk -v v="$val" 'BEGIN { printf "%.2f%%", v * 100 }'
}

delta_pct() {
  local base=$1 val=$2
  [[ "$base" == "N/A" || "$val" == "N/A" ]] && echo "N/A" && return
  awk -v a="$base" -v b="$val" 'BEGIN {
    d = (b - a) / a * 100
    if (d >= 0) printf "+%.1f%%", d
    else        printf "%.1f%%",  d
  }'
}

MVC_RPS=$(extract "$MVC_FILE"  '.metrics.http_reqs.values.rate')
VT_RPS=$(extract "$VT_FILE"    '.metrics.http_reqs.values.rate')
WFN_RPS=$(extract "$WFN_FILE"  '.metrics.http_reqs.values.rate')
WFO_RPS=$(extract "$WFO_FILE"  '.metrics.http_reqs.values.rate')

MVC_P50=$(extract "$MVC_FILE"  '.metrics.http_req_duration.values.med')
VT_P50=$(extract "$VT_FILE"    '.metrics.http_req_duration.values.med')
WFN_P50=$(extract "$WFN_FILE"  '.metrics.http_req_duration.values.med')
WFO_P50=$(extract "$WFO_FILE"  '.metrics.http_req_duration.values.med')

MVC_P99=$(extract "$MVC_FILE"  '.metrics.http_req_duration.values["p(99)"]')
VT_P99=$(extract "$VT_FILE"    '.metrics.http_req_duration.values["p(99)"]')
WFN_P99=$(extract "$WFN_FILE"  '.metrics.http_req_duration.values["p(99)"]')
WFO_P99=$(extract "$WFO_FILE"  '.metrics.http_req_duration.values["p(99)"]')

MVC_ERR=$(extract "$MVC_FILE"  '.metrics.http_req_failed.values.rate')
VT_ERR=$(extract "$VT_FILE"    '.metrics.http_req_failed.values.rate')
WFN_ERR=$(extract "$WFN_FILE"  '.metrics.http_req_failed.values.rate')
WFO_ERR=$(extract "$WFO_FILE"  '.metrics.http_req_failed.values.rate')

MVC_REQS=$(extract "$MVC_FILE"  '.metrics.http_reqs.values.count')
VT_REQS=$(extract "$VT_FILE"    '.metrics.http_reqs.values.count')
WFN_REQS=$(extract "$WFN_FILE"  '.metrics.http_reqs.values.count')
WFO_REQS=$(extract "$WFO_FILE"  '.metrics.http_reqs.values.count')

COL=22

hr() {
  printf "%-${COL}s┼%-${COL}s┼%-${COL}s┼%-${COL}s┼%-${COL}s\n" \
    "$(printf '%.0s─' $(seq 1 $COL))" \
    "$(printf '%.0s─' $(seq 1 $COL))" \
    "$(printf '%.0s─' $(seq 1 $COL))" \
    "$(printf '%.0s─' $(seq 1 $COL))" \
    "$(printf '%.0s─' $(seq 1 $COL))"
}

row() {
  printf "%-${COL}s│ %-$((COL-1))s│ %-$((COL-1))s│ %-$((COL-1))s│ %-$((COL-1))s\n" \
    "$1" "$2" "$3" "$4" "$5"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║               Spring Boot — CPU-bound Benchmark: WebFlux event loop vs offloaded                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""
row "Metric" "MVC (baseline)" "MVC + VT" "WebFlux naive" "WebFlux offloaded"
hr
row "Requests/sec"   "$(fmt_rps "$MVC_RPS")"  "$(fmt_rps "$VT_RPS")"  "$(fmt_rps "$WFN_RPS")"  "$(fmt_rps "$WFO_RPS")"
row "Total requests" "$MVC_REQS"               "$VT_REQS"               "$WFN_REQS"               "$WFO_REQS"
row "vs MVC baseline" ""                        "$(delta_pct "$MVC_RPS" "$VT_RPS")" "$(delta_pct "$MVC_RPS" "$WFN_RPS")" "$(delta_pct "$MVC_RPS" "$WFO_RPS")"
hr
row "p50 latency"    "$(fmt_ms "$MVC_P50")"   "$(fmt_ms "$VT_P50")"   "$(fmt_ms "$WFN_P50")"   "$(fmt_ms "$WFO_P50")"
row "p99 latency"    "$(fmt_ms "$MVC_P99")"   "$(fmt_ms "$VT_P99")"   "$(fmt_ms "$WFN_P99")"   "$(fmt_ms "$WFO_P99")"
hr
row "Error rate"     "$(fmt_pct "$MVC_ERR")"  "$(fmt_pct "$VT_ERR")"  "$(fmt_pct "$WFN_ERR")"  "$(fmt_pct "$WFO_ERR")"
echo ""
echo "  MVC baseline  : platform threads, Tomcat pool (200 threads)"
echo "  MVC + VT      : virtual threads — no benefit for CPU work (no IO to park on)"
echo "  WebFlux naive : computation runs on Netty event loop → starves request handling"
echo "  WebFlux fixed : subscribeOn(boundedElastic()) offloads work, frees event loop"
echo ""
