#!/usr/bin/env bash
# DEV ONLY (G6.3). Like tool/shoot.sh but against the REAL local dev stack (config/env/local.json): runs an integration test on a booted iOS
# simulator and turns every `SHOT <name>` line into a simulator screenshot named <name>_<suffix>.png. Any test failure line is echoed.
# usage: SIM_DEVICE_ID=<udid> tool/shoot_real.sh <test.dart> <out_dir> <suffix> [params_file] [extra --dart-define=… …]
set -uo pipefail
cd "$(dirname "$0")/.."
TEST=$1; OUT=$2; SUFFIX=$3; PARAMS=${4:-}; shift $(( $# < 4 ? $# : 4 ))
DEV="${SIM_DEVICE_ID:?set SIM_DEVICE_ID}"
mkdir -p "$OUT"
curl -fs http://localhost:3102/health/live >/dev/null || { echo "Dev API not running on :3102"; exit 1; }
xcrun simctl terminate "$DEV" com.solvexo.app >/dev/null 2>&1 || true
DEFS=(--dart-define-from-file=config/env/local.json)
[ -n "$PARAMS" ] && DEFS+=(--dart-define=DBG_PARAMS_FILE="$PARAMS")
flutter test "$TEST" -d "$DEV" "${DEFS[@]}" "$@" 2>&1 | while IFS= read -r line; do
  case "$line" in
    SHOT\ *) n="${line#SHOT }"; xcrun simctl io "$DEV" screenshot "$OUT/${n}_${SUFFIX}.png" >/dev/null 2>&1 && echo "saved ${n}_${SUFFIX}";;
    *"EXCEPTION CAUGHT"*|*"overflowed by"*|*"Expected:"*|*"All tests passed"*|*"Some tests failed"*|*"never reached"*) echo "$line" | cut -c1-220;;
  esac
done
