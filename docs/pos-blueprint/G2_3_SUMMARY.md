# G2.3 — Raast QR checkout on the mock provider (backend + app) — plus the hardening round

Branch `feature/jamibranch` (both repos). No PRs, no merges, no deploys; G1b runbook items still on hold. `PAYMENTS_CORE_API.md` §6, `STORAGE_AND_JOBS_NOTES.md` and `ADMIN_KYB_API.md` carry the details.

## 1. Flaky tests — all runs (backend gate = `src/pos src/pos-plans src/inventory src/product-variants src/common src/draft-orders src/markets src/auth src/scripts src/payments-core src/kyb src/admin-team`)
Baseline in every run: **10 failures = the known slug-transliteration tests** (separate note, untouched). "Clean" below means nothing else failed.

| Run | Result | Anything else that failed → cause |
|---|---|---|
| A1 (earlier, 3 workers) | pos.offline suite + 2 payments/KYB tests: 120 s hook/test timeouts | every test built its own database (~60 DBs × 35 models/indexes on the shared mongod) and my own jest runs overlapped |
| B1 | clean | – |
| B2 | 1 extra | scheduler spec asserted before the retry job had run (test asserted too early) |
| B3 | clean | – |
| C1 | clean | – |
| C2 | clean | – |
| C3 | 1 extra | the same scheduler spec: a "payment busy" collision on the retry path was counted as a failed attempt (backoff 20 s) → **product fix**: busy = skip |
| D1 | clean | – |
| D2 | 35 extra | **OS-level**: `Socket 'connect' timed out after 253746ms` — the test process was frozen ~4 min; swap was 6.5 / 7 GB (8 GB Mac) while I also ran `tsc` |
| D3 | 2 extra (120 s hangs) | same memory pressure |
| **E1, E2, E3** | **clean, clean, clean** (919 passed each) | – (3 consecutive; run with 2 workers + worker memory limit, nothing else running) |

Not accepted as an explanation, so fixed: shared database per spec file (tenants separated by store), sweeps (poller / retry / rotation / retention) use their own database, the scheduler spec waits for the retry outcome and the teardown waits for in-flight ticks, `payment busy` is a skip. The final gate for the G2.3 code is in §6 (F1, F2: clean).

## 2. Schedulers on several instances
Production = `pm2 start dist/main.js` (fork, **one** instance, no ecosystem file). Everything new is safe with several anyway: Mongo lease (`JobLeaseService`, database clock, token + heartbeat, TTL housekeeping, no package), per-payment apply/poll leases, per-inbox-row lease, retention + rotation leases; all writes stay idempotent when a lease expires mid-run (tested). Tests: two instances on one database (no duplicate events, ≤ 1 concurrent provider call per charge, each webhook / document handled once) and the **real `@nestjs/schedule` scheduler** (short `PAYMENTS_TICK_MS` / `KYB_RETENTION_CRON`) running expiry, polling, the retry queue and retention on two instances at once.

## 3. Storage (real Cloudinary, the project's account)
Upload → view → download → replace → remove → purge all verified on the real account (every test file deleted). **Two existing-helper bugs found**: `generateSignedUrl` links **never expire** (`expires_at` ignored) and `deleteFile` **deletes nothing for private assets**. KYB now uses `generateExpiringPrivateUrl` (enforced expiry, ≤ 300 s, verified 200 → 401) and `deletePrivateFile`; links never reach any log channel (tested). Please review the other callers of the old helpers.

## 4. Owner KYB screens
Recorded for G2.4 (owner section in the POS app, no KYB data cached on device, form state cleared on lock / logout / background, screenshots blocked where the platform allows). G2.3 only adds the read-only status card and the gate messaging.

## 5. G2.3 — what was built
**Backend:** `raast_qr` tender in `POST pos/sales` / `complete`: the sale exists only with a CONFIRMED, unused, same-shift, same-currency, exact-amount payment; consumed inside the sale transaction (race-safe across tills); split with QR lines; never offline / held / legacy single form; QR refunds and voids as provider refund events; reconciliation (attach by receipt number / refund / resolve with a 10+ character note) under manager PIN, audit-logged; cancel-checkout releases unpaid QR lines; manager-only verification status; `digitalPaymentsEnabled` on the subscription status; `digitalSales` shift counter and `raast_qr` in reports.
**App:** chooser with Raast QR (disabled + message: cashier "Not available for this store yet", manager/owner "Business verification required", offline "Raast QR needs internet"); QR screen (large amount, white-background QR, server-clock countdown, live status, Cancel, Generate new QR, Choose another method, back-gesture = cancel, screen kept awake, "Simulate customer paid" in debug builds only); the sale is sent only after the payment is confirmed and carries it; a failed save re-attaches the SAME payment (no second QR); a QR sale is never queued; pending payment survives kill / lock and resumes; double taps guarded; success view and receipt show "Raast" and the provider reference; Home: read-only business-verification card and a digital-payments attention row (managers/owners); Needs attention: digital items with the three manager actions.
**Packages added (approved):** `qr_flutter`, `wakelock_plus`.

## 6. Verification
| Check | Result |
|---|---|
| Backend G2.3 spec (`pos.raast.integration.spec.ts`) | 23 tests: confirm→sale, every non-confirmed status refused, late confirm after cancel → attention → sale, duplicate webhook, amount mismatch + refund, line/shift/currency/id/offline/held/legacy rules, 2-till attach race, retry race, held sale, split (+ two QR lines), cancel-attempt, full/partial/void/declined/split refunds + refund idempotency, reconciliation + audit, report, gate |
| Backend gate (final, 2 runs, G2.3 code) | **942 passed** in both runs; the only failures are the 10 known slug-transliteration tests |
| `npm run build` / `test:di` | pass; `dist/main.js` at the root; the circular Pos ↔ Payments modules resolve |
| `flutter analyze` | clean |
| `flutter test` | **696 passed** (new: QR controller 18, flow/widgets 29, home/attention 14, repository 1) |
| iOS simulator, real dev backend, mock provider (`real_backend_raast_test.dart`) | 4/4: full QR sale (+ unconfirmed payment refused, same payment refused twice, shift counts Raast, provider refund), expiry → regenerate → pay → sale, **late pay after expiry → Needs attention → attach by receipt number**, kill mid-wait → resumed, no second QR |
| Screenshots | `g2_3_screenshots/{phone,tablet}/…_{light,dark}.png`: QR screen in 10 states + chooser in 4 states |

## 7. Not verified / limits
* The simulator integration drives the app's controllers + repositories against the real backend (like the existing real-backend suites); the screens themselves are covered by widget tests and the screenshot pass — there is no tap-through UI run of the QR screen on a device.
* Android not run; no real provider (mock only); real-device camera/wake-lock behaviour not exercised beyond the plugin call.
* The G1a PIN-session employee is trusted for attribution at payment creation (any role); manager PIN is enforced on refund / reconcile / verification at the guard.
