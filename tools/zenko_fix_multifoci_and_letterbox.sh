#!/usr/bin/env bash
set -euo pipefail

# Run ONLY from repo root
if [[ ! -f "main.py" || ! -d "engine" ]]; then
  echo "STOP: run from repo root (must contain main.py + engine/). pwd=$(pwd)"
  exit 1
fi

F_DEBUG="engine/core/debug_renderer.py"
F_BOOT="engine/bootstrap.py"
F_PROFILE="engine/profiles/premium_subject_focus.py"

for f in "$F_DEBUG" "$F_BOOT" "$F_PROFILE"; do
  [[ -f "$f" ]] || { echo "STOP: missing file: $f"; exit 1; }
done

ts="$(date +%Y%m%d_%H%M%S)"

backup() {
  local f="$1"
  cp -n "$f" "${f}.bak_${ts}" || true
}

backup "$F_DEBUG"
backup "$F_BOOT"
backup "$F_PROFILE"

python - <<'PY'
from pathlib import Path
import re, sys

F_DEBUG = Path("engine/core/debug_renderer.py")
F_BOOT  = Path("engine/bootstrap.py")
F_PROF  = Path("engine/profiles/premium_subject_focus.py")

def stop(msg):
    raise SystemExit("STOP: " + msg)

# -------------------------
# 1) debug_renderer.py
# - ensure letterbox helper exists
# - ensure TargetMatchConfig has center_x/center_y/foci
# - ensure is_center uses foci if provided
# - ensure target_img is letterboxed to (W,H) before LAB sampling & blending
# -------------------------
s = F_DEBUG.read_text(encoding="utf-8")

# Ensure PIL import has Image (keep ImageFilter if already there)
if "from PIL import Image" not in s:
    stop("can't find 'from PIL import Image' import in debug_renderer.py")

# Add _letterbox_resize if missing
if "_letterbox_resize" not in s:
    s = s.replace(
        "from PIL import Image",
        "from PIL import Image\n\n"
        "def _letterbox_resize(im: Image.Image, size: tuple[int, int], fill=(220, 220, 220)) -> Image.Image:\n"
        "    \"\"\"Resize preserving aspect ratio, pad to target size (no stretching).\"\"\"\n"
        "    tw, th = size\n"
        "    im = im.convert(\"RGB\")\n"
        "    w, h = im.size\n"
        "    if w == 0 or h == 0:\n"
        "        return Image.new(\"RGB\", (tw, th), fill)\n"
        "    scale = min(tw / w, th / h)\n"
        "    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))\n"
        "    resized = im.resize((nw, nh), resample=Image.BILINEAR)\n"
        "    canvas = Image.new(\"RGB\", (tw, th), fill)\n"
        "    ox = (tw - nw) // 2\n"
        "    oy = (th - nh) // 2\n"
        "    canvas.paste(resized, (ox, oy))\n"
        "    return canvas\n"
    )

# Extend TargetMatchConfig (dataclass) with center_x/center_y + foci if missing
if "center_x:" not in s and "center_y:" not in s:
    # Insert after ellipse params block (we saw ellipse_rx/ellipse_ry present)
    pat = re.compile(r"(ellipse_rx:\s*float\s*=\s*[0-9.]+\s*\n\s*ellipse_ry:\s*float\s*=\s*[0-9.]+\s*)")
    m = pat.search(s)
    if not m:
        stop("can't find ellipse_rx/ellipse_ry block in TargetMatchConfig to extend")
    insert = (
        m.group(1)
        + "\n\n"
        + "    # focus center (normalized 0..1)\n"
        + "    center_x: float = 0.50\n"
        + "    center_y: float = 0.45\n"
        + "    # optional multi-foci (list of dicts: {cx,cy,rx,ry} all normalized)\n"
        + "    foci: list | None = None"
    )
    s = s[:m.start(1)] + insert + s[m.end(1):]

# Helper: point-in-ellipse with center offsets
# We keep existing _in_ellipse signature if present, but we need a version that accepts center_x/center_y.
# If the current _in_ellipse already uses center_x/center_y -> ok.
if "def _in_ellipse(" not in s:
    stop("can't find _in_ellipse() in debug_renderer.py")

