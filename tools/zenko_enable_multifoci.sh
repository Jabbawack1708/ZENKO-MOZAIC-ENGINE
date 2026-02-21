#!/usr/bin/env bash
set -euo pipefail

# Guard rails
if [[ ! -f "main.py" || ! -d "engine" ]]; then
  echo "STOP: run from repo root (main.py + engine/). PWD=$(pwd)"
  exit 1
fi

F_DEBUG="engine/core/debug_renderer.py"
F_BOOT="engine/bootstrap.py"
F_PROFILE="engine/profiles/premium_subject_focus.py"

for f in "$F_DEBUG" "$F_BOOT" "$F_PROFILE"; do
  [[ -f "$f" ]] || { echo "STOP: missing file: $f"; exit 1; }
done

python - <<'PY'
from pathlib import Path
import re, sys, json

F_DEBUG  = Path("engine/core/debug_renderer.py")
F_BOOT   = Path("engine/bootstrap.py")
F_PROFILE= Path("engine/profiles/premium_subject_focus.py")

def backup(p: Path):
    b = p.with_suffix(p.suffix + ".bak_multifoci")
    if not b.exists():
        b.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
    return b

def stop(msg):
    raise SystemExit("STOP: " + msg)

# -----------------------
# 1) Patch debug_renderer.py
# - add letterbox helper
# - extend TargetMatchConfig with center_x/center_y + foci
# - make "is_center" based on multi-foci (any ellipse)
# - ensure target sampling/blend uses letterboxed target (no stretch)
# -----------------------
s = F_DEBUG.read_text(encoding="utf-8")
backup(F_DEBUG)

if "def _letterbox_resize" not in s:
    # inject after "from PIL import Image" line (must exist)
    if "from PIL import Image" not in s:
        stop("debug_renderer.py: cannot find 'from PIL import Image' to inject helper.")
    inject = """
def _letterbox_resize(im: Image.Image, size: tuple[int, int], fill=(220, 220, 220)) -> Image.Image:
    \"\"\"Resize preserving aspect ratio, pad to target size (no stretching).\"\"\"
    tw, th = size
    im = im.convert("RGB")
    w, h = im.size
    if w == 0 or h == 0:
        return Image.new("RGB", (tw, th), fill)
    scale = min(tw / w, th / h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    resized = im.resize((nw, nh), resample=Image.BILINEAR)
    canvas = Image.new("RGB", (tw, th), fill)
    ox = (tw - nw) // 2
    oy = (th - nh) // 2
    canvas.paste(resized, (ox, oy))
    return canvas
"""
    s = s.replace("from PIL import Image", "from PIL import Image\n" + inject, 1)

# Extend TargetMatchConfig (dataclass) if fields missing
if "center_x:" not in s or "center_y:" not in s or "foci:" not in s:
    # We anchor near the existing ellipse_rx/ellipse_ry in the dataclass
    pat = re.compile(r"(ellipse_rx:\s*float\s*=\s*[0-9.]+\s*\n\s*ellipse_ry:\s*float\s*=\s*[0-9.]+\s*\n)", re.M)
    m = pat.search(s)
    if not m:
        stop("debug_renderer.py: cannot locate ellipse_rx/ellipse_ry block in TargetMatchConfig.")
    add = m.group(1) + "\n    # focus center (normalized 0..1)\n    center_x: float = 0.50\n    center_y: float = 0.45\n\n    # optional multi-foci: list of dicts {cx, cy, rx, ry} all normalized\n    foci: list | None = None\n"
    s = s[:m.start(1)] + add + s[m.end(1):]

# Replace _in_ellipse to support center offsets
# (we look for def _in_ellipse ... return ...)
pat_in = re.compile(r"def _in_ellipse\([^\)]*\)\s*->\s*bool:\s*\n(?:[^\n]*\n){1,12}\s*return[^\n]*\n", re.M)
m = pat_in.search(s)
if not m:
    stop("debug_renderer.py: cannot locate _in_ellipse() to patch.")
new_in = """def _in_ellipse(r: int, c: int, grid_w: int, grid_h: int, rx: float, ry: float, cx: float = 0.0, cy: float = 0.0) -> bool:
    # Map cell center into [-1..1] space, then shift by (cx, cy) in same normalized space
    nx = ((c + 0.5) / grid_w) * 2.0 - 1.0 - cx
    ny = ((r + 0.5) / grid_h) * 2.0 - 1.0 - cy
    return (nx * nx) / (rx * rx) + (ny * ny) / (ry * ry) <= 1.0
"""
s = s[:m.start()] + new_in + s[m.end():]

# Add helper to decide "is_center" using multi-foci
if "def _is_in_any_focus" not in s:
    anchor = "def _tile_path"
    if anchor not in s:
        stop("debug_renderer.py: cannot find anchor to inject _is_in_any_focus().")
    inject2 = """
def _is_in_any_focus(r: int, c: int, cfg) -> bool:
    # If foci provided, union of ellipses; else single ellipse centered at (center_x, center_y)
    if cfg.foci:
        for f in cfg.foci:
            try:
                cx = float(f.get("cx", 0.0))
                cy = float(f.get("cy", 0.0))
                rx = float(f.get("rx", cfg.ellipse_rx))
                ry = float(f.get("ry", cfg.ellipse_ry))
            except Exception:
                continue
            # cx/cy are normalized 0..1 in profile; convert to [-1..1] offset for _in_ellipse
            ox = (cx * 2.0 - 1.0)
            oy = (cy * 2.0 - 1.0)
            if _in_ellipse(r, c, cfg.grid_w, cfg.grid_h, rx, ry, cx=ox, cy=oy):
                return True
        return False
    # single focus
    ox = (cfg.center_x * 2.0 - 1.0)
    oy = (cfg.center_y * 2.0 - 1.0)
    return _in_ellipse(r, c, cfg.grid_w, cfg.grid_h, cfg.ellipse_rx, cfg.ellipse_ry, cx=ox, cy=oy)
"""
    s = s.replace(anchor, inject2 + "\n" + anchor, 1)

