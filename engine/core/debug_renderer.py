from __future__ import annotations

import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

from PIL import Image, ImageFilter

from engine.core.color_match import TileFeature, build_tile_feature_cache, distance_lab, mean_lab


@dataclass
class TargetMatchConfig:
    raw_tiles_dir: str
    target_path: str
    out_path: str

    grid_w: int
    grid_h: int
    tile_size: int

    # matching
    sample: int = 0          # 0 => use all feats (more stable, slower)
    top_k: int = 25          # consider best K matches
    seed: int = 123          # deterministic

    # diversity / A3 (center priority)
    a3_enable: bool = True
    k_center: float = 1.30
    k_edge: float = 0.05
    cap_center: int = 3

    # portrait-first blend (target dominance)
    alpha_center: float = 0.70
    alpha_edge: float = 0.12
    ellipse_rx: float = 0.38
    ellipse_ry: float = 0.55

    # anti-noise (tile-level)
    tile_blur: int = 0       # 0 = off, else GaussianBlur radius

    # selection strategy (IMPORTANT for noise)
    pick_mode: str = "best"  # "best" (stable) or "topk_random" (more variety, more noise)


def _in_ellipse(r: int, c: int, grid_w: int, grid_h: int, rx: float, ry: float) -> bool:
    nx = ((c + 0.5) / grid_w) * 2.0 - 1.0
    ny = ((r + 0.5) / grid_h) * 2.0 - 1.0
    return (nx * nx) / (rx * rx) + (ny * ny) / (ry * ry) <= 1.0


def _tile_path(raw_tiles_dir: str, tile_id: str) -> Path:
    return Path(raw_tiles_dir) / tile_id


def _load_tile(tile_file: Path, tile_size: int, blur_radius: int) -> Image.Image | None:
    try:
        with Image.open(tile_file) as im:
            tile = im.convert("RGB").resize((tile_size, tile_size), resample=Image.BILINEAR)
            if blur_radius and blur_radius > 0:
                tile = tile.filter(ImageFilter.GaussianBlur(radius=float(blur_radius)))
            return tile
    except Exception:
        return None


def _compute_target_cell_labs(
    target_img: Image.Image, grid_w: int, grid_h: int, tile_size: int
) -> List[Tuple[float, float, float]]:
    # resize target exactly to mosaic size
    w, h = grid_w * tile_size, grid_h * tile_size
    t = target_img.convert("RGB").resize((w, h), resample=Image.BILINEAR)

    labs: List[Tuple[float, float, float]] = []
    for r in range(grid_h):
        for c in range(grid_w):
            box = (c * tile_size, r * tile_size, (c + 1) * tile_size, (r + 1) * tile_size)
            patch = t.crop(box)
            labs.append(mean_lab(patch))
    return labs


