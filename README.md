# 🛡️ VPS DDoS Protection

Comprehensive DDoS protection system for VPS servers with automatic attack mitigation, real-time monitoring, and Telegram notifications.

[🇷🇺 Русская версия](README_RU.md)

## ⚡ Quick Install
```bash
git clone https://github.com/wobujidao/vps-ddos-protection.git
cd vps-ddos-protection
sudo ./install.sh
```

## 🚀 Features

- Automatic IP blocking for rate limit violations
- Real-time attack monitoring
- Telegram notifications with attacker details
- GeoIP information
- IPv4 & IPv6 support
- Systemd service with auto-start

## 📊 Usage

Check protection status:
```bash
ddos-status
```

## 📱 Telegram Setup

1. Create bot via [@BotFather](https://t.me/botfather)
2. Get your chat ID
3. Edit `/etc/vps-protection/config`

## 📄 License

MIT License - see [LICENSE](LICENSE)

---
Made with ❤️ for VPS community