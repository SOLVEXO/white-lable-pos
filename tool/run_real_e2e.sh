#!/usr/bin/env bash
# DEV ONLY. Runs the REAL-backend integration tests on the booted iOS simulator against the local dev stack.
# Prereq (solvexo-api): npm run dev:stack:up && npm run dev:seed        (see solvexo-api/dev/README.md)
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
curl -fs http://localhost:3102/health/live >/dev/null || { echo "Dev API not running on :3102 — run: (cd ../solvexo-api && npm run dev:stack:up && npm run dev:seed)"; exit 1; }
node tool/e2e_control_server.mjs & CTL=$!
trap 'kill $CTL 2>/dev/null || true' EXIT
sleep 1
FILES=("$@"); [ ${#FILES[@]} -eq 0 ] && FILES=(integration_test/real_backend_pos_flows_test.dart integration_test/real_backend_ui_test.dart)
for f in "${FILES[@]}"; do
  # a previous run's app instance left running makes the next `flutter test` hang at "loading"
  xcrun simctl terminate booted com.solvexo.app >/dev/null 2>&1 || true
  flutter test "$f" -d "$DEVICE" --dart-define-from-file=config/env/local.json
done
