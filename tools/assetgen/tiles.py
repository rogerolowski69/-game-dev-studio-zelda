"""Procedural 16x16 terrain tiles plus the atlas manifest (tiles.json).

The manifest is the single source of truth for the atlas layout: the Godot
world builder (dev/build_world.gd) reads it to create the TileSet, so tile
coordinates are never duplicated by hand.
"""

import random

from PIL import Image, ImageDraw

from .palette import C

T = 16
COLUMNS = 8

# Water edge mask bits: set when the neighbour on that side is land.
N, E, S, W = 1, 2, 4, 8


def _px(name: str) -> tuple:
    return C[name] + (255,)


def _base(name: str) -> Image.Image:
    return Image.new("RGBA", (T, T), _px(name))


def _outline_mask(im: Image.Image, mask: set, color: str = "outline") -> None:
    """Draw a 1px outline just outside the pixels in ``mask``."""
    for (x, y) in list(mask):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < T and 0 <= ny < T and (nx, ny) not in mask:
                im.putpixel((nx, ny), _px(color))


def _disc(cx: float, cy: float, r: float) -> set:
    return {(x, y) for y in range(T) for x in range(T) if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r}


# ----------------------------------------------------------------------- ground

def grass(seed: int) -> Image.Image:
    im = _base("grass")
    r = random.Random(seed)
    for _ in range(6):  # small "v" tufts
        x, y = r.randrange(1, 15), r.randrange(2, 15)
        im.putpixel((x, y), _px("grass_dark"))
        im.putpixel((x - 1, y - 1), _px("grass_light"))
        im.putpixel((x + 1, y - 1), _px("grass_light"))
    for _ in range(5):
        im.putpixel((r.randrange(T), r.randrange(T)), _px("grass_light"))
    for _ in range(3):
        im.putpixel((r.randrange(T), r.randrange(T)), _px("grass_dark"))
    return im


def flowers(seed: int) -> Image.Image:
    im = grass(seed)
    r = random.Random(seed * 7 + 1)
    spots = [(3, 4), (11, 3), (7, 9), (12, 12), (3, 12)]
    r.shuffle(spots)
    for i, (x, y) in enumerate(spots[:4]):
        petal = "white" if i % 2 == 0 else "flower_pink"
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            im.putpixel((x + dx, y + dy), _px(petal))
        im.putpixel((x, y), _px("gold"))
    return im


def sand(seed: int) -> Image.Image:
    im = _base("sand")
    r = random.Random(seed)
    for _ in range(10):
        im.putpixel((r.randrange(T), r.randrange(T)), _px("sand_dark"))
    for _ in range(8):
        im.putpixel((r.randrange(T), r.randrange(T)), _px("sand_light"))
    return im


def stone_floor() -> Image.Image:
    im = _base("stone_light")
    d = ImageDraw.Draw(im)
    for o in (0, 8):
        d.line((o, 0, o, 15), fill=_px("stone"))
        d.line((0, o, 15, o), fill=_px("stone"))
        d.line((o + 1, o + 1, o + 6, o + 1), fill=_px("stone_hi"))
    for (x, y) in ((1, 9), (9, 1), (1, 1), (9, 9)):
        d.line((x, y, x, y + 5), fill=_px("stone_hi"))
    for (x, y) in ((5, 3), (12, 11), (3, 13), (13, 5)):
        im.putpixel((x, y), _px("stone"))
    return im


def cave_floor() -> Image.Image:
    im = _base("cave_dark")
    r = random.Random(77)
    for _ in range(7):
        im.putpixel((r.randrange(T), r.randrange(T)), _px("cave"))
    return im


# ---------------------------------------------------------------------- objects

def tree(seed: int) -> Image.Image:
    im = grass(seed + 100)
    r = random.Random(seed)
    trunk = {(x, y) for x in range(6, 10) for y in range(11, 15)}
    canopy = _disc(8, 6.5, 6.0) | _disc(4.5, 8.5, 3.8) | _disc(11.5, 8.5, 3.8)
    canopy = {(x, y) for (x, y) in canopy if y <= 12}
    for (x, y) in trunk:
        im.putpixel((x, y), _px("trunk_dark" if x >= 8 else "trunk"))
    for (x, y) in canopy:
        shade = (x - 8) * 0.6 + (y - 6) * 0.9 + r.uniform(-1.2, 1.2)
        name = "leaf_light" if shade < -4.5 else "leaf" if shade < 2.5 else "leaf_dark"
        im.putpixel((x, y), _px(name))
    for _ in range(4):  # leaf highlights
        x, y = r.randrange(3, 10), r.randrange(2, 7)
        if (x, y) in canopy:
            im.putpixel((x, y), _px("grass_hi"))
    _outline_mask(im, canopy | trunk)
    return im


