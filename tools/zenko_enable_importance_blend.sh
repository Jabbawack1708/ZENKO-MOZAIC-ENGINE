#!/usr/bin/env bash
set -euo pipefail

# Must run from repo root
if [[ ! -f "main.py" || ! -d "engine" ]]; then
  echo "STOP: run from repo root (main.py + engine/). PWD=$(pwd)" >&2
  exit 1
fi

F_DEBUG="engine/core/debug_renderer.py"
F_BOOT="engine/bootstrap.py"
F_PROFILE="engine/profiles/premium_subject_focus.py"

for f in "$F_DEBUG" "$F_BOOT" "$F_PROFILE"; do
  [[ -f "$f" ]] || { echo "STOP: missing $f" >&2; exit 1; }
done

ts="$(date +%Y%m%d_%H%M%S)"
backup() { cp -n "$1" "$1.bak_${ts}" 2>/dev/null || true; }

backup "$F_DEBUG"
backup "$F_BOOT"
backup "$F_PROFILE"

python - <<'PY'
from pathlib import Path
import re

def stop(msg): raise SystemExit("STOP: " + msg)

p_debug = Path("engine/core/debug_renderer.py")
p_boot  = Path("engine/bootstrap.py")
p_prof  = Path("engine/profiles/premium_subject_focus.py")

s = p_debug.read_text(encoding="utf-8")

# --- 1) Ensure imports for ImageFilter + ImageStat exist ---
if "from PIL import Image" not in s:
  stop("debug_renderer.py: missing 'from PIL import Image'")
# Add ImageFilter + ImageStat if absent
if "ImageFilter" not in s or "ImageStat" not in s:
  s = s.replace("from PIL import Image", "from PIL import Image, ImageFilter, ImageStat")

# --- 2) Add helper: per-cell importance map ---
if "_compute_importance_cells" not in s:
  insert_after = "def _compute_target_cell_labs"
  idx = s.find(insert_after)
  if idx == -1:
    stop("debug_renderer.py: can't find _compute_target_cell_labs to anchor importance helper")

  # place helper after _compute_target_cell_labs definition block end (naive: after its 'return labs')
  m = re.search(r"def _compute_target_cell_labs[^\n]*\n(?:.*\n)*?\s*return\s+labs\s*\n", s)
  if not m:
    stop("debug_renderer.py: can't locate end of _compute_target_cell_labs()")

  helper = r"""

def _compute_importance_cells(target_resized: Image.Image, grid_w: int, grid_h: int, tile_size: int,
                              gamma: float = 1.0) -> list[float]:
    """
    Returns per-cell importance in [0..1].
    Mix of:
      - edge energy (FIND_EDGES)
      - local contrast (stddev)
      - saturation (HSV S channel)
    """
    im = target_resized.convert("RGB")
    out: list[float] = []
    for r in range(grid_h):
        for c in range(grid_w):
            box = (c * tile_size, r * tile_size, (c + 1) * tile_size, (r + 1) * tile_size)
            patch = im.crop(box)

            # edge energy
            ed = patch.convert("L").filter(ImageFilter.FIND_EDGES)
            edge_mean = ImageStat.Stat(ed).mean[0] / 255.0

            # local contrast
            l = patch.convert("L")
            std = ImageStat.Stat(l).stddev[0] / 128.0
            if std < 0.0: std = 0.0
            if std > 1.0: std = 1.0

            # saturation
            hsv = patch.convert("HSV")
            s_chan = hsv.split()[1]
            sat_mean = ImageStat.Stat(s_chan).mean[0] / 255.0

            imp = 0.55 * edge_mean + 0.25 * std + 0.20 * sat_mean
            if imp < 0.0: imp = 0.0
            if imp > 1.0: imp = 1.0

            # gamma shaping (gamma>1 => more selective)
            if gamma and gamma != 1.0:
                imp = imp ** gamma

            out.append(imp)
    return out
"""
  s = s[:m.end()] + helper + s[m.end():]

# --- 3) Extend TargetMatchConfig with new blend controls (safe defaults) ---
# We only add if not already present
if "importance_boost" not in s:
  # Find the dataclass class TargetMatchConfig block and inject after ellipse fields
  m = re.search(r"@dataclass\s*\nclass\s+TargetMatchConfig:\n(?:.*\n)*?\s*ellipse_ry:\s*float\s*=\s*[0-9.]+\s*\n", s)
  if not m:
    stop("debug_renderer.py: can't locate TargetMatchConfig ellipse_ry to extend config")

  injection = r"""    # importance-driven alpha (premium: more target on details, more mosaic on flats)
    alpha_min: float = 0.10
    alpha_max: float = 0.92
    importance_boost: float = 0.18
    importance_gamma: float = 1.35

    # suppress overly-flat whites (reduce harsh white banding)
    white_suppress: float = 0.55   # 0..1 (higher => more suppression)
    white_L: float = 92.0          # LAB L threshold
    white_C: float = 10.0          # LAB chroma threshold
"""
  s = s[:m.end()] + injection + s[m.end():]

