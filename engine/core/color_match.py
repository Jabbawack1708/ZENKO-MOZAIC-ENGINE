from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

from PIL import Image


# -----------------------------
# Color space: sRGB -> CIE Lab (D65)
# -----------------------------
def _srgb_to_linear(c: float) -> float:
    c = c / 255.0
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def _rgb_to_xyz(r: int, g: int, b: int) -> Tuple[float, float, float]:
    # linear RGB
    rl = _srgb_to_linear(r)
    gl = _srgb_to_linear(g)
    bl = _srgb_to_linear(b)

    # sRGB D65
    x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375
    y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750
    z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041
    return (x, y, z)


def _f(t: float) -> float:
    # CIE Lab helper
    delta = 6 / 29
    if t > delta**3:
        return t ** (1 / 3)
    return t / (3 * delta**2) + 4 / 29


def rgb_to_lab(r: int, g: int, b: int) -> Tuple[float, float, float]:
    x, y, z = _rgb_to_xyz(r, g, b)

    # reference white D65
    xn, yn, zn = 0.95047, 1.00000, 1.08883
    fx = _f(x / xn)
    fy = _f(y / yn)
    fz = _f(z / zn)

    L = 116 * fy - 16
    a = 500 * (fx - fy)
    b2 = 200 * (fy - fz)
    return (L, a, b2)


def mean_rgb(img: Image.Image) -> Tuple[int, int, int]:
    # ultra-fast mean via downscale to 1x1
    small = img.convert("RGB").resize((1, 1), resample=Image.BILINEAR)
    r, g, b = small.getpixel((0, 0))
    return int(r), int(g), int(b)


def mean_lab(img: Image.Image) -> Tuple[float, float, float]:
    r, g, b = mean_rgb(img)
    return rgb_to_lab(r, g, b)


@dataclass
class TileFeature:
    tile_id: str
    lab: Tuple[float, float, float]


def _cache_key_for_file(p: Path) -> str:
    st = p.stat()
    return f"{p.name}:{st.st_mtime_ns}:{st.st_size}"


def build_tile_feature_cache(
    raw_tiles_dir: str,
    cache_path: str,
    limit: int | None = None,
) -> List[TileFeature]:
    exts = {".jpg", ".jpeg", ".png", ".webp"}

    root = Path(raw_tiles_dir)
    cache_file = Path(cache_path)
    cache_file.parent.mkdir(parents=True, exist_ok=True)

    if not root.exists() or not root.is_dir():
        return []

    # load existing cache
    existing: Dict[str, Dict] = {}
    if cache_file.exists():
        try:
            existing = json.loads(cache_file.read_text(encoding="utf-8"))
        except Exception:
            existing = {}

    feats: List[TileFeature] = []
    files = [p for p in root.iterdir() if p.is_file() and p.suffix.lower() in exts]
    files.sort(key=lambda p: p.name)

    if limit is not None:
        files = files[: int(limit)]

    new_cache: Dict[str, Dict] = {}
    for p in files:
        key = _cache_key_for_file(p)
        if key in existing:
            lab = tuple(existing[key]["lab"])
            new_cache[key] = {"lab": list(lab)}
            feats.append(TileFeature(tile_id=p.name, lab=lab))  # type: ignore
            continue

        try:
            with Image.open(p) as im:
                lab = mean_lab(im)
        except Exception:
            # skip unreadable tiles
            continue

        new_cache[key] = {"lab": [lab[0], lab[1], lab[2]]}
        feats.append(TileFeature(tile_id=p.name, lab=lab))

    # write cache (atomic)
    tmp = cache_file.with_suffix(".tmp")
    tmp.write_text(json.dumps(new_cache, ensure_ascii=False), encoding="utf-8")
    tmp.replace(cache_file)

    return feats


def distance_lab(a: Tuple[float, float, float], b: Tuple[float, float, float]) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)