def render_target_match_debug(cfg: TargetMatchConfig) -> Dict[str, int]:
    raw_dir = Path(cfg.raw_tiles_dir)
    target_path = Path(cfg.target_path)
    out_path = Path(cfg.out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not target_path.exists():
        raise FileNotFoundError(f"Target not found: {target_path}")

    # Build / load tile features cache
    cache_path = str(out_path.parent / "tile_features_lab.json")
    feats: List[TileFeature] = build_tile_feature_cache(str(raw_dir), cache_path, limit=None)
    if not feats:
        raise RuntimeError(f"No usable tiles found in: {raw_dir}")

    # Load target
    with Image.open(target_path) as tim:
        target_img = tim.convert("RGB")

    # Precompute target cell LABs
    target_labs = _compute_target_cell_labs(target_img, cfg.grid_w, cfg.grid_h, cfg.tile_size)

    rng = random.Random(int(cfg.seed))

    # Helper: candidates for this cell
    def sample_features() -> List[TileFeature]:
        if cfg.sample and cfg.sample > 0 and cfg.sample < len(feats):
            # deterministic sampling per run (same seed => same sampled pools)
            return rng.sample(feats, cfg.sample)
        return feats

    # counts for diversity / repetition
    center_counts: Dict[str, int] = {}
    cap_fallbacks = 0
    max_center_repeat = 0

    # compose mosaic
    W, H = cfg.grid_w * cfg.tile_size, cfg.grid_h * cfg.tile_size
    mosaic = Image.new("RGB", (W, H), (220, 220, 220))

    for r in range(cfg.grid_h):
        for c in range(cfg.grid_w):
            idx = r * cfg.grid_w + c
            t_lab = target_labs[idx]

            is_center = _in_ellipse(r, c, cfg.grid_w, cfg.grid_h, cfg.ellipse_rx, cfg.ellipse_ry)
            k = cfg.k_center if is_center else cfg.k_edge

            candidates = sample_features()

            scored: List[Tuple[float, TileFeature]] = []
            for tf in candidates:
                cc = center_counts.get(tf.tile_id, 0)

                # B1: cap reuse only in center
                if is_center and cfg.cap_center > 0 and cc >= cfg.cap_center:
                    continue

                d = distance_lab(t_lab, tf.lab)

                # A3 penalty: stronger in center, weaker on edges
                if cfg.a3_enable and is_center:
                    d = d * (1.0 + (1.0 - math.exp(-k * cc)))
                elif cfg.a3_enable and not is_center:
                    d = d * (1.0 + 0.10 * (1.0 - math.exp(-k * cc)))

                scored.append((d, tf))

            if not scored:
                # cap blocked everything in center -> fallback to least used
                if is_center:
                    cap_fallbacks += 1
                    min_cc = min(center_counts.get(f.tile_id, 0) for f in feats)
                    pool = [f for f in feats if center_counts.get(f.tile_id, 0) == min_cc]
                    tf = rng.choice(pool)
                else:
                    tf = rng.choice(feats)
            else:
                scored.sort(key=lambda x: x[0])
                top = scored[: max(1, min(int(cfg.top_k), len(scored)))]

                if cfg.pick_mode == "topk_random":
                    tf = rng.choice([t[1] for t in top])
                else:
                    # "best" = deterministic, less noise
                    tf = top[0][1]

            # load & paste tile
            tile_img = _load_tile(_tile_path(cfg.raw_tiles_dir, tf.tile_id), cfg.tile_size, cfg.tile_blur)
            if tile_img is None:
                continue

            mosaic.paste(tile_img, (c * cfg.tile_size, r * cfg.tile_size))

            # update counts
            if is_center:
                center_counts[tf.tile_id] = center_counts.get(tf.tile_id, 0) + 1
                if center_counts[tf.tile_id] > max_center_repeat:
                    max_center_repeat = center_counts[tf.tile_id]

    # Portrait-first blend with target
    target_resized = target_img.resize((W, H), resample=Image.BILINEAR)
    blended = Image.new("RGB", (W, H))

    for r in range(cfg.grid_h):
        for c in range(cfg.grid_w):
            is_center = _in_ellipse(r, c, cfg.grid_w, cfg.grid_h, cfg.ellipse_rx, cfg.ellipse_ry)
            alpha = float(cfg.alpha_center) if is_center else float(cfg.alpha_edge)

            box = (c * cfg.tile_size, r * cfg.tile_size, (c + 1) * cfg.tile_size, (r + 1) * cfg.tile_size)
            m_patch = mosaic.crop(box)
            t_patch = target_resized.crop(box)

            # blended = alpha*target + (1-alpha)*mosaic
            blended_patch = Image.blend(m_patch, t_patch, alpha=alpha)
            blended.paste(blended_patch, box[:2])

    blended.save(out_path)

    return {
        "tiles_total": int(cfg.grid_w * cfg.grid_h),
        "tiles_pool": int(len(feats)),
        "max_center_repeat": int(max_center_repeat),
        "cap_fallbacks": int(cap_fallbacks),
    }
