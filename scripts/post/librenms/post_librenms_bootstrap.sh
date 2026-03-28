#!/usr/bin/env sh
# After compose up: wait for DB + app, then admin, optional API imports, discovery.
# Runs in docker:cli with the socket; uses docker exec into librenms / librenms-db.

set -eu

LIBRENMS="${LIBRENMS_CONTAINER:-librenms}"
DB="${DB_CONTAINER:-librenms-db}"

LNMSCMD() { docker exec -u librenms "$LIBRENMS" lnms "$@" ; }

# --- wait for DB + migrations + seeder (table exists but 'admin' role must be seeded too)
while ! docker exec -e MYSQL_PWD="$DB_PASSWORD" "$DB" mariadb -u"$DB_USER" "$DB_NAME" -N -e "SELECT name FROM roles WHERE name='admin'" 2>/dev/null | grep -q admin
do echo "Waiting for DB + migrations..." ; sleep 3 ; done && echo "LibreNMS is ready."

# --- admin (safe to re-run; password comes from .env)
LNMSCMD user:add --password="$LNMS_ADMIN_PASS" --role=admin "$LNMS_ADMIN_USER"
LNMSCMD cache:clear

# --- API token row (REST imports need this even if you skip alert rules)
if [ -n "${LNMS_API_TOKEN:-}" ]; then
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$DB" mariadb -u"$DB_USER" "$DB_NAME" -e \
    "DELETE FROM api_tokens WHERE description = 'monitor_stack bootstrap';
     INSERT INTO api_tokens (user_id, token_hash, description, disabled)
     SELECT user_id, '${LNMS_API_TOKEN}', 'monitor_stack bootstrap', 0
     FROM users WHERE username='${LNMS_ADMIN_USER}' LIMIT 1;"
fi

# --- wait for the web app to accept requests before any API calls
while ! docker exec "$LIBRENMS" curl -so /dev/null http://127.0.0.1:8000 2>/dev/null; do
echo "Waiting for web app on :8000..." ; sleep 3 ; done && echo "Web app is ready."

# --- optional: ship alert_rules.json via API (same idea as UI "add from collection")
if [ "${IMPORT_ALERT_COLLECTION:-1}" = "1" ] && [ -n "${LNMS_API_TOKEN:-}" ]; then
  docker exec \
    -e LNMS_API_TOKEN="$LNMS_API_TOKEN" \
    -e LNMS_URL=http://127.0.0.1:8000 \
    "$LIBRENMS" php /data/init-scripts/post_librenms_import_alerts.php
  LNMSCMD cache:clear
fi

# --- discovery (uses nets from env / config.php in the librenms container)
LNMSCMD scan

# --- optional: services.json via API (after scan so devices exist)
if [ "${IMPORT_SERVICES:-1}" = "1" ] && [ -n "${LNMS_API_TOKEN:-}" ]; then
  docker exec \
    -e LNMS_API_TOKEN="$LNMS_API_TOKEN" \
    -e LNMS_URL=http://127.0.0.1:8000 \
    "$LIBRENMS" php /data/init-scripts/post_librenms_import_services.php
fi
