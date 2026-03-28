#!/usr/bin/env bash
# Poll the API until it answers 200, then exit. Run after build/restart.
set -u
cd "$(dirname "$0")/../.." || exit 1
. .env

while true; do
  code=$(curl -kso /dev/null -w '%{http_code}' -H "X-Auth-Token: $LNMS_API_TOKEN" "$APP_URL/api/v0/devices" 2>/dev/null)
  echo "Devices API: $code"
  [ "$code" = "200" ] && exit 0
  sleep 5
done
