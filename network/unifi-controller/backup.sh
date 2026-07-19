#!/bin/bash
# UniFi pre-upgrade backup / downgrade restore script.
# Runs as a one-shot init container before the controller starts.
# Detects image tag changes:
#   - Same tag: skip
#   - New tag (upgrade): create backup
#   - Previously seen tag (downgrade): restore from matching backup
set -euo pipefail

BACKUP_DIR="/backups"
VERSION_FILE="${BACKUP_DIR}/.last_backup_version"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CURRENT_VERSION=$(grep -A1 'unifi-network-app:' /docker-compose.yml | grep 'image:' | sed 's/.*image: *//' | tr -d '"')
if [ -z "$CURRENT_VERSION" ]; then
    echo "[error] Could not read controller image tag from /docker-compose.yml"
    exit 1
fi

restore_from_backup() {
    local backup_path="$1"
    echo "[restore] Restoring from ${backup_path}..."

    echo "[restore] Restoring MongoDB..."
    mongorestore \
        --drop \
        --host="${MONGO_HOST}" \
        --port="${MONGO_PORT}" \
        --username="${MONGO_USER}" \
        --password="${MONGO_PASS}" \
        --authenticationDatabase="${MONGO_AUTHSOURCE:-admin}" \
        "${backup_path}/mongo"

    echo "[restore] Restoring UniFi config..."
    if [ -f "${backup_path}/unifi-config.tar.gz" ]; then
        rm -rf /unifi-config/*
        tar xzf "${backup_path}/unifi-config.tar.gz" -C /unifi-config
    fi

    echo "[restore] Restore complete."
}

# ---------------------------------------------------------------------------
# Determine if we need to restore, backup, or skip
# ---------------------------------------------------------------------------
if [ -f "$VERSION_FILE" ]; then
    LAST_VERSION=$(cat "$VERSION_FILE")

    if [ "$LAST_VERSION" = "$CURRENT_VERSION" ]; then
        echo "[check] Version unchanged (${CURRENT_VERSION}). Nothing to do."
        exit 0
    fi

    echo "[check] Version changed: ${LAST_VERSION} -> ${CURRENT_VERSION}"

    # Scan backups to see if this is a downgrade to a previously backed-up version
    FOUND_BACKUP=""
    for dir in "${BACKUP_DIR}"/*/; do
        if [ -f "${dir}/.version" ]; then
            BACKUP_VERSION=$(cat "${dir}/.version")
            if [ "$BACKUP_VERSION" = "$CURRENT_VERSION" ]; then
                FOUND_BACKUP="$dir"
                break
            fi
        fi
    done

    if [ -n "$FOUND_BACKUP" ]; then
        echo "[check] Downgrade detected! Found previous backup for ${CURRENT_VERSION}."
        restore_from_backup "$FOUND_BACKUP"
        echo "$CURRENT_VERSION" > "$VERSION_FILE"
        exit 0
    fi

    echo "[check] Upgrade detected. Creating new backup before upgrading."
else
    echo "[check] First deploy. Creating baseline backup for ${CURRENT_VERSION}."
fi

# ---------------------------------------------------------------------------
# Create new backup
# ---------------------------------------------------------------------------
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

echo "[backup] Dumping MongoDB..."
mongodump \
    --host="${MONGO_HOST}" \
    --port="${MONGO_PORT}" \
    --username="${MONGO_USER}" \
    --password="${MONGO_PASS}" \
    --authenticationDatabase="${MONGO_AUTHSOURCE:-admin}" \
    --out="${BACKUP_PATH}/mongo"

echo "[backup] Archiving UniFi config..."
tar czf "${BACKUP_PATH}/unifi-config.tar.gz" -C /unifi-config . 2>/dev/null || true

# Store the image tag inside the backup directory so we can identify it later
echo "$CURRENT_VERSION" > "${BACKUP_PATH}/.version"
echo "$CURRENT_VERSION" > "$VERSION_FILE"

# Rotate old backups (keep N most recent)
RETENTION="${BACKUP_RETENTION:-7}"
cd "$BACKUP_DIR"
ls -1dt [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | \
    tail -n +$((RETENTION + 1)) | \
    xargs -r rm -rf

echo "[backup] Complete: ${BACKUP_PATH}"
