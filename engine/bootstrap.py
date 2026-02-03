import math
import random
from pathlib import Path

from engine.profiles.registry import load_profile
from engine.core.a3_probe import run_a3_probe


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

    # --------------------------------------------------
    # V0 GRID SIMULATION (design-only, no image output)
    # --------------------------------------------------
    output = profile["output"]
    tiles_cfg = profile["tiles"]
    blend_cfg = profile["blend"]

    tile_size = tiles_cfg["size"]
    grid_w = output["width"] // tile_size
    grid_h = output["height"] // tile_size

    print("-" * 50)
    print(f"[V0] Simulating grid {grid_w} x {grid_h}")

    # Fake tile pool
    fake_tiles = [f"tile_{i:04d}" for i in range(200)]

    # --------------------------------------------------
    # A3 DIVERSITY (soft cap) - reduce repeats in center
    # --------------------------------------------------
    a3 = profile.get("a3_diversity", {})
    a3_enable = bool(a3.get("enable", True))

    # Strength of penalty (bigger => fewer repeats)
    k_center = float(a3.get("k_center", 0.25))
    k_edge = float(a3.get("k_edge", 0.05))

    # Optional global cap (0 disables). With V0 we recommend 0 (disabled).
    cap = int(a3.get("cap", 0))

    rng = random.Random(int(tiles_cfg.get("seed", 123)))

    def in_ellipse_cell(r: int, c: int) -> bool:
        nx = ((c + 0.5) / grid_w) * 2.0 - 1.0
        ny = ((r + 0.5) / grid_h) * 2.0 - 1.0
        return (nx * nx) / (blend_cfg["ellipse_rx"] ** 2) + (ny * ny) / (blend_cfg["ellipse_ry"] ** 2) <= 1.0

    # Precompute center mask (runs once, deterministic)
    center_mask = [[in_ellipse_cell(r, c) for c in range(grid_w)] for r in range(grid_h)]

    center_counts = {}
    global_counts = {}

    def weighted_pick(is_center: bool) -> str:
        # Soft penalty: weight decays as a tile repeats in CENTER
        k = k_center if is_center else k_edge

        weights = []
        total_w = 0.0
        for tid in fake_tiles:
            cc = center_counts.get(tid, 0)
            gc = global_counts.get(tid, 0)

            if cap > 0 and gc >= cap:
                w = 0.0
            else:
                w = math.exp(-k * cc) if a3_enable else 1.0

            weights.append(w)
            total_w += w

        if total_w <= 0.0:
            return rng.choice(fake_tiles)

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

            if is_center:
                center_counts[tid] = center_counts.get(tid, 0) + 1
            global_counts[tid] = global_counts.get(tid, 0) + 1

    print(f"[V0] Total placements: {len(placements)}")

    # Debug: top repeated tiles in center
    top = sorted(center_counts.items(), key=lambda kv: kv[1], reverse=True)[:10]
    print("[A3DBG] Top center repeats:", top)

    # --------------------------------------------------
    # A3 PROBE (duplication rate inside ellipse)
    # --------------------------------------------------
    res = run_a3_probe(
        placements=placements,
        grid_w=grid_w,
        grid_h=grid_h,
        ellipse_rx=blend_cfg["ellipse_rx"],
        ellipse_ry=blend_cfg["ellipse_ry"],
    )

    print("-" * 50)
    print("[A3] Center total tiles :", res.center_total)
    print("[A3] Center unique tiles:", res.center_unique)
    print("[A3] Center dup rate    :", round(res.center_dup_rate, 4))
    print("-" * 50)
