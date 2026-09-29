"""Generate GitHub social preview image (1280x640) for uz801-tools repo."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "social-preview.png")

W, H = 1280, 640
GREEN = (141, 198, 63)     # aksen web UI modem
DARK = (13, 17, 23)        # github dark
GRAY = (139, 148, 158)
WHITE = (230, 237, 243)

img = Image.new("RGB", (W, H), DARK)
d = ImageDraw.Draw(img)

# subtle top accent bar
d.rectangle([0, 0, W, 10], fill=GREEN)

# fonts (Windows)
FB = "C:/Windows/Fonts/arialbd.ttf"
FR = "C:/Windows/Fonts/arial.ttf"
f_title = ImageFont.truetype(FB, 88)
f_sub = ImageFont.truetype(FR, 40)
f_small = ImageFont.truetype(FR, 30)
f_mono = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 34)

def center(text, font, y, fill):
    w = d.textlength(text, font=font)
    d.text(((W - w) / 2, y), text, font=font, fill=fill)

center("UZ801 SMS Toolkit", f_title, 120, WHITE)
center("Web inbox  •  Send & Delete SMS  •  Telegram Forwarding", f_sub, 260, GREEN)
center("No reflashing  |  Qualcomm MSM8916  |  Stock Android 2.3.x", f_small, 340, GRAY)

# fake terminal card
tx, ty, tw, th = 160, 430, 960, 150
d.rounded_rectangle([tx, ty, tx + tw, ty + th], radius=14, fill=(22, 27, 34), outline=(48, 54, 61), width=2)
lines = [
    ("$ adb shell sh install.sh", WHITE),
    ("> SMS menu appears at http://192.168.100.1  ✓", GREEN),
    ("> new SMS -> Telegram in 5 seconds           ✓", GREEN),
]
for i, (t, c) in enumerate(lines):
    d.text((tx + 30, ty + 22 + i * 42), t, font=f_mono, fill=c)

img.save(OUT)
print("saved", OUT, img.size)
