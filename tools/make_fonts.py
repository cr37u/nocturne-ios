"""Builds static Manrope weights from the variable font (iOS handles static files most reliably)."""
import sys, pathlib
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
weights = {200: "ExtraLight", 400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold"}
for w, style in weights.items():
    f = TTFont(src)
    inst = instancer.instantiateVariableFont(f, {"wght": w}, updateFontNames=False)
    name = inst["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            name.removeNames(nameID=rec.nameID)
    name.setName("Manrope", 1, 3, 1, 0x409)
    name.setName(style if style in ("Regular", "Bold") else "Regular", 2, 3, 1, 0x409)
    name.setName(f"Manrope-{style}", 3, 3, 1, 0x409)
    name.setName(f"Manrope {style}", 4, 3, 1, 0x409)
    name.setName(f"Manrope-{style}", 6, 3, 1, 0x409)
    name.setName("Manrope", 16, 3, 1, 0x409)
    name.setName(style, 17, 3, 1, 0x409)
    if style not in ("Regular", "Bold"):
        name.setName(f"Manrope {style}", 1, 3, 1, 0x409)
    inst["OS/2"].usWeightClass = w
    inst.save(out / f"Manrope-{style}.ttf")
    print("wrote", f"Manrope-{style}.ttf", TTFont(out / f"Manrope-{style}.ttf")["name"].getDebugName(6))
