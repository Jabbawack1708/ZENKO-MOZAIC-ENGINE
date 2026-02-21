import math
import random
from pathlib import Path

from engine.profiles.registry import load_profile
from engine.core.a3_probe import run_a3_probe
from engine.core.a3_viz import render_a3_ascii_map
from engine.core.debug_renderer import TargetMatchConfig, render_target_match_debug


def run(config: dict):
    engine = config["engine"]
    paths = config["paths"]

    profile_name = engine.get("profile", "")
    profile = load_profile(profile_name)

    print("=" * 50)
    print(f"Starting {engine['name']}")
    print(f"Version : {engine['version']}")
    print(f"Profile : {profile['name']}")
    print("=" * 50)

    # --------------------------------------------------
    # Create required directories
    # --------------------------------------------------
    for key, rel_path in paths.items():
        path = Path(rel_path)
        path.mkdir(parents=True, exist_ok=True)
        print(f"[OK] {key} directory -> {path.resolve()}")

    output = profile["output"]
    tiles_cfg = profile["tiles"]
    blend_cfg = profile["blend"]

    tile_size = int(tiles_cfg["size"])
    grid_w = output["width"] // tile_size
    grid_h = output["height"] // tile_size

    print("-" * 50)
    print(f"[V0] Simulating grid {grid_w} x {grid_h}")

    # --------------------------------------------------
    # REAL TILE POOL (fallback to fake)
    # --------------------------------------------------
    def list_tile_ids(folder: str) -> list[str]:
        exts = {".jpg", ".jpeg", ".png", ".webp"}
        p = Path(folder)
        if not p.exists() or not p.is_dir():
            return []
        files = []
        for f in p.iterdir():
            if f.is_file() and f.suffix.lower() in exts:
                files.append(f.name)
        files.sort()
        return files

    raw_tiles_dir = str(paths.get("raw_tiles", "data/raw_tiles"))
    tile_ids = list_tile_ids(raw_tiles_dir)

    if tile_ids:
        max_tiles = int(tiles_cfg.get("max", len(tile_ids)))
        tile_ids = tile_ids[:max_tiles]
        print(f"[V0] Using REAL tiles from {raw_tiles_dir} (count={len(tile_ids)})")
    else:
        tile_ids = [f"tile_{i:04d}" for i in range(80)]
        print(f"[V0] Using FAKE tiles (count={len(tile_ids)})")

    fake_tiles = tile_ids

    # --------------------------------------------------
    # A3 DIVERSITY (soft cap) - reduce repeats in center
    # --------------------------------------------------
    a3 = profile.get("a3_diversity", {})
    a3_enable = bool(a3.get("enable", True))
    k_center = float(a3.get("k_center", 1.30))
    k_edge = float(a3.get("k_edge", 0.05))
    cap = int(a3.get("cap_override", a3.get("cap", 0)))

    print(f"[A3CFG] enable={a3_enable} k_center={k_center} k_edge={k_edge} cap={cap}")

    rng = random.Random(int(tiles_cfg.get("seed", 123)))

    def in_ellipse_cell(r: int, c: int) -> bool:
        nx = ((c + 0.5) / grid_w) * 2.0 - 1.0
        ny = ((r + 0.5) / grid_h) * 2.0 - 1.0
        return (nx * nx) / (blend_cfg["ellipse_rx"] ** 2) + (ny * ny) / (blend_cfg["ellipse_ry"] ** 2) <= 1.0

    center_mask = [[in_ellipse_cell(r, c) for c in range(grid_w)] for r in range(grid_h)]

    center_counts = {}
    global_counts = {}
    cap_fallbacks = 0

    def weighted_pick(is_center: bool) -> str:
        nonlocal cap_fallbacks
        k = k_center if is_center else k_edge

        weights = []
        total_w = 0.0
        for tid in fake_tiles:
            cc = center_counts.get(tid, 0)

            if is_center and cap > 0 and cc >= cap:
                w = 0.0
            else:
                w = math.exp(-k * cc) if a3_enable else 1.0

            weights.append(w)
            total_w += w

        if total_w <= 0.0:
            cap_fallbacks += 1
            min_cc = min(center_counts.get(t, 0) for t in fake_tiles)
            candidates = [t for t in fake_tiles if center_counts.get(t, 0) == min_cc]
            return rng.choice(candidates)

        x = rng.random() * total_w
        acc = 0.0
        for tid, w in zip(fake_tiles, weights):
            acc += w
            if acc >= x:
                return tid
        return fake_tiles[-1]

    placements = []
    for r in range(grid_h):
        for c in range(grid_w):
            is_center = center_mask[r][c]
            tid = weighted_pick(is_center)
            placements.append((r, c, tid))

            global_counts[tid] = global_counts.get(tid, 0) + 1
            if is_center:
                center_counts[tid] = center_counts.get(tid, 0) + 1

    top = sorted(center_counts.items(), key=lambda kv: kv[1], reverse=True)[:10]
    max_rep = top[0][1] if top else 0
    print("[B1DBG] Top center repeats:", top)
    print(f"[B1DBG] max_center_repeat={max_rep} (target <= {cap}) cap_fallbacks={cap_fallbacks}")

    res = run_a3_probe(
        placements=placements,
        grid_w=grid_w,
        grid_h=grid_h,
        ellipse_rx=blend_cfg["ellipse_rx"],
        ellipse_ry=blend_cfg["ellipse_ry"],
    )
    print("[A3] Center total tiles :", res.center_total)
    print("[A3] Center unique tiles:", res.center_unique)
    print("[A3] Center dup rate    :", round(res.center_dup_rate, 4))

    # ASCII proof (optional)
    render_a3_ascii_map(
        placements=placements,
        grid_w=grid_w,
        grid_h=grid_h,
        ellipse_rx=blend_cfg["ellipse_rx"],
        ellipse_ry=blend_cfg["ellipse_ry"],
    )

    # --------------------------------------------------
    # A4 TARGET MATCH DEBUG (LAB + cache + portrait-first blend)
    # --------------------------------------------------
    target_path = str(paths.get("target", "data/target/target.jpg"))
    if not Path(target_path).exists():
        # fallback to png if jpg absent
        if Path("data/target/target.png").exists():
            target_path = "data/target/target.png"

    out_path = str(Path(paths.get("output", "output")) / "mosaic_target_debug.png")

    print("[A4] Rendering target-match debug mosaic...")
    stats = render_target_match_debug(
        TargetMatchConfig(
            raw_tiles_dir=raw_tiles_dir,
            target_path=target_path,
            out_path=out_path,
            grid_w=grid_w,
            grid_h=grid_h,
            tile_size=tile_size,
        tile_blur=int(profile.get("a4_match", {}).get("tile_blur", 0)),

            sample=int(profile.get("a4_match", {}).get("sample", 350)),
            top_k=int(profile.get("a4_match", {}).get("top_k", 25)),
            seed=int(tiles_cfg.get("seed", 123)),
            a3_enable=a3_enable,
            k_center=k_center,
            k_edge=k_edge,
            cap_center=int(profile.get("a4_match", {}).get("cap_center", cap if cap > 0 else 3)),
            alpha_center=float(profile.get("a4_blend", {}).get("alpha_center", 0.70)),
            alpha_edge=float(profile.get("a4_blend", {}).get("alpha_edge", 0.12)),
            ellipse_rx=float(blend_cfg.get("ellipse_rx", 0.38)),
            ellipse_ry=float(blend_cfg.get("ellipse_ry", 0.55)),
        )
    )

    print(f"[A4] Debug image saved -> {out_path}")
    print(f"[A4] tiles_pool={stats['tiles_pool']} max_center_repeat={stats['max_center_repeat']} cap_fallbacks={stats['cap_fallbacks']}")
