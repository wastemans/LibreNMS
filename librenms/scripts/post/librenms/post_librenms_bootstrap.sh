#!/usr/bin/env sh
# Run-once bootstrap tasks fired by the scan service on every docker compose up.
# Runs inside the docker:cli container; uses docker exec to reach other containers.
#
# Required env vars (passed from docker-compose scan service):
#   LNMS_ADMIN_USER, LNMS_ADMIN_PASS
#   DB_USER, DB_PASSWORD, DB_NAME
#   LNMS_API_TOKEN, IMPORT_ALERT_COLLECTION

set -eu

LIBRENMS="${LIBRENMS_CONTAINER:-librenms}"
DB="${DB_CONTAINER:-librenms-db}"

# Wait for DB migrations and LibreNMS init to complete
sleep 60

# Create or update the admin user
docker exec -u librenms "$LIBRENMS" lnms user:add \
  --password="$LNMS_ADMIN_PASS" --role=admin "$LNMS_ADMIN_USER"

# Import the full alert rule collection if token is set and import is enabled
if [ "${IMPORT_ALERT_COLLECTION:-1}" = "1" ] && [ -n "${LNMS_API_TOKEN:-}" ]; then
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$DB" mariadb -u"$DB_USER" "$DB_NAME" \
    -e "DELETE FROM api_tokens WHERE description = 'monitor_stack bootstrap';"
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$DB" mariadb -u"$DB_USER" "$DB_NAME" \
    -e "INSERT INTO api_tokens (user_id, token_hash, description, disabled)
        SELECT user_id, '${LNMS_API_TOKEN}', 'monitor_stack bootstrap', 0
        FROM users WHERE username='${LNMS_ADMIN_USER}' LIMIT 1;"
  docker exec \
    -e LNMS_API_TOKEN="$LNMS_API_TOKEN" \
    -e LNMS_URL=http://127.0.0.1:8000 \
    "$LIBRENMS" php /data/init-scripts/post_librenms_import_alerts.php
fi

# Clear cache then run a discovery scan
docker exec -u librenms "$LIBRENMS" lnms cache:clear
docker exec -u librenms "$LIBRENMS" lnms scan
