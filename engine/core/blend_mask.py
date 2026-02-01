import math


def _clamp01(x: float) -> float:
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def _smoothstep(t: float) -> float:
    t = _clamp01(t)
    return t * t * (3.0 - 2.0 * t)


def alpha_at(x: float, y: float, blend: dict) -> float:
    """
    x,y in [0..1]
    Returns alpha where:
      - inside ellipse => alpha_center
      - outside ellipse => alpha_edge
      - feather controls the transition width
    """
    cx = float(blend["center_x"])
    cy = float(blend["center_y"])
    rx = max(float(blend["ellipse_rx"]), 1e-6)
    ry = max(float(blend["ellipse_ry"]), 1e-6)
    feather = max(float(blend["feather"]), 1e-6)

    a_center = float(blend["alpha_center"])
    a_edge = float(blend["alpha_edge"])

    dx = (x - cx) / rx
    dy = (y - cy) / ry
    dist = math.sqrt(dx * dx + dy * dy)  # <=1 inside ellipse

    # transition from dist=1 to dist=1+feather
    t = (dist - 1.0) / feather
    s = _smoothstep(t)

    return (1.0 - s) * a_center + s * a_edge
