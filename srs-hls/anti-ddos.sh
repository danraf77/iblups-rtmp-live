#!/bin/bash
# =============================================================
# Anti-DDoS hardening para VPS SRS-HLS (OVH)
# Ejecutar como root en el VPS: bash anti-ddos.sh
# =============================================================

set -e

echo "=== [1/3] Aplicando sysctl hardening ==="

cat > /etc/sysctl.d/99-anti-ddos.conf << 'EOF'
# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2

# Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP hardening
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Connection tuning
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 4096

# Increase connection tracking
net.netfilter.nf_conntrack_max = 262144
EOF

sysctl --system
echo "  sysctl aplicado OK"

echo ""
echo "=== [2/3] Configurando iptables ==="

# Flush reglas anteriores de la cadena ANTI_DDOS si existe
iptables -D INPUT -j ANTI_DDOS 2>/dev/null || true
iptables -F ANTI_DDOS 2>/dev/null || true
iptables -X ANTI_DDOS 2>/dev/null || true

# Crear cadena dedicada
iptables -N ANTI_DDOS

# Bloquear paquetes inválidos
iptables -A ANTI_DDOS -m state --state INVALID -j DROP

# Protección SYN flood
iptables -A ANTI_DDOS -p tcp --syn -m limit --limit 100/s --limit-burst 200 -j RETURN
iptables -A ANTI_DDOS -p tcp --syn -j DROP

# ICMP flood protection (permitir 2/seg)
iptables -A ANTI_DDOS -p icmp --icmp-type echo-request -m limit --limit 2/s --limit-burst 4 -j RETURN
iptables -A ANTI_DDOS -p icmp --icmp-type echo-request -j DROP

# Limitar conexiones por IP en puertos HLS (80, 443)
iptables -A ANTI_DDOS -p tcp --dport 80 -m connlimit --connlimit-above 60 --connlimit-mask 32 -j DROP
iptables -A ANTI_DDOS -p tcp --dport 443 -m connlimit --connlimit-above 60 --connlimit-mask 32 -j DROP

# Proteger RTMP: solo permitir pocas conexiones (publishers)
iptables -A ANTI_DDOS -p tcp --dport 1935 -m connlimit --connlimit-above 5 --connlimit-mask 32 -j DROP

# Proteger API SRS: solo localhost
iptables -A ANTI_DDOS -p tcp --dport 1985 ! -s 127.0.0.1 -j DROP

# Proteger puerto SRS HTTP directo: solo localhost (Nginx hace de proxy)
iptables -A ANTI_DDOS -p tcp --dport 8080 ! -s 127.0.0.1 -j DROP

# Insertar cadena en INPUT
iptables -I INPUT -j ANTI_DDOS

echo "  iptables aplicado OK"

echo ""
echo "=== [3/3] Persistiendo reglas iptables ==="

# Instalar iptables-persistent si no existe
if ! dpkg -l | grep -q iptables-persistent; then
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get update && apt-get install -y iptables-persistent
fi

iptables-save > /etc/iptables/rules.v4
echo "  Reglas persistidas OK"

echo ""
echo "=== RESUMEN ==="
echo "  - sysctl: SYN cookies, connection tuning, spoofing protection"
echo "  - iptables: SYN flood, ICMP flood, connlimit en 80/443/1935"
echo "  - Puerto 1985 (API) y 8080 (SRS HTTP): bloqueados desde exterior"
echo "  - Reglas persistidas en /etc/iptables/rules.v4"
echo ""
echo "Para ver reglas activas:  iptables -L ANTI_DDOS -v -n"
echo "Para deshacer todo:       iptables -D INPUT -j ANTI_DDOS && iptables -F ANTI_DDOS && iptables -X ANTI_DDOS"
