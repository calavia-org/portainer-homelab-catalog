#!/bin/bash
set -euo pipefail

# Official linuxserver.io init script for UniFi Network Application
# Creates the unifi user in the MONGO_AUTHSOURCE database with
# dbOwner rights on the application databases.

mongo --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin <<EOF
  use ${MONGO_AUTHSOURCE:-unifi}
  db.createUser({
    user: "$MONGO_USER",
    pwd: "$MONGO_PASS",
    roles: [
      { db: "$MONGO_DBNAME", role: "dbOwner" },
      { db: "${MONGO_DBNAME}_stat", role: "dbOwner" },
      { db: "${MONGO_DBNAME}_audit", role: "dbOwner" },
      { db: "${MONGO_DBNAME}_restore", role: "dbOwner" }
    ]
  });
EOF
