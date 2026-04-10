#!/bin/bash
# =============================================================
# Anti-DDoS hardening para VPS SRS-HLS (OVH)
# Ejecutar como root: bash anti-ddos.sh
# Revertir:           bash anti-ddos.sh --revert
# =============================================================

set -e

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

# Drop paquetes inválidos
iptables -A ANTI_DDOS -m state --state INVALID -j DROP

# SYN flood por IP: máx 30 conexiones nuevas/seg por IP (un viewer normal usa ~1/seg)
iptables -A ANTI_DDOS -p tcp --dport 80 --syn -m hashlimit --hashlimit-name syn80 \
    --hashlimit-above 30/s --hashlimit-burst 50 --hashlimit-mode srcip --hashlimit-htable-expire 30000 -j DROP
iptables -A ANTI_DDOS -p tcp --dport 443 --syn -m hashlimit --hashlimit-name syn443 \
    --hashlimit-above 30/s --hashlimit-burst 50 --hashlimit-mode srcip --hashlimit-htable-expire 30000 -j DROP

# ICMP flood
iptables -A ANTI_DDOS -p icmp --icmp-type echo-request -m limit --limit 2/s --limit-burst 4 -j RETURN
iptables -A ANTI_DDOS -p icmp --icmp-type echo-request -j DROP

# RTMP: whitelist srs-ingest (141.94.207.173) - sin límite de conexiones
iptables -A ANTI_DDOS -p tcp --dport 1935 -s 141.94.207.173 -j RETURN

# RTMP: whitelist srs-thumbnail (51.210.109.197)
iptables -A ANTI_DDOS -p tcp --dport 1935 -s 51.210.109.197 -j RETURN

# RTMP: máx 10 conexiones por IP para el resto (publishers externos)
iptables -A ANTI_DDOS -p tcp --dport 1935 -m connlimit --connlimit-above 10 -j DROP

# API SRS: solo localhost
iptables -A ANTI_DDOS -p tcp --dport 1985 ! -s 127.0.0.1 -j DROP

# SRS HTTP directo: abierto al exterior (consola SRS en puerto 8080)
# iptables -A ANTI_DDOS -p tcp --dport 8080 ! -s 127.0.0.1 -j DROP

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
echo "  - sysctl: SYN cookies, anti-spoofing, tuning de conexiones"
echo "  - iptables: SYN/ICMP flood, RTMP whitelist ingest+thumbnail, max 10 conn/IP resto"
echo "  - Puerto 1985 bloqueado desde exterior"
echo ""
echo "  Ver reglas:  iptables -L ANTI_DDOS -v -n"
echo "  Revertir:    bash anti-ddos.sh --revert"
