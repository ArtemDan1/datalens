#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="./docker-compose.fork.yaml"
CADDYFILE_PATH="./Caddyfile"
UPSTREAM="datalens-ui:8080"

echo "Выбери режим:"
echo "  1) HTTPS (Let's Encrypt) — нужен домен + почта, открыты 80/443"
echo "  2) HTTP  (без TLS)       — просто на :80"
read -r -p "Ввод (1/2): " MODE

gen_https() {
  local domain="$1"
  local email="$2"
  cat > "$CADDYFILE_PATH" <<EOF
{
  email $email
}

$domain {
  encode zstd gzip
  
  log {
    output stdout
    format console
  }

  reverse_proxy $UPSTREAM {
    # Подменяем Host на внутренний
    header_up Host {upstream_hostport}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-Host $domain
  }
}
EOF
}

gen_http() {
  cat > "$CADDYFILE_PATH" <<EOF
:80 {
  encode zstd gzip
  
  log {
    output stdout
    format console
  }

  reverse_proxy $UPSTREAM {
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}
EOF
}

case "$MODE" in
  1)
    read -r -p "DOMAIN (например, dl.netvisor.site): " DOMAIN
    read -r -p "EMAIL  (для Let's Encrypt): " EMAIL
    if [[ -z "${DOMAIN// }" || -z "${EMAIL// }" ]]; then
      echo "DOMAIN и EMAIL обязательны для HTTPS."
      exit 1
    fi
    gen_https "$DOMAIN" "$EMAIL"
    
    # Обновляем UI_APP_ENDPOINT в docker-compose
    export UI_APP_ENDPOINT="https://$DOMAIN"
    
    echo "✓ HTTPS сгенерен для $DOMAIN"
    ;;
  2)
    gen_http
    echo "✓ HTTP режим (только :80, без TLS)"
    ;;
  *)
    echo "Нужно выбрать 1 или 2."
    exit 1
    ;;
esac

echo ""
echo "Перезапускаю сервисы..."
HC=1 docker compose -f "$COMPOSE_FILE" down
HC=1 docker compose -f "$COMPOSE_FILE" up -d --build

echo ""
echo "✓ Готово!"
echo ""
echo "Проверь логи:"
echo "  docker compose -f $COMPOSE_FILE logs -f caddy"
echo "  docker compose -f $COMPOSE_FILE logs -f ui"
echo ""
echo "Если проблемы с 403, проверь:"
echo "  docker compose -f $COMPOSE_FILE exec ui env | grep -i host"
