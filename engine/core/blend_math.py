from __future__ import annotations

import numpy as np


def clamp01(x: np.ndarray) -> np.ndarray:
    return np.clip(x, 0.0, 1.0)


def blend_linear(
    mosaic: np.ndarray,
    target: np.ndarray,
    alpha: float,
) -> np.ndarray:
    """
    Blend contract:
    - alpha is TARGET strength in [0..1]
    - alpha = 0   => output == mosaic
    - alpha = 1   => output == target
    """
    if mosaic.shape != target.shape:
        raise ValueError(f"Shape mismatch: mosaic{mosaic.shape} vs target{target.shape}")
    if mosaic.dtype != np.float32 or target.dtype != np.float32:
        raise TypeError("mosaic and target must be float32 in [0..1]. Convert upstream.")
    a = float(alpha)
    if not (0.0 <= a <= 1.0):
        raise ValueError(f"alpha must be in [0..1], got {alpha}")

    out = (1.0 - a) * mosaic + a * target
    return clamp01(out)


def apply_focus_mask(
    alpha_map: np.ndarray,
    focus_mask: np.ndarray,
    focus_boost: float,
) -> np.ndarray:
    """
    Increase alpha toward 1 inside focus mask:
    a' = a + (1-a) * (mask * focus_boost)
    """
    if alpha_map.shape[:2] != focus_mask.shape[:2]:
        raise ValueError("alpha_map and focus_mask must share H,W")
    if alpha_map.dtype != np.float32 or focus_mask.dtype != np.float32:
        raise TypeError("alpha_map and focus_mask must be float32 in [0..1].")

    fb = float(focus_boost)
    if not (0.0 <= fb <= 1.0):
        raise ValueError(f"focus_boost must be in [0..1], got {focus_boost}")

    a = alpha_map
    m = focus_mask
    out = a + (1.0 - a) * (m * fb)
    return clamp01(out)


def blend_with_alpha_map(
    mosaic: np.ndarray,
    target: np.ndarray,
    alpha_map: np.ndarray,
) -> np.ndarray:
    """
    Per-pixel blend where alpha_map is TARGET strength:
    alpha_map=0 => mosaic
    alpha_map=1 => target
    """
    if mosaic.shape != target.shape:
        raise ValueError(f"Shape mismatch: mosaic{mosaic.shape} vs target{target.shape}")
    if mosaic.dtype != np.float32 or target.dtype != np.float32:
        raise TypeError("mosaic and target must be float32 in [0..1]. Convert upstream.")

    if alpha_map.dtype != np.float32:
        raise TypeError("alpha_map must be float32 in [0..1].")
    if alpha_map.ndim == 2:
        a = alpha_map[:, :, None]
    elif alpha_map.ndim == 3 and alpha_map.shape[2] in (1, 3):
        a = alpha_map[:, :, :1]
    else:
        raise ValueError("alpha_map must be (H,W) or (H,W,1/3)")

    if a.shape[0] != mosaic.shape[0] or a.shape[1] != mosaic.shape[1]:
        raise ValueError("alpha_map H,W must match images H,W")

    a = clamp01(a)
    out = (1.0 - a) * mosaic + a * target
    return clamp01(out)


def ellipse_mask(
    h: int,
    w: int,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    feather: float = 0.08,
) -> np.ndarray:
    """
    Soft ellipse mask in [0..1], float32, shape (H,W).
    """
    if h <= 0 or w <= 0:
        raise ValueError("Invalid h,w")
    if rx <= 0 or ry <= 0:
        raise ValueError("rx, ry must be > 0")
    f = float(feather)
    if f < 0.0:
        raise ValueError("feather must be >= 0")

    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx - cx) / rx
    ny = (yy - cy) / ry
    d = np.sqrt(nx * nx + ny * ny)

    fw = max(1e-6, f)
    t = (d - (1.0 - fw)) / (2.0 * fw)
    t = clamp01(t)

    s = t * t * (3.0 - 2.0 * t)
    mask = 1.0 - s
    return mask.astype(np.float32)
