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
    # Runs ONCE (outside the paths loop)
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

    placements = []
    idx = 0

    for r in range(grid_h):
        for c in range(grid_w):
            tile_id = fake_tiles[idx % len(fake_tiles)]
            placements.append((r, c, tile_id))
            idx += 1

    print(f"[V0] Total placements: {len(placements)}")

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
