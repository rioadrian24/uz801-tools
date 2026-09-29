#!/system/bin/sh
# tg_fwd.sh - forwards new incoming SMS (mmssms.db) to Telegram. Watchdog keeps me alive.
BB=busybox
DIR=/data/smsui
. $DIR/smslib.sh

tg_load_conf || exit 0
echo "$$" > $DIR/tg.pid

while :; do
    forward_pending
    $BB sleep 5
done
