# UZ801 SMS Toolkit 📱🇮🇩

Add full SMS features to the **UZ801 V3.2** 4G modem (Qualcomm MSM8916)
**without reflashing the firmware** — an SMS inbox appears in the modem's stock web
admin, you can delete/send SMS, auto-forward incoming messages to **Telegram**, and
control everything with a `/refresh` bot command.

> Developed and tested on stock Android firmware `v2.3.11` (AT firmware
> `UZ801_V3.0_21_V01R01B10`), board `FY_UZ801_3.2`, carrier Tri (Indonesia).
> The approach should also work on other stock Android 2.3.x builds and similar
> dongles (UFI001B/C, UF896) — please report your results in the
> [Issues](https://github.com/rioadrian24/uz801-tools/issues) page!

## Features

| Feature | Details |
|---|---|
| 🖥️ **Web inbox** | New **SMS** menu in the modem's web admin (`http://192.168.100.1`), 10-second auto-refresh |
| 🗑️ **Delete SMS** | Per message, straight from the Android database |
| ✉️ **Send SMS** | From the web UI (ASCII text) |
| 🤖 **Telegram forwarding** | Incoming SMS pushed to your Telegram chat within ~5–10 seconds |
| 💬 **Two-way bot** | `/refresh`, `/status`, `/help` answered by the modem itself |
| 🔄 **Self-healing** | Watchdog restores everything every 10 seconds and after reboots |
| 🔒 **No flashing** | Firmware untouched; uninstall restores 100% stock |

## How it works (why this is non-obvious)

The stock UZ801 web UI is an **embedded Jetty** server inside the Android app
`com.mifiservice.hello`, serving files from
`/data/data/com.mifiservice.hello/files/jetty2/`. This webroot is **re-extracted from
the APK on every boot**. Meanwhile the Android framework (RIL, `CNMI=0,0,0,0,0`)
**consumes every incoming SMS** into the `mmssms.db` database — SMS are never stored
in the SIM/ME storage readable via AT commands (`AT+CMGL` is always empty!).

The solution:

```
boot → initmifiservice.sh → boot.sh → watch.sh (watchdog, self-heals every 10s)
                                        │
        ┌───────────────────────────────┼─────────────────────────────┐
        ▼                               ▼                             ▼
  smsd.sh (5s poll)             httpd :8080 (CGI API)        tg_fwd.sh + tg_listener.sh
  reads mmssms.db →             delete / send / refresh      forwards new SMS +
  inbox.json in webroot         (AT access via lock)         answers /refresh
        │
        ▼
  Jetty webroot → sms.html page + "SMS" menu patched into main.html
```

The stock backend has no SMS API at all (only leftover artifacts: an empty
`smsHandler.js` and a commented-out `inbox.asp` link in `main.html` from an older
firmware generation), so the entire backend is built from scratch with shell scripts +
busybox + the firmware's own `sqlite3`.

## Requirements

- UZ801 modem running **stock firmware** (Android-based, not OpenStick/Debian) + active SIM
- PC with **adb** (Android platform-tools)
- WiFi connection to the modem (default SSID `4G-UFI-XX`)
- Optional: a Telegram account for forwarding

## Installation

### 1. Enable ADB on the modem (one time only)

1. Plug the modem into a PC/charger and let it fully boot (blue LED)
2. From the PC, join the modem's WiFi, then open in a browser:
   ```
   http://192.168.100.1/usbdebug.html
   ```
   (an empty page is normal). The modem reboots.
3. Once it's back up, verify from the PC:
   ```bash
   adb devices      # should show 0123456789ABCDEF device
   adb shell id     # uid=0(root) — the adb shell on this firmware is already root
   ```

### 2. Clone and push files to the modem

```bash
git clone https://github.com/rioadrian24/uz801-tools
cd uz801-tools/sms

adb shell mkdir -p /data/local/tmp/smsui
adb push smsui/* /data/local/tmp/smsui/
adb push main_orig.html /data/local/tmp/smsui/main_orig.html

# Git Bash / Windows users MUST run this first,
# otherwise adb rewrites /data/... paths:
export MSYS_NO_PATHCONV=1
```

### 3. Install

```bash
adb shell "sh /data/local/tmp/smsui/install.sh"
```

The installer copies the app to `/data/smsui`, backs up the boot script
(`initmifiservice.sh.orig`), appends the hook `sh /data/smsui/boot.sh &`, and
activates everything immediately. Done — takes **~30 seconds**.

### 4. Verify

- Open `http://192.168.100.1` (login `admin`) → a new **SMS** menu appears in the
  sidebar, or go straight to `http://192.168.100.1/sms.html`
- Send an SMS to the modem's number → it shows up in the inbox within ≤10 seconds

### 5. (Optional) Telegram forwarding

1. Create a bot: chat with [@BotFather](https://t.me/BotFather) → `/newbot` → copy the **token**
2. Get your chat ID: chat with [@userinfobot](https://t.me/userinfobot) → copy the numeric **Id**
3. **Send `/start` to your bot** (required, otherwise it cannot message you)
4. Write the config:
   ```bash
   adb shell "busybox printf 'TG_BOT_TOKEN=<YOUR_TOKEN>\nTG_CHAT_ID=<YOUR_ID>\n' > /data/smsui/tg.conf"
   adb shell "busybox chmod 600 /data/smsui/tg.conf"
   ```
5. The watchdog starts the forwarder automatically within 10 seconds. Done!

## Usage

**Web** — inbox auto-refreshes; buttons: *Refresh* (forced sync), *delete*, *Send SMS*.

**Telegram bot** — send to your bot:

| Command | Effect |
|---|---|
| `/refresh` | Sync inbox + forward any not-yet-forwarded SMS now |
| `/status` | SMS count, last forwarded ID, modem uptime |
| `/help` | Command list |

**CLI** (no web UI):

```bash
adb push sms/sms.sh /data/local/tmp/sms.sh
adb shell sh /data/local/tmp/sms.sh info        # modem/SIM/signal info
adb shell sh /data/local/tmp/sms.sh list me     # list SMS (when stored in ME)
adb shell sh /data/local/tmp/sms.sh raw 'AT+CSQ;AT+COPS?'   # free-form AT
```

**API** (JSON, no auth — see security notes):

```
http://192.168.100.1:8080/cgi-bin/api?action=refresh
http://192.168.100.1:8080/cgi-bin/api?action=delete&store=db&id=123
http://192.168.100.1:8080/cgi-bin/api?action=send&num=%2B62812..&text=hello
```

## Uninstall

```bash
adb shell "sh /data/smsui/uninstall.sh"
adb reboot
```

The boot script is restored from backup and all injected files are removed — the web
UI returns to 100% stock.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `adb devices` empty / unauthorized | Redo the usbdebug step; try another USB port/cable |
| SMS menu disappears after a while | The app re-extracted its webroot; the watchdog restores it within 10s. Check: `adb shell "busybox ps \| busybox grep watch"` |
| Inbox stays empty | SMS live in the database: `adb shell "sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db 'SELECT count(*) FROM sms WHERE type=1;'"` |
| `API unreachable` in the web UI | Ensure `httpd :8080` is up and the CGI is executable: `adb shell "busybox chmod 755 /data/smsui/www/cgi-bin/api"` |
| Telegram not delivering | Send `/start` to your bot first; check `tg.conf`; test manually: `adb shell ". /data/smsui/smslib.sh && tg_load_conf && forward_pending; echo $?; cat /data/smsui/tg.state"` |
| Bot never replies | The chat ID in `tg.conf` must exactly match your own ID (only the owner is served) |
| Changes to repo files don't show on the modem | The active files live in `/data/smsui/` — copy them again; the watchdog distributes them to the webroot |

## ⚠️ Security notes (read before using)

- **No authentication** on `inbox.json` or the `:8080` API — **anyone connected to the
  modem's WiFi can read all your SMS** (including OTP codes). This is no worse than the
  stock web admin protected only by the default `admin` password, but be aware. Avoid
  using the modem's open WiFi in public places and consider changing the WiFi password.
- The bot token is stored in `/data/smsui/tg.conf` (mode 600, root-only). The bot
  receives **all** SMS including OTPs — never share the token; use `/revoke` at
  @BotFather if it ever leaks.
- Root ADB shell stays enabled after installation (it's a prerequisite). Normal for an
  experimental device, but it means any PC plugged into the modem gets root access.

## Firmware quirks (for contributors)

This firmware is extremely stripped down; the code works around several traps —
good to know before modifying anything:

- `sqlite3` has **no** `char()` function; busybox `awk` has no `strtonum()`;
  `flock` is **completely broken** (replaced with atomic `mkdir` locks);
  `sqlite3` output has **no trailing newline** (the last row gets skipped by
  `while read`); `sed` cannot parse multi-line JSON (use `grep -o`);
  `printf`/`head`/`tail`/`timeout` only exist via `busybox`; and the webroot is
  re-extracted on every boot, which is why the watchdog exists.

## Repository layout

```
sms/
├── sms.sh              CLI reader via AT channel /dev/smd11
├── main_orig.html      Copy of the pristine webroot (menu-patch base)
└── smsui/
    ├── smslib.sh       Core library: AT session, DB→inbox.json sync, TG helpers, locking
    ├── smsd.sh         Database poller → inbox.json (every 5s)
    ├── api_cgi.sh      CGI API on :8080 (refresh/delete/send)
    ├── watch.sh        Self-healing watchdog (every 10s)
    ├── boot.sh         Entry point called from initmifiservice.sh
    ├── install.sh / uninstall.sh
    ├── sms.html / sms.js  Web inbox page
    ├── tg_fwd.sh       SMS → Telegram forwarder
    ├── tg_listener.sh  Bot commands (/refresh /status /help)
    └── tg.conf.example Telegram config example
```

## Credits & license

UZ801 community research: [AlienWolfX/UZ801-USB-MODEM](https://github.com/AlienWolfX/UZ801-USB-MODEM),
[OpenStick](https://github.com/OpenStick), [Rayhunter (EFF)](https://efforg.github.io/rayhunter/uz801.html),
[EDL tool](https://github.com/bkerler/edl). Use responsibly — at your own risk.
