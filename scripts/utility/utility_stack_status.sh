#!/usr/bin/env bash
# Poll the API until it answers 200. Run after build/restart.
set -u
cd "$(dirname "$0")/../.." || exit 1
. .env

while true; do
  printf "HTTP Return: " ; curl -kso /dev/null -w 'Devices API: %{http_code}\n' -H "X-Auth-Token: $LNMS_API_TOKEN" "$APP_URL/api/v0/devices" 2>/dev/null
  echo "Scan container log: "
  docker logs librenms-scan
  echo "Sleeping for 5 seconds..." ; sleep 5
done
