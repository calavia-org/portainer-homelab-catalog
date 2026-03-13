#!/usr/bin/env bash
# Smoke-test the UniFi Controller stack:
#   1. MongoDB starts and its healthcheck passes.
#   2. The configured user can authenticate to MongoDB (the key prerequisite
#      for the UniFi controller to connect successfully).
#   3. The UniFi controller container starts.
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/../network/unifi-controller" && pwd)"
export MONGO_USER="${MONGO_USER:-unifi}"
export MONGO_PASS="${MONGO_PASS:-testpass}"
cd "$STACK_DIR"

cleanup() { docker compose down -v 2>/dev/null || true; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Start MongoDB and wait until it is accepting connections
# ---------------------------------------------------------------------------
echo "--- Starting MongoDB"
docker compose up -d unifi-db

echo "--- Waiting for MongoDB to accept connections (up to 60s)"
deadline=$((SECONDS + 60))
until docker exec unifi-db mongo --quiet --eval 'db.adminCommand({ping:1})' > /dev/null 2>&1; do
  [ $SECONDS -lt $deadline ] || { echo "FAIL: MongoDB did not become reachable within 60s"; exit 1; }
  sleep 3
done

# ---------------------------------------------------------------------------
# 2. Verify the configured user can authenticate
# ---------------------------------------------------------------------------
echo "--- Verifying MongoDB authentication for user '${MONGO_USER}'"
docker exec unifi-db mongo \
  -u "$MONGO_USER" -p "$MONGO_PASS" \
  --authenticationDatabase admin \
  --quiet \
  --eval 'if (db.adminCommand({ping:1}).ok !== 1) { quit(1); }'
echo "PASS: MongoDB authentication succeeded for user '${MONGO_USER}'"

# ---------------------------------------------------------------------------
# 3. Start the full stack and verify the controller container comes up
# ---------------------------------------------------------------------------
echo "--- Starting full stack (controller + MongoDB)"
docker compose up -d

echo "--- Waiting for UniFi controller container to enter 'running' state (up to 60s)"
deadline=$((SECONDS + 60))
until [ "$(docker inspect --format='{{.State.Status}}' unifi-controller 2>/dev/null)" = "running" ]; do
  [ $SECONDS -lt $deadline ] || { echo "FAIL: unifi-controller did not start within 60s"; exit 1; }
  sleep 3
done
echo "PASS: unifi-controller is running"
