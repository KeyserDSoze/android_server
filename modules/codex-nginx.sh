#!/bin/sh
set -eu

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }

if [ -f /etc/alpine-release ]; then OS_ID=alpine; else OS_ID=debian; fi

BACKEND_PORT="${CODEX_PROXY_PORT:-22001}"
PUBLIC_PORT="${CODEX_NGINX_PROXY_PORT:-22000}"
CORS_ORIGINS="${CODEX_NGINX_PROXY_CORS_ORIGIN:-*}"

if [ -f /etc/default/codex-proxy ]; then
  . /etc/default/codex-proxy
  BACKEND_PORT="${CODEX_PROXY_PORT:-22001}"
  PUBLIC_PORT="${CODEX_NGINX_PROXY_PORT:-22000}"
  CORS_ORIGINS="${CODEX_NGINX_PROXY_CORS_ORIGIN:-*}"
elif [ -f /etc/conf.d/codex-proxy ]; then
  . /etc/conf.d/codex-proxy
  BACKEND_PORT="${CODEX_PROXY_PORT:-22001}"
  PUBLIC_PORT="${CODEX_NGINX_PROXY_PORT:-22000}"
  CORS_ORIGINS="${CODEX_NGINX_PROXY_CORS_ORIGIN:-*}"
fi

if [ -f /etc/alpine-release ]; then
  apk add --no-cache nginx
else
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q nginx
fi

if [ "$CORS_ORIGINS" = "*" ]; then
  CORS_MAP=""
  # Echo the requesting origin so browser credentialed requests also work.
  CORS_HEADER_VALUE='$http_origin'
else
  CORS_MAP=''
  CORS_HEADER_VALUE='$codex_cors_origin'
  OLD_IFS="$IFS"
  IFS=,
  for origin in $CORS_ORIGINS; do
    origin="$(printf '%s' "$origin" | sed 's/^ *//;s/ *$//')"
    [ -n "$origin" ] || continue
    CORS_MAP="$CORS_MAP
      \"$origin\" \"$origin\";"
  done
  IFS="$OLD_IFS"
fi

if [ -f /etc/alpine-release ]; then
  NGINX_CONF_DIR="/etc/nginx/http.d"
  mkdir -p "$NGINX_CONF_DIR"
  NGINX_CONF="$NGINX_CONF_DIR/codex-proxy.conf"
else
  NGINX_CONF_DIR="/etc/nginx/sites-available"
  mkdir -p "$NGINX_CONF_DIR" /etc/nginx/sites-enabled
  NGINX_CONF="$NGINX_CONF_DIR/codex-proxy"
fi

cat > "$NGINX_CONF" <<NGINX
map \$http_origin \$codex_cors_origin {
    default "";
$CORS_MAP
}

server {
    listen $PUBLIC_PORT;
    server_name _;

    location / {
        if (\$request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin $CORS_HEADER_VALUE always;
            add_header Vary Origin always;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
            add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept, Origin" always;
            add_header Access-Control-Max-Age 86400 always;
            add_header Content-Length 0;
            return 204;
        }

        add_header Access-Control-Allow-Origin $CORS_HEADER_VALUE always;
        add_header Vary Origin always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept, Origin" always;

        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_read_timeout 3600s;
    }
}
NGINX

if [ ! -f /etc/alpine-release ]; then
  ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/codex-proxy
fi

nginx -t
if [ -f /etc/alpine-release ]; then
  rc-update add nginx default >/dev/null 2>&1 || true
  rc-service nginx restart
else
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl reload nginx 2>/dev/null || systemctl restart nginx
fi

printf 'nginx CORS proxy: public port %s -> Codex backend port %s\n' "$PUBLIC_PORT" "$BACKEND_PORT"
printf 'nginx CORS origins: %s\n' "$CORS_ORIGINS"
