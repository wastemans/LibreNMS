#!/usr/bin/env sh
# Nginx startup: strips scheme from APP_URL, generates a self-signed cert,
# substitutes SERVER_NAME into the nginx config template, then starts nginx.
#
# Required env var: APP_URL (e.g. https://lmns.i)

set -eu

apk add --no-cache openssl gettext -q

SN="${APP_URL#*//}"

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /tmp/key.pem -out /tmp/cert.pem \
  -subj "/CN=$SN" 2>/dev/null

SERVER_NAME="$SN" envsubst '${SERVER_NAME}' \
  < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
