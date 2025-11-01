#!/bin/bash

# Пути к файлам
CONFIG_FILE="/etc/vps-protection/config"
LOG_FILE="/var/log/vps-protection.log"
ATTACK_LOG="/var/log/vps-attacks.json"
PID_FILE="/var/run/vps-protection-monitor.pid"

# Проверка конфига
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config not found: $CONFIG_FILE"
    exit 1
fi

# Загружаем конфигурацию
source "$CONFIG_FILE"

# Функция отправки в Telegram
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null 2>&1
}

# Функция получения информации об IP
get_ip_info() {
    local ip="$1"
    local info=$(curl -s "http://ipinfo.io/${ip}/json" 2>/dev/null)
    echo "$info"
}

# Функция анализа атакующих
analyze_attackers() {
    local service="$1"
    local port="$2"
    
    local attackers=$(netstat -nu | grep ":${port}" | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5)
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
    echo "[$(date)] Starting protection..." >> $LOG_FILE
    
    # Ждём доступности сети
    local network_attempts=0
    while ! ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; do
        echo "[$(date)] Waiting for network..." >> $LOG_FILE
        sleep 5
        network_attempts=$((network_attempts + 1))
        if [[ $network_attempts -gt 12 ]]; then  # Максимум ждём 60 секунд
            echo "[$(date)] Network timeout, continuing anyway..." >> $LOG_FILE
            break
        fi
    done
    
    # Проверяем доступность Telegram API
    local telegram_attempts=0
    while ! curl -s --connect-timeout 5 "https://api.telegram.org" > /dev/null 2>&1; do
        echo "[$(date)] Waiting for Telegram API..." >> $LOG_FILE
        sleep 5
        telegram_attempts=$((telegram_attempts + 1))
        if [[ $telegram_attempts -gt 6 ]]; then  # Максимум ждём 30 секунд
            echo "[$(date)] Telegram API timeout, continuing without notifications..." >> $LOG_FILE
            break
        fi
    done
    
    # Создаём ipset
    ipset create -exist blacklist4 hash:ip family inet timeout $BLOCK_TIME 2>/dev/null
    ipset create -exist blacklist6 hash:ip family inet6 timeout $BLOCK_TIME 2>/dev/null
    
    # IPv4 правила для TeamSpeak
    iptables -I INPUT -p udp --dport 9987 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    iptables -I INPUT -p udp --dport 9987 -m recent --name ts3 --set 2>/dev/null
    iptables -I INPUT -p udp --dport 9987 -m recent --name ts3 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    
    # IPv4 правила для WireGuard
    iptables -I INPUT -p udp --dport 51820 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    iptables -I INPUT -p udp --dport 51820 -m recent --name wg --set 2>/dev/null
    iptables -I INPUT -p udp --dport 51820 -m recent --name wg --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    
    # IPv6 правила
    ip6tables -I INPUT -p udp --dport 9987 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    ip6tables -I INPUT -p udp --dport 9987 -m recent --name ts3v6 --set 2>/dev/null
    ip6tables -I INPUT -p udp --dport 9987 -m recent --name ts3v6 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    
    ip6tables -I INPUT -p udp --dport 51820 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    ip6tables -I INPUT -p udp --dport 51820 -m recent --name wgv6 --set 2>/dev/null
    ip6tables -I INPUT -p udp --dport 51820 -m recent --name wgv6 --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    
    echo "[$(date)] Protection rules applied" >> $LOG_FILE
    
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
    
    echo "[$(date)] Protection started successfully" >> $LOG_FILE
}

# Функция остановки защиты
stop_protection() {
    echo "[$(date)] Stopping protection..." >> $LOG_FILE
    
    if [ -f $PID_FILE ]; then
        kill $(cat $PID_FILE) 2>/dev/null
        rm $PID_FILE
    fi
    
    # Удаляем IPv4 правила
    iptables -D INPUT -p udp --dport 9987 -m recent --name ts3 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport 9987 -m recent --name ts3 --set 2>/dev/null
    iptables -D INPUT -p udp --dport 9987 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    
    iptables -D INPUT -p udp --dport 51820 -m recent --name wg --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport 51820 -m recent --name wg --set 2>/dev/null
    iptables -D INPUT -p udp --dport 51820 -m set --match-set blacklist4 src -j DROP 2>/dev/null
    
    # Удаляем IPv6 правила
    ip6tables -D INPUT -p udp --dport 9987 -m recent --name ts3v6 --update --seconds 1 --hitcount $TS_RATE_LIMIT -j DROP 2>/dev/null
    ip6tables -D INPUT -p udp --dport 9987 -m recent --name ts3v6 --set 2>/dev/null
    ip6tables -D INPUT -p udp --dport 9987 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    
    ip6tables -D INPUT -p udp --dport 51820 -m recent --name wgv6 --update --seconds 1 --hitcount $WG_RATE_LIMIT -j DROP 2>/dev/null
    ip6tables -D INPUT -p udp --dport 51820 -m recent --name wgv6 --set 2>/dev/null
    ip6tables -D INPUT -p udp --dport 51820 -m set --match-set blacklist6 src -j DROP 2>/dev/null
    
    ipset destroy blacklist4 2>/dev/null
    ipset destroy blacklist6 2>/dev/null
    
    echo "[$(date)] Protection stopped" >> $LOG_FILE
    send_telegram "⚠️ DDoS защита отключена на $SERVER_NAME"
}

# Функция мониторинга
monitor_attacks() {
    local last_alert=0
    
    while true; do
        sleep 30
        
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
                
                echo "[$(date)] Attack detected! Target: $main_target, TS:$TS_BLOCKED WG:$WG_BLOCKED" >> $LOG_FILE
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
        else
            echo "Protection not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
