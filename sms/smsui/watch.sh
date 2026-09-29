#!/system/bin/sh
# watch.sh - self-healing watchdog for the UZ801 SMS UI.
# The MifiService app re-extracts its jetty2 webroot (overwriting main.html) at every
# boot, possibly AFTER boot.sh ran. This loop re-applies everything every 10s.
BB=busybox
DIR=/data/smsui
. $DIR/smslib.sh

echo "$$" > $H/watch.pid

while :; do
    if [ -d $WEB ] && [ -f $WEB/main.html ]; then
        # static UI files (vanish when the app re-extracts the webroot)
        $BB cmp -s $DIR/sms.html $WEB/sms.html || { $BB cp $DIR/sms.html $WEB/; $BB chmod 644 $WEB/sms.html; }
        $BB cmp -s $DIR/sms.js $WEB/js/sms.js || { $BB cp $DIR/sms.js $WEB/js/sms.js; $BB chmod 644 $WEB/js/sms.js; }
        if [ -f $MASTER ]; then
            $BB cmp -s $MASTER $LIVE || { $BB cp $MASTER $LIVE; $BB chmod 644 $LIVE; }
        fi
        # menu patch in main.html
        if ! $BB grep -q 'sms.html' $WEB/main.html; then
            $BB sed '/<span id="body6">/i\<li><a href="./sms.html" target="mainifr" lang="SMS">SMS</a></li>' \
                $DIR/main_orig.html > $WEB/main.html
            $BB chmod 644 $WEB/main.html
        fi
    fi

    # CGI API server on :8080 (always ensure fresh script + exec bit)
    $BB mkdir -p /data/smsui/www/cgi-bin
    $BB cp $DIR/api_cgi.sh /data/smsui/www/cgi-bin/api
    $BB chmod 755 /data/smsui/www/cgi-bin/api
    if ! $BB ps | $BB grep 'httpd -p 8080' | $BB grep -v grep >/dev/null 2>&1; then
        $BB setsid $BB httpd -p 8080 -h /data/smsui/www >/dev/null 2>&1 </dev/null &
    fi

    # SMS poll daemon
    if ! $BB ps | $BB grep 'smsd\.sh 5' | $BB grep -v grep >/dev/null 2>&1; then
        $BB rm -f $H/smsd.pid
        $BB setsid sh $DIR/smsd.sh 5 >/dev/null 2>&1 </dev/null &
    fi

    # Telegram forwarder + command listener (only if configured)
    if [ -f $DIR/tg.conf ]; then
        if ! $BB ps | $BB grep 'tg_fwd\.sh' | $BB grep -v grep >/dev/null 2>&1; then
            $BB rm -f $DIR/tg.pid
            $BB setsid sh $DIR/tg_fwd.sh >/dev/null 2>&1 </dev/null &
        fi
        if ! $BB ps | $BB grep 'tg_listener\.sh' | $BB grep -v grep >/dev/null 2>&1; then
            $BB rm -f $DIR/tgl.pid
            $BB setsid sh $DIR/tg_listener.sh >/dev/null 2>&1 </dev/null &
        fi
    fi

    $BB sleep 10
done
