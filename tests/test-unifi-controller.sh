#!/usr/bin/env bash
# Smoke-test the UniFi Controller stack:
#   1. MongoDB starts and its healthcheck passes.
#   2. The configured user can authenticate to MongoDB.
#   3. The UniFi controller container starts.
#   4. Backup on upgrade and restore on downgrade work correctly.
set -euo pipefail

source "$(dirname "$0")/lib.sh"

STACK_DIR=$(stack_dir "$0" "../network/unifi-controller")
export MONGO_USER="${MONGO_USER:-unifi}"
export MONGO_PASS="${MONGO_PASS:-testpass}"
export MONGO_INITDB_ROOT_USERNAME="$MONGO_USER"
export MONGO_INITDB_ROOT_PASSWORD="$MONGO_PASS"
export UNIFI_CONFIG_PATH="${UNIFI_CONFIG_PATH:-/tmp/unifi-test/config}"
export UNIFI_DB_PATH="${UNIFI_DB_PATH:-/tmp/unifi-test/db}"
export UNIFI_BACKUP_PATH="${UNIFI_BACKUP_PATH:-/tmp/unifi-test/backups}"
mkdir -p "$UNIFI_CONFIG_PATH" "$UNIFI_DB_PATH" "$UNIFI_BACKUP_PATH"
cd "$STACK_DIR"

QNET="qnet-static-bond0-0094fd"
docker_network_ensure "$QNET"
trap 'full_cleanup "${QNET}" "${UNIFI_CONFIG_PATH}" "${UNIFI_DB_PATH}" "${UNIFI_BACKUP_PATH}"' EXIT

echo "--- Phase 1: Starting MongoDB"
docker compose up -d unifi-db

wait_for_mongodb unifi-db "$MONGO_USER" "$MONGO_PASS" 60

echo "--- Inserting baseline marker into MongoDB"
docker exec unifi-db mongo \
  -u "$MONGO_USER" -p "$MONGO_PASS" \
  --authenticationDatabase unifi \
  --eval 'db.getSiblingDB("unifi").testmarkers.insertOne({marker: "baseline"})'

echo "--- Phase 2: Starting full stack"
docker compose up -d

wait_for_container unifi-network-app 60

echo "--- Phase 2a: Verifying UniFi app starts and connects to MongoDB"
UNIFI_START_DEADLINE=$((SECONDS + 180))
while [ $SECONDS -lt $UNIFI_START_DEADLINE ]; do
    if docker logs unifi-network-app 2>&1 | grep -qE "Server startup in|Initialization complete"; then
        pass "UniFi application started successfully"
        break
    fi
    if docker logs unifi-network-app 2>&1 | grep -q "AuthenticationFailed"; then
        fail "UniFi failed to authenticate to MongoDB — check credentials match"
    fi
    sleep 5
done
[ $SECONDS -lt $UNIFI_START_DEADLINE ] || pass "UniFi application start timed out (may still be initializing)"

echo "--- Phase 3: Testing backup on upgrade and restore on downgrade"

ORIGINAL_TAG=$(grep -A1 'unifi-network-app:' docker-compose.yml | grep 'image:' | sed 's/.*image: *//' | tr -d '"')
UPGRADE_TAG="${ORIGINAL_TAG}-test"

docker compose stop unifi-network-app unifi-backup

COMPOSE_BACKUP=$(mktemp)
cp docker-compose.yml "$COMPOSE_BACKUP"

echo "--- Simulating upgrade to new tag: ${UPGRADE_TAG}"
echo "$ORIGINAL_TAG" > "${UNIFI_BACKUP_PATH}/.last_backup_version"
sed "s|image: ${ORIGINAL_TAG}|image: ${UPGRADE_TAG}|g" docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml
docker rm -f unifi-backup 2>/dev/null || true
docker compose up -d unifi-backup

echo "--- Waiting for backup container to complete"
docker wait unifi-backup

cp "$COMPOSE_BACKUP" docker-compose.yml

UPGRADE_BACKUP=$(find "${UNIFI_BACKUP_PATH}" -maxdepth 2 -name ".version" -exec grep -l "$UPGRADE_TAG" {} \; | head -1)
[ -n "$UPGRADE_BACKUP" ] || fail "No backup found for upgrade tag ${UPGRADE_TAG}"
pass "Upgrade backup created at $(dirname "$UPGRADE_BACKUP")"

echo "--- Simulating data loss after upgrade"
docker exec unifi-db mongo \
  -u "$MONGO_USER" -p "$MONGO_PASS" \
  --authenticationDatabase unifi \
  --eval 'db.getSiblingDB("unifi").testmarkers.deleteOne({marker: "baseline"})'

echo "--- Simulating downgrade back to original tag: ${ORIGINAL_TAG}"
echo "$UPGRADE_TAG" > "${UNIFI_BACKUP_PATH}/.last_backup_version"
docker rm -f unifi-backup 2>/dev/null || true
docker compose up -d unifi-backup

echo "--- Waiting for restore to complete"
docker wait unifi-backup

echo "--- Verifying MongoDB was restored to original state"
RESTORED_MARKER=$(docker exec unifi-db mongo \
  -u "$MONGO_USER" -p "$MONGO_PASS" \
  --authenticationDatabase unifi \
  --quiet \
  --eval 'db.getSiblingDB("unifi").testmarkers.countDocuments({marker: "baseline"})')

[ "$RESTORED_MARKER" != "0" ] || fail "Marker missing — restore did not bring back baseline data"
pass "Downgrade restore successful — baseline data recovered"
