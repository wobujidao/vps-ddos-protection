#!/bin/bash

# VPS DDoS Protection - Uninstaller Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║     VPS DDoS Protection - Uninstall Script           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

read -p "Are you sure you want to uninstall VPS DDoS Protection? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled"
    exit 1
fi

# Stop and disable service
echo "Stopping service..."
systemctl stop vps-protection 2>/dev/null || true
systemctl disable vps-protection 2>/dev/null || true

# Remove files
echo "Removing files..."
rm -f /usr/local/bin/vps-protection.sh
rm -f /usr/local/bin/ddos-status
rm -f /etc/systemd/system/vps-protection.service
systemctl daemon-reload

# Clean iptables rules
echo "Cleaning firewall rules..."
/usr/local/bin/vps-protection.sh stop 2>/dev/null || true

# Remove ipsets
ipset destroy blacklist4 2>/dev/null || true
ipset destroy blacklist6 2>/dev/null || true

# Ask about config and logs
read -p "Remove configuration and logs? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /etc/vps-protection
    rm -f /var/log/vps-protection.log
    rm -f /var/log/vps-attacks.json
fi

echo -e "${GREEN}✓${NC} VPS DDoS Protection uninstalled successfully"