def rock_tile() -> Image.Image:
    im = grass(901)
    boulder = {(x, y) for y in range(T) for x in range(T)
               if ((x + 0.5 - 8) / 6.2) ** 2 + ((y + 0.5 - 8.8) / 5.6) ** 2 <= 1}
    for (x, y) in boulder:
        s = (x - 8) + (y - 8.8) * 1.3
        name = "stone_hi" if s < -7 else "stone_light" if s < -2 else "stone" if s < 5 else "stone_dark"
        im.putpixel((x, y), _px(name))
    for (x, y) in ((9, 7), (10, 8), (10, 9)):
        im.putpixel((x, y), _px("stone_dark"))
    _outline_mask(im, boulder)
    return im


def statue() -> Image.Image:
    im = stone_floor()
    body = ({(x, y) for x in range(4, 12) for y in range(12, 15)}          # pedestal
            | {(x, y) for x in range(5, 11) for y in range(6, 12)}          # torso
            | _disc(8, 4.5, 3.2))                                             # head
    for (x, y) in body:
        name = "stone_hi" if x <= 5 else "stone_dark" if x >= 10 else "stone"
        im.putpixel((x, y), _px(name))
    for (x, y) in ((6, 4), (9, 4)):
        im.putpixel((x, y), _px("outline"))           # eyes
    im.putpixel((7, 9), _px("stone_dark"))
    im.putpixel((8, 9), _px("stone_dark"))
    _outline_mask(im, body)
    return im


def grave() -> Image.Image:
    im = grass(55)
    stone = ({(x, y) for x in range(4, 12) for y in range(6, 14)} | _disc(8, 6.5, 4.0))
    stone = {(x, y) for (x, y) in stone if y <= 13}
    for (x, y) in stone:
        name = "stone_light" if x <= 5 else "stone_dark" if x >= 11 else "stone"
        im.putpixel((x, y), _px(name))
    for (x, y) in ((8, 5), (8, 6), (8, 7), (8, 8), (7, 6), (9, 6)):
        im.putpixel((x, y), _px("stone_dark"))         # engraved cross
    _outline_mask(im, stone)
    for x in range(3, 13):
        im.putpixel((x, 15), _px("grass_dark"))        # shadow
    return im


def stone_wall() -> Image.Image:
    im = _base("stone")
    d = ImageDraw.Draw(im)
    for row in range(4):
        y = row * 4
        d.line((0, y, 15, y), fill=_px("stone_light"))
        d.line((0, y + 3, 15, y + 3), fill=_px("stone_dark"))
        off = 0 if row % 2 == 0 else 4
        for x in (off, off + 8):
            d.line((x, y, x, y + 3), fill=_px("stone_dark"))
    return im


def cave_wall() -> Image.Image:
    im = _base("cave")
    r = random.Random(31)
    for _ in range(9):
        x, y = r.randrange(0, 14), r.randrange(0, 14)
        w, h = r.randrange(2, 5), r.randrange(2, 4)
        for yy in range(y, min(y + h, T)):
            for xx in range(x, min(x + w, T)):
                im.putpixel((xx, yy), _px("cave_light"))
        for xx in range(x, min(x + w, T)):
            if y + h < T:
                im.putpixel((xx, y + h), _px("cave_dark"))
    return im


