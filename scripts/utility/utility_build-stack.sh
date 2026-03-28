#!/usr/bin/env bash
# Build images and start all containers.
set -euo pipefail
cd "$(dirname "$0")/../.."

docker compose build
docker compose up -d
bash "$(dirname "$0")/utility_stack_status.sh"
