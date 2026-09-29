# UZ801 SMS Toolkit 📱

Tambahkan fitur SMS lengkap ke modem 4G **UZ801 V3.2** (chipset Qualcomm MSM8916)
**tanpa flash firmware** — inbox SMS tampil di web admin bawaan modem, bisa hapus/kirim
SMS, auto-forward ke **Telegram**, plus bot dengan perintah `/refresh`.

> Dikembangkan & diuji pada firmware stock Android `v2.3.11` (AT firmware
> `UZ801_V3.0_21_V01R01B10`), papan `FY_UZ801_3.2`, operator Tri (Indonesia).
> Prinsipnya seharusnya bekerja juga di firmware stock Android 2.3.x lain dan
> dongle sejenis (UFI001B/C, UF896) — konfirmasi hasil di [Issues](../../issues)!

## Fitur

| Fitur | Keterangan |
|---|---|
| 🖥️ **Web inbox** | Menu **SMS** baru di web admin modem (`http://192.168.100.1`), auto-refresh 10 detik |
| 🗑️ **Hapus SMS** | Per pesan, langsung dari database Android |
| ✉️ **Kirim SMS** | Dari web UI (teks ASCII) |
| 🤖 **Forward Telegram** | SMS masuk otomatis diteruskan ke chat Telegram Anda dalam ~5–10 detik |
| 💬 **Bot dua arah** | `/refresh`, `/status`, `/help` dibalas langsung oleh modem |
| 🔄 **Self-healing** | Watchdog memulihkan semuanya tiap 10 detik & setelah reboot |
| 🔒 **Tanpa flash** | Firmware tidak diubah; uninstall mengembalikan 100% kondisi awal |

## Cara kerja (kenapa ini tidak standar)

Web UI bawaan UZ801 adalah **Jetty embedded** di dalam aplikasi Android
`com.mifiservice.hello`, yang menyajikan file dari
`/data/data/com.mifiservice.hello/files/jetty2/`. Webroot ini **di-extract ulang dari
APK setiap boot** — dan framework Android (RIL, `CNMI=0,0,0,0,0`) **mengonsumsi semua
SMS masuk** ke database `mmssms.db`, sehingga SMS tidak pernah tersimpan di SIM/ME
yang bisa dibaca lewat perintah AT (`AT+CMGL` selalu kosong!).

Solusinya:

```
boot → initmifiservice.sh → boot.sh → watch.sh (watchdog, self-healing tiap 10 dtk)
                                        │
        ┌───────────────────────────────┼─────────────────────────────┐
        ▼                               ▼                             ▼
  smsd.sh (poll 5 dtk)          httpd :8080 (CGI API)        tg_fwd.sh + tg_listener.sh
  baca mmssms.db →              hapus / kirim / refresh      forward SMS baru +
  inbox.json di webroot         (akses AT via lock)          jawab /refresh via bot
        │
        ▼
  Jetty webroot → halaman sms.html + menu "SMS" di main.html (di-patch)
```

Karena backend firmware tidak punya API SMS sama sekali (hanya tersisa `smsHandler.js`
kosong dan link `inbox.asp` ter-comment di `main.html` dari firmware lama), seluruh
backend dibangun dari nol dengan shell script + busybox + `sqlite3` bawaan firmware.

## Persyaratan

- Modem UZ801 dengan **firmware stock** (Android-based, bukan OpenStick/Debian) + SIM aktif
- PC dengan **adb** (Android platform-tools)
- Koneksi WiFi ke modem (default SSID `4G-UFI-XX`)
- Opsional: akun Telegram untuk fitur forward

## Instalasi

### 1. Aktifkan ADB di modem (sekali saja)

1. Tancapkan modem ke PC/charger, tunggu boot selesai (LED biru)
2. Dari PC, konek ke WiFi modem, lalu buka di browser:
   ```
   http://192.168.100.1/usbdebug.html
   ```
   (halaman kosong = normal). Modem akan reboot.
3. Setelah nyala lagi, cek dari PC:
   ```bash
   adb devices      # harus muncul 0123456789ABCDEF device
   adb shell id     # uid=0(root) — shell adb di firmware ini sudah root
   ```

### 2. Clone & push file ke modem

```bash
git clone https://github.com/rioadrian24/uz801-tools
cd uz801-tools/sms

adb shell mkdir -p /data/local/tmp/smsui
adb push smsui/* /data/local/tmp/smsui/
adb push main_orig.html /data/local/tmp/smsui/main_orig.html

# Pengguna Git Bash/Windows wajib: export MSYS_NO_PATHCONV=1
# sebelum perintah adb yang mengandung path /data/...
```

### 3. Install

```bash
adb shell "sh /data/local/tmp/smsui/install.sh"
```

Installer akan: menyalin aplikasi ke `/data/smsui`, mem-backup boot script
(`initmifiservice.sh.orig`), menambahkan hook `sh /data/smsui/boot.sh &`, lalu
mengaktifkan semuanya langsung. Selesai — **±30 detik**.

### 4. Cek hasilnya

- Buka `http://192.168.100.1` (login `admin`) → ada menu **SMS** di sidebar, atau
  langsung `http://192.168.100.1/sms.html`
- Kirim SMS ke nomor modem → muncul di inbox ≤10 detik

### 5. (Opsional) Forward ke Telegram

