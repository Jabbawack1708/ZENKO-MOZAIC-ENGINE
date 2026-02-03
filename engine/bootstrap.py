import math
import random
from pathlib import Path

from engine.profiles.registry import load_profile
from engine.core.a3_probe import run_a3_probe
from engine.core.a3_viz import render_a3_ascii_map



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
    fake_tiles = [f"tile_{i:04d}" for i in range(80)]

    # --------------------------------------------------
    # A3 DIVERSITY (soft cap) - reduce repeats in center
    # --------------------------------------------------
    a3 = profile.get("a3_diversity", {})
    a3_enable = bool(a3.get("enable", True))
    k_center = float(a3.get("k_center", 1.30))
    k_edge = float(a3.get("k_edge", 0.05))
    cap = int(a3.get("cap", 0))

    print(f"[A3CFG] enable={a3_enable} k_center={k_center} k_edge={k_edge} cap={cap}")

    rng = random.Random(int(tiles_cfg.get("seed", 123)))

    def in_ellipse_cell(r: int, c: int) -> bool:
        nx = ((c + 0.5) / grid_w) * 2.0 - 1.0
        ny = ((r + 0.5) / grid_h) * 2.0 - 1.0
        return (nx * nx) / (blend_cfg["ellipse_rx"] ** 2) + (ny * ny) / (blend_cfg["ellipse_ry"] ** 2) <= 1.0

    center_mask = [[in_ellipse_cell(r, c) for c in range(grid_w)] for r in range(grid_h)]

    center_counts = {}
    global_counts = {}
    center_counts = {}
    cap_fallbacks = 0  # combien de fois CAP a bloqué tous les choix (devrait rester faible)

    def weighted_pick(is_center: bool) -> str:
        """
        B1: CAP appliqué UNIQUEMENT au centre (center_mask).
        - centre: hard cap via center_counts (<= cap) + pénalité A3 exp(-k*cc)
        - bord: pas de cap (portrait-first = centre propre, périphérie libre)
        """
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

    print(f"[B1CFG] cap(center)={cap} a3_enable={a3_enable} k_center={k_center} k_edge={k_edge}")
    top = sorted(center_counts.items(), key=lambda kv: kv[1], reverse=True)[:10]
    max_rep = top[0][1] if top else 0
    print("[B1DBG] Top center repeats:", top)
    print(f"[B1DBG] max_center_repeat={max_rep} (target <= {cap}) cap_fallbacks={cap_fallbacks}")

    print("-" * 50)
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
    print("-" * 50)

    # --------------------------------------------------
    # A3 VISUAL PROOF (PNG outputs)
    # --------------------------------------------------
    render_a3_ascii_map(
    placements=placements,
    grid_w=grid_w,
    grid_h=grid_h,
    ellipse_rx=blend_cfg["ellipse_rx"],
    ellipse_ry=blend_cfg["ellipse_ry"],
)
