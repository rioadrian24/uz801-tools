#!/system/bin/sh
# boot.sh - entry point called from initmifiservice.sh: just start the watchdog detached.
BB=busybox
DIR=/data/smsui

# single watchdog instance
for p in $($BB ps | $BB grep 'watch\.sh' | $BB grep -v grep | $BB awk '{print $1}'); do
    $BB kill $p 2>/dev/null
done

$BB setsid sh $DIR/watch.sh >/dev/null 2>&1 </dev/null &
echo "smsui boot done"
