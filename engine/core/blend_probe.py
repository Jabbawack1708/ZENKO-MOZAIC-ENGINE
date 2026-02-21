from __future__ import annotations

import os
import numpy as np
from PIL import Image

from engine.core.blend_math import (
    blend_linear,
    ellipse_mask,
    apply_focus_mask,
    blend_with_alpha_map,
)


def to_float01(img: Image.Image) -> np.ndarray:
    arr = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    return arr


def to_img(arr: np.ndarray) -> Image.Image:
    arr = np.clip(arr, 0.0, 1.0)
    out = (arr * 255.0).astype(np.uint8)
    return Image.fromarray(out, mode="RGB")


def main() -> None:
    target_path = "data/target/target.jpg"
    mosaic_path = "data/target/mosaic_debug_resized.png"

    if not os.path.exists(target_path):
        raise FileNotFoundError(f"Missing {target_path}")
    if not os.path.exists(mosaic_path):
        raise FileNotFoundError(f"Missing {mosaic_path}")

    target = to_float01(Image.open(target_path))
    mosaic = to_float01(Image.open(mosaic_path))

    if target.shape != mosaic.shape:
        raise ValueError(
            f"target and mosaic must have same shape for probe.\n"
            f"target={target.shape} mosaic={mosaic.shape}\n"
            f"Tip: make mosaic_debug same resolution as target."
        )

    os.makedirs("output/blend_probe", exist_ok=True)

    out_a0 = blend_linear(mosaic, target, alpha=0.0)
    out_a1 = blend_linear(mosaic, target, alpha=1.0)
    out_a15 = blend_linear(mosaic, target, alpha=0.15)

    to_img(out_a0).save("output/blend_probe/alpha_0_must_equal_mosaic.jpg")
    to_img(out_a1).save("output/blend_probe/alpha_1_must_equal_target.jpg")
    to_img(out_a15).save("output/blend_probe/alpha_015.jpg")

    h, w = target.shape[:2]
    base_alpha = np.full((h, w), 0.12, dtype=np.float32)

    m1 = ellipse_mask(h, w, cx=w * 0.5, cy=h * 0.48, rx=w * 0.18, ry=h * 0.28, feather=0.06)

    alpha_focus = apply_focus_mask(base_alpha, m1, focus_boost=0.70)
    out_focus = blend_with_alpha_map(mosaic, target, alpha_focus)

    to_img(out_focus).save("output/blend_probe/focus_ellipse_boost.jpg")

    Image.fromarray((m1 * 255).astype(np.uint8), mode="L").save("output/blend_probe/mask_ellipse.jpg")
    Image.fromarray((alpha_focus * 255).astype(np.uint8), mode="L").save("output/blend_probe/alpha_map.jpg")

    print("OK. Check output/blend_probe/*.jpg")


if __name__ == "__main__":
    main()
