"""Draws the Nocturne app icon (crescent moon + sound wave on the 135° blue→purple gradient)
and writes every iOS size into AppIcon.appiconset. Run: python -I tools/make_icon.py <appiconset dir>"""
import json, math, sys, pathlib
from PIL import Image, ImageDraw

OUT = pathlib.Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
S = 4096  # supersampled canvas

def lerp(a, b, t): return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
def hexc(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

# 135° CSS gradient on a square == diagonal from top-left to bottom-right.
grad = Image.new("RGB", (256, 256))
c0, c1 = hexc("#1E40AF"), hexc("#3B0764")
px = grad.load()
for y in range(256):
    for x in range(256):
        px[x, y] = lerp(c0, c1, (x + y) / 510)
img = grad.resize((S, S), Image.BICUBIC)

# Soft glow behind the moon.
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse([S * .2, S * .2, S * .8, S * .8], fill=70)
from PIL import ImageFilter
glow = glow.filter(ImageFilter.GaussianBlur(S * .08))
img = Image.composite(Image.new("RGB", (S, S), hexc("#7C3AED")), img, glow)

def arc_points(p1, p2, r, large, sweep, n=2400):
    """SVG elliptical-arc (circle) endpoint → sampled points."""
    (x1, y1), (x2, y2) = p1, p2
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    d2 = dx * dx + dy * dy
    r = max(r, math.sqrt(d2))
    k = math.sqrt(max(r * r - d2, 0) / d2)
    if large == sweep: k = -k
    cx, cy = k * dy + (x1 + x2) / 2, -k * dx + (y1 + y2) / 2
    a1 = math.atan2(y1 - cy, x1 - cx); a2 = math.atan2(y2 - cy, x2 - cx)
    da = a2 - a1
    if sweep and da < 0: da += 2 * math.pi
    if not sweep and da > 0: da -= 2 * math.pi
    return [(cx + r * math.cos(a1 + da * i / n), cy + r * math.sin(a1 + da * i / n)) for i in range(n + 1)]

# Lucide-style moon "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z" + wave "M8 13v2M11 11v6M14 12.5v3"
# drawn in a 24-unit box occupying 60% of the icon.
scale = S * 0.6 / 24; off = S * 0.2
T = lambda p: (off + p[0] * scale, off + p[1] * scale)
stroke = 1.25 * scale
layer = Image.new("L", (S, S), 0); d = ImageDraw.Draw(layer)
pts = arc_points((20, 14.5), (9.5, 4), 8, 1, 1) + arc_points((9.5, 4), (20, 14.5), 6.5, 0, 0)
pts = [T(p) for p in pts]
def dot(p):
    d.ellipse([p[0] - stroke / 2, p[1] - stroke / 2, p[0] + stroke / 2, p[1] + stroke / 2], fill=255)
for p in pts:
    dot(p)
for (x, ya, yb) in ((8, 13, 15), (11, 11, 17), (14, 12.5, 15.5)):
    a, b = T((x, ya)), T((x, yb))
    for i in range(201):
        dot((a[0], a[1] + (b[1] - a[1]) * i / 200))
white = Image.new("RGB", (S, S), hexc("#F1F1F7"))
img = Image.composite(white, img, layer.point(lambda v: v * 0.92))

master = img.resize((1024, 1024), Image.LANCZOS)
sizes = [("iphone", 20, 2), ("iphone", 20, 3), ("iphone", 29, 2), ("iphone", 29, 3), ("iphone", 40, 2),
         ("iphone", 40, 3), ("iphone", 60, 2), ("iphone", 60, 3), ("ipad", 20, 1), ("ipad", 20, 2),
         ("ipad", 29, 1), ("ipad", 29, 2), ("ipad", 40, 1), ("ipad", 40, 2), ("ipad", 76, 1), ("ipad", 76, 2),
         ("ipad", 83.5, 2), ("ios-marketing", 1024, 1)]
images = []
for idiom, pt, sc in sizes:
    px_ = int(round(pt * sc)); fn = f"icon-{px_}.png"
    if not (OUT / fn).exists() or px_ == 1024:
        master.resize((px_, px_), Image.LANCZOS).save(OUT / fn, optimize=True)
    ptstr = f"{pt:g}"
    images.append({"idiom": idiom, "size": f"{ptstr}x{ptstr}", "scale": f"{sc}x", "filename": fn})
(OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2))
master.save(pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else OUT / "icon-1024.png")
print("ok", len(images))
