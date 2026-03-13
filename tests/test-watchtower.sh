#!/usr/bin/env bash
# Smoke-test the Watchtower stack: verify the container starts and stays running.
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/../system/watchtower" && pwd)"
cd "$STACK_DIR"

cleanup() { docker compose down -v 2>/dev/null || true; }
trap cleanup EXIT

echo "--- Starting Watchtower stack"
docker compose up -d

echo "--- Waiting for watchtower container to enter 'running' state (up to 30s)"
deadline=$((SECONDS + 30))
until [ "$(docker inspect --format='{{.State.Status}}' watchtower 2>/dev/null)" = "running" ]; do
  [ $SECONDS -lt $deadline ] || { echo "FAIL: watchtower did not start within 30s"; exit 1; }
  sleep 2
done

echo "PASS: watchtower is running"
