#!/bin/bash
# =============================================================
# Anti-DDoS para VPS SRS-HLS (37.59.97.144)
# Protege el consumo abusivo de HLS y restringe RTMP al ingest
# Ejecutar como root: bash anti-ddos.sh
# Revertir:           bash anti-ddos.sh --revert
# =============================================================

set -e

# --- Servidor de confianza (único permitido en RTMP) ---
SRS_INGEST="141.94.207.173"

# --- REVERTIR ---
if [ "$1" = "--revert" ]; then
    echo "=== Revirtiendo anti-ddos ==="
    iptables -D INPUT -j ANTI_DDOS 2>/dev/null || true
    iptables -F ANTI_DDOS 2>/dev/null || true
    iptables -X ANTI_DDOS 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    echo "  Revertido OK"
    exit 0
fi

# --- APLICAR ---

echo "=== [1/2] iptables ==="

# Limpiar cadena si existe
iptables -D INPUT -j ANTI_DDOS 2>/dev/null || true
iptables -F ANTI_DDOS 2>/dev/null || true
iptables -X ANTI_DDOS 2>/dev/null || true

iptables -N ANTI_DDOS

# --- Whitelist: ingest y localhost (sin límite) ---
iptables -A ANTI_DDOS -s $SRS_INGEST -j RETURN
iptables -A ANTI_DDOS -s 127.0.0.1 -j RETURN

# --- RTMP: solo ingest, bloquear todo el resto ---
iptables -A ANTI_DDOS -p tcp --dport 1935 -j DROP

# --- API SRS: solo localhost e ingest ---
iptables -A ANTI_DDOS -p tcp --dport 1985 -j DROP

# --- HLS: limitar requests abusivos por IP ---
# .m3u8 se pide cada 2-4 seg por viewer, 30/s por IP es generoso
iptables -A ANTI_DDOS -p tcp --dport 80 --syn -m hashlimit --hashlimit-name hls80 \
    --hashlimit-above 30/s --hashlimit-burst 60 --hashlimit-mode srcip --hashlimit-htable-expire 30000 -j DROP
iptables -A ANTI_DDOS -p tcp --dport 443 --syn -m hashlimit --hashlimit-name hls443 \
    --hashlimit-above 30/s --hashlimit-burst 60 --hashlimit-mode srcip --hashlimit-htable-expire 30000 -j DROP

# --- Limitar conexiones simultáneas por IP en HLS ---
iptables -A ANTI_DDOS -p tcp --dport 80 -m connlimit --connlimit-above 100 -j DROP
iptables -A ANTI_DDOS -p tcp --dport 443 -m connlimit --connlimit-above 100 -j DROP

# --- Insertar cadena en INPUT ---
iptables -I INPUT -j ANTI_DDOS
echo "  OK"

echo "=== [2/2] Persistir reglas ==="

if ! dpkg -l | grep -q iptables-persistent; then
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get update -qq && apt-get install -y -qq iptables-persistent
fi

iptables-save > /etc/iptables/rules.v4
echo "  OK"

echo ""
echo "=== LISTO ==="
echo "  - RTMP (1935): solo $SRS_INGEST"
echo "  - API (1985): solo localhost e ingest"
echo "  - HLS (80/443): max 30 req/s y 100 conn por IP"
echo "  - Puerto 8080: abierto (consola SRS)"
echo ""
echo "  Ver reglas:  iptables -L ANTI_DDOS -v -n"
echo "  Revertir:    bash anti-ddos.sh --revert"
