#!/usr/bin/env bash
# Pull latest base images, rebuild local images, restart all containers.
# Data is preserved.
set -euo pipefail
cd "$(dirname "$0")/../.."

docker-compose down
docker-compose build --pull
docker-compose up -d
