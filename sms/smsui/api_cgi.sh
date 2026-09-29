#!/system/bin/sh
# api_cgi.sh - CGI backend for the UZ801 SMS UI (served by busybox httpd on :8080)
# URL: http://192.168.100.1:8080/cgi-bin/api?action=refresh|delete|send
BB=busybox
DIR=/data/smsui
. $DIR/smslib.sh

json() {
    $BB printf 'Content-Type: application/json\r\n'
    $BB printf 'Access-Control-Allow-Origin: *\r\n'
    $BB printf 'Cache-Control: no-store\r\n\r\n'
    $BB printf '%s\n' "$1"
}

ACTION=""; ID=""; STORE=""; NUM=""; TEXT=""
IFS='&'
set -- $QUERY_STRING
unset IFS
for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    case "$k" in
        action) ACTION=$v ;;
        id)     ID=$v ;;
        store)  STORE=$v ;;
        num)    NUM=$(urldecode "$v") ;;
        text)   TEXT=$(urldecode "$v") ;;
    esac
done

case "$ACTION" in
    delete)
        case "$ID" in
            ''|*[!0-9]*) json '{"flag":"0","error_info":"bad id"}'; exit 0 ;;
        esac
        if [ "$STORE" = "db" -o -z "$STORE" ]; then
            $SQLITE "$SMSDB" "DELETE FROM sms WHERE _id=$ID;" 2>/dev/null
            sync_inbox
            json '{"flag":"1","error_info":"ok"}'
        else
            case "$STORE" in me) S=ME ;; *) S=SM ;; esac
            R=$(at_session "AT+CPMS=\"$S\"" "AT+CMGD=$ID")
            case "$R" in
                *OK*) sync_inbox; json '{"flag":"1","error_info":"ok"}' ;;
                *)    json '{"flag":"0","error_info":"modem error"}' ;;
            esac
        fi
        ;;
    refresh)
        if sync_inbox; then
            json '{"flag":"1","error_info":"ok"}'
        else
            json '{"flag":"0","error_info":"sync failed"}'
        fi
        ;;
    send)
        [ -z "$NUM" -o -z "$TEXT" ] && { json '{"flag":"0","error_info":"num/text required"}'; exit 0; }
        case "$TEXT" in
            *[!-~]*) json '{"flag":"0","error_info":"non-ascii not supported"}'; exit 0 ;;
        esac
        tlock at || { json '{"flag":"0","error_info":"AT busy, try again"}'; exit 0; }
        {
            $BB printf 'ATE0\r';          $BB sleep 1
            $BB printf 'AT+CMGF=1\r';     $BB sleep 1
            $BB printf 'AT+CMGS="%s"\r' "$NUM"; $BB sleep 2
            $BB printf '%s\032' "$TEXT"
            $BB sleep 8
        } > $DEV 2>/dev/null < $DEV
        tunlock at
        json '{"flag":"1","error_info":"send attempted"}'
        ;;
    *)
        json '{"flag":"0","error_info":"unknown action"}'
        ;;
esac
exit 0