# --- 4) In render_target_match_debug: ensure letterbox used for target_resized (avoid stretch) ---
# It's already resized via target_img.resize(W,H). We'll switch to letterbox if helper exists.
# Replace the line: target_resized = target_img.resize((W, H), resample=Image.BILINEAR)
if "_letterbox_resize" in s and "target_resized = target_img.resize((W, H)" in s:
  s = s.replace(
    "target_resized = target_img.resize((W, H), resample=Image.BILINEAR)",
    "target_resized = _letterbox_resize(target_img, (W, H))"
  )

# If _letterbox_resize isn't present, add it near imports (lightweight)
if "_letterbox_resize" not in s:
  # add right after PIL imports line
  m = re.search(r"from PIL import Image, ImageFilter, ImageStat\s*\n", s)
  if not m:
    stop("debug_renderer.py: can't anchor _letterbox_resize insertion")
  helper = r"""
def _letterbox_resize(im: Image.Image, size: tuple[int, int], fill=(220, 220, 220)) -> Image.Image:
    """ + '"""Resize preserving aspect ratio, pad to target size (no stretching)."""' + r"""
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
  s = s[:m.end()] + helper + s[m.end():]

# --- 5) Compute importance cells once and use per-cell alpha ---
# Anchor before blend loop. We expect the line: blended = Image.new("RGB", (W, H))
if "_compute_importance_cells" in s and "blended = Image.new(\"RGB\", (W, H))" in s:
  if "importance_cells =" not in s:
    s = s.replace(
      "blended = Image.new(\"RGB\", (W, H))",
      "blended = Image.new(\"RGB\", (W, H))\n\n    importance_cells = _compute_importance_cells(\n        target_resized, cfg.grid_w, cfg.grid_h, cfg.tile_size,\n        gamma=float(getattr(cfg, 'importance_gamma', 1.0))\n    )"
    )

# Now modify alpha computation inside the blend loop
# Find: alpha = cfg.alpha_center if is_center else cfg.alpha_edge
# Replace with adaptive alpha based on importance + clamps + white suppress
s = s.replace(
  "alpha = cfg.alpha_center if is_center else cfg.alpha_edge",
  "alpha_base = cfg.alpha_center if is_center else cfg.alpha_edge\n"
  "            imp = importance_cells[idx] if 'importance_cells' in locals() else 0.0\n"
  "            alpha = alpha_base + float(getattr(cfg, 'importance_boost', 0.0)) * imp\n"
  "            a_min = float(getattr(cfg, 'alpha_min', 0.0))\n"
  "            a_max = float(getattr(cfg, 'alpha_max', 1.0))\n"
  "            if alpha < a_min: alpha = a_min\n"
  "            if alpha > a_max: alpha = a_max\n"
  "            # white-suppress: in flat whites, reduce alpha (show more mosaic)\n"
  "            t_lab = mean_lab(t_patch)\n"
  "            L, a, b = t_lab\n"
  "            C = (a*a + b*b) ** 0.5\n"
  "            if L >= float(getattr(cfg, 'white_L', 100.0)) and C <= float(getattr(cfg, 'white_C', 0.0)):\n"
  "                sup = float(getattr(cfg, 'white_suppress', 0.0))\n"
  "                if sup < 0.0: sup = 0.0\n"
  "                if sup > 1.0: sup = 1.0\n"
  "                alpha = alpha * (1.0 - sup)"
)

p_debug.write_text(s, encoding="utf-8")
print("OK: patched engine/core/debug_renderer.py")
PY

# --- 6) Patch bootstrap: pass new a4_blend fields into TargetMatchConfig call ---
python - <<'PY'
from pathlib import Path
import re

def stop(msg): raise SystemExit("STOP: " + msg)

p = Path("engine/bootstrap.py")
s = p.read_text(encoding="utf-8")

# Anchor: the TargetMatchConfig call in A4 section already exists
if "TargetMatchConfig(" not in s or "render_target_match_debug" not in s:
  stop("bootstrap.py: can't find TargetMatchConfig/render_target_match_debug block")

# If already patched, skip
if "importance_boost" in s and "alpha_min" in s:
  print("OK: bootstrap.py already has importance blend args (skip)")
else:
  # Insert args just before closing ')'
  # We anchor around ellipse_ry=... line
  pat = r"(ellipse_ry=float\(blend_cfg\.get\(\"ellipse_ry\", 0\.55\)\),\n)"
  m = re.search(pat, s)
  if not m:
    stop("bootstrap.py: can't find ellipse_ry line to anchor insertion")

  inject = m.group(1) + (
    "        alpha_min=float(profile.get(\"a4_blend\", {}).get(\"alpha_min\", 0.10)),\n"
    "        alpha_max=float(profile.get(\"a4_blend\", {}).get(\"alpha_max\", 0.92)),\n"
    "        importance_boost=float(profile.get(\"a4_blend\", {}).get(\"importance_boost\", 0.18)),\n"
    "        importance_gamma=float(profile.get(\"a4_blend\", {}).get(\"importance_gamma\", 1.35)),\n"
    "        white_suppress=float(profile.get(\"a4_blend\", {}).get(\"white_suppress\", 0.55)),\n"
    "        white_L=float(profile.get(\"a4_blend\", {}).get(\"white_L\", 92.0)),\n"
    "        white_C=float(profile.get(\"a4_blend\", {}).get(\"white_C\", 10.0)),\n"
  )
  s = s[:m.start(1)] + inject + s[m.end(1):]
  p.write_text(s, encoding="utf-8")
  print("OK: patched engine/bootstrap.py")

PY

# --- 7) Patch profile defaults (premium_subject_focus): add a4_blend section if missing or extend it ---
python - <<'PY'
from pathlib import Path
import re

def stop(msg): raise SystemExit("STOP: " + msg)

p = Path("engine/profiles/premium_subject_focus.py")
s = p.read_text(encoding="utf-8")

# Ensure PROFILE dict contains a4_blend
if "\"a4_blend\"" in s:
  # add keys if missing (light touch)
  def ensure(k, line):
    nonlocal_s = None

  # Insert missing keys inside a4_blend dict
  m = re.search(r"\"a4_blend\"\s*:\s*\{\n", s)
  if not m:
    stop("profile: found a4_blend string but couldn't locate dict start")

  # Find end of that dict block (naive: first closing brace at same indent)
  start = m.end()
  # find the next "\n    }," at same indentation level (4 spaces) after start
  endm = re.search(r"\n\s*\},\s*\n", s[start:])
  if not endm:
    stop("profile: couldn't locate end of a4_blend block")

  block = s[start:start+endm.start()]
  additions = []
  def add_if_missing(key, val_line):
    nonlocal block, additions
    if key not in block:
      additions.append(val_line)

  add_if_missing("alpha_min", '        "alpha_min": 0.10,\n')
  add_if_missing("alpha_max", '        "alpha_max": 0.92,\n')
  add_if_missing("importance_boost", '        "importance_boost": 0.18,\n')
  add_if_missing("importance_gamma", '        "importance_gamma": 1.35,\n')
  add_if_missing("white_suppress", '        "white_suppress": 0.55,\n')
  add_if_missing("white_L", '        "white_L": 92.0,\n')
  add_if_missing("white_C", '        "white_C": 10.0,\n')

  if additions:
    # add near top of a4_blend block (after opening)
    block = "".join(additions) + block
    s = s[:start] + block + s[start+endm.start():]
    p.write_text(s, encoding="utf-8")
    print("OK: extended a4_blend keys in profile")
  else:
    print("OK: profile already has all a4_blend keys (skip)")
else:
  # Create a4_blend block right after "blend": {...}
  # Anchor after '"blend": { ... },'
  m = re.search(r"\"blend\"\s*:\s*\{(?:.*\n)*?\s*\},\s*\n", s)
  if not m:
    stop("profile: can't anchor after blend block")
  insert = (
    '    "a4_blend": {\n'
    '        "alpha_min": 0.10,\n'
    '        "alpha_max": 0.92,\n'
    '        "importance_boost": 0.18,\n'
    '        "importance_gamma": 1.35,\n'
    '        "white_suppress": 0.55,\n'
    '        "white_L": 92.0,\n'
    '        "white_C": 10.0,\n'
    '    },\n'
  )
  s = s[:m.end()] + insert + s[m.end():]
  p.write_text(s, encoding="utf-8")
  print("OK: added a4_blend block to profile")

PY

# --- 8) Compile + quick import sanity ---
python -m py_compile "$F_DEBUG" "$F_BOOT" "$F_PROFILE"
python -c "from engine.bootstrap import run; print('OK import bootstrap')"

echo "OK: importance blend enabled."
echo "Run: python main.py"
