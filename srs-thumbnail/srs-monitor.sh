#!/bin/bash
# srs-monitor.sh (Thumbnail)

FAIL_COUNT_FILE="/tmp/srs_thumb_fail_count"
MAX_FAILS=3
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $BASE_DIR/.env 2>/dev/null

check_health() {
    # 1. Container running
    if ! docker ps | grep -q 'iblups-srs-thumbnail'; then return 1; fi
    
    # 2. Ports Open (8080 HTTP and 1935 RTMP)
    if ! netstat -tuln | grep -q :8080; then return 1; fi
    if ! netstat -tuln | grep -q :1935; then return 1; fi
    
    # 3. HTTP 200 on SRS API
    if ! curl -s -f http://127.0.0.1:1985/api/v1/versions > /dev/null; then return 1; fi
    
    return 0
}

send_email() {
    local subject="$1"
    local message="$2"
    curl -s -X POST "https://api.resend.com/emails" \
         -H "Authorization: Bearer $RESEND_API_KEY" \
         -H "Content-Type: application/json" \
         -d "{
               \"from\": \"alertas@iblups.com\",
               \"to\": [\"$ALERT_EMAIL\"],
               \"subject\": \"$subject\",
               \"text\": \"$message\"
             }"
}

if check_health; then
    if [ -f "$FAIL_COUNT_FILE" ]; then
        rm "$FAIL_COUNT_FILE"
        send_email "OK: IBLUPS Thumbnail $SERVER_ID" "Servidor recuperado exitosamente."
    fi
    exit 0
fi

FAILS=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo "0")
FAILS=$((FAILS+1))
echo "$FAILS" > "$FAIL_COUNT_FILE"

if [ "$FAILS" -eq 1 ]; then
    send_email "WARNING (1): IBLUPS Thumbnail $SERVER_ID" "Falla detectada. Reintentando."
elif [ "$FAILS" -eq 2 ]; then
    send_email "ALERT (2): IBLUPS Thumbnail $SERVER_ID" "Segunda falla detectada."
elif [ "$FAILS" -ge 3 ]; then
    send_email "CRITICAL (3): IBLUPS Thumbnail $SERVER_ID" "Reiniciando el stack completo (docker compose down/up)."
    cd $BASE_DIR || exit 1
    docker compose down
    docker compose up -d
    rm "$FAIL_COUNT_FILE"
fi
