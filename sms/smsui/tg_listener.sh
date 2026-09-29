#!/system/bin/sh
# tg_listener.sh - long-poll Telegram getUpdates and answer bot commands.
# Commands: /refresh - sync inbox + forward pending SMS now
#           /status  - quick system status
#           /help    - list commands
# One update per request (limit=1) = trivial parsing, fine for a personal bot.
BB=busybox
DIR=/data/smsui
. $DIR/smslib.sh

tg_load_conf || exit 0
echo "$$" > $DIR/tgl.pid
OFFSET=0

send_to_chat() {
    # send_to_chat <chat_id> <text>
    $TG_CURL -k -s -m 20 \
        --data-urlencode "chat_id=$1" \
        --data-urlencode "text=$2" \
        "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" > /dev/null 2>&1
}

while :; do
    RESP=$($TG_CURL -k -s -m 35 "https://api.telegram.org/bot$TG_BOT_TOKEN/getUpdates?timeout=30&limit=1&offset=$OFFSET" 2>/dev/null)

    case "$RESP" in
        *'"update_id"'*)
            scrape_fields "$RESP"
            case "$UPD_ID" in ''|*[!0-9]*) sleep 2; continue ;; esac
            case "$CHAT_ID" in ''|*[!0-9]*) OFFSET=$((UPD_ID + 1)); continue ;; esac
            OFFSET=$((UPD_ID + 1))

            # only respond to the configured owner chat
            [ "$CHAT_ID" = "$TG_CHAT_ID" ] || continue

            case "$TEXT" in
                /refresh*)
                    send_to_chat "$CHAT_ID" "🔄 Menyinkronkan..."
                    sync_inbox
                    if forward_pending; then
                        CNT=$($SQLITE "$SMSDB" "SELECT count(*) FROM sms WHERE type=1;" 2>/dev/null)
                        send_to_chat "$CHAT_ID" "✅ Selesai. Inbox berisi $CNT SMS. SMS baru sudah diteruskan di atas."
                    else
                        send_to_chat "$CHAT_ID" "✅ Sinkron selesai. Tidak ada SMS baru yang belum diteruskan."
                    fi
                    ;;
                /status*)
                    UP=$($BB cat /proc/uptime 2>/dev/null | $BB cut -d' ' -f1 | $BB cut -d. -f1)
                    CNT=$($SQLITE "$SMSDB" "SELECT count(*) FROM sms WHERE type=1;" 2>/dev/null)
                    LAST=$($BB cat $TGSTATE 2>/dev/null)
                    send_to_chat "$CHAT_ID" "📊 Status modem
• SMS di inbox: $CNT
• ID terakhir diteruskan: $LAST
• Modem uptime: $UP detik"
                    ;;
                /help*|/start*)
                    send_to_chat "$CHAT_ID" "📖 Perintah bot:
/refresh - sinkron & teruskan SMS baru sekarang
/status - status ringkas modem
/help - bantuan"
                    ;;
                *)
                    send_to_chat "$CHAT_ID" "Perintah tidak dikenal. Kirim /help untuk daftar perintah."
                    ;;
            esac
            ;;
    esac
done
