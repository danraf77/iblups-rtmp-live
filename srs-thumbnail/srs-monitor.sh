#!/bin/bash
# srs-monitor.sh (Thumbnail)

FAIL_COUNT_FILE="/tmp/srs_thumb_fail_count"
MAX_FAILS=3
THUMBNAIL_DIR="/var/lib/docker/volumes/srs-thumbnail_srs-data/_data"
THUMBNAIL_MAX_AGE=300  # 5 minutos: 2.5x el intervalo de captura (120s)

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$BASE_DIR/.env" 2>/dev/null

check_health() {
    # 1. Contenedor SRS corriendo
    if ! docker ps | grep -q 'iblups-srs-thumbnail'; then
        echo "[FAIL] Contenedor iblups-srs-thumbnail no está corriendo"
        return 1
    fi

    # 2. Contenedor Nginx corriendo
    if ! docker ps | grep -q 'iblups-thumbnail-nginx'; then
        echo "[FAIL] Contenedor iblups-thumbnail-nginx no está corriendo"
        return 1
    fi

    # 3. Puertos abiertos (80 HTTP y 1935 RTMP)
    if ! ss -tuln | grep -q ':80 '; then
        echo "[FAIL] Puerto 80 (Nginx) no está escuchando"
        return 1
    fi
    if ! ss -tuln | grep -q ':1935 '; then
        echo "[FAIL] Puerto 1935 (RTMP) no está escuchando"
        return 1
    fi

    # 4. API de SRS responde HTTP 200
    if ! curl -s -f http://127.0.0.1:1985/api/v1/versions > /dev/null; then
        echo "[FAIL] API SRS no responde en :1985"
        return 1
    fi

    # 5. Thumbnails recientes: al menos un .jpg modificado en los últimos THUMBNAIL_MAX_AGE segundos
    if [ -d "$THUMBNAIL_DIR" ]; then
        RECENT=$(find "$THUMBNAIL_DIR" -name "*.jpg" -newer /proc/1 \
                 -mmin -$((THUMBNAIL_MAX_AGE / 60)) 2>/dev/null | head -1)
        if [ -z "$RECENT" ]; then
            echo "[FAIL] No hay thumbnails .jpg recientes en los últimos ${THUMBNAIL_MAX_AGE}s"
            return 1
        fi
    fi

    return 0
}

send_email() {
    local subject="$1"
    local message="$2"
    curl -s -X POST "https://api.resend.com/emails" \
         -H "Authorization: Bearer $RESEND_API_KEY" \
         -H "Content-Type: application/json" \
         -d "{
               \"from\": \"$RESEND_FROM\",
               \"to\": [\"$RESEND_TO\"],
               \"subject\": \"$subject\",
               \"text\": \"$message\"
             }"
}

if check_health; then
    # Recuperado tras fallos previos → notificar y limpiar contador
    if [ -f "$FAIL_COUNT_FILE" ]; then
        rm "$FAIL_COUNT_FILE"
        send_email "OK: IBLUPS Thumbnail $SERVER_ID" "Servidor recuperado exitosamente."
    fi
    exit 0
fi

# Acumular fallos
FAILS=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo "0")
FAILS=$((FAILS + 1))
echo "$FAILS" > "$FAIL_COUNT_FILE"

if [ "$FAILS" -eq 1 ]; then
    send_email "WARNING (1/3): IBLUPS Thumbnail $SERVER_ID" "Falla detectada. Reintentando en 1 minuto."
elif [ "$FAILS" -eq 2 ]; then
    send_email "ALERT (2/3): IBLUPS Thumbnail $SERVER_ID" "Segunda falla consecutiva detectada. Monitoreando."
elif [ "$FAILS" -ge "$MAX_FAILS" ]; then
    send_email "CRITICAL (3/3): IBLUPS Thumbnail $SERVER_ID" "Tres fallas consecutivas. Reiniciando el stack completo."
    cd "$BASE_DIR" || exit 1
    docker compose down
    docker compose up -d
    rm -f "$FAIL_COUNT_FILE"
fi