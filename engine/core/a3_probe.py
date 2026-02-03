from __future__ import annotations
from dataclasses import dataclass
from typing import Iterable, Tuple


@dataclass
class A3ProbeResult:
    center_total: int
    center_unique: int
    center_dup_rate: float


def _in_ellipse(nx: float, ny: float, rx: float, ry: float) -> bool:
    v = (nx * nx) / (rx * rx) + (ny * ny) / (ry * ry)
    return v <= 1.0


def run_a3_probe(
    placements: Iterable[Tuple[int, int, str]],
    grid_w: int,
    grid_h: int,
    ellipse_rx: float,
    ellipse_ry: float,
) -> A3ProbeResult:
    center_ids = []

    for r, c, tile_id in placements:
        # Normalize cell center to [-1, 1] range
        nx = ((c + 0.5) / grid_w) * 2.0 - 1.0
        ny = ((r + 0.5) / grid_h) * 2.0 - 1.0

        if _in_ellipse(nx, ny, ellipse_rx, ellipse_ry):
            center_ids.append(tile_id)

    total = len(center_ids)
    unique = len(set(center_ids))
    dup_rate = 0.0 if total == 0 else 1.0 - (unique / total)

    return A3ProbeResult(total, unique, dup_rate)
