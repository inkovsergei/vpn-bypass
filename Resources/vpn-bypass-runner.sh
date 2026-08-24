#!/bin/bash

set -u

STATE_FILE="/var/tmp/com.github.inkovsergei.vpnbypass.routes"
STATUS_FILE="/var/tmp/com.github.inkovsergei.vpnbypass.status"
LOCK_DIR="/var/tmp/com.github.inkovsergei.vpnbypass.lock"
DOMAINS_FILE=""
DESIRED_FILE=""
NEXT_STATE_FILE=""

usage() {
    echo "Использование: $0 --domains-file FILE | --remove | --check FILE"
}

find_normal_gateway() {
    netstat -rn -f inet 2>/dev/null |
        awk '$1 == "default" && $NF !~ /^utun/ { print $2; exit }'
}

remove_old_routes() {
    echo "Удаляю bypass-маршруты..."
    for ROUTES_FILE in "$STATE_FILE" /var/tmp/vpn-bypass-0.routes /tmp/vpn-bypass-ru.routes; do
        [ -f "$ROUTES_FILE" ] || continue
        while IFS= read -r IP; do
            [ -z "$IP" ] && continue
            route -n delete -host "$IP" >/dev/null 2>&1 || true
        done < "$ROUTES_FILE"
        rm -f "$ROUTES_FILE"
    done
}

migrate_legacy_state() {
    for LEGACY_FILE in /var/tmp/vpn-bypass-0.routes /tmp/vpn-bypass-ru.routes; do
        [ -f "$LEGACY_FILE" ] || continue
        cat "$LEGACY_FILE" >> "$STATE_FILE"
        rm -f "$LEGACY_FILE"
    done
    if [ -f "$STATE_FILE" ]; then
        sort -u "$STATE_FILE" -o "$STATE_FILE"
        chmod 600 "$STATE_FILE"
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
    while IFS= read -r DOMAIN || [ -n "$DOMAIN" ]; do
        DOMAIN="$(printf '%s' "$DOMAIN" | tr -d '\r' | xargs)"
        [ -z "$DOMAIN" ] && continue
        [ "${#DOMAIN}" -le 253 ] || { echo "❌ Слишком длинный домен."; exit 2; }
        case "$DOMAIN" in
            *..*|.*|*.) echo "❌ Некорректный домен: $DOMAIN"; exit 2 ;;
        esac
        OLD_IFS="$IFS"
        IFS='.'
        for LABEL in $DOMAIN; do
            [ "${#LABEL}" -le 63 ] || { echo "❌ Слишком длинная часть домена: $DOMAIN"; exit 2; }
            case "$LABEL" in
                -*) echo "❌ Некорректный домен: $DOMAIN"; exit 2 ;;
                *-) echo "❌ Некорректный домен: $DOMAIN"; exit 2 ;;
            esac
        done
        IFS="$OLD_IFS"
    done < "$FILE"
}

cleanup() {
    [ -n "$DESIRED_FILE" ] && rm -f "$DESIRED_FILE"
    [ -n "$NEXT_STATE_FILE" ] && rm -f "$NEXT_STATE_FILE"
    rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}

write_status() {
    local MESSAGE="$1"
    umask 022
    printf '%s\n%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MESSAGE" > "$STATUS_FILE"
}

if [ "${1:-}" = "--remove" ]; then
    remove_old_routes
    write_status "Маршруты удалены"
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

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "ℹ️  Другое обновление маршрутов уже выполняется."
    exit 0
fi
trap cleanup EXIT INT TERM
migrate_legacy_state

GATEWAY="$(find_normal_gateway)"
if [ -z "${GATEWAY:-}" ]; then
    write_status "Обычный интернет-gateway не найден"
    echo "❌ Не удалось определить обычный интернет-gateway."
    exit 1
fi

DESIRED_FILE="$(mktemp /var/tmp/com.github.inkovsergei.vpnbypass.desired.XXXXXX)"
NEXT_STATE_FILE="$(mktemp /var/tmp/com.github.inkovsergei.vpnbypass.next.XXXXXX)"
umask 077
: > "$DESIRED_FILE"
: > "$NEXT_STATE_FILE"

RESOLVE_FAILED=0
while IFS= read -r DOMAIN || [ -n "$DOMAIN" ]; do
    DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | xargs)"
    [ -z "$DOMAIN" ] && continue
    IPS="$(resolve_domain "$DOMAIN")"
    if [ -z "$IPS" ]; then
        echo "⚠️  $DOMAIN — IPv4 не найден"
        RESOLVE_FAILED=$((RESOLVE_FAILED + 1))
        continue
    fi
    while IFS= read -r IP; do
        [ -n "$IP" ] && printf '%s %s\n' "$IP" "$DOMAIN" >> "$DESIRED_FILE"
    done <<< "$IPS"
done < "$DOMAINS_FILE"

sort -u -k1,1 "$DESIRED_FILE" -o "$DESIRED_FILE"

REMOVED=0
if [ -f "$STATE_FILE" ]; then
    while IFS= read -r OLD_IP; do
        [ -z "$OLD_IP" ] && continue
        if ! awk -v ip="$OLD_IP" '$1 == ip { found=1 } END { exit !found }' "$DESIRED_FILE"; then
            route -n delete -host "$OLD_IP" >/dev/null 2>&1 || true
            REMOVED=$((REMOVED + 1))
        fi
    done < "$STATE_FILE"
fi

ADDED=0
KEPT=0
FAILED=0
while read -r IP DOMAIN; do
    [ -z "$IP" ] && continue
    CURRENT_GATEWAY="$(route -n get "$IP" 2>/dev/null | awk '/gateway:/{print $2; exit}')"
    if [ "$CURRENT_GATEWAY" = "$GATEWAY" ]; then
        echo "$IP" >> "$NEXT_STATE_FILE"
        KEPT=$((KEPT + 1))
        continue
    fi

    route -n delete -host "$IP" >/dev/null 2>&1 || true
    if route -n add -host "$IP" "$GATEWAY" >/dev/null 2>&1; then
        printf "✅ %-30s %s → %s\n" "$DOMAIN" "$IP" "$GATEWAY"
        echo "$IP" >> "$NEXT_STATE_FILE"
        ADDED=$((ADDED + 1))
    else
        echo "⚠️  Не удалось добавить $IP ($DOMAIN)"
        FAILED=$((FAILED + 1))
    fi
done < "$DESIRED_FILE"

sort -u "$NEXT_STATE_FILE" -o "$NEXT_STATE_FILE"
cp "$NEXT_STATE_FILE" "$STATE_FILE"
chmod 600 "$STATE_FILE"

TOTAL=$((ADDED + KEPT))
SUMMARY="Маршрутов: $TOTAL; добавлено: $ADDED; сохранено: $KEPT; удалено: $REMOVED; предупреждений: $((FAILED + RESOLVE_FAILED)); gateway: $GATEWAY"
write_status "$SUMMARY"
echo "$SUMMARY"

if [ "$TOTAL" -eq 0 ]; then
    echo "❌ Не удалось подготовить ни одного маршрута."
    exit 1
fi
