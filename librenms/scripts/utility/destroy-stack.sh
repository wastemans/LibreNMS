#!/usr/bin/env bash
# WARNING: Stops all containers and destroys all persistent data. Does not rebuild.
set -euo pipefail
cd "$(dirname "$0")/../.."

DATA_DIR=$(grep '^DATA_DIR=' .env | cut -d= -f2-)

echo "WARNING: This will permanently delete all data at: ${DATA_DIR}"
read -r -p "Type YES to confirm: " confirm
[ "$confirm" = "YES" ] || { echo "Aborted."; exit 1; }

docker compose down
rm -rf "${DATA_DIR:?}"
