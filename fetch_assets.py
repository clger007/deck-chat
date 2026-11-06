#!/usr/bin/env python3
"""Download WoW's interface art and font into assets/ and turn them into what the page uses.

The files are Blizzard's (the Friz Quadrata font is also licensed from ITC), so they are not in this repository:
this script fetches them from the game files that wago.tools serves, for your own copy only. Needs Pillow (it
reads BLP textures): `pip install pillow`. assets/background.jpg is the author's own Dark Portal screenshot; swap
in any image you like.
"""
import io
import urllib.request
from pathlib import Path

from PIL import Image

ASSETS = Path(__file__).with_name("assets")
CASC = "https://wago.tools/api/casc/{}?download"

# file id in the game data → what it is
FILES = {
    "frizqt": 615960,           # fonts/frizqt__.ttf
    "gold-border": 131076,      # interface/dialogframe/ui-dialogbox-gold-border.blp
    "stone-border": 131072,     # interface/dialogframe/ui-dialogbox-border.blp
    "button-up": 130828,        # interface/buttons/ui-panel-button-up.blp
    "button-down": 130825,      # interface/buttons/ui-panel-button-down.blp
    "header": 131080,           # interface/dialogframe/ui-dialogbox-header.blp
    "portal": 7703531,          # interface/icons/achievement_dungeon_outland_dungeonmaster_256.blp
}


def fetch(name):
    req = urllib.request.Request(CASC.format(FILES[name]), headers={"User-Agent": "deck-chat fetch_assets.py"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def texture(name):
    return Image.open(io.BytesIO(fetch(name))).convert("RGBA")


def nine_slice(strip):
    """WoW keeps a frame border as 8 squares in a row (left, right, top, bottom, then the 4 corners; top and
    bottom stored on their side). CSS border-image wants them in a 3 x 3 grid."""
    s = strip.height
    left, right, top, bottom, tl, tr, bl, br = (strip.crop((i * s, 0, i * s + s, s)) for i in range(8))
    grid = Image.new("RGBA", (3 * s, 3 * s), (0, 0, 0, 0))
    for tile, x, y in [(tl, 0, 0), (tr, 2, 0), (bl, 0, 2), (br, 2, 2), (left, 0, 1), (right, 2, 1),
                       (top.transpose(Image.Transpose.ROTATE_270), 1, 0),
                       (bottom.transpose(Image.Transpose.ROTATE_270), 1, 2)]:
        grid.paste(tile, (x * s, y * s))
    return grid


def main():
    ASSETS.mkdir(exist_ok=True)
    (ASSETS / "frizqt.ttf").write_bytes(fetch("frizqt"))
    nine_slice(texture("gold-border")).save(ASSETS / "frame-gold.png")
    nine_slice(texture("stone-border")).save(ASSETS / "frame-stone.png")
    for name in ("button-up", "button-down"):
        texture(name).crop((0, 0, 80, 22)).save(ASSETS / f"{name}.png")  # the button is the top-left 80 x 22
    header = texture("header")
    header.crop(header.getbbox()).save(ASSETS / "header.png")
    portal = texture("portal")
    portal.resize((96, 96), Image.LANCZOS).save(ASSETS / "icon.png")
    inner = portal.crop((14, 14, 242, 242))  # without the icon's own frame, for the phone's home screen
    inner.convert("RGB").resize((180, 180), Image.LANCZOS).save(ASSETS / "icon-180.png")
    inner.resize((64, 64), Image.LANCZOS).save(ASSETS / "icon-64.png")
    print("assets written to", ASSETS)


if __name__ == "__main__":
    main()
