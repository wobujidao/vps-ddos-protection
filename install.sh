#!/bin/bash

# VPS DDoS Protection - Installer Script
# https://github.com/wobujidao/vps-ddos-protection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║     VPS DDoS Protection - Installation Script        ║"
echo "║     https://github.com/wobujidao/vps-ddos-protection ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Install dependencies
print_info "Installing dependencies..."
apt-get update -qq
apt-get install -y ipset iptables ip6tables curl jq netstat-nat > /dev/null 2>&1
print_success "Dependencies installed"

# Create directories
print_info "Creating directories..."
mkdir -p /etc/vps-protection
mkdir -p /var/log
print_success "Directories created"

# Copy files
print_info "Installing protection scripts..."
cp src/vps-protection.sh /usr/local/bin/
cp src/ddos-status.sh /usr/local/bin/ddos-status
chmod +x /usr/local/bin/vps-protection.sh
chmod +x /usr/local/bin/ddos-status
print_success "Scripts installed"

# Install config
if [ ! -f /etc/vps-protection/config ]; then
    print_info "Installing configuration..."
    cp config/config.example /etc/vps-protection/config
    chmod 600 /etc/vps-protection/config
    print_success "Configuration installed"
    
    echo ""
    print_info "Please configure Telegram settings:"
    echo "  Edit: /etc/vps-protection/config"
    echo "  Add your TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID"
    echo ""
else
    print_info "Configuration already exists, skipping..."
fi

# Install systemd service
print_info "Installing systemd service..."
cp config/vps-protection.service /etc/systemd/system/
systemctl daemon-reload
print_success "Systemd service installed"

# Create log files
touch /var/log/vps-protection.log
touch /var/log/vps-attacks.json
chmod 644 /var/log/vps-protection.log
chmod 644 /var/log/vps-attacks.json
print_success "Log files created"

# Enable and start service
print_info "Enabling service..."
systemctl enable vps-protection.service
print_success "Service enabled"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           Installation Complete!                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "1. Configure Telegram (optional):"
echo "   nano /etc/vps-protection/config"
echo ""
echo "2. Start the protection:"
echo "   systemctl start vps-protection"
echo ""
echo "3. Check status:"
echo "   ddos-status"
echo ""
print_success "VPS DDoS Protection installed successfully!"
