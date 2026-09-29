#!/system/bin/sh
# uninstall.sh - remove SMS UI (run on device via adb shell)
BB=busybox
INIT=/system/bin/initmifiservice.sh

# stop daemons
[ -f /data/smsui/api.pid ]  && kill "$(cat /data/smsui/api.pid)"  2>/dev/null
[ -f /data/smsui/smsd.pid ] && kill "$(cat /data/smsui/smsd.pid)" 2>/dev/null
[ -f /data/smsui/watch.pid ] && kill "$(cat /data/smsui/watch.pid)" 2>/dev/null
for p in $($BB ps | $BB grep -E 'watch\.sh|smsd\.sh|tg_fwd\.sh' | $BB grep -v grep | $BB awk '{print $1}'); do
    $BB kill $p 2>/dev/null
done
$BB killall httpd 2>/dev/null
$BB killall nc 2>/dev/null

# restore boot script
SELINUX=$(getenforce 2>/dev/null)
[ "$SELINUX" = "Enforcing" ] && setenforce 0 2>/dev/null
toolbox mount -o remount,rw /system 2>/dev/null || busybox mount -o rw,remount /system 2>/dev/null
if [ -f $INIT.orig ]; then
    $BB cp $INIT.orig $INIT
    $BB rm -f $INIT.orig
    echo "initmifiservice.sh restored"
else
    $BB sed -i '/# smsui/,+1d' $INIT 2>/dev/null
fi
toolbox mount -o remount,ro /system 2>/dev/null || busybox mount -o ro,remount /system 2>/dev/null
[ "$SELINUX" = "Enforcing" ] && setenforce 1 2>/dev/null

# remove injected web files (originals reappear at next boot anyway)
WEB=/data/data/com.mifiservice.hello/files/jetty2
$BB rm -f $WEB/sms.html $WEB/inbox.json $WEB/js/sms.js
$BB cp /data/smsui/main_orig.html $WEB/main.html 2>/dev/null

# remove app dir
$BB rm -rf /data/smsui
echo "smsui removed. reboot modem to fully restore stock web UI."
