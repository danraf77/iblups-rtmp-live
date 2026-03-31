#!/bin/bash
# ==============================================
# Inicialización de certificados Let's Encrypt
# para sc2.escuela4.com
# ==============================================

DOMAIN="sc2.escuela4.com"
EMAIL="danraf77@gmail.com"
COMPOSE="docker compose"

echo ">>> Creando certificado dummy para que Nginx pueda arrancar..."
$COMPOSE run --rm --entrypoint "\
  mkdir -p /etc/letsencrypt/live/$DOMAIN && \
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
    -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
    -subj '/CN=localhost'" certbot

echo ">>> Iniciando Nginx..."
$COMPOSE up -d nginx-cdn-edge

echo ">>> Eliminando certificado dummy..."
$COMPOSE run --rm --entrypoint "\
  rm -rf /etc/letsencrypt/live/$DOMAIN && \
  rm -rf /etc/letsencrypt/archive/$DOMAIN && \
  rm -rf /etc/letsencrypt/renewal/$DOMAIN.conf" certbot

echo ">>> Solicitando certificado real a Let's Encrypt..."
$COMPOSE run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --email $EMAIL \
  --domain $DOMAIN \
  --agree-tos \
  --no-eff-email \
  --force-renewal

echo ">>> Recargando Nginx..."
$COMPOSE exec nginx-cdn-edge nginx -s reload

echo ">>> ¡Listo! HTTPS habilitado para $DOMAIN"
