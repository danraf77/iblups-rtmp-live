#!/bin/bash
# ==============================================
# Inicialización de certificados Let's Encrypt
# para thumbnail.iblups.com
# ==============================================

set -e

DOMAIN="thumbnail.iblups.com"
EMAIL="danraf77@gmail.com"
COMPOSE="docker compose"

echo ">>> Paso 1: Parando Nginx si está corriendo..."
$COMPOSE stop nginx-thumbnail-edge 2>/dev/null || true

echo ">>> Paso 2: Obteniendo certificado con certbot standalone..."
echo "    (certbot levanta su propio servidor en puerto 80 temporalmente)"
$COMPOSE run --rm -p 80:80 --entrypoint "" certbot \
  certbot certonly \
  --standalone \
  --email $EMAIL \
  --domain $DOMAIN \
  --agree-tos \
  --no-eff-email \
  --force-renewal

echo ">>> Paso 3: Levantando todos los servicios..."
$COMPOSE up -d

echo ""
echo ">>> ¡Listo! HTTPS habilitado para $DOMAIN"
echo ">>> Verifica con: curl -I https://$DOMAIN/health"
