#!/usr/bin/env bash
# Quick health check: is the web UI up, and has discovery found devices?
set -u
cd "$(dirname "$0")/../.." || exit 1

APP_URL=$(grep '^APP_URL=' .env | cut -d= -f2-)
TOKEN=$(grep '^LNMS_API_TOKEN=' .env | cut -d= -f2-)

echo "Web UI:  $(curl -kso /dev/null -w '%{http_code}' "$APP_URL")"
echo "Devices: $(curl -kso /dev/null -w '%{http_code}' -H "X-Auth-Token: $TOKEN" "$APP_URL/api/v0/devices")"
