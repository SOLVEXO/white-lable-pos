#!/usr/bin/env bash
# DEV ONLY. Runs an integration test on the booted iOS simulator and turns every `SHOT <name>` line it prints into a REAL
# simulator screenshot. usage: tool/shoot.sh <test.dart> <out_dir> <suffix> [params_file]   (suffix e.g. light|dark)
set -uo pipefail
cd "$(dirname "$0")/.."
TEST=$1; OUT=$2; SUFFIX=$3; PARAMS=${4:-}
DEV="${SIM_DEVICE_ID:-552F7A5B-229D-45A5-9D2D-B3F3BC3E6A98}"
mkdir -p "$OUT"
xcrun simctl terminate "$DEV" com.solvexo.app >/dev/null 2>&1 || true
DEFS=(--dart-define-from-file=config/env/dev.json)
[ -n "$PARAMS" ] && DEFS+=(--dart-define=DBG_PARAMS_FILE="$PARAMS")
flutter test "$TEST" -d "$DEV" "${DEFS[@]}" 2>&1 | while IFS= read -r line; do
  case "$line" in
    SHOT\ *) n="${line#SHOT }"; xcrun simctl io "$DEV" screenshot "$OUT/${n}_${SUFFIX}.png" >/dev/null 2>&1 && echo "saved ${n}_${SUFFIX}";;
    *"All tests passed"*|*"Some tests failed"*) echo "$line";;
  esac
done