# Ensure target sampling uses letterbox, not stretch
# Replace: target_img = tim.convert("RGB") + subsequent precompute
# We'll inject a letterboxed version when building labs and when blending.
if "_letterbox_resize" in s:
    # in render_target_match_debug: find "target_img = tim.convert"
    s = re.sub(
        r"(target_img\s*=\s*tim\.convert\(\"RGB\"\)\s*\n)",
        r"\1    # A4: preserve aspect ratio (no stretch)\n    target_lb = _letterbox_resize(target_img, (W, H), fill=(220,220,220))\n",
        s,
        count=1,
        flags=re.M
    )
    # In _compute_target_cell_labs call, replace target_img with target_lb if present
    s = s.replace(
        "_compute_target_cell_labs(target_img, cfg.grid_w, cfg.grid_h, cfg.tile_size)",
        "_compute_target_cell_labs(target_lb, cfg.grid_w, cfg.grid_h, cfg.tile_size)"
    )
    # In blending phase: replace target_resized = target_img.resize(...) with target_resized = target_lb
    s = re.sub(
        r"target_resized\s*=\s*target_img\.resize\(\(W,\s*H\),\s*resample=Image\.BILINEAR\)\s*\n",
        "target_resized = target_lb\n",
        s,
        flags=re.M
    )

# Replace is_center line in main loop to use multi-foci
s = re.sub(
    r"is_center\s*=\s*_in_ellipse\([^\)]*\)\s*\n",
    "is_center = _is_in_any_focus(r, c, cfg)\n",
    s,
    count=1,
    flags=re.M
)

F_DEBUG.write_text(s, encoding="utf-8")

# -----------------------
# 2) Patch bootstrap.py
# - pass center_x/center_y + foci into TargetMatchConfig (A4 block)
# -----------------------
s = F_BOOT.read_text(encoding="utf-8")
backup(F_BOOT)

# only patch if not already present
if "foci=profile.get(\"a4_match\"" not in s and "center_x=float(blend_cfg.get(\"center_x\"" not in s:
    # Find the A4 TargetMatchConfig call area and patch only that call block
    # We search for the contiguous ellipse_rx/ellipse_ry lines (as in your snippet)
    old = (
        "ellipse_rx=float(blend_cfg.get(\"ellipse_rx\", 0.38)),\n"
        "            ellipse_ry=float(blend_cfg.get(\"ellipse_ry\", 0.55)),\n"
    )
    if old not in s:
        stop("bootstrap.py: cannot find expected ellipse_rx/ellipse_ry block (pattern mismatch).")
    new = (
        "ellipse_rx=float(blend_cfg.get(\"ellipse_rx\", 0.38)),\n"
        "            ellipse_ry=float(blend_cfg.get(\"ellipse_ry\", 0.55)),\n"
        "            center_x=float(blend_cfg.get(\"center_x\", 0.50)),\n"
        "            center_y=float(blend_cfg.get(\"center_y\", 0.45)),\n"
        "            foci=profile.get(\"a4_match\", {}).get(\"foci\", None),\n"
    )
    s = s.replace(old, new, 1)

F_BOOT.write_text(s, encoding="utf-8")

# -----------------------
# 3) Patch premium_subject_focus.py
# - add a4_match.foci default (2 ellipses)
# - ensure a4_match exists so config is explicit
# -----------------------
s = F_PROFILE.read_text(encoding="utf-8")
backup(F_PROFILE)

if '"a4_match"' not in s:
    # insert before the final closing "}" of PROFILE dict
    # We'll locate the last "}" at end of file and insert before it (safe enough for this file)
    insert = """
    # --- A4 : target-match debug (Lab + cache + portrait-first blend) ---
    "a4_match": {
        # 2 foci for the couple (normalized 0..1)
        "foci": [
            {"cx": 0.40, "cy": 0.55, "rx": 0.26, "ry": 0.34},
            {"cx": 0.63, "cy": 0.42, "rx": 0.26, "ry": 0.34},
        ],
        # speed/quality
        "sample": 350,
        "top_k": 25,
        # optional softening of tile edges (keep 0 unless you tune it later)
        "tile_blur": 0,
    },
"""
    # place it right before the last closing brace of PROFILE dict
    idx = s.rfind("}")
    if idx == -1:
        stop("premium_subject_focus.py: cannot find closing brace to insert a4_match.")
    s = s[:idx] + insert + s[idx:]

F_PROFILE.write_text(s, encoding="utf-8")

print("OK: multi-foci + letterbox patches applied")
print("Backups created with .bak_multifoci suffix (only if not already present).")
PY

echo
echo "---- git diff (patched files) ----"
git diff -- engine/core/debug_renderer.py engine/bootstrap.py engine/profiles/premium_subject_focus.py || true
echo "----------------------------------"
echo
echo "Now running: python main.py"
python main.py
