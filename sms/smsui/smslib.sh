#!/system/bin/sh
# smslib.sh - shared functions for UZ801 SMS UI (sourced by smsd.sh, api_cgi.sh, watch.sh)
BB=busybox
H=/data/smsui
WEB=/data/data/com.mifiservice.hello/files/jetty2
DEV=/dev/smd11
LOCK=$H/at.lock
MASTER=$H/inbox.json
LIVE=$WEB/inbox.json
SMSDB=/data/data/com.android.providers.telephony/databases/mmssms.db
SQLITE=/system/xbin/sqlite3

# ---- locking (busybox flock is BROKEN on this firmware; use atomic mkdir locks) ----
# tlock <name> : acquire exclusive lock; returns 1 if held by a live process
tlock() {
    L=$H/$1.lockd
    if [ -d "$L" ]; then
        LP=$($BB cat $L/pid 2>/dev/null)
        case "$LP" in
            ''|*[!0-9]*) $BB rm -rf "$L" ;;
            *) kill -0 "$LP" 2>/dev/null || $BB rm -rf "$L" ;;
        esac
    fi
    $BB mkdir "$L" 2>/dev/null || return 1
    echo $$ > $L/pid
    return 0
}

# tunlock <name> : release lock
tunlock() {
    $BB rm -rf "$H/$1.lockd" 2>/dev/null
}

# at_session "<cmd1>" "<cmd2>" ... : open AT channel, init, send commands, drain output
# (used by the send action; the inbox comes from the Android telephony database,
#  because the RIL framework consumes all incoming SMS - CNMI 0,0,0,0,0)
at_session() {
    tlock at || return 1
    exec 3<>$DEV 2>/dev/null || { tunlock at; return 1; }
    $BB printf 'ATE0\r' >&3
    $BB sleep 1
    $BB printf 'AT+CMGF=1\r' >&3
    $BB sleep 1
    $BB printf 'AT+CSCS="IRA"\r' >&3
    $BB sleep 1
    for c in "$@"; do
        $BB printf '%s\r' "$c" >&3
        $BB sleep 2
    done
    $BB timeout 6 cat <&3 2>/dev/null
    exec 3<&- 3>&-
    tunlock at
    return 0
}

# sync_inbox : rebuild inbox.json from mmssms.db (received SMS, newest first, max 60)
# NOTE: this firmware's sqlite3 lacks char(), so the body is pulled as hex() and
# decoded in awk. datetime() exists and formats the timestamp device-locally.
sync_inbox() {
    [ -f "$SMSDB" ] || return 1
    OUT=$($SQLITE "$SMSDB" "SELECT _id||'|'||ifnull(address,'')||'|'||datetime(ifnull(date,0)/1000,'unixepoch','localtime')||'|'||ifnull(read,1)||'|'||hex(ifnull(body,'')) FROM sms WHERE type=1 ORDER BY date DESC LIMIT 60;" 2>/dev/null) || return 1
    NOW=$($BB date '+%Y-%m-%d %H:%M:%S')
    $BB printf '%s' "$OUT" | $BB awk -v now="$NOW" '
        BEGIN{ for(i=0;i<256;i++){ tbl[sprintf("%02X",i)]=sprintf("%c",i) } delete tbl["00"] }
        function hexdec(s,  r,i){ r=""; for(i=1;i<=length(s);i+=2){ r=r tbl[substr(s,i,2)] } return r }
        function esc(s){ gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); gsub(/\r/,"",s); gsub(/\n/,"\\n",s); return s }
        {
            nf=split($0,f,"|")
            id=f[1]; from=f[2]; dt=f[3]; rd=f[4]
            hx=""
            for(j=5;j<=nf;j++){ if(j>5){ hx=hx "|" } hx=hx f[j] }
            txt=esc(hexdec(hx))
            n++
            e[n]=sprintf("{\"id\":%s,\"store\":\"db\",\"read\":%s,\"from\":\"%s\",\"date\":\"%s\",\"text\":\"%s\"}", id, rd+0, esc(from), dt, txt)
        }
        END{
            printf("{\"updated\":\"%s\",\"src\":\"mmssms.db\",\"count\":%d,\"sms\":[", now, n)
            for(i=1;i<=n;i++){ printf("%s%s", (i>1)?",":"", e[i]) }
            printf("]}\n")
        }
    ' > $MASTER.new.$$ 2>/dev/null
    $BB grep -q '"sms"' $MASTER.new.$$ 2>/dev/null || { $BB rm -f $MASTER.new.$$; return 1; }
    $BB cmp -s $MASTER.new.$$ $MASTER || {
        $BB cp $MASTER.new.$$ $MASTER
        $BB cp $MASTER.new.$$ $LIVE
        $BB chmod 644 $MASTER $LIVE
    }
    $BB rm -f $MASTER.new.$$
    return 0
}

# ---- Telegram helpers (shared by tg_fwd.sh and tg_listener.sh) ----
TGCONF=$H/tg.conf
TGSTATE=$H/tg.state
TG_OFF=$H/tg.off
TG_CURL=/system/bin/curl

