#!/bin/bash

set -euo pipefail

LABEL="com.github.inkovsergei.vpnbypass.helper"
HELPER_PATH="/Library/PrivilegedHelperTools/$LABEL"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"

render_plist() {
    local CONFIG_PATH="$1"
    local OUTPUT_PATH="$2"

    plutil -create xml1 "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $HELPER_PATH" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string --domains-file" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string $CONFIG_PATH" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :StartInterval integer 300" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :WatchPaths array" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :WatchPaths:0 string $CONFIG_PATH" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :ProcessType string Background" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :StandardOutPath string /var/tmp/com.github.inkovsergei.vpnbypass.log" "$OUTPUT_PATH"
    /usr/libexec/PlistBuddy -c "Add :StandardErrorPath string /var/tmp/com.github.inkovsergei.vpnbypass.log" "$OUTPUT_PATH"
    plutil -lint "$OUTPUT_PATH" >/dev/null
}

case "${1:-}" in
    --install)
        SOURCE_HELPER="${2:-}"
        CONFIG_PATH="${3:-}"
        [ -f "$SOURCE_HELPER" ] || { echo "Runner не найден."; exit 2; }
        [ -f "$CONFIG_PATH" ] || { echo "Файл доменов не найден."; exit 2; }

        TMP_PLIST="$(mktemp /var/tmp/com.github.inkovsergei.vpnbypass.plist.XXXXXX)"
        trap 'rm -f "$TMP_PLIST"' EXIT
        render_plist "$CONFIG_PATH" "$TMP_PLIST"

        install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
        install -o root -g wheel -m 755 "$SOURCE_HELPER" "$HELPER_PATH"
        install -o root -g wheel -m 644 "$TMP_PLIST" "$PLIST_PATH"

        launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
        launchctl bootstrap system "$PLIST_PATH"
        launchctl kickstart -k "system/$LABEL"
        echo "✅ Автоматический helper установлен."
        ;;
    --uninstall)
        launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
        if [ -x "$HELPER_PATH" ]; then
            "$HELPER_PATH" --remove >/dev/null 2>&1 || true
        fi
        rm -f "$HELPER_PATH" "$PLIST_PATH"
        rm -f /var/tmp/com.github.inkovsergei.vpnbypass.routes
        rm -f /var/tmp/com.github.inkovsergei.vpnbypass.status
        rm -f /var/tmp/com.github.inkovsergei.vpnbypass.log
        echo "✅ Автоматический helper удалён."
        ;;
    --render-plist)
        render_plist "${2:?Нужен путь конфигурации}" "${3:?Нужен выходной путь}"
        ;;
    *)
        echo "Использование: $0 --install RUNNER CONFIG | --uninstall | --render-plist CONFIG OUTPUT"
        exit 2
        ;;
esac
