#!/bin/bash
# Script de inicialización - ejecutar UNA VEZ antes del primer docker compose up
# Uso: ./init-letsencrypt.sh tu@email.com

set -e

DOMAIN="live.cdnlivecdn.com"
EMAIL="${1:-}"

if [ -z "$EMAIL" ]; then
  echo "Uso: ./init-letsencrypt.sh tu@email.com"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Creando directorios..."
mkdir -p "$SCRIPT_DIR/letsencrypt" "$SCRIPT_DIR/certbot-webroot"

echo "==> Deteniendo servicios si están corriendo (para liberar puerto 80)..."
cd "$SCRIPT_DIR"
docker compose down 2>/dev/null || true

echo "==> Obteniendo certificado SSL para $DOMAIN..."
docker run --rm \
  --network host \
  -v "$SCRIPT_DIR/letsencrypt:/etc/letsencrypt" \
  certbot/certbot certonly --standalone \
  --preferred-challenges http \
  -d "$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos --no-eff-email

echo ""
echo "==> Certificado obtenido exitosamente!"
echo "==> Ahora inicia el stack con: docker compose up -d"
