#!/bin/bash

# VPS DDoS Protection Script
# Version: 1.2.0
# https://github.com/wobujidao/vps-ddos-protection

# Пути к файлам
CONFIG_FILE="/etc/vps-protection/config"
LOG_FILE="/var/log/vps-protection.log"
ATTACK_LOG="/var/log/vps-attacks.json"
PID_FILE="/var/run/vps-protection-monitor.pid"

# Максимальный размер лога (10MB)
MAX_LOG_SIZE=10485760

# Проверка конфига
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config not found: $CONFIG_FILE"
    exit 1
fi

# Проверка прав доступа к конфигу
CONFIG_PERMS=$(stat -c %a "$CONFIG_FILE")
if [[ "$CONFIG_PERMS" != "600" ]]; then
    echo "WARNING: Config file permissions are not secure!"
    echo "Fixing permissions..."
    chmod 600 "$CONFIG_FILE"
fi

# Загружаем конфигурацию
source "$CONFIG_FILE"

# Функция проверки всех зависимостей
check_dependencies() {
    local missing_deps=()
    
    for cmd in ipset iptables ip6tables curl netstat; do
        if ! command -v $cmd &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # jq опциональный - только предупреждение
    if ! command -v jq &>/dev/null; then
        echo "[$(date)] WARNING: jq not installed - JSON parsing may be limited" >> "$LOG_FILE"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "[$(date)] ERROR: Missing required dependencies: ${missing_deps[*]}" >> "$LOG_FILE"
        echo "ERROR: Missing required dependencies: ${missing_deps[*]}"
        echo "Install with: apt-get install ${missing_deps[*]}"
        return 1
    fi
    
    echo "[$(date)] All required dependencies are installed" >> "$LOG_FILE"
    return 0
}

# Функция ротации логов
rotate_logs() {
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
        echo "[$(date)] Log rotated" >> "$LOG_FILE"
    fi
    
    if [[ -f "$ATTACK_LOG" ]] && [[ $(stat -c%s "$ATTACK_LOG") -gt $MAX_LOG_SIZE ]]; then
        mv "$ATTACK_LOG" "$ATTACK_LOG.old"
        touch "$ATTACK_LOG"
        chmod 644 "$ATTACK_LOG"
    fi
}

