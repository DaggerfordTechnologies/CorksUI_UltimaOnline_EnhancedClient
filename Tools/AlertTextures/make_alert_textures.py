"""Builds the centre-screen alert graphics used by Corks' Alerts.

Each alert is a word or two of gradient text with a dark outline and a drop
shadow, in the same style as the Repair popup. The files are written to
Textures/ as uncompressed 32-bit DDS, the format the client loads for the
other CST textures, and the sizes are printed so they can be copied into
CorksAlerts.TEXTURES in Source/CorksAlerts.lua.

Needs Python 3 and Pillow (pip install pillow). Run it from anywhere:
    python Tools/AlertTextures/make_alert_textures.py
"""

import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "Textures"))
FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")

IMPACT = "impact.ttf"
SERIF = "georgiaz.ttf"  # Georgia Bold Italic, like the Repair popup

# Gradient colours run from the top of the letters to the bottom.
FIRE = [(255, 240, 120), (255, 170, 20), (230, 60, 0), (120, 10, 0)]
BLOOD = [(255, 120, 110), (220, 20, 20), (110, 0, 0)]
GOLD = [(255, 255, 190), (255, 225, 40), (200, 140, 0)]
ICE = [(225, 245, 255), (110, 180, 255), (20, 70, 190)]
TEAL = [(210, 255, 250), (40, 210, 200), (0, 110, 120)]
STEEL = [(255, 255, 255), (190, 200, 210), (95, 105, 120)]
ROSE = [(255, 225, 240), (240, 140, 190), (150, 50, 100)]
VIOLET = [(255, 200, 120), (240, 70, 60), (120, 30, 160)]
SEA = [(200, 240, 255), (40, 150, 230), (10, 60, 130)]
PUMPKIN = [(255, 220, 120), (255, 130, 0), (130, 40, 120)]
HOLLY = [(255, 120, 110), (200, 20, 30), (20, 110, 40)]
CLOVER = [(215, 255, 210), (80, 200, 100), (20, 90, 50)]
PETAL = [(255, 230, 190), (255, 150, 60), (190, 70, 20)]

# file name (without .dds), text, font, gradient, sparks (lava speckle)
ALERTS = [
    ("cst_CorksCalmed",       "Calmed",            SERIF,  ICE,     False),
    ("cst_CorksStripped",     "Stripped!",         SERIF,  ROSE,    False),
    ("cst_CorksDeathStrike",  "DEATH STRIKE",      IMPACT, BLOOD,   False),
    ("cst_CorksRevealed",     "REVEALED!",         IMPACT, GOLD,    False),
    ("cst_CorksHitSplinter",  "Target Splintered", SERIF,  STEEL,   False),
    ("cst_CorksHitDisarm",    "Target Disarmed",   SERIF,  BLOOD,   False),
    ("cst_CorksHiddenObject", "Hidden Object",     SERIF,  SEA,     False),
    ("cst_CorksStealther",    "Stealther!",        SERIF,  TEAL,    False),
    ("cst_CorksMeteor",       "METEOR!",           IMPACT, FIRE,    True),
    ("cst_CorksEruption",     "ERUPTION!",         IMPACT, FIRE,    True),
    ("cst_CorksLavaRock",     "LAVA ROCK!",        IMPACT, FIRE,    True),
    ("cst_CorksAmbush",       "AMBUSH!",           IMPACT, VIOLET,  False),
    ("cst_CorksTreat",        "Treat!",            SERIF,  PUMPKIN, False),
    ("cst_CorksCargo",        "Cargo Crate!",      SERIF,  SEA,     False),
    ("cst_CorksKrampus",      "Krampus!",          SERIF,  HOLLY,   False),
    ("cst_CorksLuckRanOut",   "Luck Ran Out",      SERIF,  CLOVER,  False),
    ("cst_CorksPetals",       "Petals Wore Off",   SERIF,  PETAL,   False),
]

FONT_SIZE = 60
PAD_X = 14
HEIGHT = 84
OUTLINE = 5   # MaxFilter size, so roughly a 2px outline
SHADOW = (3, 4)


def gradient_color(stops, t):
    t = min(1.0, max(0.0, t))
    seg = 1.0 / (len(stops) - 1)
    i = min(int(t / seg), len(stops) - 2)
    u = (t - i * seg) / seg
    a, b = stops[i], stops[i + 1]
    return tuple(int(a[k] + (b[k] - a[k]) * u) for k in range(3))


def render(text, font_file, stops, sparks):
    font = ImageFont.truetype(os.path.join(FONTS, font_file), FONT_SIZE)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    left, top, right, bottom = probe.textbbox((0, 0), text, font=font)
    width = (right - left) + PAD_X * 2 + SHADOW[0]
    width += width % 2  # keep even

    mask = Image.new("L", (width, HEIGHT), 0)
    x = PAD_X - left
    y = (HEIGHT - (bottom - top)) // 2 - top - 2
    ImageDraw.Draw(mask).text((x, y), text, font=font, fill=255)

    text_top = y + top
    text_bottom = y + bottom
    fill = Image.new("RGBA", (width, HEIGHT))
    pixels = fill.load()
    for row in range(HEIGHT):
        color = gradient_color(stops, (row - text_top) / max(1, text_bottom - text_top)) + (255,)
        for col in range(width):
            pixels[col, row] = color

    if sparks:
        rng = random.Random(text)
        draw = ImageDraw.Draw(fill)
        for _ in range(width // 2):
            px, py = rng.randrange(width), rng.randrange(HEIGHT)
            hot = rng.random() < 0.5
            draw.point((px, py), fill=(255, 235, 100, 255) if hot else (90, 0, 0, 255))

    # A soft highlight across the top third of the letters
    shine = Image.new("L", (width, HEIGHT), 0)
    ImageDraw.Draw(shine).rectangle((0, 0, width, text_top + (text_bottom - text_top) // 3), fill=70)
    shine = Image.composite(shine, Image.new("L", (width, HEIGHT), 0), mask)

    outline = mask.filter(ImageFilter.MaxFilter(OUTLINE))
    shadow = Image.new("L", (width, HEIGHT), 0)
    shadow.paste(outline.filter(ImageFilter.GaussianBlur(3)), SHADOW)

    dark = tuple(max(0, c // 6) for c in stops[-1])
    out = Image.new("RGBA", (width, HEIGHT), (0, 0, 0, 0))
    out.paste((0, 0, 0, 200), (0, 0), shadow)
    out.paste(dark + (255,), (0, 0), outline)
    out.paste(fill, (0, 0), mask)
    out.paste((255, 255, 255, 255), (0, 0), shine)
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    preview = []
    for name, text, font_file, stops, sparks in ALERTS:
        image = render(text, font_file, stops, sparks)
        image.save(os.path.join(OUT_DIR, name + ".dds"))
        preview.append(image)
        print('%-22s %3d x %d' % (name, image.width, image.height))

    # Contact sheet for checking the set by eye (not used by the UI)
    sheet_w = max(i.width for i in preview)
    sheet = Image.new("RGBA", (sheet_w, sum(i.height for i in preview)), (60, 60, 60, 255))
    y = 0
    for image in preview:
        sheet.alpha_composite(image, (0, y))
        y += image.height
    sheet.save(os.path.join(HERE, "preview.png"))


if __name__ == "__main__":
    main()
