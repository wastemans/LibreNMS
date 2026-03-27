#!/usr/bin/env bash
# Optional manual re-run of the same import the bootstrap uses (PHP inside librenms).
#
# Usage (from host, repo librenms/ directory):
#   export LNMS_API_TOKEN='...'   # same value as in .env
#   ./scripts/import-alert-collection.sh

set -euo pipefail

CONTAINER="${LIBRENMS_CONTAINER:-librenms}"

docker exec \
  -e LNMS_API_TOKEN="${LNMS_API_TOKEN:?set LNMS_API_TOKEN}" \
  -e LNMS_URL="${LNMS_URL:-http://127.0.0.1:8000}" \
  "$CONTAINER" php /data/init-scripts/import-alert-collection.php