1. Buat bot: chat [@BotFather](https://t.me/BotFather) → `/newbot` → salin **token**
2. Ambil chat ID: chat [@userinfobot](https://t.me/userinfobot) → salin angka **Id**
3. **Kirim `/start` ke bot Anda** (wajib, agar bot boleh mengirim ke Anda)
4. Tulis konfigurasi:
   ```bash
   adb shell "busybox printf 'TG_BOT_TOKEN=<TOKEN_ANDA>\nTG_CHAT_ID=<ID_ANDA>\n' > /data/smsui/tg.conf"
   adb shell "busybox chmod 600 /data/smsui/tg.conf"
   ```
5. Watchdog otomatis menjalankan forwarder ≤10 detik kemudian. Selesai!

## Pemakaian

**Web** — inbox auto-refresh, tombol *Refresh* (sinkron paksa), *delete*, *Send SMS*.

**Bot Telegram** — kirim ke bot Anda:

| Perintah | Efek |
|---|---|
| `/refresh` | Sinkron inbox + teruskan SMS yang belum terkirim |
| `/status` | Jumlah SMS, ID terakhir diteruskan, uptime modem |
| `/help` | Daftar perintah |

**CLI** (tanpa web):

```bash
adb push sms/sms.sh /data/local/tmp/sms.sh
adb shell sh /data/local/tmp/sms.sh info        # info modem/SIM/sinyal
adb shell sh /data/local/tmp/sms.sh list me     # daftar SMS (bila tersimpan di ME)
adb shell sh /data/local/tmp/sms.sh raw 'AT+CSQ;AT+COPS?'   # AT bebas
```

**API** (JSON, tanpa auth — lihat catatan keamanan):

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

Boot script dikembalikan dari backup, semua file injected dibersihkan — web UI kembali
100% stock.

## Troubleshooting

| Gejala | Solusi |
|---|---|
| `adb devices` kosong / unauthorized | Ulangi langkah usbdebug; coba USB port/kabel lain |
| Menu SMS hilang setelah beberapa menit | Webroot di-re-extract app; watchdog akan memulihkan ≤10 dtk. Pastikan `watch.sh` hidup: `adb shell "busybox ps \| busybox grep watch"` |
| Inbox kosong terus | SMS tersimpan di database: cek `adb shell "sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db 'SELECT count(*) FROM sms WHERE type=1;'"` |
| `API unreachable` di web | Pastikan `httpd :8080` hidup & CGI executable: `adb shell "busybox chmod 755 /data/smsui/www/cgi-bin/api"` |
| Telegram tidak terkirim | Kirim `/start` ke bot dulu; cek `tg.conf` terisi; cek manual: `adb shell ". /data/smsui/smslib.sh && tg_load_conf && forward_pending; echo $?; cat /data/smsui/tg.state"` |
| Bot tidak membalas | Chat ID di `tg.conf` harus persis sama dengan ID Anda (hanya owner yang dilayani) |
| Setelah update file di repo tidak berubah di modem | File aktif ada di `/data/smsui/` — salin ulang, watchdog yang menyebarkan ke webroot |

## ⚠️ Catatan keamanan (baca sebelum dipakai)

- **Tidak ada autentikasi** pada `inbox.json` dan API `:8080` — **siapa pun yang terhubung
  ke WiFi modem bisa membaca semua SMS Anda** (termasuk OTP). Ini sama seperti web admin
  bawaan yang hanya dilindungi password `admin`. Jangan gunakan WiFi modem terbuka di
  tempat umum, dan pertimbangkan mengubah password WiFi.
- Token bot disimpan di `/data/smsui/tg.conf` (permission 600, hanya root). Bot menerima
  **semua** SMS termasuk OTP — jangan sebarkan token; gunakan `/revoke` di @BotFather bila
  token pernah bocor.
- Root shell via ADB tetap aktif setelah instalasi (memang syarat kerjanya). Ini normal
  untuk perangkat eksperimen, tapi berarti PC mana pun yang menancap ke modem punya akses root.

## Quirk firmware (untuk kontributor)

Firmware ini sangat terpotong; banyak jebakan yang sudah ditangani di kode —
penting diketahui bila ingin memodifikasi:

- `sqlite3` **tanpa** `char()`, `strtonum()` tidak ada di busybox `awk`, `flock`
  **rusak total** (diganti lock `mkdir` atomik), output `sqlite3` **tanpa newline
  akhir** (baris terakhir terlewat oleh `while read`), `sed` tidak berguna untuk
  JSON multi-baris (pakai `grep -o`), `printf`/`head`/`tail`/`timeout` hanya ada
  lewat `busybox`, dan webroot di-extract ulang tiap boot sehingga butuh watchdog.

## Struktur repo

```
sms/
├── sms.sh              CLI reader via AT channel /dev/smd11
├── main_orig.html      Salinan webroot asli (dasar patch menu)
└── smsui/
    ├── smslib.sh       Library inti: AT session, sync DB→inbox.json, TG helpers, locking
    ├── smsd.sh         Poll database → inbox.json (tiap 5 dtk)
    ├── api_cgi.sh      CGI API :8080 (refresh/delete/send)
    ├── watch.sh        Watchdog self-healing (tiap 10 dtk)
    ├── boot.sh         Entry point dari initmifiservice.sh
    ├── install.sh / uninstall.sh
    ├── sms.html / sms.js  Halaman inbox web
    ├── tg_fwd.sh       Forwarder SMS → Telegram
    ├── tg_listener.sh  Bot command (/refresh /status /help)
    └── tg.conf.example Contoh konfigurasi Telegram
```

## Kredit & lisensi

Riset komunitas UZ801: [AlienWolfX/UZ801-USB-MODEM](https://github.com/AlienWolfX/UZ801-USB-MODEM),
[OpenStick](https://github.com/OpenStick), [Rayhunter (EFF)](https://efforg.github.io/rayhunter/uz801.html),
[EDL tool](https://github.com/bkerler/edl). Gunakan dengan bijak — risiko ditanggung sendiri.
