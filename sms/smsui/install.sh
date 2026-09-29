#!/system/bin/sh
# install.sh - install SMS UI into UZ801 stock firmware (run on device via adb shell)
BB=busybox
SRC=/data/local/tmp/smsui
DIR=/data/smsui

echo "[1/5] copy files to $DIR"
$BB mkdir -p $DIR
$BB cp $SRC/smslib.sh $SRC/smsd.sh $SRC/api_cgi.sh $SRC/watch.sh $SRC/boot.sh $SRC/tg_fwd.sh $DIR/
$BB cp $SRC/sms.html $SRC/sms.js $SRC/main_orig.html $DIR/
[ -f $SRC/tg.conf ] && $BB cp $SRC/tg.conf $DIR/
$BB chmod 755 $DIR/*.sh
$BB chmod 644 $DIR/sms.html $DIR/sms.js $DIR/main_orig.html

echo "[2/5] backup initmifiservice.sh"
INIT=/system/bin/initmifiservice.sh
SELINUX=$(getenforce 2>/dev/null)
[ "$SELINUX" = "Enforcing" ] && setenforce 0 2>/dev/null
toolbox mount -o remount,rw /system 2>/dev/null || busybox mount -o rw,remount /system 2>/dev/null
if [ ! -f $INIT.orig ]; then
    $BB cp $INIT $INIT.orig && echo "  backup saved: $INIT.orig"
else
    echo "  backup exists: $INIT.orig"
fi

echo "[3/5] patch initmifiservice.sh (idempotent)"
if ! $BB grep -q 'smsui' $INIT; then
    $BB printf '\n# smsui: SMS inbox web UI (added by uz801-tools)\nsh /data/smsui/boot.sh &\n' >> $INIT
    echo "  patched"
else
    echo "  already patched"
fi
toolbox mount -o remount,ro /system 2>/dev/null || busybox mount -o ro,remount /system 2>/dev/null
[ "$SELINUX" = "Enforcing" ] && setenforce 1 2>/dev/null

echo "[4/5] prepare main.html base (menu patch source)"
if [ ! -s $DIR/main_orig.html ]; then
    $BB cat /data/data/com.mifiservice.hello/files/jetty2/main.html > $DIR/main_orig.html 2>/dev/null
fi

echo "[5/5] activate now"
sh $DIR/boot.sh

echo "done. open http://192.168.100.1/sms.html (or main page -> menu SMS)"
