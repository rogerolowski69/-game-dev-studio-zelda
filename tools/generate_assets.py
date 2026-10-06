#!/usr/bin/env python3
"""Regenerate every art and audio asset of Glade Quest into ../assets.

Usage:  python3 tools/generate_assets.py [--preview DIR]

Requires Pillow and numpy. Output is deterministic. After regenerating, run
Godot once (editor, or `godot --headless --import`) so it re-imports the files,
then rebuild the world if the tile atlas changed:
`godot --headless --path . res://dev/build_world.tscn`.
"""

import argparse
import json
from pathlib import Path

from PIL import Image

from assetgen import audio, font, sprites, tiles
from assetgen.pixels import save

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

SPRITES = {
    "sprites/hero.png": sprites.hero_sheet,
    "sprites/sword.png": sprites.sword,
    "sprites/slime.png": sprites.slime_sheet,
    "sprites/spitter.png": sprites.spitter_sheet,
    "sprites/rock.png": sprites.rock,
    "sprites/sage.png": sprites.sage,
    "sprites/fire.png": sprites.fire_sheet,
    "sprites/items.png": sprites.items_sheet,
    "sprites/gate.png": sprites.gate,
    "sprites/poof.png": sprites.poof_sheet,
    "ui/hud.png": sprites.hud_sheet,
    "ui/title_logo.png": font.build_logo,
}

SFX_PEAK = {"text": 0.4, "hurt": 0.7, "game_over": 0.7, "victory": 0.7, "item_get": 0.7}


def generate(preview_dir: Path | None) -> list:
    written = []

    for rel, fn in SPRITES.items():
        save(fn(), ASSETS / rel)
        written.append(rel)

    atlas, manifest = tiles.build()
    save(atlas, ASSETS / "tiles/tiles.png")
    (ASSETS / "tiles/tiles.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    written += ["tiles/tiles.png", "tiles/tiles.json"]

    tex, fnt = font.build_font()
    save(tex, ASSETS / "fonts/pixel_font.png")
    (ASSETS / "fonts/pixel_font.fnt").write_text(fnt)
    written += ["fonts/pixel_font.png", "fonts/pixel_font.fnt"]

    save(sprites.icon(128), ROOT / "icon.png")
    written.append("../icon.png")

    for name, fn in audio.SFX.items():
        audio.write_wav(ASSETS / f"audio/sfx/{name}.wav", fn(), peak=SFX_PEAK.get(name, 0.75))
        written.append(f"audio/sfx/{name}.wav")
    for name, fn in audio.MUSIC.items():
        audio.write_wav(ASSETS / f"audio/music/{name}.wav", fn(), peak=0.6, loop=True)
        written.append(f"audio/music/{name}.wav")

    if preview_dir:
        _contact_sheet(preview_dir)
    return written


def _contact_sheet(out_dir: Path) -> None:
    """Upscaled overview of all images, for eyeballing changes."""
    images = [Image.open(ASSETS / rel) for rel in list(SPRITES) + ["tiles/tiles.png", "fonts/pixel_font.png"]]
    width = max(im.width for im in images) + 8
    height = sum(im.height + 6 for im in images) + 4
    canvas = Image.new("RGBA", (width, height), (63, 154, 58, 255))
    y = 4
    for im in images:
        canvas.alpha_composite(im.convert("RGBA"), (4, y))
        y += im.height + 6
    out_dir.mkdir(parents=True, exist_ok=True)
    canvas.resize((width * 4, height * 4), Image.NEAREST).save(out_dir / "contact_sheet.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="also write an upscaled contact sheet into this directory")
    args = parser.parse_args()
    written = generate(args.preview)
    print(f"wrote {len(written)} files under {ASSETS.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
