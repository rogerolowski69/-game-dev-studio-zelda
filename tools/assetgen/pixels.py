"""Small helpers for turning text grids into images and packing sprite sheets."""

from PIL import Image, ImageOps

from .palette import C


def grid(text: str, legend: dict, size: tuple | None = None) -> Image.Image:
    """Render a text grid. ``legend`` maps characters to palette names; '.' is transparent."""
    rows = text.strip("\n").split("\n")
    w, h = size or (len(rows[0]), len(rows))
    if len(rows) != h or any(len(r) != w for r in rows):
        raise ValueError(f"grid must be {w}x{h}, got rows of {[len(r) for r in rows]}")
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            im.putpixel((x, y), C[legend[ch]] + (255,))
    return im


def mirror(im: Image.Image) -> Image.Image:
    return ImageOps.mirror(im)


def sheet(frames: list, columns: int, cell: tuple = (16, 16)) -> Image.Image:
    """Pack equally sized frames left-to-right, top-to-bottom."""
    rows = (len(frames) + columns - 1) // columns
    out = Image.new("RGBA", (cell[0] * columns, cell[1] * rows), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        if frame is None:
            continue
        out.alpha_composite(frame, ((i % columns) * cell[0], (i // columns) * cell[1]))
    return out


def centered(im: Image.Image, size: tuple = (16, 16)) -> Image.Image:
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.alpha_composite(im, ((size[0] - im.width) // 2, (size[1] - im.height) // 2))
    return out


def save(im: Image.Image, path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # optimize=False keeps output byte-stable across Pillow runs.
    im.save(path, optimize=False)
