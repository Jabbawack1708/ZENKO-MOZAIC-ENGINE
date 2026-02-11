from __future__ import annotations

from pathlib import Path
from PIL import Image


def render_mosaic_debug(
    placements,
    grid_w: int,
    grid_h: int,
    tile_size: int,
    raw_tiles_dir: str,
    output_path,
) -> None:
    """
    Debug render:
    - loads images from raw_tiles_dir using tile_id as filename
    - resizes to tile_size x tile_size
    - pastes them on a grid
    - saves to output_path
    """

    raw_dir = Path(raw_tiles_dir)
    out_path = Path(output_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGB", (grid_w * tile_size, grid_h * tile_size))

    cache: dict[str, Image.Image] = {}

    for r, c, tile_id in placements:
        tile_path = raw_dir / tile_id

        if tile_id not in cache:
            try:
                img = Image.open(tile_path).convert("RGB")
                img = img.resize((tile_size, tile_size), Image.BILINEAR)
                cache[tile_id] = img
            except Exception:
                # unreadable/corrupt image -> red square
                cache[tile_id] = Image.new("RGB", (tile_size, tile_size), (255, 0, 0))

        canvas.paste(cache[tile_id], (c * tile_size, r * tile_size))

    canvas.save(out_path)
