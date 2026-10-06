"""A 5x7 pixel font exported as a BMFont (.fnt + .png) and a title logo built from it.

Godot imports BMFont text files natively as a FontFile, so the font needs no
extra tooling. Lowercase letters map onto the uppercase glyphs (all-caps,
retro style) except ``x``, which has its own smaller glyph for counters.
"""

from PIL import Image

from .palette import C

GLYPHS = {
    "A": ".###.|#...#|#...#|#####|#...#|#...#|#...#",
    "B": "####.|#...#|#...#|####.|#...#|#...#|####.",
    "C": ".###.|#...#|#....|#....|#....|#...#|.###.",
    "D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
    "E": "#####|#....|#....|####.|#....|#....|#####",
    "F": "#####|#....|#....|####.|#....|#....|#....",
    "G": ".###.|#...#|#....|#.###|#...#|#...#|.####",
    "H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
    "I": ".###.|..#..|..#..|..#..|..#..|..#..|.###.",
    "J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
    "K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
    "L": "#....|#....|#....|#....|#....|#....|#####",
    "M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
    "N": "#...#|#...#|##..#|#.#.#|#..##|#...#|#...#",
    "O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
    "P": "####.|#...#|#...#|####.|#....|#....|#....",
    "Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
    "R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
    "S": ".####|#....|#....|.###.|....#|....#|####.",
    "T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
    "U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
    "V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
    "W": "#...#|#...#|#...#|#.#.#|#.#.#|#.#.#|.#.#.",
    "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
    "Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
    "Z": "#####|....#|...#.|..#..|.#...|#....|#####",
    "0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
    "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
    "2": ".###.|#...#|....#|...#.|..#..|.#...|#####",
    "3": "####.|....#|....#|.###.|....#|....#|####.",
    "4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
    "5": "#####|#....|####.|....#|....#|#...#|.###.",
    "6": "..##.|.#...|#....|####.|#...#|#...#|.###.",
    "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
    "8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
    "9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
    "!": "..#..|..#..|..#..|..#..|..#..|.....|..#..",
    "?": ".###.|#...#|....#|...#.|..#..|.....|..#..",
    ".": ".....|.....|.....|.....|.....|.....|..#..",
    ",": ".....|.....|.....|.....|.....|..#..|.#...",
    ":": ".....|..#..|.....|.....|.....|..#..|.....",
    "'": "..#..|..#..|.#...|.....|.....|.....|.....",
    '"': ".#.#.|.#.#.|.....|.....|.....|.....|.....",
    "-": ".....|.....|.....|.###.|.....|.....|.....",
    "/": "....#|....#|...#.|..#..|.#...|#....|#....",
    "+": ".....|..#..|..#..|#####|..#..|..#..|.....",
    "=": ".....|.....|#####|.....|#####|.....|.....",
    "(": "...#.|..#..|.#...|.#...|.#...|..#..|...#.",
    ")": ".#...|..#..|...#.|...#.|...#.|..#..|.#...",
    "%": "##..#|##.#.|...#.|..#..|.#...|.#.##|#..##",
    "#": ".#.#.|#####|.#.#.|.#.#.|.#.#.|#####|.#.#.",
    "_": ".....|.....|.....|.....|.....|.....|#####",
    "*": ".....|.#.#.|..#..|#####|..#..|.#.#.|.....",
    "x": ".....|.....|#...#|.#.#.|..#..|.#.#.|#...#",
}

GLYPH_W, GLYPH_H = 5, 7
CELL_W, CELL_H = 6, 9          # glyph + 1px gutter on the right/bottom of each cell
PER_ROW = 16
SPACE_ADVANCE = 4


def glyph_bitmap(ch: str) -> list:
    return GLYPHS[ch].split("|")


def build_font() -> tuple:
    """Return (texture, fnt text) for Godot's BMFont importer."""
    chars = list(GLYPHS.keys())
    rows = (len(chars) + PER_ROW - 1) // PER_ROW
    tex = Image.new("RGBA", (PER_ROW * CELL_W, max(rows * CELL_H, 1)), (0, 0, 0, 0))
    entries = [f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance={SPACE_ADVANCE} page=0 chnl=15"]
    positions = {}
    for i, ch in enumerate(chars):
        ox, oy = (i % PER_ROW) * CELL_W, (i // PER_ROW) * CELL_H
        for y, row in enumerate(glyph_bitmap(ch)):
            for x, bit in enumerate(row):
                if bit == "#":
                    tex.putpixel((ox + x, oy + y), (255, 255, 255, 255))
        positions[ch] = (ox, oy)
    for ch, (ox, oy) in positions.items():
        entries.append(f"char id={ord(ch)} x={ox} y={oy} width={GLYPH_W} height={GLYPH_H} "
                       f"xoffset=0 yoffset=1 xadvance={GLYPH_W + 1} page=0 chnl=15")
    for ch in "abcdefghijklmnopqrstuvwyz":      # lowercase reuses uppercase glyphs ('x' has its own)
        ox, oy = positions[ch.upper()]
        entries.append(f"char id={ord(ch)} x={ox} y={oy} width={GLYPH_W} height={GLYPH_H} "
                       f"xoffset=0 yoffset=1 xadvance={GLYPH_W + 1} page=0 chnl=15")
    header = [
        ('info face="GladePixel" size=8 bold=0 italic=0 charset="" unicode=1 stretchH=100 '
         'smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0'),
        (f"common lineHeight=10 base=8 scaleW={tex.width} scaleH={tex.height} pages=1 packed=0 "
         "alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4"),
        'page id=0 file="pixel_font.png"',
        f"chars count={len(entries)}",
    ]
    return tex, "\n".join(header + entries) + "\n"


def text_mask(text: str, scale: int) -> set:
    """Pixel set for ``text`` rendered with the font at an integer scale."""
    pts, x = set(), 0
    for ch in text:
        if ch == " ":
            x += SPACE_ADVANCE * scale
            continue
        for gy, row in enumerate(glyph_bitmap(ch)):
            for gx, bit in enumerate(row):
                if bit == "#":
                    for sy in range(scale):
                        for sx in range(scale):
                            pts.add((x + gx * scale + sx, gy * scale + sy))
        x += (GLYPH_W + 1) * scale
    return pts


def build_logo(text: str = "GLADE QUEST", scale: int = 3) -> Image.Image:
    """Gold gradient lettering with a thick dark outline and a drop shadow."""
    fill = text_mask(text, scale)
    pad = 3
    w = max(x for x, _ in fill) + 1 + pad * 2 + 2
    h = GLYPH_H * scale + pad * 2 + 2
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    border = set()
    for (x, y) in fill:
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                if abs(dx) + abs(dy) <= 3:
                    border.add((x + dx, y + dy))
    for (x, y) in border:                      # shadow
        out.putpixel((x + pad + 2, y + pad + 2), C["outline"] + (160,))
    for (x, y) in border:
        out.putpixel((x + pad, y + pad), C["outline"] + (255,))
    ramp = ["gold_light", "gold_light", "gold", "gold", "gold", "orange", "orange"]
    for (x, y) in fill:
        band = min(int(y / (GLYPH_H * scale) * len(ramp)), len(ramp) - 1)
        out.putpixel((x + pad, y + pad), C[ramp[band]] + (255,))
    return out
