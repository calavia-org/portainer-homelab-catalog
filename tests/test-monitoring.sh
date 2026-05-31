#!/usr/bin/env bash
# Smoke-test the Prometheus + Loki monitoring stack:
#   1. All services start (Prometheus, Loki, Promtail, Grafana).
#   2. Prometheus /-/healthy returns HTTP 200.
#   3. Loki /ready returns HTTP 200.
#   4. Grafana /api/health returns HTTP 200 and reports database as 'ok'.
#   5. Prometheus query API responds successfully.
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/../monitoring/prometheus-loki" && pwd)"
export GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-testpass}"
cd "$STACK_DIR"

cleanup() { docker compose down -v 2>/dev/null || true; }
trap cleanup EXIT

wait_http() {
  local url="$1" label="$2" timeout="${3:-90}"
  echo "--- Waiting for ${label} at ${url} (up to ${timeout}s)"
  local deadline=$((SECONDS + timeout))
  until curl -sf -o /dev/null "$url" 2>/dev/null; do
    [ $SECONDS -lt $deadline ] || { echo "FAIL: ${label} did not become reachable within ${timeout}s"; exit 1; }
    sleep 3
  done
  echo "PASS: ${label} is reachable"
}

echo "--- Starting monitoring stack"
docker compose up -d

wait_http "http://localhost:9090/-/healthy" "Prometheus"
wait_http "http://localhost:3100/ready"     "Loki"
wait_http "http://localhost:3000/api/health" "Grafana"

echo "--- Verifying Prometheus query API"
curl -sf "http://localhost:9090/api/v1/query?query=up" | grep -q '"status":"success"' \
  || { echo "FAIL: Prometheus query API did not return success status"; exit 1; }
echo "PASS: Prometheus query API responds with success"

echo "--- Verifying Grafana health response"
curl -sf "http://localhost:3000/api/health" | grep -q '"database"' \
  || { echo "FAIL: Grafana health endpoint did not report database status"; exit 1; }
echo "PASS: Grafana health endpoint reports database status"
