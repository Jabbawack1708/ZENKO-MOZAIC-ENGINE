#!/usr/bin/env bash
set -euo pipefail

# --- Guard rails ---
if [[ ! -f "main.py" || ! -d "engine" ]]; then
  echo "STOP: run from repo root (main.py + engine/). Pwd=$(pwd)"
  exit 1
fi

PROFILE_FILE="engine/profiles/premium_subject_focus.py"
if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "STOP: missing $PROFILE_FILE"
  exit 1
fi

# --- Read current base tile size from the PROFILE dict ---
BASE_TILE_SIZE="$(python - <<'PY'
import re
from pathlib import Path
p = Path("engine/profiles/premium_subject_focus.py")
s = p.read_text(encoding="utf-8")

# Find the tiles block then the size inside it
m = re.search(r'"tiles"\s*:\s*\{[^}]*"size"\s*:\s*(\d+)', s, flags=re.S)
if not m:
    raise SystemExit("STOP: cannot find PROFILE['tiles']['size'] in premium_subject_focus.py")
print(m.group(1))
PY
)"

PLUS20_TILE_SIZE=$((BASE_TILE_SIZE + 20))
PLUS35_TILE_SIZE=$((BASE_TILE_SIZE + 35))

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="output/comparatif_tile_size_${TS}"
mkdir -p "$OUTDIR"

backup() {
  local f="$1"
  cp -n "$f" "${f}.bak_${TS}" 2>/dev/null || true
}

patch_tile_size_in_profile() {
  local new_size="$1"
  python - <<PY
import re
from pathlib import Path

p = Path("$PROFILE_FILE")
s = p.read_text(encoding="utf-8")

# Replace only the size inside the "tiles" dict
pattern = r'("tiles"\\s*:\\s*\\{[^}]*"size"\\s*:\\s*)(\\d+)'
m = re.search(pattern, s, flags=re.S)
if not m:
    raise SystemExit("STOP: tiles->size not found in profile (unexpected format)")

s2 = re.sub(pattern, r'\\g<1>%s' % $new_size, s, count=1, flags=re.S)
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched PROFILE tiles.size -> {$new_size}")
PY
}

collect_outputs() {
  local tag="$1"
  # copy common outputs if they exist
  for f in \
    output/mosaic.jpg \
    output/mosaic_final.jpg \
    output/mosaic_target_debug.png \
    output/mosaic_debug.png \
    output/mosaic.png \
    output/mosaic_final.png
  do
    if [[ -f "$f" ]]; then
      cp -f "$f" "${OUTDIR}/${tag}__$(basename "$f")"
    fi
  done

  # optional run log if you have one
  if [[ -f "output/run.log" ]]; then
    cp -f "output/run.log" "${OUTDIR}/${tag}__run.log"
  fi
}

run_one() {
  local tag="$1"
  local size="$2"

  echo
  echo "========== ${tag} (tile_size=${size}) =========="
  patch_tile_size_in_profile "$size"

  # Clean only output images (DO NOT touch data/ or caches)
  rm -f output/mosaic.jpg output/mosaic_final.jpg output/mosaic_target_debug.png output/mosaic_debug.png \
        output/mosaic.png output/mosaic_final.png 2>/dev/null || true

  python main.py
  collect_outputs "$tag"
  echo "[OK] saved outputs -> ${OUTDIR} (${tag})"
}

# --- Backups ---
backup "$PROFILE_FILE"

echo "[INFO] BASE_TILE_SIZE=${BASE_TILE_SIZE}  PLUS20=${PLUS20_TILE_SIZE}  PLUS35=${PLUS35_TILE_SIZE}"
echo "[INFO] OUTDIR=${OUTDIR}"

run_one "BASE"   "$BASE_TILE_SIZE"
run_one "PLUS20" "$PLUS20_TILE_SIZE"
run_one "PLUS35" "$PLUS35_TILE_SIZE"

# Restore original
patch_tile_size_in_profile "$BASE_TILE_SIZE"
echo
echo "[DONE] Compare tile sizes in: ${OUTDIR}"
ls -la "$OUTDIR" | sed -n '1,200p'
