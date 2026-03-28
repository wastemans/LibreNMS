#!/usr/bin/env bash
# Stop and restart all containers. Data is preserved.
set -euo pipefail
cd "$(dirname "$0")/../.."

docker compose down
docker compose up -d
