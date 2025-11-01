# 🛡️ VPS DDoS Protection

<div align="center">

![GitHub release](https://img.shields.io/github/v/release/wobujidao/vps-ddos-protection)
![GitHub stars](https://img.shields.io/github/stars/wobujidao/vps-ddos-protection?style=social)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-E95420?logo=ubuntu)
![Debian](https://img.shields.io/badge/Debian-11%2B-A81D33?logo=debian)
![Shell Script](https://img.shields.io/badge/Shell_Script-Bash-4EAA25?logo=gnu-bash)

**Comprehensive DDoS protection system for VPS servers with automatic attack mitigation, real-time monitoring, and instant Telegram notifications**

[🇷🇺 Русская версия](README_RU.md) | [📖 Documentation](docs/) | [🐛 Report Bug](https://github.com/wobujidao/vps-ddos-protection/issues)

</div>

## 🎯 Why VPS DDoS Protection?

Modern VPS servers face constant threats from DDoS attacks, especially on UDP services like VPN and game servers. This solution provides enterprise-grade protection without expensive hardware.

### 🔥 Key Problems It Solves

- **UDP Flood Attacks** - Automatically detects and blocks flood attacks
- **Resource Exhaustion** - Prevents server overload from massive packet floods  
- **Zero-Day Protection** - Works immediately without learning period
- **False Positives** - Smart rate limiting that doesn't block legitimate users

## ✨ Features

<table>
<tr>
<td width="50%">

### 🚀 Core Protection
- ⚡ **Rate Limiting** per IP address
- 🔒 **Auto-blocking** with timeout
- 🌐 **Dual Stack** IPv4/IPv6 support
- 📝 **JSON Logging** for analysis
- 🔄 **Auto-recovery** after attacks

</td>
<td width="50%">

### 📊 Monitoring & Alerts
- 📱 **Telegram Notifications**
- 🌍 **GeoIP Information**
- 📈 **Real-time Statistics**
- 🎯 **Attack Pattern Analysis**
- ⏰ **Instant Alerts**

</td>
</tr>
</table>

## 📸 Screenshots

<details>
<summary>📊 View Status Monitor</summary>

```
╔══════════════════════════════════════════════════════╗
║          DDoS Protection Status Monitor              ║
╚══════════════════════════════════════════════════════╝
🛡️  Service: active
⏱️  Uptime: 14:29
📊 Blocked Packets:
   WireGuard: 15,161 packets
   TeamSpeak: 0 packets
🚫 Blacklisted:
   IPv4: 1 IPs
   IPv6: 1 IPs
👥 Active Connections:
   WireGuard: 10 clients
   TeamSpeak: 1 server running
⚙️  Protection Settings:
   WireGuard: 200 packets/sec
   TeamSpeak: 50 packets/sec
```

</details>

<details>
<summary>📱 Telegram Notifications</summary>

- ✅ Service startup confirmations
- 🚨 Attack alerts with attacker details
- 📊 GeoIP location of attackers
- 📈 Real-time statistics

</details>

## ⚡ Quick Start

### Prerequisites

- Ubuntu 20.04+ / Debian 11+
- Root or sudo access
- 512MB+ RAM

### One-Line Installation

```bash
curl -sSL https://raw.githubusercontent.com/wobujidao/vps-ddos-protection/main/install.sh | sudo bash
```

### Standard Installation

```bash
# 1. Clone repository
git clone https://github.com/wobujidao/vps-ddos-protection.git
cd vps-ddos-protection

# 2. Run installer
sudo ./install.sh

# 3. Configure (optional)
sudo nano /etc/vps-protection/config

# 4. Start protection
sudo systemctl start vps-protection

# 5. Check status
ddos-status
```

## 📱 Telegram Setup

<details>
<summary>Click to expand detailed Telegram setup</summary>

### 1. Create Bot
1. Open [@BotFather](https://t.me/botfather)
2. Send `/newbot`
3. Choose name and username
4. Save the token

### 2. Get Chat ID
1. Send message to your bot
2. Open: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Find `"chat":{"id":NUMBER}`

### 3. Configure
```bash
sudo nano /etc/vps-protection/config

# Add your credentials:
TELEGRAM_BOT_TOKEN="your_token"
TELEGRAM_CHAT_ID="your_chat_id"
```

</details>

## 🎮 Usage

### Service Management

```bash
# Control service
sudo systemctl {start|stop|restart|status} vps-protection

# View protection status
ddos-status

# Monitor attacks in real-time
watch -n 1 ddos-status

# Check logs
tail -f /var/log/vps-protection.log
```

### Emergency Commands

```bash
# View blacklist
sudo ipset list blacklist4

# Unblock specific IP
sudo ipset del blacklist4 192.168.1.100

# Clear all blocks
sudo ipset flush blacklist4
```

## ⚙️ Configuration

Edit `/etc/vps-protection/config`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TS_RATE_LIMIT` | 50 | TeamSpeak packets/sec limit |
| `WG_RATE_LIMIT` | 200 | WireGuard packets/sec limit |
| `BLOCK_TIME` | 1800 | Block duration in seconds |
| `ALERT_THRESHOLD` | 100 | Alert after N blocked packets |
| `TELEGRAM_BOT_TOKEN` | "" | Your Telegram bot token |
| `TELEGRAM_CHAT_ID` | "" | Your Telegram chat ID |
| `ENABLE_GEO` | true | Enable GeoIP lookups |

## 🔌 Protected Services

Pre-configured protection for:

| Service | Port | Protocol | Default Limit |
|---------|------|----------|---------------|
| WireGuard VPN | 51820 | UDP | 200 pkt/s |
| TeamSpeak 3 | 9987 | UDP | 50 pkt/s |
| Custom | Any | UDP/TCP | Configurable |

## 📊 How It Works

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Packet    │────▶│ Rate Limiter │────▶│   ACCEPT    │
└─────────────┘     └──────────────┘     └─────────────┘
                            │                     
                            ▼                     
                    ┌──────────────┐     ┌─────────────┐
                    │  Over Limit  │────▶│    DROP     │
                    └──────────────┘     └─────────────┘
                            │                     
                            ▼                     
                    ┌──────────────┐     ┌─────────────┐
                    │   Blacklist  │────▶│   Telegram  │
                    └──────────────┘     └─────────────┘
```

## 🛠️ Advanced Usage

<details>
<summary>Adding Custom Service Protection</summary>

Edit `/usr/local/bin/vps-protection.sh` and add:

```bash
# Custom service on port 8080
iptables -I INPUT -p tcp --dport 8080 -m recent --name custom --set
iptables -I INPUT -p tcp --dport 8080 -m recent --name custom \
    --update --seconds 1 --hitcount 100 -j DROP
```

</details>

<details>
<summary>Whitelist Management</summary>

```bash
# Create whitelist
sudo ipset create whitelist hash:ip

# Add trusted IP
sudo ipset add whitelist 192.168.1.100

# Save whitelist
sudo ipset save whitelist > /etc/whitelist.save

# Restore on boot
sudo ipset restore < /etc/whitelist.save
```

</details>

## 🚀 Performance Impact

- **CPU Usage**: < 1% under normal conditions
- **Memory**: ~10MB for service + ipset tables
- **Latency**: < 1ms added to packet processing
- **Scalability**: Tested with 1000+ concurrent connections

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 Roadmap

- [ ] Web dashboard for monitoring
- [ ] Multiple service profiles
- [ ] Machine learning for attack patterns
- [ ] Integration with Cloudflare API
- [ ] Docker container version
- [ ] Grafana dashboard integration
- [ ] Email notifications support
- [ ] REST API for management

## 🐛 Troubleshooting

<details>
<summary>Service won't start?</summary>

```bash
# Check logs
sudo journalctl -xe | grep vps-protection

# Verify dependencies
which ipset iptables ip6tables

# Check config syntax
bash -n /usr/local/bin/vps-protection.sh
```

</details>

<details>
<summary>Not receiving Telegram alerts?</summary>

```bash
# Test Telegram connection
source /etc/vps-protection/config
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"

# Check network connectivity
ping -c 1 api.telegram.org
```

</details>

<details>
<summary>High CPU usage?</summary>

- Check if you're under active attack
- Increase rate limits if too strict
- Check for duplicate rules: `iptables -L INPUT -n`

</details>

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Thanks to the open-source community
- Inspired by real-world DDoS attacks on personal VPS servers
- Built for self-hosting enthusiasts

## 📮 Support & Contact

- **Issues**: [GitHub Issues](https://github.com/wobujidao/vps-ddos-protection/issues)
- **Discussions**: [GitHub Discussions](https://github.com/wobujidao/vps-ddos-protection/discussions)
- **Wiki**: [GitHub Wiki](https://github.com/wobujidao/vps-ddos-protection/wiki)

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=wobujidao/vps-ddos-protection&type=Date)](https://star-history.com/#wobujidao/vps-ddos-protection&Date)

## 📈 Statistics

![GitHub commit activity](https://img.shields.io/github/commit-activity/m/wobujidao/vps-ddos-protection)
![GitHub last commit](https://img.shields.io/github/last-commit/wobujidao/vps-ddos-protection)
![GitHub code size](https://img.shields.io/github/languages/code-size/wobujidao/vps-ddos-protection)

---

<div align="center">

**If this project helps protect your server, please consider giving it a ⭐!**

Made with ❤️ for the VPS community

*Protecting servers, one packet at a time* 🛡️

</div>
