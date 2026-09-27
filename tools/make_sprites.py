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
    # ------------------------------------------------------------ WEAPONS
    # Held weapons are drawn next to their owner, pointing right.
    "w_laser": {  # Willow's laser pointer blaster
        "palette": {"p": "#ff8fab", "d": "#c75a7a", "w": "#ffffff", "r": "#ff3b3b"},
        "rows": [
            "....ww......",
            "pppppppppwrr",
            "pdddppppppr.",
            "..dd........",
        ],
    },
    "w_bazooka": {  # Biscuit's catnip bazooka
        "palette": {"g": "#5cbf6a", "l": "#a8e6a0", "o": "#2f7a44", "d": "#8a5a3c"},
        "rows": [
            "gggggggggggggoo",
            "gllgllgggggggoo",
            "ggggggggggggg..",
            "...dd..........",
        ],
    },
    "w_gatling": {  # Pepper's tennis ball gatling
        "palette": {"y": "#e8f25c", "g": "#c9d64a", "s": "#9aa3b0", "b": "#5a6272", "d": "#8a5a3c"},
        "rows": [
            "..yy........",
            ".yggy.......",
            ".yyyy.......",
            "ssssssssssbb",
            "ssssssssssbb",
            "..dd........",
        ],
    },
    "w_dustcannon": {  # Zoomba's dust cannon turret
        "palette": {"m": "#b3bccb", "c": "#5a6272"},
        "rows": [
            "..mmm....",
            ".mmmmcccc",
            ".mmmmcccc",
            "mmmmmm...",
        ],
    },
    "w_toaster": {  # Unit-7's toaster cannon
        "palette": {"t": "#e8b86d", "s": "#c9d0da", "w": "#ffffff", "b": "#5a6272", "d": "#3b3b44"},
        "rows": [
            "..tt.tt....",
            ".ssssssss..",
            "sssssssssbb",
            "swwssssssbb",
            "sssssssss..",
            ".d.....d...",
        ],
    },
    "w_wreckingball": {  # The Claw's wrecking ball
        "palette": {"c": "#8a93a3", "k": "#3b4150", "h": "#8a93a3"},
        "rows": [
            "....c....",
            "....c....",
            "....c....",
            "..kkkkk..",
            ".kkkkkkk.",
            "kkkhkkkkk",
            "kkhkkkkkk",
            "kkkkkkkkk",
            ".kkkkkkk.",
            "..kkkkk..",
        ],
    },
    "w_bone": {  # Pepper's Big Bone (held upright, swung like a bat)
        "palette": {"b": "#fff6ea", "s": "#e8d9b8"},
        "rows": [
            ".bb.bb.",
            "bbbbbbb",
            ".bbsbb.",
            "..bsb..",
            "..bsb..",
            "..bsb..",
            "..bsb..",
            "..bsb..",
            "..bsb..",
            ".bbsbb.",
            "bbbbbbb",
            ".bb.bb.",
        ],
    },
    "p_litter": {  # a litter box in flight
        "palette": {"b": "#5d8fe0", "d": "#3f6ab0", "l": "#d8cdb8"},
        "rows": [
            ".llll.",
            "bbbbbb",
            "bddddb",
            "bbbbbb",
        ],
    },
    "plaster": {  # dust and chunks from a smashed wall
        "palette": {"a": "#f4efe6", "b": "#d9d2c5", "c": "#b8ab94", "d": "#ffffff"},
        "rows": [
            "..d.a....",
            ".abab.ca.",
            "abcbaabba",
            ".ab.b.a..",
        ],
    },
    "litter": {  # spilled cat litter
        "palette": {"a": "#d8cdb8", "b": "#b8ab94", "c": "#efe7d6"},
        "rows": [
            "..ab.ca..",
            ".abcbbac.",
            "abbacbbab",
            ".ab..ba..",
        ],
    },
    "p_bird": {  # one budgie of the flock
        "palette": {"g": "#63d163", "y": "#ffe45c", "o": "#ff9a3c", "b": "#4a8ff0"},
        "rows": [
            "...yy.",
            "..yyyo",
            "bggg..",
            ".gg...",
        ],
    },
    "p_rocket": {  # catnip rocket
        "palette": {"g": "#5cbf6a", "l": "#a8e6a0", "f": "#ff9a3c"},
        "rows": [
            "..ggggg.",
            "ffggllgg",
            "..ggggg.",
        ],
    },
    "p_ball": {
        "palette": {"y": "#e8f25c"},
        "rows": [
            ".y.",
            "yyy",
            ".y.",
        ],
    },
    "p_egg": {
        "palette": {"w": "#fffdf0"},
        "rows": [
            ".ww.",
            "wwww",
            "wwww",
            ".ww.",
        ],
    },
    "p_toast": {
        "palette": {"t": "#c0873f", "b": "#e8c07a"},
        "rows": [
            ".tttt.",
            "tbbbbt",
            "tbbbbt",
            "tttttt",
        ],
    },
    "scorch": {  # scorch mark left by explosions
        "palette": {"k": "#2b2226"},
        "outline": "#5a4a4a",
        "rows": [
            "..kkkk....",
            ".kkkkkkkk.",
            "kkkkkkkkk.",
            "..kkkkk...",
        ],
    },
    "yolk": {  # egg splat
        "palette": {"w": "#fffdf0", "y": "#ffc93c"},
        "outline": "#e8d9b8",
        "rows": [
            "..wwww....",
            ".wwwwwwww.",
            "wwwyyyww..",
            ".wwyyyww..",
            "..wwww....",
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
    "pie": {  # farmhouse: a cherry pie cooling on the floor, obviously
        "palette": {"c": "#e8b86d", "f": "#d9434e", "t": "#a7adbd"},
        "rows": [
            "..cccccc..",
            ".cfcfcfcc.",
            "cfcfcfcfcc",
            "cccccccccc",
            ".tttttttt.",
        ],
    },
    "milk": {
        "palette": {"w": "#f4f7fb", "b": "#5d8fe0"},
        "rows": [
            "..ww..",
            "..ww..",
            ".wwww.",
            "wwwwww",
            "wbbbbw",
            "wbwwbw",
            "wbbbbw",
            "wwwwww",
        ],
    },
    "boots": {  # yellow rain boots by the door
        "palette": {"y": "#ffd84d", "d": "#c9962a"},
        "rows": [
            "yy...yy...",
            "yy...yy...",
            "yy...yy...",
            "yyy..yyy..",
            "yyyy.yyyy.",
            "dddd.dddd.",
        ],
    },
    "guitar": {
        "palette": {"h": "#3b2a30", "n": "#8a5a3c", "w": "#e0905a", "k": "#3b2a30"},
        "rows": [
            "..hh...",
            "..nn...",
            "..nn...",
            "..nn...",
            "..nn...",
            "..nn...",
            ".wwww..",
            "wwwwww.",
            "wwkkww.",
            "wwkkww.",
            "wwwwww.",
            ".wwww..",
            "wwwwww.",
            "wwwwww.",
            ".wwww..",
        ],
    },
    "toys": {  # a teetering stack of blocks
        "palette": {"r": "#e05a5a", "b": "#5d8fe0", "y": "#ffd84d", "g": "#5cbf6a", "p": "#c78cff"},
        "rows": [
            "...rr.....",
            "...rr.....",
            "..bbbb....",
            "..bbbb....",
            ".yyy.ggg..",
            ".yyy.ggg..",
            "pppp.rrrr.",
            "pppp.rrrr.",
        ],
    },
    "trash_can": {
        "palette": {"g": "#8a93a3", "d": "#6d7688"},
        "rows": [
            ".ggggggg.",
            "ggggggggg",
            ".ddddddd.",
            ".ggggggg.",
            ".gdgdgdg.",
            ".gdgdgdg.",
            ".gdgdgdg.",
            ".gdgdgdg.",
            ".ggggggg.",
            "..ggggg..",
        ],
    },
    "garbage": {  # spill from a knocked-over trash can
        "palette": {"a": "#c9b18a", "b": "#e8d35c", "c": "#e05a5a"},
        "rows": [
            "..b.a..c..",
            ".abbca.aa.",
            "aacbbaacb.",
            ".a..cba...",
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
