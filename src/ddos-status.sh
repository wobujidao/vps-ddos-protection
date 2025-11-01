#!/bin/bash
clear
echo "╔══════════════════════════════════════════════════════╗"
echo "║          DDoS Protection Status Monitor              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "🛡️  Service: $(systemctl is-active vps-protection)"
echo "⏱️  Uptime: $(ps -o etime= -p $(cat /var/run/vps-protection-monitor.pid 2>/dev/null) 2>/dev/null || echo 'N/A')"
echo ""
echo "📊 Blocked Packets:"
WG_BLOCKED=$(sudo iptables -L INPUT -n -v -x 2>/dev/null | grep "DROP.*51820" | head -1 | awk '{print $1}')
TS_BLOCKED=$(sudo iptables -L INPUT -n -v -x 2>/dev/null | grep "DROP.*9987" | head -1 | awk '{print $1}')
printf "   WireGuard: %'d packets\n" ${WG_BLOCKED:-0} 2>/dev/null || echo "   WireGuard: ${WG_BLOCKED:-0} packets"
printf "   TeamSpeak: %'d packets\n" ${TS_BLOCKED:-0} 2>/dev/null || echo "   TeamSpeak: ${TS_BLOCKED:-0} packets"
echo ""
echo "🚫 Blacklisted:"
echo "   IPv4: $(sudo ipset list blacklist4 2>/dev/null | grep -c timeout || echo 0) IPs"
echo "   IPv6: $(sudo ipset list blacklist6 2>/dev/null | grep -c timeout || echo 0) IPs"
echo ""
echo "👥 Active Connections:"

# Проверяем WireGuard - сначала нативный, потом Docker
if command -v wg &>/dev/null && sudo wg show wg0 &>/dev/null; then
    # Нативная установка WireGuard
    WG_CLIENTS=$(sudo wg show wg0 | grep "latest handshake" | wc -l)
    echo "   WireGuard: $WG_CLIENTS clients (native)"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "wg-easy"; then
    # Docker установка
    WG_CLIENTS=$(docker exec wg-easy wg show 2>/dev/null | grep "latest handshake" | wc -l || echo "0")
    echo "   WireGuard: $WG_CLIENTS clients (docker)"
else
    echo "   WireGuard: Not detected"
fi

# Проверяем TeamSpeak
if ps aux | grep -q "[t]s3server"; then
    echo "   TeamSpeak: Server running"
else
    echo "   TeamSpeak: Server not running"
fi

echo ""
echo "⚙️  Protection Settings:"
source /etc/vps-protection/config 2>/dev/null
echo "   WireGuard: ${WG_RATE_LIMIT:-200} packets/sec"
echo "   TeamSpeak: ${TS_RATE_LIMIT:-50} packets/sec"
echo "   Alert threshold: ${ALERT_THRESHOLD:-100} packets"
echo "   Block duration: $((BLOCK_TIME/60)) minutes"
echo ""
echo "═══════════════════════════════════════════════════════"
