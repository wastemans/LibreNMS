#!/usr/bin/env bash
# Quick health check: is the web UI up, and has discovery found devices?
set -u
cd "$(dirname "$0")/../.." || exit 1
. .env

echo "Web UI:  $(curl -kso /dev/null -w '%{http_code}' "$APP_URL")"
echo "Devices: $(curl -kso /dev/null -w '%{http_code}' -H "X-Auth-Token: $LNMS_API_TOKEN" "$APP_URL/api/v0/devices")"
