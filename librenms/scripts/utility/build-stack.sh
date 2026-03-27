#!/usr/bin/env bash
# Build images and start all containers.
set -euo pipefail
cd "$(dirname "$0")/../.."

docker-compose build
docker-compose up -d
