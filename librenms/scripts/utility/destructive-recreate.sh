#!/usr/bin/env bash
# WARNING: Destroys all persistent data, then rebuilds and starts the stack.
# This wipes the database, all discovered devices, graphs, and syslog history.
set -euo pipefail
cd "$(dirname "$0")/../.."

DATA_DIR=$(grep '^DATA_DIR=' .env | cut -d= -f2-)

echo "WARNING: This will permanently delete all data at: ${DATA_DIR}"
read -r -p "Type YES to confirm: " confirm
[ "$confirm" = "YES" ] || { echo "Aborted."; exit 1; }

docker compose down
rm -rf "${DATA_DIR:?}"
docker compose build
docker compose up -d