# tg_load_conf : sets TG_BOT_TOKEN and TG_CHAT_ID; returns 1 if not configured
tg_load_conf() {
    [ -f "$TGCONF" ] || return 1
    . "$TGCONF"
    [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]
}

# tg_send "<text>" : send message to TG_CHAT_ID; returns 0 if Telegram accepted
tg_send() {
    $TG_CURL -k -s -m 20 \
        --data-urlencode "chat_id=$TG_CHAT_ID" \
        --data-urlencode "text=$1" \
        "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" > $H/.tg_out 2>/dev/null
    case "$($BB cat $H/.tg_out 2>/dev/null)" in
        *'"ok":true'*) return 0 ;;
        *) return 1 ;;
    esac
}

# scrape_fields "<json>" : set UPD_ID / CHAT_ID / TEXT from a Telegram update.
# Uses grep -o (multi-line safe; sed is line-based and unusable on pretty JSON).
scrape_fields() {
    UPD_ID=$($BB printf '%s' "$1" | $BB grep -o '"update_id":[0-9]*' | $BB head -1 | $BB tr -dc '0-9')
    CHAT_ID=$($BB printf '%s' "$1" | $BB grep -o '"chat":{"id":[0-9]*' | $BB head -1 | $BB tr -dc '0-9')
    TEXT=$($BB printf '%s' "$1" | $BB grep -o '"text":"[^"]*"' | $BB head -1 | $BB sed 's/^"text":"//;s/"$//')
}

# hexdec "<hex>" : decode hex string to raw text (no strtonum in this firmware)
hexdec() {
    $BB printf '%s' "$1" | $BB awk '
        BEGIN{ for(i=0;i<256;i++){ tbl[sprintf("%02X",i)]=sprintf("%c",i) } delete tbl["00"] }
        { r=""; for(i=1;i<=length($0);i+=2){ r=r tbl[substr($0,i,2)] } printf("%s",r) }
    '
}

# forward_pending : forward all not-yet-forwarded SMS (type=1) to Telegram.
# Updates TGSTATE per sent row. Returns 0 if at least one row was forwarded.
forward_pending() {
    [ -f "$SMSDB" ] || return 1
    LAST=$($BB cat $TGSTATE 2>/dev/null)
    case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
    MAX=$($SQLITE "$SMSDB" "SELECT ifnull(max(_id),0) FROM sms;" 2>/dev/null)
    case "$MAX" in ''|*[!0-9]*) return 1 ;; esac
    [ "$MAX" -gt "$LAST" ] || return 1
    ROWS=$($SQLITE "$SMSDB" "SELECT _id||'|'||ifnull(address,'')||'|'||datetime(ifnull(date,0)/1000,'unixepoch','localtime')||'|'||hex(ifnull(body,'')) FROM sms WHERE _id > $LAST AND type=1 ORDER BY _id ASC LIMIT 20;" 2>/dev/null) || return 1
    # one forwarder at a time (poller and /refresh may race) - flock is broken here
    tlock tg || return 1
    # NOTE: trailing newline is required - sqlite output has none and `while read`
    # would silently skip the last (often only) row
    $BB printf '%s\n' "$ROWS" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        ID=$($BB printf '%s' "$line" | $BB cut -d '|' -f 1)
        FROM=$($BB printf '%s' "$line" | $BB cut -d '|' -f 2)
        DT=$($BB printf '%s' "$line" | $BB cut -d '|' -f 3)
        HX=$($BB printf '%s' "$line" | $BB cut -d '|' -f 4-)
        [ -z "$ID" -o -z "$HX" ] && continue
        BODY=$(hexdec "$HX")
        if tg_send "📩 SMS baru

Dari: $FROM
Waktu: $DT

$BODY"; then
            echo "$ID" > $TGSTATE
        else
            break
        fi
    done
    tunlock tg
    NEW=$($BB cat $TGSTATE 2>/dev/null)
    case "$NEW" in ''|*[!0-9]*) return 1 ;; esac
    [ "$NEW" -gt "$LAST" ]
}

# http_json "<code>" "<body>" : emit minimal JSON HTTP response on stdout
http_json() {
    $BB printf 'HTTP/1.0 %s\r\n' "$1"
    $BB printf 'Content-Type: application/json\r\n'
    $BB printf 'Access-Control-Allow-Origin: *\r\n'
    $BB printf 'Cache-Control: no-store\r\n\r\n'
    $BB printf '%s\n' "$2"
}

# urldecode <string> : percent-decode via awk (lookup table; no strtonum in this firmware)
urldecode() {
    $BB printf '%s' "$1" | $BB awk '
        BEGIN{ for(i=0;i<256;i++){ tbl[sprintf("%02X",i)]=sprintf("%c",i) } delete tbl["00"] }
        function dec(s,  out,k,pair){
            gsub(/\+/," ",s); out=""; k=1
            while(k<=length(s)){
                if(substr(s,k,1)=="%" && k+2<=length(s)){
                    pair=toupper(substr(s,k+1,2))
                    if(pair in tbl){ out=out tbl[pair]; k+=3; continue }
                }
                out=out substr(s,k,1); k++
            }
            return out
        }
        { print dec($0) }
    '
}
