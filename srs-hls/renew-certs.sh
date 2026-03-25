#!/bin/bash
# Renovación automática de certificados SSL
# Agregar a cron del servidor: 0 0,12 * * * /ruta/srs-hls/renew-certs.sh >> /var/log/certbot-renew.log 2>&1

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker run --rm \
  --network host \
  -v "$SCRIPT_DIR/letsencrypt:/etc/letsencrypt" \
  -v "$SCRIPT_DIR/certbot-webroot:/var/www/certbot" \
  certbot/certbot renew \
  --webroot -w /var/www/certbot \
  --quiet

# Recargar nginx para aplicar el nuevo certificado
docker exec iblups-hls-nginx nginx -s reload
echo "$(date): Certificados renovados y nginx recargado"
