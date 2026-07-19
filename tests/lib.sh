#!/usr/bin/env bash
# Standard test library for Portainer stack smoke tests.
# Usage: source "$(dirname "$0")/lib.sh"
set -euo pipefail

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# ---------------------------------------------------------------------------
# Directory / path helpers
# ---------------------------------------------------------------------------

# Resolve the stack directory from a test script path.
# Usage: STACK_DIR=$(stack_dir "$0" "../network/unifi-controller")
stack_dir() {
    local script_path="$1"
    local relative="$2"
    cd "$(dirname "$script_path")/$relative" && pwd
}

# ---------------------------------------------------------------------------
# Docker network lifecycle (for external networks like qnet)
# ---------------------------------------------------------------------------

# Create an external Docker network if it does not already exist.
# Usage: docker_network_ensure qnet-static-bond0-0094fd
docker_network_ensure() {
    local net="$1"
    if ! docker network ls --format '{{.Name}}' | grep -qx "$net"; then
        echo "--- Creating external network: ${net}"
        docker network create "$net"
    fi
}

# Remove a Docker network if it exists.
# Usage: docker_network_remove qnet-static-bond0-0094fd
docker_network_remove() {
    local net="$1"
    docker network rm "$net" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Wait helpers
# ---------------------------------------------------------------------------

# Wait until a container reaches the 'running' state.
# Usage: wait_for_container unifi-network-app 60
wait_for_container() {
    local name="$1"
    local timeout="${2:-60}"
    echo "--- Waiting for ${name} to enter running state (up to ${timeout}s)"
    local deadline=$((SECONDS + timeout))
    until [ "$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null)" = "running" ]; do
        [ $SECONDS -lt $deadline ] || fail "${name} did not start within ${timeout}s"
        sleep 3
    done
    pass "${name} is running"
}

# Wait until an HTTP endpoint returns 200 OK.
# Usage: wait_for_http http://localhost:9090/-/healthy Prometheus 90
wait_for_http() {
    local url="$1"
    local label="$2"
    local timeout="${3:-90}"
    echo "--- Waiting for ${label} at ${url} (up to ${timeout}s)"
    local deadline=$((SECONDS + timeout))
    until curl -sf -o /dev/null "$url" 2>/dev/null; do
        [ $SECONDS -lt $deadline ] || fail "${label} did not become reachable within ${timeout}s"
        sleep 3
    done
    pass "${label} is reachable"
}

# Wait until MongoDB accepts authenticated connections.
# Usage: wait_for_mongodb unifi-db unifi testpass 60
wait_for_mongodb() {
    local container="$1"
    local user="$2"
    local pass="$3"
    local timeout="${4:-60}"
    echo "--- Waiting for MongoDB to accept authenticated connections (up to ${timeout}s)"
    local deadline=$((SECONDS + timeout))
    until docker exec "$container" mongo --quiet -u "$user" -p "$pass" \
        --authenticationDatabase unifi --eval 'db.adminCommand({ping:1})' > /dev/null 2>&1; do
        [ $SECONDS -lt $deadline ] || fail "MongoDB did not become reachable within ${timeout}s"
        sleep 3
    done
    pass "MongoDB accepts authenticated connections"
}

# ---------------------------------------------------------------------------
# Cleanup helpers
# ---------------------------------------------------------------------------

# Standard cleanup: stop compose stack and remove volumes.
# Usage: trap 'standard_cleanup' EXIT
standard_cleanup() {
    docker compose down -v 2>/dev/null || true
}

# Extended cleanup that also removes an external network and temp directories.
# Usage: trap 'full_cleanup "qnet-static-bond0-0094fd" "/tmp/foo"' EXIT
full_cleanup() {
    standard_cleanup
    local net="${1:-}"
    shift || true
    [ -n "$net" ] && docker_network_remove "$net"
    for dir in "$@"; do
        [ -n "$dir" ] && rm -rf "$dir" 2>/dev/null || true
    done
}
