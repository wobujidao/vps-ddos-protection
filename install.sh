#!/bin/bash

# VPS DDoS Protection - Installer Script
# Version: 1.1.0
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
echo "║     Version: 1.1.0                                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Check OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    print_error "Cannot detect OS version"
    exit 1
fi

print_info "Detected OS: $OS $VER"

# Install dependencies
print_info "Installing dependencies..."
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update -qq
    apt-get install -y ipset iptables ip6tables curl jq net-tools > /dev/null 2>&1
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]]; then
    yum install -y ipset iptables ip6tables curl jq net-tools > /dev/null 2>&1
else
    print_error "Unsupported OS: $OS"
    exit 1
fi
print_success "Dependencies installed"

# Check for required commands
for cmd in ipset iptables ip6tables curl; do
    if ! command -v $cmd &> /dev/null; then
        print_error "Required command not found: $cmd"
        exit 1
    fi
done
print_success "All required commands available"

# Create directories
print_info "Creating directories..."
mkdir -p /etc/vps-protection
mkdir -p /var/log
print_success "Directories created"

# Copy files
print_info "Installing protection scripts..."
if [[ ! -f src/vps-protection.sh ]]; then
    print_error "Source file not found: src/vps-protection.sh"
    exit 1
fi
if [[ ! -f src/ddos-status.sh ]]; then
    print_error "Source file not found: src/ddos-status.sh"
    exit 1
fi

cp src/vps-protection.sh /usr/local/bin/
cp src/ddos-status.sh /usr/local/bin/ddos-status
chmod +x /usr/local/bin/vps-protection.sh
chmod +x /usr/local/bin/ddos-status
print_success "Scripts installed"

# Install config with security checks
if [ ! -f /etc/vps-protection/config ]; then
    print_info "Installing configuration..."
    cp config/config.example /etc/vps-protection/config
    
    # Set secure permissions
    chmod 600 /etc/vps-protection/config
    chown root:root /etc/vps-protection/config
    
    print_success "Configuration installed with secure permissions (600)"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║             ⚠️  IMPORTANT CONFIGURATION ⚠️             ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    print_info "Please configure your settings:"
    echo "  1. Edit configuration file:"
    echo "     ${GREEN}nano /etc/vps-protection/config${NC}"
    echo ""
    echo "  2. Required settings:"
    echo "     • TELEGRAM_BOT_TOKEN - Get from @BotFather"
    echo "     • TELEGRAM_CHAT_ID - Your chat or group ID"
    echo ""
    echo "  3. Optional settings:"
    echo "     • WHITELIST_IPS - Add trusted IP addresses"
    echo "     • SERVER_NAME - Your server identifier"
    echo ""
else
    print_info "Configuration already exists, checking permissions..."
    
    # Check and fix permissions
    CONFIG_PERMS=$(stat -c %a /etc/vps-protection/config)
    if [[ "$CONFIG_PERMS" != "600" ]]; then
        print_info "Fixing configuration permissions ($CONFIG_PERMS -> 600)..."
        chmod 600 /etc/vps-protection/config
        chown root:root /etc/vps-protection/config
        print_success "Permissions fixed"
    else
        print_success "Configuration permissions OK (600)"
    fi
fi

# Install systemd service
print_info "Installing systemd service..."
if [[ ! -f config/vps-protection.service ]]; then
    print_error "Service file not found: config/vps-protection.service"
    exit 1
fi
cp config/vps-protection.service /etc/systemd/system/
systemctl daemon-reload
print_success "Systemd service installed"

# Install logrotate configuration
if [[ -d /etc/logrotate.d ]]; then
    print_info "Installing logrotate configuration..."
    cat > /etc/logrotate.d/vps-protection << 'EOF'
/var/log/vps-protection.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl reload vps-protection >/dev/null 2>&1 || true
    endscript
}

/var/log/vps-attacks.json {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    print_success "Logrotate configuration installed"
fi

# Create log files with proper permissions
touch /var/log/vps-protection.log
touch /var/log/vps-attacks.json
chmod 644 /var/log/vps-protection.log
chmod 644 /var/log/vps-attacks.json
chown root:root /var/log/vps-protection.log
chown root:root /var/log/vps-attacks.json
print_success "Log files created"

# Enable service
print_info "Enabling service..."
systemctl enable vps-protection.service
print_success "Service enabled for autostart"

# Check if we should start the service
echo ""
read -p "Do you want to start the protection now? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check if config has been edited
    if grep -q "YOUR_BOT_TOKEN_HERE" /etc/vps-protection/config; then
        print_info "⚠️  Warning: Telegram is not configured yet"
        print_info "Starting without Telegram notifications..."
    fi
    
    systemctl start vps-protection
    print_success "Protection service started"
    
    echo ""
    print_info "Checking service status..."
    sleep 2
    if systemctl is-active --quiet vps-protection; then
        print_success "Service is running"
    else
        print_error "Service failed to start. Check: journalctl -xe"
    fi
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           Installation Complete!                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Configure settings (if not done):"
echo "   ${GREEN}nano /etc/vps-protection/config${NC}"
echo ""
echo "2. Manage the service:"
echo "   ${GREEN}systemctl start vps-protection${NC}   - Start protection"
echo "   ${GREEN}systemctl stop vps-protection${NC}    - Stop protection"
echo "   ${GREEN}systemctl restart vps-protection${NC} - Restart protection"
echo "   ${GREEN}systemctl status vps-protection${NC}  - Check status"
echo ""
echo "3. Monitor protection:"
echo "   ${GREEN}ddos-status${NC}                      - View current status"
echo "   ${GREEN}tail -f /var/log/vps-protection.log${NC} - View logs"
echo ""
echo "4. Manage whitelist:"
echo "   ${GREEN}/usr/local/bin/vps-protection.sh whitelist-add IP${NC}"
echo "   ${GREEN}/usr/local/bin/vps-protection.sh whitelist-list${NC}"
echo ""
print_success "VPS DDoS Protection v1.1.0 installed successfully!"
echo ""
echo "⭐ Star us on GitHub: https://github.com/wobujidao/vps-ddos-protection"
echo ""