def cliff(face: bool) -> Image.Image:
    """Brown rock wall. ``face`` adds the shaded lower edge used where walkable ground is below."""
    im = _base("cliff")
    r = random.Random(13 if face else 12)
    for y in (3, 8, 13):
        x = 0
        while x < T:
            seg = r.randrange(3, 7)
            yy = y + r.choice((0, 0, 1))
            for xx in range(x, min(x + seg, T)):
                im.putpixel((xx, yy), _px("cliff_dark"))
                if yy - 1 >= 0:
                    im.putpixel((xx, yy - 1), _px("cliff_light"))
            x += seg + r.randrange(1, 3)
    for _ in range(3):  # vertical cracks
        x, y = r.randrange(1, 15), r.randrange(0, 10)
        for yy in range(y, y + 3):
            im.putpixel((x, yy), _px("cliff_dark"))
    if face:
        for x in range(T):
            im.putpixel((x, 13), _px("cliff_dark"))
            im.putpixel((x, 14), _px("trunk_dark"))
            im.putpixel((x, 15), _px("outline"))
    return im


def cave_entrance() -> Image.Image:
    im = cliff(face=True)
    hole = {(x, y) for x in range(4, 12) for y in range(7, 16)} | _disc(8, 7.5, 4.0)
    for (x, y) in hole:
        im.putpixel((x, y), _px("outline"))
    _outline_mask(im, hole, "trunk_dark")
    return im


# ------------------------------------------------------------------------- water

def water(mask: int, frame: int) -> Image.Image:
    im = _base("water")
    for (x, y) in ((3, 11), (4, 11), (11, 4), (12, 4), (12, 5)):
        im.putpixel((x, y), _px("water_deep"))
    for (x, y) in ((2, 3), (9, 7), (5, 13), (12, 12)):
        for dx in range(3):
            im.putpixel(((x + dx + frame * 2) % T, y), _px("water_light"))
    for side, rect, inner in ((N, (0, 0, 15, 0), (0, 1, 15, 1)), (S, (0, 15, 15, 15), (0, 14, 15, 14)),
                              (W, (0, 0, 0, 15), (1, 0, 1, 15)), (E, (15, 0, 15, 15), (14, 0, 14, 15))):
        if mask & side:
            d = ImageDraw.Draw(im)
            d.rectangle(inner, fill=_px("water_light"))
            d.rectangle(rect, fill=_px("foam"))
    return im


# ------------------------------------------------------------------------- atlas

def build() -> tuple:
    """Return (atlas image, manifest dict)."""
    named = [
        ("grass_0", grass(1), False, None), ("grass_1", grass(2), False, None),
        ("grass_2", grass(3), False, None), ("flowers", flowers(4), False, None),
        ("sand_0", sand(5), False, None), ("sand_1", sand(6), False, None),
        ("stone_floor", stone_floor(), False, None), ("cave_floor", cave_floor(), False, None),
        ("tree_0", tree(7), True, "chamfer"), ("tree_1", tree(8), True, "chamfer"),
        ("rock", rock_tile(), True, "chamfer"), ("statue", statue(), True, "chamfer"),
        ("grave", grave(), True, "chamfer"), ("stone_wall", stone_wall(), True, "full"),
        ("cave_wall", cave_wall(), True, "full"), ("cliff", cliff(False), True, "full"),
        ("cliff_face", cliff(True), True, "full"), ("cave_entrance", cave_entrance(), False, None),
    ]
    water_row = (len(named) + COLUMNS - 1) // COLUMNS
    rows = water_row + 4  # 16 masks x 2 frames = 32 cells = 4 rows of 8
    atlas = Image.new("RGBA", (COLUMNS * T, rows * T), (0, 0, 0, 0))
    tiles = {}
    for i, (name, im, solid, shape) in enumerate(named):
        x, y = i % COLUMNS, i // COLUMNS
        atlas.alpha_composite(im, (x * T, y * T))
        tiles[name] = {"atlas": [x, y], "solid": solid, "shape": shape}
    for mask in range(16):
        x, y = (mask % 4) * 2, water_row + mask // 4
        atlas.alpha_composite(water(mask, 0), (x * T, y * T))
        atlas.alpha_composite(water(mask, 1), ((x + 1) * T, y * T))
        tiles[f"water_{mask}"] = {"atlas": [x, y], "solid": True, "shape": "full",
                                  "frames": 2, "frame_duration": 0.7}
    manifest = {"tile_size": T, "columns": COLUMNS, "texture": "res://assets/tiles/tiles.png",
                "water_mask_bits": {"N": N, "E": E, "S": S, "W": W}, "tiles": tiles}
    return atlas, manifest