# Patch _in_ellipse to accept center offsets only if it doesn't already
if "center_x" not in s.split("def _in_ellipse",1)[1].split("def",1)[0]:
    # Replace signature and body conservatively (only if it matches old simple form)
    pat = re.compile(
        r"def _in_ellipse\(\s*r:\s*int,\s*c:\s*int,\s*grid_w:\s*int,\s*grid_h:\s*int,\s*rx:\s*float,\s*ry:\s*float\s*\)\s*->\s*bool:\s*\n"
        r"(?P<body>(?:\s+.*\n){1,10})"
    )
    m = pat.search(s)
    if not m:
        stop("can't locate _in_ellipse() block to patch safely")
    new = (
        "def _in_ellipse(r: int, c: int, grid_w: int, grid_h: int, rx: float, ry: float, center_x: float, center_y: float) -> bool:\n"
        "    # normalized cell center in [-1,1] space, with center offsets\n"
        "    nx = ((c + 0.5) / grid_w) * 2.0 - 1.0\n"
        "    ny = ((r + 0.5) / grid_h) * 2.0 - 1.0\n"
        "    cx = center_x * 2.0 - 1.0\n"
        "    cy = center_y * 2.0 - 1.0\n"
        "    nx -= cx\n"
        "    ny -= cy\n"
        "    return (nx * nx) / (rx * rx) + (ny * ny) / (ry * ry) <= 1.0\n"
    )
    s = s[:m.start()] + new + s[m.end():]

# Add _in_any_focus helper if missing
if "_in_any_focus" not in s:
    s += "\n\n" + (
        "def _in_any_focus(r: int, c: int, grid_w: int, grid_h: int, ellipse_rx: float, ellipse_ry: float, center_x: float, center_y: float, foci) -> bool:\n"
        "    \"\"\"Return True if (r,c) is inside the main ellipse OR any focus ellipse.\"\"\"\n"
        "    if foci:\n"
        "        try:\n"
        "            for f in foci:\n"
        "                cx = float(f.get('cx', center_x))\n"
        "                cy = float(f.get('cy', center_y))\n"
        "                rx = float(f.get('rx', ellipse_rx))\n"
        "                ry = float(f.get('ry', ellipse_ry))\n"
        "                if _in_ellipse(r, c, grid_w, grid_h, rx, ry, cx, cy):\n"
        "                    return True\n"
        "        except Exception:\n"
        "            pass\n"
        "    return _in_ellipse(r, c, grid_w, grid_h, ellipse_rx, ellipse_ry, center_x, center_y)\n"
    )

# Ensure render_target_match_debug uses _in_any_focus and letterbox
# 1) Replace is_center assignment line to use _in_any_focus
s = re.sub(
    r"is_center\s*=\s*_in_ellipse\(\s*r,\s*c,\s*cfg\.grid_w,\s*cfg\.grid_h,\s*cfg\.ellipse_rx,\s*cfg\.ellipse_ry\s*\)",
    "is_center = _in_any_focus(r, c, cfg.grid_w, cfg.grid_h, cfg.ellipse_rx, cfg.ellipse_ry, cfg.center_x, cfg.center_y, cfg.foci)",
    s
)

# 2) Replace any remaining _in_ellipse(...) call for is_center that includes ellipse_rx/ry but not center offsets
s = re.sub(
    r"is_center\s*=\s*_in_ellipse\(\s*r,\s*c,\s*cfg\.grid_w,\s*cfg\.grid_h,\s*cfg\.ellipse_rx,\s*cfg\.ellipse_ry\s*,\s*cfg\.center_x\s*,\s*cfg\.center_y\s*\)",
    "is_center = _in_any_focus(r, c, cfg.grid_w, cfg.grid_h, cfg.ellipse_rx, cfg.ellipse_ry, cfg.center_x, cfg.center_y, cfg.foci)",
    s
)

# 3) Ensure target_img is letterboxed to (W,H) before LAB computation.
# We locate "target_img = tim.convert("RGB")" then ensure a line right after uses _letterbox_resize(target_img, (W,H))
if "target_img = tim.convert(\"RGB\")" in s:
    # Only add if not already present
    if "_letterbox_resize(target_img" not in s:
        s = s.replace(
            "target_img = tim.convert(\"RGB\")",
            "target_img = tim.convert(\"RGB\")\n    # prevent stretch: letterbox to mosaic canvas size\n    target_img = _letterbox_resize(target_img, (W, H))"
        )
else:
    stop("can't find target_img conversion line in debug_renderer.py")

# 4) Ensure target_resized uses the same (already letterboxed) image (avoid re-stretching)
# If code still does: target_resized = target_img.resize((W,H), ...)
# we can simplify to: target_resized = target_img  (since target_img is already (W,H))
s = re.sub(
    r"target_resized\s*=\s*target_img\.resize\(\(\s*W\s*,\s*H\s*\)\s*,\s*resample=Image\.BILINEAR\s*\)",
    "target_resized = target_img  # already letterboxed to (W,H)",
    s
)

