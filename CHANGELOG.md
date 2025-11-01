# Changelog

All notable changes to VPS DDoS Protection will be documented in this file.

## [1.2.0] - 2025-11-01

### Added
- Dependency checking on service startup (ipset, iptables, curl, netstat)
- GeoIP response caching with configurable TTL (default 1 hour)
- GeoIP rate limiting (minimum 2 seconds between requests)
- Configurable network timeout on startup (NETWORK_TIMEOUT, NETWORK_CHECK_INTERVAL)
- Native WireGuard support check in ddos-status (fallback to Docker if native not found)

### Security
- Enhanced dependency validation before starting protection
- Rate limiting for external API calls (ipinfo.io)
- Better error handling for missing dependencies

### Fixed
- Docker dependency in ddos-status.sh - now checks native WireGuard first
- Potential API rate limit issues during large attacks
- Improved startup reliability on slow networks

### Changed
- ddos-status.sh now supports both native and Docker WireGuard installations
- Better error messages for missing dependencies
- Improved logging for network availability checks

## [1.1.0] - 2025-11-01

### Added
- Whitelist functionality with management commands
- Automatic log rotation (10MB limit + logrotate integration)
- OS detection in installer (Ubuntu/Debian/CentOS)
- Configuration backup option on uninstall
- Network availability check before starting protection

### Security
- Secure placeholders in config.example
- Automatic chmod 600 for config file
- Config permissions validation on startup
- Root privilege checks in scripts

### Fixed
- Potential hang in IP geolocation (added 3s timeout)
- Handle missing ipset gracefully
- Improved network timeout handling (12 attempts with 5s delay)
- Better error handling in monitor loop

### Changed
- Improved installer with color output
- Enhanced status display formatting
- Better logging with timestamps

## [1.0.0] - 2025-10-XX

### Initial Release
- Basic DDoS protection for WireGuard (UDP:51820) and TeamSpeak (UDP:9987)
- Rate limiting per IP address
- Automatic blocking with configurable timeout
- IPv4/IPv6 dual stack support
- Telegram notifications with GeoIP information
- Real-time attack monitoring
- JSON logging for attack analysis
- Systemd service integration
- Status monitoring tool (ddos-status)
