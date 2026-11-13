#!/usr/bin/env bash
# DEV ONLY (G6.1) — "older backend" mode: runs this app's core real-backend flows against the API as it runs in production today
# (tag pos-backend-g5.1 = c889af0), to prove everything added since then hides or degrades gracefully there.
#   1. a throw-away worktree of solvexo-api at the tag (outside the repo), its own dev stack (:3102) and seed;
#   2. the core flows: sales, refunds, voids, offline return on another till, shifts / cash, printing, G5.1;
#   3. stop the stack (the worktree is kept for the next run; delete it with `git worktree remove`).
# Nothing else heavy should run meanwhile (one simulator). Usage: tool/run_older_backend_e2e.sh [worktree dir]
set -euo pipefail
cd "$(dirname "$0")/.."
API_REPO="$(cd ../solvexo-api && pwd)"
WT="${1:-${TMPDIR:-/tmp}/solvexo-api-g51}"
TAG=pos-backend-g5.1
[ -d "$WT" ] || git -C "$API_REPO" worktree add -f "$WT" "$TAG"
[ "$(git -C "$WT" rev-parse HEAD)" = "$(git -C "$API_REPO" rev-parse "$TAG^{commit}")" ] || { echo "$WT is not at $TAG" >&2; exit 1; }
[ -d "$WT/node_modules" ] || (cd "$WT" && npm ci --no-audit --no-fund)
curl -fs http://localhost:3102/health/live >/dev/null && { echo "Something already runs on :3102 — stop the current dev stack first" >&2; exit 1; }
(cd "$WT" && bash dev/up.sh && npm run dev:seed >/dev/null)
trap '(cd "$WT" && bash dev/down.sh) >/dev/null 2>&1 || true' EXIT
CORE=(real_backend_pos_flows_test real_backend_ui_test g24_checkout_flow_test g25_returns_flow_test g27_offline_return_other_till_test g35_cash_flow_test g4_flow_test g51_flow_test)   # g51 needs the draft PO that g4 creates
FILES=(); for f in "${CORE[@]}"; do FILES+=("integration_test/$f.dart"); done
E2E_API_DIR="$WT" bash tool/run_real_e2e.sh "${FILES[@]}"   # the control server stops / starts / seeds THIS stack (not ../solvexo-api)
