# UZ801 SMS (firmware stock)

Dua cara pakai SMS di UZ801 V3.2 (firmware stock Android v2.3.11) **tanpa flash firmware**:

1. **CLI** — baca SMS via `adb shell` (script `sms.sh`).
2. **Web UI** — inbox SMS tampil di web admin modem (`http://192.168.100.1`), menu **SMS**.
   Sumber data: **database telefony Android** (`mmssms.db`) — karena RIL framework
   (CNMI 0,0,0,0,0) mengonsumsi semua SMS masuk, SMS tidak pernah tersimpan di SIM/ME
   yang terbaca via AT. Daemon membaca DB itu tiap 5 detik dan menerbitkan `inbox.json`
   di webroot Jetty; halaman inbox + refresh/delete/send ditambahkan ke web UI.
   (Catatan: sqlite3 firmware ini minim fitur — tanpa `char()`; body dibaca sebagai
   `hex()` lalu didecode di awk tanpa `strtonum`, memakai lookup table.)

## Prasyarat (sekali saja)

1. ADB terpasang di PC (platform-tools).
2. ADB aktif di modem. Jika belum: konek WiFi ke modem, buka `http://192.168.100.1/usbdebug.html`,
   tunggu modem reboot, cabut-pasang lagi.

## Install Web UI

Dari folder `uz801-tools/sms`:

```bash
export MSYS_NO_PATHCONV=1   # wajib di Git Bash / Windows
adb shell mkdir -p /data/local/tmp/smsui
adb push smsui/* /data/local/tmp/smsui/
adb push main_orig.html /data/local/tmp/smsui/main_orig.html
adb shell "sh /data/local/tmp/smsui/install.sh"
```

Setelah itu:

- Buka `http://192.168.100.1` (login admin) → menu **SMS** di sidebar, atau langsung
  `http://192.168.100.1/sms.html`
- Auto-refresh tiap 10 detik; tombol **Refresh** sinkron paksa dengan modem;
  **Send SMS** untuk mengirim (ASCII); tautan **delete** menghapus SMS dari SIM/memori modem.

## Persistensi

`jetty2/` (webroot) di-extract ulang dari APK setiap boot, dan `install.sh` menambahkan

```
sh /data/smsui/boot.sh &
```

ke `/system/bin/initmifiservice.sh` (dibackup ke `initmifiservice.sh.orig`). `boot.sh`
hanya menjalankan **watchdog** (`watch.sh`, detached via `setsid`) yang tiap 10 detik
memastikan: file `sms.html/js/inbox.json` ada di webroot, menu SMS ter-patch di
`main.html` (app bisa meng-overwrite webroot belakangan setelah boot), `httpd :8080`
(API CGI) dan `smsd` (poll AT tiap 15 detik) berjalan — semuanya self-healing.

## Forward otomatis ke Telegram (opsional)

1. Buat bot via [@BotFather](https://t.me/BotFather) (`/newbot`) → salin token.
2. Chat [@userinfobot](https://t.me/userinfobot) → salin Id (chat ID).
3. Kirim `/start` ke bot Anda (wajib, agar bot bisa mengirim ke Anda).
4. Tulis konfigurasi:

```bash
adb shell "busybox printf 'TG_BOT_TOKEN=<token>\nTG_CHAT_ID=<id>\n' > /data/smsui/tg.conf"
adb shell "busybox chmod 600 /data/smsui/tg.conf"
```

5. Watchdog otomatis menjalankan `tg_fwd.sh` ≤10 detik kemudian (juga ikut boot).
   SMS baru diteruskan dalam ~5-10 detik dengan format pengirim/waktu/isi.

Mekanisme: `tg_fwd.sh` poll `mmssms.db` tiap 5 detik, kirim via `/system/bin/curl -k`
(HTTPS, verify CA dilewati karena device tanpa CA bundle), state `tg.state` = id SMS
terakhir yang diteruskan (riwayat lama tidak di-spam; gagal kirim = diulang siklus
berikutnya). Hapus `tg.conf` untuk mematikan forwarder.

## Uninstall

```bash
adb shell "sh /data/smsui/uninstall.sh"
```

lalu reboot modem untuk memulihkan web UI penuh (menu SMS hilang setelah webroot re-extract).

## CLI (tanpa web UI)

```bash
adb push sms/sms.sh /data/local/tmp/sms.sh
adb shell sh /data/local/tmp/sms.sh info          # info modem/SIM/sinyal + status penyimpanan
adb shell sh /data/local/tmp/sms.sh list sm       # daftar SMS di SIM
adb shell sh /data/local/tmp/sms.sh list me       # daftar SMS di memori modem
adb shell sh /data/local/tmp/sms.sh read 1 sm     # baca SMS index 1 dari SIM
adb shell sh /data/local/tmp/sms.sh del 1 sm      # hapus SMS index 1 dari SIM
adb shell sh /data/local/tmp/sms.sh raw 'AT+CSQ;AT+COPS?'   # AT command bebas
```

## Catatan teknis

- Channel AT: `/dev/smd11` (izin `rw-rw-rw-`, tanpa root pun bisa; installer pakai root
  untuk patch boot script).
- API CGI: `http://192.168.100.1:8080/cgi-bin/api?action=refresh|delete&store=db&id=N|send&num=..&text=..`
  (busybox httpd, root di `/data/smsui/www`; delete default menghapus baris di `mmssms.db`).
- Akses AT channel (`/dev/smd11`) kini hanya untuk **kirim SMS**; dikunci `flock` di
  `/data/smsui/at.lock` agar tidak tabrakan dengan MifiService.
- File temp sync memakai suffix `$$` (PID) agar daemon poller dan CGI tidak saling
  menimpa saat menulis bersamaan.
- Mode SMS teks (`AT+CMGF=1`), charset IRA — untuk kirim; SMS masuk tampil apa adanya
  dari database (unicode/emoji tetap terbaca sebagai teks DB).
- `smsd` hanya menulis ulang `inbox.json` jika isinya berubah (poll 5 detik).
- Diuji pada firmware `UZ801_V3.0_21_V01R01B10`, operator Tri; OTP Bima+ (sender
  "bima+ OTP") terbaca di inbox web.
