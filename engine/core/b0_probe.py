from configs.default import CONFIG
from engine.profiles.premium_subject_focus import PROFILE
from engine.core.blend_mask import compute_blend_stats


def run_probe():
    # Use profile output as the reference resolution for the probe
    w = int(PROFILE["output"]["width"])
    h = int(PROFILE["output"]["height"])
    blend_cfg = PROFILE["blend"]

    stats = compute_blend_stats(w, h, blend_cfg, step=40)

    print("=== B0 PROBE ===")
    print(f"config.engine.profile (default.py): {CONFIG['engine']['profile']}")
    print(f"profile.name (premium_subject_focus): {PROFILE['name']}")
    print("")
    print(f"resolution: {stats.width}x{stats.height}")
    print(f"alpha_center: {stats.alpha_center}")
    print(f"alpha_edge  : {stats.alpha_edge}")
    print("")
    print(f"min_alpha : {stats.min_alpha:.4f}")
    print(f"max_alpha : {stats.max_alpha:.4f}")
    print(f"mean_alpha: {stats.mean_alpha:.4f}")
    print(f"mean_center (dist<=0.25): {stats.mean_center:.4f}")
    print(f"mean_edges  (dist>=0.55): {stats.mean_edges:.4f}")

    # Acceptance: edges should be higher than center in PREMIUM_SUBJECT_FOCUS
    if stats.mean_edges <= stats.mean_center:
        raise RuntimeError("B0 probe failed: edges are not more mosaic than center (mean_edges <= mean_center)")

    print("\n[OK] B0 probe passed: edges > center")


if __name__ == "__main__":
    run_probe()
