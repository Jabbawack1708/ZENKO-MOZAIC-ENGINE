#!/usr/bin/env bash
set -euo pipefail

# Must run from repo root
[[ -f "main.py" && -d "engine" ]] || { echo "STOP: run from repo root (main.py + engine/). PWD=$(pwd)"; exit 1; }

F_PROFILE="engine/profiles/premium_subject_focus.py"

ts="$(date +%Y%m%d_%H%M%S)"
cp -n "$F_PROFILE" "${F_PROFILE}.bak_${ts}" || true
echo "[OK] backup -> ${F_PROFILE}.bak_${ts}"

python - <<'PY'
from pathlib import Path
import re

p = Path("engine/profiles/premium_subject_focus.py")
s = p.read_text(encoding="utf-8")

def sub_num(key: str, new_val: str) -> None:
    global s
    # matches: "key": 0.12,
    pat = rf'("{re.escape(key)}"\s*:\s*)([0-9]*\.?[0-9]+)(\s*,)'
    if not re.search(pat, s):
        raise SystemExit(f"STOP: key not found: {key}")
    s = re.sub(pat, rf'\1{new_val}\3', s, count=1)

# --- Goal:
# - Make the "protected" ellipse cover BOTH faces by centering between them and enlarging it
# - Reduce the "too tiled" look by increasing target dominance at edges + tiny blur in A4 debug
#
# You can iterate these 4 numbers if needed:
# center_x/center_y = where the ellipse is centered (0..1)
# ellipse_rx/ellipse_ry = ellipse radii (0..1)

# 1) Stronger portrait dominance overall (less tiled)
sub_num("alpha_center", "0.90")  # was 0.82
sub_num("alpha_edge",   "0.35")  # was 0.18 (big reason it looks too tiled)
sub_num("feather",      "0.30")  # was 0.22 (smoother transition)

# 2) Two-faces ellipse (center between the two faces + larger radii)
sub_num("center_x",   "0.52")  # move right a bit (between faces)
sub_num("center_y",   "0.40")  # move slightly up (toward the male face)
sub_num("ellipse_rx", "0.42")  # wider ellipse -> catches both faces
sub_num("ellipse_ry", "0.34")  # a bit taller but not too much

# 3) Ensure a4_match.tile_blur exists (debug blend smoother)
if '"a4_match"' not in s:
    # insert just before final closing "}" of PROFILE dict
    m = re.search(r'\n\}\s*\n\Z', s)
    if not m:
        raise SystemExit("STOP: can't locate end of PROFILE dict to insert a4_match")
    insert = '\n  "a4_match": {\n    "tile_blur": 1\n  },\n'
    s = s[:m.start()] + insert + s[m.start():]
else:
    # update or add tile_blur inside a4_match block
    if '"tile_blur"' in s:
        s = re.sub(r'("a4_match"\s*:\s*\{[^}]*"tile_blur"\s*:\s*)(\d+)', r'\g<1>1', s, count=1, flags=re.S)
    else:
        s = re.sub(r'("a4_match"\s*:\s*\{)', r'\1\n    "tile_blur": 1,', s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] tuned blend + added a4_match.tile_blur=1")
PY

# compile check
python -m py_compile "$F_PROFILE"
echo "[OK] py_compile"

# run engine
python main.py
echo "[OK] run done. Check output/mosaic_target_debug.png"
