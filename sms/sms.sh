#!/system/bin/sh
# sms.sh - SMS reader for UZ801 (stock Android firmware) via AT channel /dev/smd11
# Runs ON the modem. Usage (from PC): adb shell sh /data/local/tmp/sms.sh <command> [args]
#
# Commands:
#   info              modem/SIM/network info + SMS storage status
#   list [sm|me]      list all SMS (default storage: sm = SIM)
#   read <idx> [sm|me]  read one SMS by index
#   del <idx> [sm|me]   delete one SMS by index
#   raw <AT;AT;...>   send raw AT command(s), semicolon separated
#
# Requires: busybox (present on stock UZ801 firmware)

DEV=/dev/smd11
BB=busybox

send() { $BB printf '%s\r' "$1" >&3; }

drain() {
    # read whatever the modem sent, with a timeout in seconds
    $BB timeout "$1" cat <&3 2>/dev/null
}

# run "<seq-name>" : open channel, send init + command sequence, print response
run() {
    exec 3<>$DEV 2>/dev/null || { echo "ERROR: cannot open $DEV (is the modem fully booted?)"; exit 1; }
    send 'ATE0'      # echo off, keep output clean
    sleep 1
    while [ $# -gt 0 ]; do
        case "$1" in
            @cmgf) send 'AT+CMGF=1'; sleep 1 ;;                # SMS text mode
            @ira)  send 'AT+CSCS="IRA"'; sleep 1 ;;            # ASCII charset
            @sm)   send 'AT+CPMS="SM"'; sleep 1 ;;             # storage = SIM
            @me)   send 'AT+CPMS="ME"'; sleep 1 ;;             # storage = modem
            *)     send "$1"; sleep 2 ;;
        esac
        shift
    done
    drain 6
    exec 3<&- 3>&-
}

CMD="$1"
shift 2>/dev/null

case "$CMD" in
    info)
        run 'ATI' 'AT+CPMS?' 'AT+CMGF?' 'AT+CSCS?' 'AT+CNMI?' 'AT+CSQ' 'AT+COPS?'
        ;;
    list)
        ST="${1:-sm}"
        if [ "$ST" = "me" ]; then
            run '@cmgf' '@ira' '@me' 'AT+CMGL="ALL"'
        else
            run '@cmgf' '@ira' '@sm' 'AT+CMGL="ALL"'
        fi
        ;;
    read)
        IDX="$1"; ST="${2:-sm}"
        [ -z "$IDX" ] && { echo "usage: read <idx> [sm|me]"; exit 1; }
        if [ "$ST" = "me" ]; then
            run '@cmgf' '@ira' '@me' "AT+CMGR=$IDX"
        else
            run '@cmgf' '@ira' '@sm' "AT+CMGR=$IDX"
        fi
        ;;
    del)
        IDX="$1"; ST="${2:-sm}"
        [ -z "$IDX" ] && { echo "usage: del <idx> [sm|me]"; exit 1; }
        if [ "$ST" = "me" ]; then
            run '@cmgf' '@me' "AT+CMGD=$IDX"
        else
            run '@cmgf' '@sm' "AT+CMGD=$IDX"
        fi
        ;;
    raw)
        [ -z "$1" ] && { echo "usage: raw \"AT+...;AT+...\""; exit 1; }
        IFS=';'
        set -- $1
        unset IFS
        run "$@"
        ;;
    *)
        echo "usage: sh $0 {info|list [sm|me]|read <idx> [sm|me]|del <idx> [sm|me]|raw <cmds>}"
        exit 1
        ;;
esac
