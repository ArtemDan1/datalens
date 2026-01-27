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
# HTTP → HTTPS redirect
:80 {
	redir https://{host}{uri} permanent
}

# HTTPS
$domain {
	encode zstd gzip

	log {
		output stdout
		format console
	}

	tls $email

	reverse_proxy $UPSTREAM {
        header_up Host {host}
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-For {remote_host}
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
        header_up Host {host}
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-For {remote_host}
    }
}
EOF
}

case "$MODE" in
  1)
    read -r -p "DOMAIN (например, dl.example.com): " DOMAIN
    read -r -p "EMAIL  (для Let's Encrypt): " EMAIL

    if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
      echo "DOMAIN и EMAIL обязательны для HTTPS."
      exit 1
    fi

    gen_https "$DOMAIN" "$EMAIL"
    echo "Ок: HTTPS + редирект 80→443 сгенерен для $DOMAIN"
    ;;
  2)
    gen_http
    echo "Ок: HTTP режим (:80)"
    ;;
  *)
    echo "Нужно выбрать 1 или 2."
    exit 1
    ;;
esac

echo "Перезапускаю сервисы..."
HC=1 docker compose -f "$COMPOSE_FILE" down
HC=1 docker compose -f "$COMPOSE_FILE" up -d --build
echo "Готово."
