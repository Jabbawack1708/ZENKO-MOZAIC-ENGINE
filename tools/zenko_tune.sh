#!/usr/bin/env bash
set -euo pipefail

# --- Guard rails ---
if [[ ! -f "main.py" || ! -d "engine" ]]; then
  echo "STOP: run me from repo root (where main.py + engine/ exist)."
  echo "PWD=$(pwd)"
  exit 1
fi

PROFILE_FILE="engine/profiles/premium_subject_focus.py"

if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "STOP: missing $PROFILE_FILE"
  exit 1
fi

# --- Defaults (can be overridden by args) ---
ALPHA_CENTER="${1:-0.72}"
ALPHA_EDGE="${2:-0.28}"
FEATHER="${3:-}"   # optional (leave empty to not change)
RUN="${4:-run}"    # "run" or "no-run"

python - <<PY
from pathlib import Path
import re, sys

profile_path = Path("$PROFILE_FILE")
s = profile_path.read_text(encoding="utf-8")

def ensure_float(x, name):
    try:
        v = float(x)
    except Exception:
        raise SystemExit(f"STOP: {name} must be a float, got {x!r}")
    if not (0.0 <= v <= 1.0):
        raise SystemExit(f"STOP: {name} must be in [0,1], got {v}")
    return v

alpha_center = ensure_float("$ALPHA_CENTER", "alpha_center")
alpha_edge   = ensure_float("$ALPHA_EDGE", "alpha_edge")

feather_arg = "$FEATHER".strip()
feather = None
if feather_arg:
    feather = ensure_float(feather_arg, "feather")

# Backup once per run
bak = profile_path.with_suffix(profile_path.suffix + ".bak_tune")
bak.write_text(s, encoding="utf-8")

def sub_or_stop(pattern, repl, label):
    nonlocal_s = None
    new_s, n = re.subn(pattern, repl, s, flags=re.M)
    if n == 0:
        raise SystemExit(f"STOP: couldn't patch {label} (pattern not found)")
    return new_s

# Patch alpha_center / alpha_edge
s = re.sub(r'("alpha_center"\s*:\s*)([0-9]*\.?[0-9]+)', rf'\g<1>{alpha_center:.2f}', s, count=1)
if '"alpha_center"' not in s:
    raise SystemExit("STOP: alpha_center key not present after patch (unexpected)")

s = re.sub(r'("alpha_edge"\s*:\s*)([0-9]*\.?[0-9]+)', rf'\g<1>{alpha_edge:.2f}', s, count=1)
if '"alpha_edge"' not in s:
    raise SystemExit("STOP: alpha_edge key not present after patch (unexpected)")

# Optional feather patch
if feather is not None:
    if re.search(r'"feather"\s*:\s*[0-9]*\.?[0-9]+', s):
        s = re.sub(r'("feather"\s*:\s*)([0-9]*\.?[0-9]+)', rf'\g<1>{feather:.2f}', s, count=1)
    else:
        raise SystemExit("STOP: feather key not found in profile to patch")

profile_path.write_text(s, encoding="utf-8")

print("OK: patched premium_subject_focus.py")
print(f" - alpha_center={alpha_center:.2f}")
print(f" - alpha_edge  ={alpha_edge:.2f}")
if feather is not None:
    print(f" - feather     ={feather:.2f}")
print(f"Backup: {bak}")
PY

echo
echo "---- git diff (profile only) ----"
git diff -- "$PROFILE_FILE" || true
echo "---------------------------------"
echo

if [[ "$RUN" == "run" ]]; then
  python main.py
else
  echo "OK: no-run (changes applied, main.py not executed)."
fi
