#!/bin/bash
set -euo pipefail

mongo --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin <<EOF
  db = db.getSiblingDB("$MONGO_INITDB_DATABASE");
  db.createUser({
    user: "$MONGO_INITDB_ROOT_USERNAME",
    pwd: "$MONGO_INITDB_ROOT_PASSWORD",
    roles: [{ role: "dbOwner", db: "$MONGO_INITDB_DATABASE" }]
  });
EOF
