#!/bin/bash
# =============================================================
# Anti-DDoS hardening para VPS SRS-HLS (37.59.97.144)
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
    rm -f /etc/sysctl.d/99-anti-ddos.conf
    sysctl --system > /dev/null 2>&1
    echo "  Revertido OK"
    exit 0
fi

# --- APLICAR ---

echo "=== [1/3] Sysctl hardening ==="

cat > /etc/sysctl.d/99-anti-ddos.conf << 'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 4096
EOF

sysctl --system > /dev/null 2>&1
echo "  OK"

echo "=== [2/3] iptables ==="

# Limpiar cadena si existe
iptables -D INPUT -j ANTI_DDOS 2>/dev/null || true
iptables -F ANTI_DDOS 2>/dev/null || true
iptables -X ANTI_DDOS 2>/dev/null || true

iptables -N ANTI_DDOS

# --- Whitelist: servidores de confianza (sin límite) ---
iptables -A ANTI_DDOS -s $SRS_INGEST -j RETURN
iptables -A ANTI_DDOS -s 127.0.0.1 -j RETURN

# --- Drop paquetes inválidos ---
iptables -A ANTI_DDOS -m state --state INVALID -j DROP

# --- SYN flood en puertos HTTP/HTTPS ---
iptables -A ANTI_DDOS -p tcp --dport 80 --syn -m hashlimit --hashlimit-name syn80 \
    --hashlimit-above 30/s --hashlimit-burst 50 --hashlimit-mode srcip --hashlimit-htable-expire 30000 -j DROP
iptables -A ANTI_DDOS -p tcp --dport 443 --syn -m hashlimit --hashlimit-name syn443 \
    --hashlimit-above 30/s --hashlimit-burst 50 --hashlimit-mode srcip --hashlimit-htable-expire 30000 -j DROP

# --- ICMP flood ---
iptables -A ANTI_DDOS -p icmp --icmp-type echo-request -m limit --limit 2/s --limit-burst 4 -j RETURN
iptables -A ANTI_DDOS -p icmp --icmp-type echo-request -j DROP

# --- RTMP: solo srs-ingest, bloquear todo el resto ---
iptables -A ANTI_DDOS -p tcp --dport 1935 -j DROP

# --- API SRS: solo localhost (ya whitelisted arriba) ---
iptables -A ANTI_DDOS -p tcp --dport 1985 -j DROP

# --- Insertar cadena en INPUT ---
iptables -I INPUT -j ANTI_DDOS
echo "  OK"

echo "=== [3/3] Persistir reglas ==="

if ! dpkg -l | grep -q iptables-persistent; then
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get update -qq && apt-get install -y -qq iptables-persistent
fi

iptables-save > /etc/iptables/rules.v4
echo "  OK"

echo ""
echo "=== LISTO ==="
echo "  - Whitelist: $SRS_INGEST (ingest), localhost"
echo "  - SYN/ICMP flood protection en HTTP/HTTPS"
echo "  - RTMP: solo $SRS_INGEST permitido, resto bloqueado"
echo "  - Puerto 1985 solo accesible desde localhost e ingest"
echo "  - Puerto 8080 abierto (consola SRS)"
echo ""
echo "  Ver reglas:  iptables -L ANTI_DDOS -v -n"
echo "  Revertir:    bash anti-ddos.sh --revert"
