#!/bin/bash

set -u

STATE_FILE="/var/tmp/vpn-bypass-${SUDO_UID:-$(id -u)}.routes"
DOMAINS_FILE=""

usage() {
    echo "Использование: $0 --domains-file FILE | --remove | --check FILE"
}

find_normal_gateway() {
    netstat -rn -f inet 2>/dev/null |
        awk '$1 == "default" && $NF !~ /^utun/ { print $2; exit }'
}

remove_old_routes() {
    if [ -f "$STATE_FILE" ]; then
        echo "Удаляю старые bypass-маршруты..."
        while IFS= read -r IP; do
            [ -z "$IP" ] && continue
            route -n delete -host "$IP" >/dev/null 2>&1 || true
        done < "$STATE_FILE"
        rm -f "$STATE_FILE"
    fi
}

resolve_domain() {
    local DOMAIN="$1"
    dig +short A "$DOMAIN" 2>/dev/null |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
        sort -u
}

validate_domains_file() {
    local FILE="$1"
    [ -f "$FILE" ] || { echo "❌ Файл доменов не найден."; exit 2; }
    [ -r "$FILE" ] || { echo "❌ Файл доменов нельзя прочитать."; exit 2; }
    if grep -Ev '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$|^[[:space:]]*$' "$FILE" >/dev/null 2>&1; then
        echo "❌ В файле есть некорректный домен."
        exit 2
    fi
}

if [ "${1:-}" = "--remove" ]; then
    remove_old_routes
    echo "✅ Bypass-маршруты удалены."
    exit 0
elif [ "${1:-}" = "--domains-file" ] && [ -n "${2:-}" ]; then
    DOMAINS_FILE="$2"
elif [ "${1:-}" = "--check" ] && [ -n "${2:-}" ]; then
    validate_domains_file "$2"
    GATEWAY="$(find_normal_gateway)"
    [ -n "$GATEWAY" ] || { echo "❌ Обычный интернет-gateway не найден."; exit 1; }
    echo "✅ Проверка пройдена. Gateway: $GATEWAY"
    exit 0
else
    usage
    exit 2
fi

validate_domains_file "$DOMAINS_FILE"

GATEWAY="$(find_normal_gateway)"
if [ -z "${GATEWAY:-}" ]; then
    echo "❌ Не удалось определить обычный интернет-gateway."
    echo "Текущая таблица маршрутов:"
    netstat -rn -f inet
    exit 1
fi

echo "VPN BYPASS"
echo "Обычный gateway: $GATEWAY"
echo

remove_old_routes
umask 077
: > "$STATE_FILE"

COUNT=0
FAILED=0
while IFS= read -r DOMAIN || [ -n "$DOMAIN" ]; do
    DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | xargs)"
    [ -z "$DOMAIN" ] && continue

    IPS="$(resolve_domain "$DOMAIN")"
    if [ -z "$IPS" ]; then
        echo "⚠️  $DOMAIN — IPv4 не найден"
        FAILED=$((FAILED + 1))
        continue
    fi

    while IFS= read -r IP; do
        [ -z "$IP" ] && continue
        if grep -qx "$IP" "$STATE_FILE" 2>/dev/null; then
            continue
        fi

        route -n delete -host "$IP" >/dev/null 2>&1 || true
        if route -n add -host "$IP" "$GATEWAY" >/dev/null 2>&1; then
            printf "✅ %-30s %s → %s\n" "$DOMAIN" "$IP" "$GATEWAY"
            echo "$IP" >> "$STATE_FILE"
            COUNT=$((COUNT + 1))
        else
            echo "⚠️  Не удалось добавить $IP ($DOMAIN)"
            FAILED=$((FAILED + 1))
        fi
    done <<< "$IPS"
done < "$DOMAINS_FILE"

echo
echo "Готово. Добавлено маршрутов: $COUNT. Предупреждений: $FAILED."
echo "Gateway: $GATEWAY"

if [ "$COUNT" -eq 0 ]; then
    echo "❌ Не удалось добавить ни одного маршрута."
    exit 1
fi
