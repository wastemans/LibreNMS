#!/usr/bin/env bash
# Manual re-run of the same alert import the bootstrap uses.
#
# Usage (from host, repo librenms/ directory):
#   export LNMS_API_TOKEN='...'   # same value as in .env
#   ./scripts/post/librenms/post_librenms_import_alerts.sh

set -euo pipefail

CONTAINER="${LIBRENMS_CONTAINER:-librenms}"

docker exec \
  -e LNMS_API_TOKEN="${LNMS_API_TOKEN:?set LNMS_API_TOKEN}" \
  -e LNMS_URL="${LNMS_URL:-http://127.0.0.1:8000}" \
  "$CONTAINER" php /data/init-scripts/post_librenms_import_alerts.php
