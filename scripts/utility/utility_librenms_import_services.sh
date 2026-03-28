#!/usr/bin/env bash
# This only exists to allow manual re-running of the service import.
#
# Usage (from host, repo root):
# export LNMS_API_TOKEN='...' ./scripts/utility/utility_librenms_import_services.sh

set -euo pipefail

CONTAINER="${LIBRENMS_CONTAINER:-librenms}"

docker exec \
  -e LNMS_API_TOKEN="${LNMS_API_TOKEN:?set LNMS_API_TOKEN}" \
  -e LNMS_URL="${LNMS_URL:-http://127.0.0.1:8000}" \
  "$CONTAINER" php /data/init-scripts/post_librenms_import_services.php
