#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/zenko-mozaic-engine"
PROFILE_FILE="$REPO/engine/profiles/premium_subject_focus.py"
OUTROOT="$REPO/output"

ts(){ date +"%Y%m%d_%H%M%S"; }
RUN_ID="demo_perceptual_$(ts)"
OUTDIR="$OUTROOT/$RUN_ID"
mkdir -p "$OUTDIR"

cd "$REPO"

cp -f "$PROFILE_FILE" "$OUTDIR/profile__ORIGINAL.py"

patch_blend () {
  local AC="$1" AE="$2" FE="$3" CX="$4" CY="$5" RX="$6" RY="$7"
  python - <<PY
import pathlib, re, sys
path = pathlib.Path("$PROFILE_FILE")
txt = path.read_text(encoding="utf-8")

def patch_number(key, value):
    global txt
    pat = re.compile(r'((?:["\'])' + re.escape(key) + r'(?:["\'])\s*:\s*)([0-9.]+)')
    def repl(m):
        return m.group(1) + str(value)
    new, n = pat.subn(repl, txt, count=1)
    if n != 1:
        raise RuntimeError(f"Could not patch {key} (found {n} matches)")
    txt = new

try:
    patch_number("alpha_center", $AC)
    patch_number("alpha_edge",   $AE)
    patch_number("feather",      $FE)
    patch_number("center_x",     $CX)
    patch_number("center_y",     $CY)
    patch_number("ellipse_rx",   $RX)
    patch_number("ellipse_ry",   $RY)
except Exception as e:
    print("PATCH_ERROR:", e)
    sys.exit(2)

path.write_text(txt, encoding="utf-8")
print("OK patched blend:",
      "alpha_center=", $AC,
      "alpha_edge=", $AE,
      "feather=", $FE,
      "center=(", $CX, ",", $CY, ")",
      "ellipse=(", $RX, ",", $RY, ")")
PY
}

run_and_collect () {
  local TAG="$1"
  echo
  echo "================ $TAG ================"
  python main.py

  for f in mosaic_target_debug.png mosaic_debug.png mosaic_final.jpg mosaic.jpg tile_features_lab.json; do
    if [[ -f "$OUTROOT/$f" ]]; then
      cp -f "$OUTROOT/$f" "$OUTDIR/${TAG}__${f}"
    fi
  done
  echo "$(date -Iseconds) | SAVED $TAG" >> "$OUTDIR/runlog.txt"
}

echo "OUTDIR=$OUTDIR" | tee "$OUTDIR/runlog.txt"

run_and_collect "BASE"

patch_blend 0.96 0.25 0.34 0.50 0.46 0.44 0.46
echo "$(date -Iseconds) | FACEBOOST_V0 params applied" >> "$OUTDIR/runlog.txt"
run_and_collect "FACEBOOST_V0"

patch_blend 0.96 0.62 0.42 0.50 0.46 0.44 0.46
echo "$(date -Iseconds) | FACEBOOST_V0_ANTIWHITE params applied" >> "$OUTDIR/runlog.txt"
run_and_collect "FACEBOOST_V0_ANTIWHITE"

cp -f "$OUTDIR/profile__ORIGINAL.py" "$PROFILE_FILE"
cp -f "$PROFILE_FILE" "$OUTDIR/profile__RESTORED.py"

echo
echo "DONE. Results in: $OUTDIR"
ls -la "$OUTDIR" | sed -n '1,220p'
