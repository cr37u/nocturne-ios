"""Renders docs/images/banner.png, screens.png and screens-2.png for the README
from the iOS design boards (design/ios in the Android repo).
Run: python -I tools/make_readme_images.py <design/ios dir>"""
import sys, pathlib
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BOARDS = pathlib.Path(sys.argv[1])
OUT = pathlib.Path("docs/images"); OUT.mkdir(parents=True, exist_ok=True)
FONTS = pathlib.Path("Shared/Resources/Fonts")
def font(w, size): return ImageFont.truetype(str(FONTS / f"Manrope-{w}.ttf"), size)
def hexc(h, a=255): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (a,)

def gradient(size, stops, angle_diag=True):
    w, h = size
    small = Image.new("RGBA", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510 if angle_diag else y / 255
            for i in range(len(stops) - 1):
                (p0, c0), (p1, c1) = stops[i], stops[i + 1]
                if p0 <= t <= p1:
                    k = (t - p0) / max(p1 - p0, 1e-6)
                    px[x, y] = tuple(round(c0[j] + (c1[j] - c0[j]) * k) for j in range(4))
                    break
    return small.resize((w, h), Image.BICUBIC)

def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m

def phone(shot_path, width, ratio=None):
    """iPhone-style frame: bright-gradient rim + dark bezel + rounded screenshot."""
    shot = Image.open(shot_path).convert("RGBA")
    sw = width - 28
    sh = round(sw * shot.height / shot.width) if ratio is None else round(sw * ratio)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    W, H = width, sh + 28
    rim = gradient((W, H), [(0, hexc("#3B6CF6")), (1, hexc("#7C3AED"))])
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(rim, (0, 0), rounded_mask((W, H), int(W * 0.15)))
    bez = Image.new("RGBA", (W - 6, H - 6), hexc("#05050B"))
    out.paste(bez, (3, 3), rounded_mask((W - 6, H - 6), int(W * 0.145)))
    out.paste(shot, (14, 14), rounded_mask((sw, sh), int(sw * 0.13)))
    return out

def shadowed(img, blur=40, offset=(0, 30), alpha=170):
    pad = blur * 3
    canvas = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    sh = Image.new("RGBA", img.size, (5, 3, 20, alpha))
    canvas.paste(sh, (pad + offset[0], pad + offset[1]), img.split()[3])
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(img, (pad, pad))
    return canvas, pad

def chip(base, x, y, text, fill, fg, f):
    """Alpha-blended pill (ImageDraw alone would overwrite alpha instead of blending)."""
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    tw = draw.textlength(text, font=f)
    h = 58
    draw.rounded_rectangle([x, y, x + tw + 44, y + h], h // 2, fill=fill)
    base.alpha_composite(layer)
    ImageDraw.Draw(base).text((x + 22, y + h / 2), text, font=f, fill=fg, anchor="lm")
    return x + tw + 44 + 14

def moon_tile(size):
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    g = gradient((size, size), [(0, hexc("#1E40AF")), (1, hexc("#3B0764"))])
    tile.paste(g, (0, 0), rounded_mask((size, size), int(size * 0.3)))
    icon = Image.open("App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png").convert("RGBA").resize((size, size), Image.LANCZOS)
    tile.paste(icon, (0, 0), rounded_mask((size, size), int(size * 0.3)))
    return tile

# ---------------- banner ----------------
W, H = 1600, 820
bg = gradient((W, H), [(0, hexc("#1E3FAE")), (0.55, hexc("#2A1670")), (1, hexc("#3B0764"))])
d = ImageDraw.Draw(bg)
bg.alpha_composite(moon_tile(112), (112, 200))
d.text((104, 470), "Nocturne", font=font("ExtraBold", 140), fill=hexc("#F1F1F7"), anchor="ls")
d.text((114, 548), "Your YouTube music — downloaded once,", font=font("Regular", 36), fill=hexc("#D4D4EA"), anchor="ls")
d.text((114, 596), "played offline, on every iPhone.", font=font("Regular", 36), fill=hexc("#D4D4EA"), anchor="ls")
cf = font("Bold", 26)
x = chip(bg, 114, 640, "Offline", hexc("#F5B942"), hexc("#1A1030"), cf)
for label in ["iOS 16+", "Swift · SwiftUI", "Dynamic Island"]:
    x = chip(bg, x, 640, label, hexc("#F1F1F7", 38), hexc("#F1F1F7"), cf)
p1 = phone(BOARDS / "04-iPhone-ProMax-Biblioteca.png", 330).rotate(5, expand=True, resample=Image.BICUBIC)
p2 = phone(BOARDS / "03-iPhone-DynamicIsland-SeRedaAcum.png", 330).rotate(-4, expand=True, resample=Image.BICUBIC)
for img, pos in ((p1, (960, 70)), (p2, (1190, 120))):
    s, pad = shadowed(img)
    bg.alpha_composite(s, (pos[0] - pad, pos[1] - pad))
bg.convert("RGB").save(OUT / "banner.png", optimize=True)

# ---------------- screens ----------------
items = [
    ("04-iPhone-ProMax-Biblioteca.png", "Library", "Search, sort, swipe to delete"),
    ("03-iPhone-DynamicIsland-SeRedaAcum.png", "Now Playing", "Gapless, shuffle & repeat"),
    ("02-iPhone-Notch-SeRedaAcum.png", "Every iPhone", "Notch, Dynamic Island, Pro Max"),
    ("01-iPhone-SE-Biblioteca.png", "iPhone SE", "Compact layout, same app"),
]
PW, GAP, TOP = 400, 56, 70
W = 4 * PW + 3 * GAP + 2 * 70
H = 1120
bg = gradient((W, H), [(0, hexc("#0E0E1F")), (1, hexc("#0A0A14"))], angle_diag=False)
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([W * 0.2, -300, W * 0.8, 500], fill=hexc("#3B6CF6", 50))
bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(120)))
d = ImageDraw.Draw(bg)
x = 70
phone_h = 0
for name, title, sub in items:
    ratio = 2.165 if "SE" not in name else None
    ph = phone(BOARDS / name, PW, ratio=ratio)
    if "SE" in name:
        # Same height as the others: SE is shorter, center it vertically.
        ph_y = TOP + (phone_h - ph.height) // 2 if phone_h else TOP
    else:
        ph_y = TOP
        phone_h = phone_h or ph.height
    s, pad = shadowed(ph, blur=30, offset=(0, 20), alpha=150)
    bg.alpha_composite(s, (x - pad, ph_y - pad))
    cx = x + PW // 2
    d.text((cx, TOP + phone_h + 70), title, font=font("Bold", 42), fill=hexc("#F1F1F7"), anchor="ms")
    d.text((cx, TOP + phone_h + 118), sub, font=font("Regular", 28), fill=hexc("#9A9AB8"), anchor="ms")
    x += PW + GAP
bg.convert("RGB").save(OUT / "screens.png", optimize=True)

# ---------------- Dynamic Island / Live Activity ----------------
board = Image.open(BOARDS / "05-DynamicIsland-LiveActivity.png").convert("RGBA")
bw = 1600
board = board.resize((bw, round(bw * board.height / board.width)), Image.LANCZOS)
W, H = bw + 120, board.height + 120
bg = gradient((W, H), [(0, hexc("#0E0E1F")), (1, hexc("#0A0A14"))], angle_diag=False)
card = Image.new("RGBA", board.size, (0, 0, 0, 0))
card.paste(board, (0, 0), rounded_mask(board.size, 36))
s, pad = shadowed(card, blur=30, offset=(0, 20), alpha=150)
bg.alpha_composite(s, (60 - pad, 60 - pad))
bg.convert("RGB").save(OUT / "live-activity.png", optimize=True)
print("ok")