F_DEBUG.write_text(s, encoding="utf-8")

# -------------------------
# 2) bootstrap.py
# - pass center_x/center_y + foci into TargetMatchConfig (A4 block)
# -------------------------
b = F_BOOT.read_text(encoding="utf-8")

needle = "ellipse_rx=float(blend_cfg.get(\"ellipse_rx\", 0.38)),"
if needle not in b:
    stop("can't find expected A4 TargetMatchConfig ellipse_rx line in bootstrap.py")

# If center_x already present, skip
if "center_x=" not in b or "foci=" not in b:
    # Insert after ellipse_ry line (must exist nearby)
    old_block = (
        "ellipse_rx=float(blend_cfg.get(\"ellipse_rx\", 0.38)),\n"
        "            ellipse_ry=float(blend_cfg.get(\"ellipse_ry\", 0.55)),\n"
    )
    if old_block not in b:
        # fallback: look for ellipse_ry line and inject after
        m = re.search(r"(ellipse_ry=float\(blend_cfg\.get\(\"ellipse_ry\", 0\.55\)\),\n)", b)
        if not m:
            stop("can't locate ellipse_ry line in bootstrap.py A4 block")
        inject = m.group(1) + (
            "            center_x=float(blend_cfg.get(\"center_x\", 0.50)),\n"
            "            center_y=float(blend_cfg.get(\"center_y\", 0.45)),\n"
            "            foci=profile.get(\"a4_match\", {}).get(\"foci\", None),\n"
        )
        b = b.replace(m.group(1), inject, 1)
    else:
        new_block = old_block + (
            "            center_x=float(blend_cfg.get(\"center_x\", 0.50)),\n"
            "            center_y=float(blend_cfg.get(\"center_y\", 0.45)),\n"
            "            foci=profile.get(\"a4_match\", {}).get(\"foci\", None),\n"
        )
        b = b.replace(old_block, new_block, 1)

F_BOOT.write_text(b, encoding="utf-8")

# -------------------------
# 3) premium_subject_focus.py
# - add a4_match with tile_blur + foci (2 ellipses)
# - do NOT put tile_blur inside blend (your previous error came from that)
# -------------------------
p = F_PROF.read_text(encoding="utf-8")

# Ensure there's an a4_match block. If missing, insert before final closing "}"
if "\"a4_match\"" not in p:
    # Insert near a3_diversity block end or before final }
    # We'll append just before the last "\n}" of the PROFILE dict.
    ins = (
        "\n    # --- A4: target-match debug (Lab + cache + portrait-first blend) ---\n"
        "    \"a4_match\": {\n"
        "        # speed/quality knobs\n"
        "        \"sample\": 350,\n"
        "        \"top_k\": 25,\n"
        "        # soften micro-noise (0=off). This is applied ONLY in A4 debug renderer.\n"
        "        \"tile_blur\": 1,\n"
        "        # Couple focus: two ellipses (normalized). TUNE cx/cy/rx/ry if needed.\n"
        "        \"foci\": [\n"
        "            {\"cx\": 0.42, \"cy\": 0.52, \"rx\": 0.24, \"ry\": 0.30},\n"
        "            {\"cx\": 0.62, \"cy\": 0.42, \"rx\": 0.24, \"ry\": 0.30},\n"
        "        ],\n"
        "    },\n"
    )
    # naive but safe: insert before last closing brace of PROFILE dict
    idx = p.rfind("\n}")
    if idx == -1:
        stop("can't find end of PROFILE dict in premium_subject_focus.py")
    p = p[:idx] + ins + p[idx:]
else:
    # If exists, ensure tile_blur is inside it (leave user tuning to later)
    pass

F_PROF.write_text(p, encoding="utf-8")

print("OK: patched debug_renderer.py + bootstrap.py + premium_subject_focus.py")
PY

echo
echo "---- Running a quick syntax check ----"
python -m py_compile engine/core/debug_renderer.py engine/bootstrap.py engine/profiles/premium_subject_focus.py
echo "OK: python compile"

echo
echo "---- Git diff (patch result) ----"
git diff -- engine/core/debug_renderer.py engine/bootstrap.py engine/profiles/premium_subject_focus.py | sed -n '1,220p' || true

echo
echo "NEXT: run => python main.py"
