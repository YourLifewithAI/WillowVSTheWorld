#!/usr/bin/env python3
"""Generates the placeholder pixel-art sprites for Willow VS The World.

Every sprite is drawn as a small text grid: one character per pixel, '.' is
transparent, and every other character looks up a colour in that sprite's
palette. A 1px outline is added automatically around the silhouette, so the
grids only describe fills.

These are *placeholders*. When real art exists (e.g. exported from Aseprite),
drop the PNGs into game/assets/sprites/ with the same file names and delete
the matching entry here.

Usage:
    pip install pillow
    python3 tools/make_sprites.py            # writes game/assets/sprites/*.png
    python3 tools/make_sprites.py --preview  # also writes a scaled contact sheet
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "game" / "assets" / "sprites"

OUTLINE = "#2b1d2a"

# Shared colours
EYE = "#241a22"
PINK = "#ff9eb0"
WHITE = "#fff6ea"

SPRITES: dict[str, dict] = {
    # ------------------------------------------------------------------ PETS
    "willow": {  # orange tabby cat, facing right
        "palette": {"o": "#f2a34f", "d": "#c56a2c", "w": WHITE, "p": PINK, "e": EYE},
        "rows": [
            "........o.....o...",
            ".......opo...opo..",
            "..o....ooooooooo..",
            ".o.....oododdoooo.",
            ".d.....ooeoooeooo.",
            ".o.....owwwpwwwoo.",
            ".d.....oowwwwwooo.",
            ".oooddoodoowwwoo..",
            "..oooooooooowwwo..",
            "..odoodoodoowwoo..",
            "..oooooooooooooo..",
            "..oo.oo....oo.oo..",
            "..ww.ww....ww.ww..",
        ],
    },
    "biscuit": {  # chonky grey-and-white cat
        "palette": {"g": "#a7adbd", "d": "#747b8f", "w": WHITE, "p": PINK, "e": EYE},
        "rows": [
            ".........g.....g....",
            "........gpg...gpg...",
            "........ggggggggg...",
            ".......gggdgdgggg...",
            ".......gggegggeggg..",
            ".......ggwwwpwwwgg..",
            "...gggggggwwwwwwwgg.",
            "..gdggdggwwwwwwwggg.",
            ".ggggggggwwwwwwwggg.",
            "dgdggdgggwwwwwwgggg.",
            "d.gggggggggwwwwgggg.",
            "..gggggggggggggggg..",
            "...ww.ww....ww.ww...",
        ],
    },
    "pepper": {  # floppy-eared pup
        "palette": {"b": "#b8743f", "l": "#f0cf9c", "d": "#5e3b28", "e": EYE,
                    "n": "#2a1a14", "t": "#ff7a8a", "c": "#e84a5f", "y": "#ffd34e"},
        "rows": [
            "...........bbbbb....",
            "..........bbbbbbb...",
            "..b.......ddbbbebb..",
            "..b.......ddbbblllln",
            ".b........ddbbbblll.",
            ".b........ddbbbbltt.",
            ".bbbbbbbbbbbbbccb...",
            "..bbbbbbbbbbbbbyl...",
            "..bbllbbbbbbbblll...",
            "..bbbbbbbbbbbblll...",
            "...llllllllllll.....",
            "...bb.bb....bb.bb...",
            "...ll.ll....ll.ll...",
        ],
    },
    "kiwi": {  # budgie
        "palette": {"g": "#63d163", "d": "#2f9a4a", "y": "#ffe45c", "b": "#4a8ff0",
                    "o": "#ff9a3c", "e": EYE},
        "rows": [
            ".......yyyy...",
            "......yyyyyy..",
            "......yyyeyyo.",
            "......yyyyyyoo",
            ".....gggyyyy..",
            "....ggddgggg..",
            "...gdgdgdggg..",
            "..ggdddddgggg.",
            ".bggdgdggggg..",
            "bb.gggggggg...",
            "b....o..o.....",
        ],
    },
    # ---------------------------------------------------------------- ROBOTS
    "zoomba": {  # robot vacuum
        "palette": {"s": "#dfe4ec", "m": "#b3bccb", "d": "#4d5566", "b": "#2c3140",
                    "c": "#62f2ff"},
        "rows": [
            "......ssssssss......",
            "...ssssssssssssss...",
            ".ssssssmmmmmmssssss.",
            "sssssmmmmmmmmmmsssss",
            "ssssssmmmmmmmmssssss",
            ".ssssssssssssssssss.",
            "bddddddddddddcddcddb",
            ".bdddddddddddddddddb",
            "...bbbbbbbbbbbbbb...",
        ],
    },
    "butler": {  # humanoid helper bot
        "palette": {"w": "#eef2f7", "g": "#b8c0cc", "d": "#5a6272", "v": "#243048",
                    "c": "#62f2ff", "r": "#ff5a6e", "b": "#4aa3ff"},
        "rows": [
            ".......r........",
            ".......g........",
            "....wwwwwwww....",
            "...wwwwwwwwww...",
            "...wvvvvvvvvw...",
            "...wvvcvvvcvw...",
            "...wvvvvvvvvw...",
            "...wwwwwwwwww...",
            "....gggggggg....",
            "..gwwwwbbwwwwg..",
            ".ggwwwwbbwwwwgg.",
            ".g.wwwwwwwwww.g.",
            ".w.wwwwwwwwww.w.",
            "...dddddddddd...",
            "....ww....ww....",
            "....gg....gg....",
            "...ddd....ddd...",
        ],
    },
    "claw": {  # ceiling gantry claw
        "palette": {"y": "#ffc93c", "o": "#d88a1c", "g": "#8a93a3", "d": "#3b4150",
                    "c": "#62f2ff"},
        "rows": [
            ".......gg.......",
            "....yyyyyyyy....",
            "...yyyyyyyyyy...",
            "...yyyydccdyy...",
            "...oooooooooo...",
            "....dddddddd....",
            "...gg..gg..gg...",
            "..gg...gg...gg..",
            "..g....gg....g..",
            "..gg...dd...gg..",
            "...d........d...",
        ],
    },
    "bass": {  # smart speaker
        "palette": {"f": "#3f4d70", "m": "#5a6b93", "r": "#62f2ff", "t": "#1f2638",
                    "e": "#d9fbff"},
        "rows": [
            "...rrrrrrrr...",
            "..rttttttttr..",
            "..rrrrrrrrrr..",
            "..ffffffffff..",
            "..fmfmfmfmff..",
            "..ffffeffeff..",
            "..ffffeffeff..",
            "..fmfmfmfmff..",
            "..fffffmmfff..",
            "..fmfmfmfmff..",
            "..ffffffffff..",
            "...ffffffff...",
            "....tttttt....",
        ],
    },
    # ----------------------------------------------------------------- PROPS
    "remote": {
        "palette": {"b": "#34344a", "r": "#ff4d5e", "g": "#5cd65c", "y": "#ffd84d",
                    "w": "#e9e9f5"},
        "rows": [
            "bbbb",
            "brbb",
            "bbbb",
            "bwwb",
            "bwwb",
            "bbbb",
            "bgyb",
            "bbbb",
        ],
    },
    "fur": {  # debris left when a pet gets KO'd
        "palette": {"a": "#f2a34f", "b": "#e6d7c3", "c": "#a7adbd"},
        "rows": [
            ".a..b.",
            "abbaca",
            ".cabb.",
        ],
    },
    "bolts": {  # debris left when a robot gets KO'd
        "palette": {"a": "#b3bccb", "b": "#6d7688", "o": "#3f3a36"},
        "rows": [
            "a...bb",
            "ab..ba",
            "..o...",
            "b..aa.",
        ],
    },
    "feather": {
        "palette": {"g": "#63d163", "d": "#2f9a4a"},
        "rows": [
            "..ggg",
            "gdddg",
            "ggg..",
        ],
    },
    "rocket_fist": {
        "palette": {"w": "#eef2f7", "g": "#b8c0cc", "o": "#ff9a3c", "y": "#ffe45c"},
        "rows": [
            "....www.",
            "yoggwwww",
            "oyggwwww",
            "....www.",
        ],
    },
    "hairball": {
        "palette": {"a": "#f2a34f", "b": "#c56a2c"},
        "rows": [
            ".ab.",
            "abab",
            ".ba.",
        ],
    },
    "note": {
        "palette": {"c": "#62f2ff"},
        "rows": [
            "..cc",
            "..c.",
            "..c.",
            "ccc.",
            "cc..",
        ],
    },
    # ---------------------------------------------------------- MESS ITEMS
    "lamp": {  # floor lamp
        "palette": {"s": "#ffe9b0", "h": "#f5c96a", "p": "#5b4a42", "b": "#3d312c"},
        "rows": [
            "..ssss..",
            ".ssssss.",
            ".shhhhs.",
            "ssssssss",
            "...pp...",
            "...pp...",
            "...pp...",
            "...pp...",
            "...pp...",
            "...pp...",
            "...pp...",
            "...pp...",
            "...pp...",
            "...pp...",
            "..bbbb..",
            ".bbbbbb.",
        ],
    },
    "plant": {  # potted plant
        "palette": {"g": "#5cbf6a", "d": "#2f8a4a", "t": "#d9774f", "r": "#b55a3a"},
        "rows": [
            "....g..g....",
            "..g.gd.g.g..",
            ".gdg.gdgdg..",
            "..gdggdgdgg.",
            ".ggdgdggdg..",
            "...gdgdgg...",
            "....dgd.....",
            "..tttttttt..",
            "..rrrrrrrr..",
            "...tttttt...",
            "...tttttt...",
            "....tttt....",
        ],
    },
    "cushion": {
        "palette": {"p": "#ff8fab", "d": "#e0607f", "w": "#ffd6e0"},
        "rows": [
            ".pppppppp.",
            "ppwppppwpp",
            "pppppppppp",
            "ppppddpppp",
            "pppppppppp",
            "ppwppppwpp",
            ".dddddddd.",
        ],
    },
    "cushion_teal": {
        "palette": {"p": "#5fd3c8", "d": "#3a9f9a", "w": "#c9fff8"},
        "rows": [
            ".pppppppp.",
            "ppwppppwpp",
            "pppppppppp",
            "ppppddpppp",
            "pppppppppp",
            "ppwppppwpp",
            ".dddddddd.",
        ],
    },
    "vase": {
        "palette": {"b": "#5d8fe0", "l": "#9dc0ff", "r": "#ff5a6e", "y": "#ffd84d",
                    "g": "#5cbf6a"},
        "rows": [
            ".r.y.r.",
            "rgryrgr",
            ".g.g.g.",
            "..ggg..",
            "..bbb..",
            ".blbbb.",
            "bblbbbb",
            "bblbbbb",
            ".bbbbb.",
            "..bbb..",
        ],
    },
    "books": {
        "palette": {"r": "#e05a5a", "b": "#5d8fe0", "y": "#f2c14e", "g": "#5cbf6a",
                    "w": "#fff6ea"},
        "rows": [
            ".rrrrrrr.",
            ".wwwwwwwr",
            "bbbbbbbb.",
            "bwwwwwwwb",
            ".yyyyyyyy",
            ".wwwwwwwy",
            "gggggggg.",
            "gwwwwwwwg",
        ],
    },
    "bookshelf": {  # heavy: needs two helpers to stand back up
        "palette": {"w": "#a0673f", "d": "#6e4428", "r": "#e05a5a", "b": "#5d8fe0",
                    "y": "#f2c14e", "g": "#5cbf6a", "p": "#ff8fab"},
        "rows": [
            "wwwwwwwwwwwwww",
            "wddddddddddddw",
            "wdrbbydgpprbdw",
            "wdrbbydgpprbdw",
            "wwwwwwwwwwwwww",
            "wddddddddddddw",
            "wdgyypbrrdddgw",
            "wdgyypbrrdyggw",
            "wwwwwwwwwwwwww",
            "wddddddddddddw",
            "wdbbrrgdddyydw",
            "wdbbrrgpdbyydw",
            "wwwwwwwwwwwwww",
            "wddddddddddddw",
            "wdyyyggrbdddpw",
            "wdyyyggrbddppw",
            "wwwwwwwwwwwwww",
            ".dd........dd.",
        ],
    },
    "basket": {  # laundry basket: heavy
        "palette": {"w": "#d9b98a", "d": "#a7835a", "s": "#ff8fab", "b": "#5d8fe0",
                    "y": "#fff6ea"},
        "rows": [
            "...s..byy.b...",
            "..ssbyyybbss..",
            "wwwwwwwwwwwwww",
            "wdwdwdwdwdwdww",
            "wwwwwwwwwwwwww",
            ".wdwdwdwdwdww.",
            ".wwwwwwwwwwww.",
            ".wdwdwdwdwdww.",
            "..wwwwwwwwww..",
        ],
    },
    "dirt": {  # spill left behind by a knocked-over plant
        "palette": {"a": "#7a5536", "b": "#5c3e27", "g": "#5cbf6a"},
        "rows": [
            "..aab.a...",
            ".abaabbag.",
            "aabbabaab.",
            ".a.abba...",
        ],
    },
}


def parse_color(hex_str: str) -> tuple[int, int, int, int]:
    h = hex_str.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def render(name: str, spec: dict) -> Image.Image:
    rows = spec["rows"]
    width = max(len(r) for r in rows)
    rows = [r.ljust(width, ".") for r in rows]
    palette = {k: parse_color(v) for k, v in spec["palette"].items()}
    outline = parse_color(spec.get("outline", OUTLINE))

    # 1px padding on every side leaves room for the outline.
    w, h = width + 2, len(rows) + 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    filled = [[False] * w for _ in range(h)]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            if ch not in palette:
                sys.exit(f"{name}: row {y} uses unknown colour key {ch!r}")
            px[x + 1, y + 1] = palette[ch]
            filled[y + 1][x + 1] = True

    for y in range(h):
        for x in range(w):
            if filled[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and filled[ny][nx]:
                    px[x, y] = outline
                    break
    return img


def contact_sheet(images: dict[str, Image.Image], scale: int = 6) -> Image.Image:
    cell = max(max(i.width, i.height) for i in images.values()) * scale + 8
    cols = 6
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (238, 226, 205, 255))
    for idx, img in enumerate(images.values()):
        big = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        cx = (idx % cols) * cell + (cell - big.width) // 2
        cy = (idx // cols) * cell + (cell - big.height) // 2
        sheet.alpha_composite(big, (cx, cy))
    return sheet


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", metavar="PNG", nargs="?", const="sprite_preview.png",
                        help="also write an enlarged contact sheet to this path")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    images = {}
    for name, spec in SPRITES.items():
        img = render(name, spec)
        img.save(OUT_DIR / f"{name}.png")
        images[name] = img
    print(f"wrote {len(images)} sprites to {OUT_DIR.relative_to(ROOT)}")
    if args.preview:
        contact_sheet(images).save(args.preview)
        print(f"preview: {args.preview}")


if __name__ == "__main__":
    main()
