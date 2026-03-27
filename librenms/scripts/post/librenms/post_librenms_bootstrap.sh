#!/usr/bin/env sh
# Post-start bootstrap: runs once on every docker compose up.
# Runs in the docker:cli container; orchestrates other containers via docker exec.

# Abort on undefined variables and any failed command (no silent half-runs).
set -eu

# Container names for docker exec (override if compose renames them).
LIBRENMS="${LIBRENMS_CONTAINER:-librenms}"
DB="${DB_CONTAINER:-librenms-db}"

# Run lnms as the librenms user; run SQL via mariadb client in the DB container.
lnms()   { docker exec -u librenms "$LIBRENMS" lnms "$@"; }
db_sql() { docker exec -e MYSQL_PWD="$DB_PASSWORD" "$DB" mariadb -u"$DB_USER" "$DB_NAME" -e "$1"; }

# LibreNMS often needs more than 60s on first boot (migrations). Wait until the app answers.
echo "Waiting for LibreNMS (lnms) to be ready..."
i=0
max=600
while ! lnms config:get nets >/dev/null 2>&1; do
  i=$((i + 5))
  if [ "$i" -ge "$max" ]; then
    echo "Timed out after ${max}s — check: docker logs -f librenms" >&2
    exit 1
  fi
  sleep 5
done
echo "LibreNMS is ready."

# Ensure admin exists (idempotent re-run on each compose up updates password).
lnms user:add --password="$LNMS_ADMIN_PASS" --role=admin "$LNMS_ADMIN_USER"

# Optional: register API token in DB and POST bundled alert rules via init script.
if [ "${IMPORT_ALERT_COLLECTION:-1}" = "1" ] && [ -n "${LNMS_API_TOKEN:-}" ]; then
  db_sql "DELETE FROM api_tokens WHERE description = 'monitor_stack bootstrap';
          INSERT INTO api_tokens (user_id, token_hash, description, disabled)
          SELECT user_id, '${LNMS_API_TOKEN}', 'monitor_stack bootstrap', 0
          FROM users WHERE username='${LNMS_ADMIN_USER}' LIMIT 1;"
  docker exec \
    -e LNMS_API_TOKEN="$LNMS_API_TOKEN" \
    -e LNMS_URL=http://127.0.0.1:8000 \
    "$LIBRENMS" php /data/init-scripts/post_librenms_import_alerts.php
fi

# Drop stale config so discovery uses current settings.
lnms cache:clear
# Subnet discovery for $config['nets'] (from env/config.php in librenms).
lnms scan

# Optional: attach TCP service checks from init script (needs devices from scan).
if [ "${IMPORT_SERVICES:-1}" = "1" ] && [ -n "${LNMS_API_TOKEN:-}" ]; then
  docker exec \
    -e LNMS_API_TOKEN="$LNMS_API_TOKEN" \
    -e LNMS_URL=http://127.0.0.1:8000 \
    "$LIBRENMS" php /data/init-scripts/post_librenms_import_services.php
fi
