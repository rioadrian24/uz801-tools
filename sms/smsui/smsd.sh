#!/system/bin/sh
# smsd.sh - SMS poll daemon for UZ801 stock web UI
# Source: Android telephony database (framework consumes all incoming SMS).
# Publishes inbox.json to the Jetty webroot every POLL seconds.
BB=busybox
DIR=/data/smsui
. $DIR/smslib.sh

POLL=${1:-5}
echo "$$" > $H/smsd.pid

while :; do
    sync_inbox
    $BB sleep $POLL
done
