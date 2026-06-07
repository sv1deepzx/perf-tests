#!/usr/bin/env bash
# Parses two k6 handleSummary JSON files and prints a side-by-side comparison table.
set -euo pipefail

NO_VT_FILE=${1:-k6/results/no-vt.json}
VT_FILE=${2:-k6/results/vt.json}

if [[ ! -f "$NO_VT_FILE" || ! -f "$VT_FILE" ]]; then
  echo "Usage: $0 <no-vt.json> <vt.json>" >&2
  exit 1
fi

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
  local a=$1 b=$2
  [[ "$a" == "N/A" || "$b" == "N/A" ]] && echo "N/A" && return
  awk -v a="$a" -v b="$b" 'BEGIN {
    d = (b - a) / a * 100
    if (d >= 0) printf "+%.1f%%", d
    else        printf "%.1f%%",  d
  }'
}

# Extract metrics
NVT_RPS=$(extract "$NO_VT_FILE" '.metrics.http_reqs.values.rate')
VT_RPS=$(extract "$VT_FILE"     '.metrics.http_reqs.values.rate')

NVT_P50=$(extract "$NO_VT_FILE" '.metrics.http_req_duration.values.med')
VT_P50=$(extract "$VT_FILE"     '.metrics.http_req_duration.values.med')

NVT_P95=$(extract "$NO_VT_FILE" '.metrics.http_req_duration.values["p(95)"]')
VT_P95=$(extract "$VT_FILE"     '.metrics.http_req_duration.values["p(95)"]')

NVT_P99=$(extract "$NO_VT_FILE" '.metrics.http_req_duration.values["p(99)"]')
VT_P99=$(extract "$VT_FILE"     '.metrics.http_req_duration.values["p(99)"]')

NVT_ERR=$(extract "$NO_VT_FILE" '.metrics.http_req_failed.values.rate')
VT_ERR=$(extract "$VT_FILE"     '.metrics.http_req_failed.values.rate')

NVT_REQS=$(extract "$NO_VT_FILE" '.metrics.http_reqs.values.count')
VT_REQS=$(extract "$VT_FILE"     '.metrics.http_reqs.values.count')

# Print table
COL=18
SEP="─"

hr() { printf "%-${COL}s┼%-${COL}s┼%-${COL}s┼%-${COL}s\n" \
  "$(printf '%.0s─' $(seq 1 $COL))" \
  "$(printf '%.0s─' $(seq 1 $COL))" \
  "$(printf '%.0s─' $(seq 1 $COL))" \
  "$(printf '%.0s─' $(seq 1 $COL))"; }

row() { printf "%-${COL}s│ %-$((COL-1))s│ %-$((COL-1))s│ %-$((COL-1))s\n" "$1" "$2" "$3" "$4"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║            Spring Boot — Virtual Threads Benchmark Results          ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
row "Metric" "No VT" "VT" "Delta"
hr
row "Requests/sec"   "$(fmt_rps "$NVT_RPS")" "$(fmt_rps "$VT_RPS")"   "$(delta_pct "$NVT_RPS" "$VT_RPS")"
row "Total requests" "$NVT_REQS"              "$VT_REQS"                "$(delta_pct "$NVT_REQS" "$VT_REQS")"
hr
row "p50 latency"    "$(fmt_ms "$NVT_P50")"  "$(fmt_ms "$VT_P50")"    "$(delta_pct "$NVT_P50" "$VT_P50")"
row "p95 latency"    "$(fmt_ms "$NVT_P95")"  "$(fmt_ms "$VT_P95")"    "$(delta_pct "$NVT_P95" "$VT_P95")"
row "p99 latency"    "$(fmt_ms "$NVT_P99")"  "$(fmt_ms "$VT_P99")"    "$(delta_pct "$NVT_P99" "$VT_P99")"
hr
row "Error rate"     "$(fmt_pct "$NVT_ERR")" "$(fmt_pct "$VT_ERR")"   ""
echo ""
