#!/usr/bin/env bash
# Parses three k6 handleSummary JSON files and prints a side-by-side comparison table.
set -euo pipefail

MVC_FILE=${1:-k6/results/mvc.json}
VT_FILE=${2:-k6/results/mvc-vt.json}
WF_FILE=${3:-k6/results/webflux.json}

for f in "$MVC_FILE" "$VT_FILE" "$WF_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "Usage: $0 <mvc.json> <mvc-vt.json> <webflux.json>" >&2
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

# Delta relative to MVC baseline (positive = improvement vs baseline)
delta_pct() {
  local base=$1 val=$2
  [[ "$base" == "N/A" || "$val" == "N/A" ]] && echo "N/A" && return
  awk -v a="$base" -v b="$val" 'BEGIN {
    d = (b - a) / a * 100
    if (d >= 0) printf "+%.1f%%", d
    else        printf "%.1f%%",  d
  }'
}

# For latency: negative delta is improvement
delta_lat() {
  local base=$1 val=$2
  [[ "$base" == "N/A" || "$val" == "N/A" ]] && echo "N/A" && return
  awk -v a="$base" -v b="$val" 'BEGIN {
    d = (b - a) / a * 100
    if (d >= 0) printf "+%.1f%%", d
    else        printf "%.1f%%",  d
  }'
}

# Extract metrics
MVC_RPS=$(extract "$MVC_FILE" '.metrics.http_reqs.values.rate')
VT_RPS=$(extract "$VT_FILE"   '.metrics.http_reqs.values.rate')
WF_RPS=$(extract "$WF_FILE"   '.metrics.http_reqs.values.rate')

MVC_P50=$(extract "$MVC_FILE" '.metrics.http_req_duration.values.med')
VT_P50=$(extract "$VT_FILE"   '.metrics.http_req_duration.values.med')
WF_P50=$(extract "$WF_FILE"   '.metrics.http_req_duration.values.med')

MVC_P95=$(extract "$MVC_FILE" '.metrics.http_req_duration.values["p(95)"]')
VT_P95=$(extract "$VT_FILE"   '.metrics.http_req_duration.values["p(95)"]')
WF_P95=$(extract "$WF_FILE"   '.metrics.http_req_duration.values["p(95)"]')

MVC_P99=$(extract "$MVC_FILE" '.metrics.http_req_duration.values["p(99)"]')
VT_P99=$(extract "$VT_FILE"   '.metrics.http_req_duration.values["p(99)"]')
WF_P99=$(extract "$WF_FILE"   '.metrics.http_req_duration.values["p(99)"]')

MVC_ERR=$(extract "$MVC_FILE" '.metrics.http_req_failed.values.rate')
VT_ERR=$(extract "$VT_FILE"   '.metrics.http_req_failed.values.rate')
WF_ERR=$(extract "$WF_FILE"   '.metrics.http_req_failed.values.rate')

MVC_REQS=$(extract "$MVC_FILE" '.metrics.http_reqs.values.count')
VT_REQS=$(extract "$VT_FILE"   '.metrics.http_reqs.values.count')
WF_REQS=$(extract "$WF_FILE"   '.metrics.http_reqs.values.count')

# Print table
COL=20

hr() { printf "%-${COL}s┼%-${COL}s┼%-${COL}s┼%-${COL}s┼%-${COL}s\n" \
  "$(printf '%.0s─' $(seq 1 $COL))" \
  "$(printf '%.0s─' $(seq 1 $COL))" \
  "$(printf '%.0s─' $(seq 1 $COL))" \
  "$(printf '%.0s─' $(seq 1 $COL))" \
  "$(printf '%.0s─' $(seq 1 $COL))"; }

row() { printf "%-${COL}s│ %-$((COL-1))s│ %-$((COL-1))s│ %-$((COL-1))s│ %-$((COL-1))s\n" "$1" "$2" "$3" "$4" "$5"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                        Spring Boot — WebFlux vs MVC Benchmark Results                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""
row "Metric" "MVC (baseline)" "MVC + VT" "WebFlux" "VT vs MVC / WF vs MVC"
hr
row "Requests/sec"   "$(fmt_rps "$MVC_RPS")"  "$(fmt_rps "$VT_RPS")"  "$(fmt_rps "$WF_RPS")"  "$(delta_pct "$MVC_RPS" "$VT_RPS") / $(delta_pct "$MVC_RPS" "$WF_RPS")"
row "Total requests" "$MVC_REQS"               "$VT_REQS"               "$WF_REQS"               "$(delta_pct "$MVC_REQS" "$VT_REQS") / $(delta_pct "$MVC_REQS" "$WF_REQS")"
hr
row "p50 latency"    "$(fmt_ms "$MVC_P50")"   "$(fmt_ms "$VT_P50")"   "$(fmt_ms "$WF_P50")"   "$(delta_lat "$MVC_P50" "$VT_P50") / $(delta_lat "$MVC_P50" "$WF_P50")"
row "p95 latency"    "$(fmt_ms "$MVC_P95")"   "$(fmt_ms "$VT_P95")"   "$(fmt_ms "$WF_P95")"   "$(delta_lat "$MVC_P95" "$VT_P95") / $(delta_lat "$MVC_P95" "$WF_P95")"
row "p99 latency"    "$(fmt_ms "$MVC_P99")"   "$(fmt_ms "$VT_P99")"   "$(fmt_ms "$WF_P99")"   "$(delta_lat "$MVC_P99" "$VT_P99") / $(delta_lat "$MVC_P99" "$WF_P99")"
hr
row "Error rate"     "$(fmt_pct "$MVC_ERR")"  "$(fmt_pct "$VT_ERR")"  "$(fmt_pct "$WF_ERR")"  ""
echo ""