# Функция отправки в Telegram
send_telegram() {
    local message="$1"
    if [[ "$ENABLE_TELEGRAM" == "true" ]] && [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" \
            --connect-timeout 5 \
            --max-time 10 > /dev/null 2>&1
    fi
}

# Кэш для GeoIP запросов (в памяти)
declare -A GEO_CACHE
declare -A GEO_CACHE_TIME
GEO_CACHE_TTL=${GEO_CACHE_TTL:-3600}  # Кэш на 1 час по умолчанию
GEO_REQUEST_INTERVAL=${GEO_REQUEST_INTERVAL:-2}  # Минимум 2 секунды между запросами
LAST_GEO_REQUEST=0

# Функция получения информации об IP с кэшированием и rate limiting
get_ip_info() {
    local ip="$1"
    local current_time=$(date +%s)
    
    # Проверяем кэш
    if [[ -n "${GEO_CACHE[$ip]}" ]]; then
        local cache_age=$((current_time - GEO_CACHE_TIME[$ip]))
        if [[ $cache_age -lt $GEO_CACHE_TTL ]]; then
            echo "${GEO_CACHE[$ip]}"
            return 0
        fi
    fi
    
    # Rate limiting - не чаще раза в N секунд
    local time_since_last=$((current_time - LAST_GEO_REQUEST))
    if [[ $time_since_last -lt $GEO_REQUEST_INTERVAL ]]; then
        sleep $((GEO_REQUEST_INTERVAL - time_since_last))
    fi
    
    # Запрашиваем информацию
    local info=$(curl -s "http://ipinfo.io/${ip}/json" --connect-timeout 3 --max-time 5 2>/dev/null)
    LAST_GEO_REQUEST=$(date +%s)
    
    if [[ -z "$info" ]] || echo "$info" | grep -q "error"; then
        info='{"country":"Unknown","org":"Unknown"}'
    fi
    
    # Сохраняем в кэш
    GEO_CACHE[$ip]="$info"
    GEO_CACHE_TIME[$ip]=$current_time
    
    echo "$info"
}

# Функция создания белого списка
setup_whitelist() {
    # Создаём ipset для белого списка если не существует
    if ! ipset list whitelist4 &>/dev/null; then
        ipset create whitelist4 hash:ip family inet 2>/dev/null
    fi
    if ! ipset list whitelist6 &>/dev/null; then
        ipset create whitelist6 hash:ip family inet6 2>/dev/null
    fi
    
    # Добавляем IP из конфига
    if [[ -n "$WHITELIST_IPS" ]]; then
        for ip in $WHITELIST_IPS; do
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ipset add whitelist4 "$ip" 2>/dev/null
                echo "[$(date)] Added $ip to IPv4 whitelist" >> "$LOG_FILE"
            elif [[ "$ip" =~ ^[a-fA-F0-9:]+$ ]]; then
                ipset add whitelist6 "$ip" 2>/dev/null
                echo "[$(date)] Added $ip to IPv6 whitelist" >> "$LOG_FILE"
            fi
        done
    fi
}

# Функция проверки ipset
check_ipset() {
    if ! command -v ipset &>/dev/null; then
        echo "[$(date)] ERROR: ipset not installed!" >> "$LOG_FILE"
        return 1
    fi
    return 0
}

# Функция анализа атакующих
analyze_attackers() {
    local service="$1"
    local port="$2"
    
    local attackers=$(netstat -nu 2>/dev/null | grep ":${port}" | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5)
    local report="<b>🎯 Топ атакующих на ${service}:</b>%0A%0A"
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local count=$(echo "$line" | awk '{print $1}')
            local ip=$(echo "$line" | awk '{print $2}')
            
            if [[ "$ENABLE_GEO" == "true" ]]; then
                local geo_info=$(get_ip_info "$ip")
                local country=$(echo "$geo_info" | grep -oP '"country":\s*"\K[^"]+' || echo "Unknown")
                local org=$(echo "$geo_info" | grep -oP '"org":\s*"\K[^"]+' || echo "Unknown")
                
                report+="• <code>${ip}</code> (${country})%0A"
                report+="  🏢 ${org}%0A"
                report+="  📊 ${count} подключений%0A%0A"
            else
                report+="• <code>${ip}</code> - ${count} подключений%0A"
            fi
            
            # Логируем в JSON
            echo "{\"time\":\"$(date -Iseconds)\",\"service\":\"${service}\",\"ip\":\"${ip}\",\"count\":${count}}" >> "$ATTACK_LOG"
        fi
    done <<< "$attackers"
    
    echo -e "$report"
}

# Функция старта защиты
start_protection() {
    echo "[$(date)] Starting protection..." >> "$LOG_FILE"
    
    # Проверяем зависимости
    if ! check_dependencies; then
        echo "ERROR: Cannot start - missing dependencies"
        exit 1
    fi
    
    # Проверяем ipset
    if ! check_ipset; then
        echo "ERROR: ipset is required but not installed"
        exit 1
    fi
    
    # Ротация логов при старте
    rotate_logs
    
    # Ждём доступности сети (настраиваемо через конфиг)
    NETWORK_TIMEOUT=${NETWORK_TIMEOUT:-60}  # По умолчанию 60 секунд
    NETWORK_CHECK_INTERVAL=${NETWORK_CHECK_INTERVAL:-5}  # Проверка каждые 5 сек
    local network_attempts=0
    local max_attempts=$((NETWORK_TIMEOUT / NETWORK_CHECK_INTERVAL))
    
    while ! ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; do
        echo "[$(date)] Waiting for network... (attempt $((network_attempts + 1))/$max_attempts)" >> "$LOG_FILE"
        sleep $NETWORK_CHECK_INTERVAL
        network_attempts=$((network_attempts + 1))
        if [[ $network_attempts -ge $max_attempts ]]; then
            echo "[$(date)] Network timeout after ${NETWORK_TIMEOUT}s, continuing anyway..." >> "$LOG_FILE"
            break
        fi
    done
    
    if [[ $network_attempts -gt 0 ]]; then
        echo "[$(date)] Network is now available (took $((network_attempts * NETWORK_CHECK_INTERVAL))s)" >> "$LOG_FILE"
    fi
    
    # Создаём ipset для чёрных списков
    ipset create -exist blacklist4 hash:ip family inet timeout $BLOCK_TIME 2>/dev/null
    ipset create -exist blacklist6 hash:ip family inet6 timeout $BLOCK_TIME 2>/dev/null
    
    # Настраиваем белый список
    setup_whitelist
    
    # IPv4 правила для TeamSpeak
    # Сначала проверяем белый список
    iptables -I INPUT -p udp --dport 9987 -m set --match-set whitelist4 src -j ACCEPT 2>/dev/null
    # Затем чёрный список
    iptables -I INPUT -p udp --dport 9987 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    # Rate limiting
    iptables -I INPUT -p udp --dport 9987 -m recent --name ts3 --set 2>/dev/null
    iptables -I INPUT -p udp --dport 9987 -m recent --name ts3 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    
    # IPv4 правила для WireGuard
    iptables -I INPUT -p udp --dport 51820 -m set --match-set whitelist4 src -j ACCEPT 2>/dev/null
    iptables -I INPUT -p udp --dport 51820 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    iptables -I INPUT -p udp --dport 51820 -m recent --name wg --set 2>/dev/null
    iptables -I INPUT -p udp --dport 51820 -m recent --name wg --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    
    # IPv6 правила (аналогично)
    ip6tables -I INPUT -p udp --dport 9987 -m set --match-set whitelist6 src -j ACCEPT 2>/dev/null
    ip6tables -I INPUT -p udp --dport 9987 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    ip6tables -I INPUT -p udp --dport 9987 -m recent --name ts3v6 --set 2>/dev/null
    ip6tables -I INPUT -p udp --dport 9987 -m recent --name ts3v6 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    
    ip6tables -I INPUT -p udp --dport 51820 -m set --match-set whitelist6 src -j ACCEPT 2>/dev/null
    ip6tables -I INPUT -p udp --dport 51820 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    ip6tables -I INPUT -p udp --dport 51820 -m recent --name wgv6 --set 2>/dev/null
    ip6tables -I INPUT -p udp --dport 51820 -m recent --name wgv6 --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    
    echo "[$(date)] Protection rules applied" >> "$LOG_FILE"
    
    # Отправляем уведомление
    send_telegram "✅ <b>DDoS защита активирована</b>
🖥 Сервер: $SERVER_NAME
📊 TeamSpeak: $TS_RATE_LIMIT пакетов/сек
📊 WireGuard: $WG_RATE_LIMIT пакетов/сек
⏱ Автоблокировка: $((BLOCK_TIME/60)) минут
🕐 Время запуска: $(date '+%H:%M:%S')"
    
    # Запускаем монитор
    monitor_attacks &
    echo $! > $PID_FILE
    
    echo "[$(date)] Protection started successfully" >> "$LOG_FILE"
}

# Функция остановки защиты
stop_protection() {
    echo "[$(date)] Stopping protection..." >> "$LOG_FILE"
    
    if [ -f $PID_FILE ]; then
        kill $(cat $PID_FILE) 2>/dev/null
        rm $PID_FILE
    fi
    
    # Удаляем IPv4 правила для TeamSpeak
    iptables -D INPUT -p udp --dport 9987 -m recent --name ts3 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport 9987 -m recent --name ts3 --set 2>/dev/null
    iptables -D INPUT -p udp --dport 9987 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport 9987 -m set --match-set whitelist4 src -j ACCEPT 2>/dev/null
    
    # Удаляем IPv4 правила для WireGuard
    iptables -D INPUT -p udp --dport 51820 -m recent --name wg --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport 51820 -m recent --name wg --set 2>/dev/null
    iptables -D INPUT -p udp --dport 51820 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport 51820 -m set --match-set whitelist4 src -j ACCEPT 2>/dev/null
    
    # Удаляем IPv6 правила (аналогично)
    ip6tables -D INPUT -p udp --dport 9987 -m recent --name ts3v6 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    ip6tables -D INPUT -p udp --dport 9987 -m recent --name ts3v6 --set 2>/dev/null
    ip6tables -D INPUT -p udp --dport 9987 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    ip6tables -D INPUT -p udp --dport 9987 -m set --match-set whitelist6 src -j ACCEPT 2>/dev/null
    
    ip6tables -D INPUT -p udp --dport 51820 -m recent --name wgv6 --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    ip6tables -D INPUT -p udp --dport 51820 -m recent --name wgv6 --set 2>/dev/null
    ip6tables -D INPUT -p udp --dport 51820 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    ip6tables -D INPUT -p udp --dport 51820 -m set --match-set whitelist6 src -j ACCEPT 2>/dev/null
    
    # Удаляем ipset
    ipset destroy blacklist4 2>/dev/null
    ipset destroy blacklist6 2>/dev/null
    ipset destroy whitelist4 2>/dev/null
    ipset destroy whitelist6 2>/dev/null
    
    echo "[$(date)] Protection stopped" >> "$LOG_FILE"
    send_telegram "⚠️ DDoS защита отключена на $SERVER_NAME"
}

# Функция мониторинга
monitor_attacks() {
    local last_alert=0
    local log_rotate_check=0
    
    while true; do
        sleep 30
        
        # Проверяем существование ipset
        if ! ipset list blacklist4 &>/dev/null; then
            echo "[$(date)] ERROR: blacklist4 ipset not found!" >> "$LOG_FILE"
            continue
        fi
        
        # Ротация логов каждые 30 минут
        log_rotate_check=$((log_rotate_check + 1))
        if [[ $log_rotate_check -ge 60 ]]; then
            rotate_logs
            log_rotate_check=0
        fi
        
        # Подсчитываем заблокированные пакеты
        TS_BLOCKED=$(iptables -L INPUT -n -v 2>/dev/null | grep "dpt:9987.*DROP" | awk '{s+=$1} END {print s+0}')
        WG_BLOCKED=$(iptables -L INPUT -n -v 2>/dev/null | grep "dpt:51820.*DROP" | awk '{s+=$1} END {print s+0}')
        BLACKLISTED4=$(ipset list blacklist4 2>/dev/null | grep -c "timeout" || echo 0)
        BLACKLISTED6=$(ipset list blacklist6 2>/dev/null | grep -c "timeout" || echo 0)
        
        if [[ "$TS_BLOCKED" -gt "$ALERT_THRESHOLD" || "$WG_BLOCKED" -gt "$ALERT_THRESHOLD" ]]; then
            current_time=$(date +%s)
            
            if [[ $((current_time - last_alert)) -gt "$ALERT_COOLDOWN" ]]; then
                local main_target=""
                local details=""
                
                if [[ "$TS_BLOCKED" -gt "$WG_BLOCKED" ]]; then
                    main_target="TeamSpeak (UDP:9987)"
                    details=$(analyze_attackers "TeamSpeak" "9987")
                else
                    main_target="WireGuard (UDP:51820)"
                    details=$(analyze_attackers "WireGuard" "51820")
                fi
                
                local message="🚨 <b>DDoS атака обнаружена!</b>%0A%0A"
                message+="🖥 Сервер: <code>${SERVER_NAME}</code>%0A"
                message+="🎯 Основная цель: ${main_target}%0A%0A"
                message+="<b>📊 Статистика блокировок:</b>%0A"
                message+="• TeamSpeak: ${TS_BLOCKED} пакетов%0A"
                message+="• WireGuard: ${WG_BLOCKED} пакетов%0A"
                message+="• IPv4 в чёрном списке: ${BLACKLISTED4}%0A"
                message+="• IPv6 в чёрном списке: ${BLACKLISTED6}%0A%0A"
                message+="${details}"
                message+="⏰ Время: $(date '+%Y-%m-%d %H:%M:%S')"
                
                send_telegram "$message"
                
                echo "[$(date)] Attack detected! Target: $main_target, TS:$TS_BLOCKED WG:$WG_BLOCKED" >> "$LOG_FILE"
                last_alert=$current_time
            fi
        fi
    done
}

# Основной блок
case "$1" in
    start)
        start_protection
        ;;
    stop)
        stop_protection
        ;;
    restart)
        stop_protection
        sleep 1
        start_protection
        ;;
    status)
        if [ -f $PID_FILE ]; then
            echo "Protection running (PID: $(cat $PID_FILE))"
            echo "TeamSpeak limit: $TS_RATE_LIMIT packets/sec"
            echo "WireGuard limit: $WG_RATE_LIMIT packets/sec"
            echo "Whitelist IPs: ${WHITELIST_IPS:-none}"
        else
            echo "Protection not running"
        fi
        ;;
    whitelist-add)
        if [[ -n "$2" ]]; then
            ipset add whitelist4 "$2" 2>/dev/null && echo "Added $2 to whitelist"
        else
            echo "Usage: $0 whitelist-add IP_ADDRESS"
        fi
        ;;
    whitelist-remove)
        if [[ -n "$2" ]]; then
            ipset del whitelist4 "$2" 2>/dev/null && echo "Removed $2 from whitelist"
        else
            echo "Usage: $0 whitelist-remove IP_ADDRESS"
        fi
        ;;
    whitelist-list)
        echo "IPv4 Whitelist:"
        ipset list whitelist4 2>/dev/null | grep -E "^[0-9]"
        echo "IPv6 Whitelist:"
        ipset list whitelist6 2>/dev/null | grep -E "^[a-f0-9:]"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|whitelist-add|whitelist-remove|whitelist-list}"
        exit 1
        ;;
esac
