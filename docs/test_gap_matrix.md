# Test-gap matrix — Phase 0 audit gaps #1–#30, decisions Q1–Q14 and every "not run / residual" item

**Date:** 2026-11-03 · Phase 5H-B. Sources: `phase5_production_readiness_audit.md` (§3 gaps, Area 9 critical-path table, "verify before release" lists), `phase5_decisions.md`, and the *Not run / Deferred / Residual* sections of every `phase5*_summary.md`.

Legend: ✅ covered before this pass · 🆕 covered by a test added in this pass · 🔧 cannot be automated here — the manual check that replaces it is given.
Paths: **BE** = `solvexo-api/src/…` (jest, real Mongo via `pos/testing/mongo-harness.ts` unless noted), **APP** = `pos/test/…` (`flutter test`), **IT** = `pos/integration_test/…` (iOS simulator).
Test names are quoted from the files; where a gap has many tests only the load-bearing ones are listed.

## Summary

| Status | Count | Gaps |
|---|---|---|
| ✅ Covered before | 23 | #1–#11, #13–#19, #21, #22, #24, #25, #26 |
| 🆕 Newly covered | 3 | #23, #27, #28 |
| 🔧 Not (fully) automatable | 3 | #12, #20 (hardware part), #29 |
| Process item, no test applies | 1 | #30 |

Each "✅" gap also has a *manual residue* where something real-world can't be unit-tested (printers, Apple servers, devices); those are in §3 and carried into `go_no_go.md`. This pass also **hardened** #1, #2, #3 and #6 with new tests (marked 🆕 inside their rows) and **found and fixed two real bugs** (§4).

## 1. The 30 audit gaps

| # | Gap | Status | Covering tests |
|---|---|---|---|
| 1 | POS-plan entitlement enforced server-side | ✅ + 🆕 | BE `pos/guards/pos-entitlement.guard.spec.ts` (active/expired/never bought/suspended/fails closed/rollout flag); `pos.integration.spec.ts` *entitlement guard + manual admin grants*; `pos.offline.integration.spec.ts` *entitlement is judged at the time the offline sale was MADE*; APP `pos_entitlement_service_test`, `billing_ux_test`. 🆕 BE `pos/pos.route-gating.spec.ts` pins **which routes are gated** (selling/shift-opening only) and that close/refund/void/cash/report/PIN-login stay open after expiry (decision Q4) — a new selling route without the guard, or a class-level guard, now fails. |
| 2 | Idempotency on every mutating POS route, per-intent keys | ✅ + 🆕 | BE `common/idempotency.interceptor.spec.ts`; `pos.integration.spec.ts` *idempotent createSale (real Mongo)* (concurrent same key → one sale/one decrement, in-progress 409, stale-claim takeover, replay returns original); APP `pos_repository_idempotency_test`, `idempotency_intent_store_test`, `offline_checkout_resilience_test` (*the checkout identity*, kill/restart). 🆕 `pos.route-gating.spec.ts` asserts every sale/refund/void/cash/shift mutation carries `IdempotencyInterceptor` and lists the only documented exceptions. |
| 3 | Atomic sale pipeline (races, held double-complete, unlimited restore, open-session unique index) | ✅ + 🆕 | BE `pos.integration.spec.ts` (*never oversells*, *only ONE of many concurrent openSession*, *two terminals completing the same held sale*, *concurrent double refund / void vs refund*, *refund and void on an UNLIMITED variant leave stock untouched*); `pos.service.integrity.spec.ts`. 🆕 BE `pos.session-close.integration.spec.ts` *racing the cashier's normal close* — the owner **force-close was not status-guarded** and could overwrite a just-counted shift (bug fixed, §4). |
| 4 | Server recompute of tax/discount/total | ✅ | BE `pos.money.integration.spec.ts` (*a TAMPERED client total is rejected … no sale, no stock taken*, *client `tax` is IGNORED*, *discount over the subtotal*); `pos-money.util.spec.ts`; APP `pos_totals_test`, `pos_cart_math_test`. |
| 5 | Currency + exponent snapshot, one formatter | ✅ | BE `pos.money.integration.spec.ts` (USD/JPY/KWD/PKR stores, reports/CSV exponent, legacy sales backfilled); `pos-money.util.spec.ts` (49 rounding cases); APP `receipt_data_test` (*JPY: no decimals; KWD: three*), `pos_totals_test`. |
| 6 | Partial-refund reconciliation, reports include partial, pro-rating | ✅ + 🆕 | BE `pos.money.integration.spec.ts` (*expected cash after a partial CASH refund (the drawer reconciles)*, *refunds against split tender*, *pro-rates discount AND tax*, *daily report … partially-refunded sales included*); APP `offline_support_test` (*refund instructions per tender … equals what the server deducts*), `pos_session_reconciliation_test`. 🆕 `pos.session-close.integration.spec.ts` *forceCloseSession expected cash = opening + cash sales + cash-in − cash-out* (the owner's force-close math had no test). |
| 7 | iOS usage strings, privacy manifest | ✅ | APP `store_release_test` *iOS: usage strings for every used permission, export-compliance key, privacy manifest in the target*; `ios_config_test`. 🔧 residue: App Store Connect privacy questionnaire (console). |
| 8 | Billing model: no in-app purchase surface | ✅ | APP `billing_ux_test` *source contains no plan list, checkout, Stripe or WebView code* (fails the build if it returns), plan-not-active screen widgets. |
| 9 | Account deletion + Sign in with Apple | ✅ | BE `account-deletion/seller-account-deletion.integration.spec.ts` (*schedules the purge, revokes sessions + every device + PIN sessions, suspends the stores … can be cancelled*; *de-identifies people but KEEPS the sales/tax records*; *idempotent, leaves other sellers alone*), `deletion-reauth.integration.spec.ts` (social re-auth success/mismatch/no password bypass; public OTP: no enumeration, throttle, expiry), `apple-revocation.integration.spec.ts`, `auth/apple-signin-5g1.integration.spec.ts`; APP `store_release_test` *delete account screen* (password, Google-only, Apple, cancelled provider), `apple_signin_test`. 🆕 APP `delete_account_unsynced_test` — the **screen itself** refuses deletion while sales are unsynced (the other tests bypass the guard with `skipUnsyncedGuard`). 🔧 residue: Apple/Google servers (verifier is stubbed in tests) — real-device check in `go_no_go.md`. |
| 10 | Release hygiene (signing guard, R8/proguard, permissions) | ✅ | APP `store_release_test` *Android: minimal permissions…*, *R8 on, proguard rules, targets API 36, release signing fails clearly, secrets git-ignored*, env-config tests. 🔧 residue: run the **release APK/AAB on a real phone** (R8 behaviour) — never done. |
| 11 | Crash reporting, no PII, log gating | ✅ | APP `store_release_test` *crash reporting carries no personal data* (scrub emails/phones/tokens/PINs/ids, path scrubbing, truncation). 🔧 residue: live Crashlytics delivery (needs a real project/build). |
| 12 | Play SHA-1 / `serverClientId` match | 🔧 | Console configuration — not code. Manual: build the **release-signed** AAB, install via Play internal testing, sign in with Google; a wrong SHA-1 shows as `ApiException: 10`. Server side: `GOOGLE_CLIENT_ID` must equal the app's `serverClientId` (verify by decoding the token `aud` in a real sign-in; the verifier itself is stubbed in tests). |
| 13 | Backend test env + specs for createSale/refund/void/interceptor/plans | ✅ | Whole `src/pos`, `src/pos-plans`, `src/common/idempotency*` suites (see rows 1–6, 22); jest `maxWorkers: 2` + shared mongod (`test/jest-global-*.ts`). |
| 14 | Split tender | ✅ | BE `pos.money.integration.spec.ts` *split tender* (card + cash with change, short/over/unknown rejected with **no stock taken**, held sale completed split, legacy single-payment sale refundable); APP `offline_support_test`, `receipt_data_test` (*split tender: one row per tender*). |
| 15 | Offline: queue, clientCreatedAt, rejections, cart persistence | ✅ | BE `pos.offline.integration.spec.ts` (timestamp/window/session period, **oversell recorded + flagged, negative stock**, same key twice concurrently → one sale, price-change-while-offline flagged, approver deactivated after sale, manager review/discard audited); APP `pending_sale_queue_test` (restart survival, FIFO, mutex, backoff, **definite rejection kept, never dropped**), `offline_support_test` (UnsyncedGuard), `offline_checkout_resilience_test` (crash/kill restore, quote-before-charge, cached catalog), `queue_encryption_test`; IT `offline_sync_test`. 🔧 residue: a real airplane-mode toggle (the unit tests use a fake network) — run in 5H-A. |
| 16 | `'∞ Unlimited'` contract + `unlimitedStock` | ✅ | APP `unlimited_stock_parsing_test`, `inventory_models_test`; BE `pos.integration.spec.ts` (*refund and void on an UNLIMITED variant …*). |
| 17 | Customer search store-scoped | ✅ | BE `pos.integration.spec.ts` *store-scoped customer search* (never other stores' buyers; regex-looking query is literal); `pos.service.integrity.spec.ts` (one-char queries). The *shared draft-orders route* is a **product decision**, deliberately unchanged (see §3, R13). |
| 18 | Employee-token 403/401 handling, device revoke, Google sign-out | ✅ | APP `shared_device_security_test` (*the Dio layer turns a POS_DEVICE_REVOKED 401 into exactly that — and NOT a wipe-everything logout*, *POS_LEGACY_AUTH_DISABLED (403) asks the app for device setup and wipes nothing*, *an expired OWNER session … only ends that session*), `pos_pin_login_test`. BE `pos.security.integration.spec.ts` (device token scope, immediate revocation, employee-token revocation in Redis). |
| 19 | Manager gating of reports/settings/employees; PIN-login throttle | ✅ | BE `pos.security.integration.spec.ts` (*manager-PIN gate for devices*: `MANAGER_PIN_REQUIRED`, cashier refused, revoked manager session fails; *per-device PIN rate limiting* → 429 and other devices unaffected; 5-wrong-PIN employee lockout also ends open sessions); `pos.integration.spec.ts` (*a cashier token cannot refund*). The per-IP `@Throttle` decorators are only asserted as metadata (§3, R12). |
| 20 | Printing: permissions, paper width, drawer, auto-print, iOS stance | ✅ / 🔧 | APP `printing_test` (58/80 mm layout, wrapping, copies, drawer pulse first, reconnect once, errors, fire-and-forget, offline cash sale still kicks drawer), `network_printing_test` (fake `ServerSocket`: bytes, timeouts, refusal, discovery, picker). 🔧 **Hardware cannot be automated**: real Bluetooth Classic/BLE/Wi-Fi printer + drawer per platform — manual matrix in `store_submission_checklist.md` §6 (print test page, kick drawer, 58 and 80 mm, iPhone BLE + LAN, Android BT + LAN, unplugged-printer error). |
| 21 | Unified ReceiptData | ✅ | APP `receipt_data_test` (address/tax id/cashier/receipt no., COPY on reprints, VOID/REFUNDED banners, split tender rows, refund rows per tender, non-Latin names, PDF and ESC/POS from the same data). |
| 22 | Plan webhooks: refund/dispute revoke, admin grant/revoke, plan limits | ✅ | BE `pos-plans/pos-plans.billing.integration.spec.ts` (paid-only, redelivery no-op, concurrent redelivery → one purchase, stacking before/after expiry, full/partial refund, newer/older stacked refund, dispute created/won/lost, admin grant/extend/revoke interplay, plan limits) — 23 tests. 🔧 residue: **live Stripe delivery** (needs test keys + Stripe CLI; see R15). |
| 23 | Stock edit via reason-coded delta route; 409/400 surfaced | 🆕 | 🆕 APP `inventory_adjust_stock_test` (delta + reason, never absolute `stock`; same `Idempotency-Key` reused after a lost response; new key after a final answer; **server's 409/400 text reaches the user**). Needed a one-line injectable `client` on `InventoryRepository` (backward compatible). Server side: BE `inventory/inventory.integration.spec.ts` *adjustments* (50 concurrent −1 → exactly 20 succeed, never below reserved) — **env-gated** (needs a replica set via `INVENTORY_IT_MONGO`), so it is skipped in a plain `npm test`; it is run in 5H-A against the local replica-set stack. |
| 24 | Owner-route middleware / device-mode separation | ✅ | APP `shared_device_security_test` (*which routes need the owner, and which credential a request carries*, owner session expiry/slide/end, gate screen, auto-lock, sign-out rules, device registration swaps owner session for device token). BE `pos.security.integration.spec.ts` (*JwtAuthGuard refuses device and PIN-session tokens*). |
| 25 | `GET /api/branding/config` 404 | ✅ | APP `billing_ux_test` *Solvexo POS is one fixed brand (no fetched/white-label config)*; no `branding/config` reference remains in `pos/lib` (grep). |
| 26 | Dead code prune, analyzer clean | ✅ | `flutter analyze` = 0 issues (enforced in CI by the new workflow, below); source-scan tests (`billing_ux_test`, `store_release_test` "no URL hard-coded"). |
| 27 | Flutter CI + integration test | 🆕 | 🆕 `pos/.github/workflows/ci.yml` — `flutter pub get`, `flutter analyze`, `flutter test` on every PR/push (Flutter 3.35.6 pinned). **Not executed here** (no GitHub runner; first real run happens once pushed). `integration_test/` needs a simulator + the local API, so it is a pre-release step (the local-stack doc written in 5H-A), not per-push. Backend CI (`solvexo-api/.github/workflows/ci.yml`) already ran build + jest. |
| 28 | PIN length mismatch (reset 4–6 vs login 4), `create-store` country, CORS header | 🆕 | 🆕 BE `pos/dto/pin-contract.spec.ts` — *every endpoint that SETS a PIN accepts only PINs that PIN-login accepts*. It **failed**: `reset-pin` accepted 5–6 digits, which could never log in (bug fixed, §4). CORS allowed-header list (`Idempotency-Key`, `X-CSRF-Token`, `X-Auth-Mode`) is configuration in `main.ts` with **no automated test** — verified by the portal's real preflight in 5H-A; `PORTAL_ORIGINS` parsing: 🆕 `common/portal-origins.util.spec.ts`. `create-store` country: exercised by the web dashboard only (no POS-owned test; low). |
| 29 | Accessibility / localization | 🔧 | Localization **deliberately deferred** (English-only v1, documented). Accessibility can't be proven by unit tests: manual VoiceOver (iOS) and TalkBack (Android) pass over PIN login, cart, charge, receipt, close shift; check 200 % text scale and touch targets ≥ 44 pt. Listed as *post-launch* in `go_no_go.md`. |
| 30 | Commit pending fixes / WIP | n/a | Process item — closed in 5A (`RedisModule` fix upstream `64889f0`; WIP committed on the branch). |

## 2. Decisions Q1–Q14 → tests

| Decision | Covered by |
|---|---|
| Q1/D1 money model | rows 4–6, 14 |
| Q2 sale currency = store base currency | `pos.money.integration.spec.ts` (*getPosSettings reports the store currency and exponent*) |
| Q3/D2 no mobile billing | row 8 |
| Q4 expired plan: may close/refund/void/read, may not open or sell | 🆕 `pos.route-gating.spec.ts`; `pos-entitlement.guard.spec.ts`; `pos.offline.integration.spec.ts` (*…but not when it was made after the plan had already expired*) |
| Q5 plan limits mechanism | `pos-plans.billing.integration.spec.ts` *optional plan limits* |
| Q6/D4 shared-device model | row 24 + 18 |
| Q7 offline oversell: accept + flag; 72 h window; provisional receipt | `pos.offline.integration.spec.ts`; APP `pending_sale_queue_test`, `offline_support_test` |
| Q8 printers | row 20 |
| Q9 Apple sign-in / account deletion | row 9 |
| Q10 crash reporting | row 11 |
| Q11 environment config | `store_release_test` *environment config* |
| Q12 marketplace leftovers | row 26 |
| Q13 onboarding slides static | no behaviour to test (decision) |
| Q14 WIP commits | process |

## 3. Residual risks from the phase summaries ("Not run / Deferred / Residual")

| Ref | Item (source) | Status |
|---|---|---|
| R1 | Live end-to-end against a real backend + MongoDB; Phase 4 curl matrix not repeated (5A, 5B, 5C) | 🔧 Run in **5H-A** (local stack, simulator + Playwright). |
| R2 | No Mongo transactions; "residual windows" in the sale pipeline (5A) | ✅ Mitigated by atomic status-guarded claims; the race tests in rows 1–3, 6 exercise them against a real mongod. A replica-set reconciliation job remains a post-launch decision. |
| R3 | `inventory.integration.spec.ts` skipped (44 tests; needs replica set) (5A–5F) | 🔧 Run with `INVENTORY_IT_MONGO=…` in 5H-A. |
| R4 | `pos.module-di.smoke.spec.ts` env-gated on `MONGO_URI`; failed once in a combined run with a 180 s connect timeout, passes alone and against a throwaway DB (5G.1) | 🔧 Cause not found; it checks Nest DI wiring only. Re-run in 5H-A against the real stack. |
| R5 | 5 unrelated backend failures present before this work (slug transliteration, translations, themes compat, stripe-connect payouts, payment-webhooks) (5C, 5D) | Out of scope; identical on the base commit. Fix before relying on a full-suite CI gate. |
| R6 | Real OS airplane-mode toggle (5C) | 🔧 5H-A (simulator can toggle the network) + manual on a phone. |
| R7 | Real thermal printer / drawer (5C, 5F, 5F.1) | 🔧 Hardware — row 20. |
| R8 | Apple/Google servers: verifier and revocation are stubbed (5F.1, 5G.1) | 🔧 Real-device sign-in + one real deletion on a throwaway account. |
| R9 | Crashlytics delivery; Play/App Store upload; R8 build on a phone (5F) | 🔧 Manual, in `go_no_go.md`. |
| R10 | CryptoKit/Android crypto path; unit tests run the pure-Dart fallback (5F.1) | 🔧 Manual: install the previous (5F) build, queue a sale offline, upgrade to the RC, confirm the sale still syncs. Format compatibility is pinned by `queue_encryption_test` (*pinned AES-256-GCM vector*, *values written by app versions up to 5F still decrypt*). |
| R11 | Safari ITP / third-party-cookie behaviour of the portal refresh cookie (5G.1) | 🔧 Cannot be emulated by Playwright/Chromium. Manual: sign in on Safari at `account.<domain>`, reload, confirm still signed in; repeat from a `*.vercel.app` preview and confirm it is **not** (documented). |
| R12 | `@Throttle` per-IP limits asserted as metadata only (5G) | Low. The per-**device** PIN limiter and the per-email OTP cooldown are behaviour-tested. A load test against the deployed API is the real check. |
| R13 | Shared draft-orders customer search leaks across stores (web dashboard) (5A) | **Product decision pending**, not a test. POS uses its own scoped route (row 17). |
| R14 | **New finding:** Stripe `successUrl`/`cancelUrl` accept any http(s) host (`IsUrl` only) — an authenticated seller can only redirect *themselves*, so low risk, but the portal's URLs could be allow-listed against `PORTAL_ORIGINS` | Reported, not changed (behaviour change for the existing web dashboard). |
| R15 | Live Stripe delivery (purchase, early-renewal stacking, refund, dispute) (5D.1, 5E, 5E.1) | 🔧 Needs Stripe test keys + Stripe CLI (neither is in this repo); the same flows are covered with simulated webhook events in `pos-plans.billing.integration.spec.ts`. |
| R16 | Android emulator/device smoke test of the R8 release build (5F) | 🔧 Manual. |
| R17 | Entitlement not visible in an unsigned IPA (5F.1) | Static wiring test only (`ios_config_test`); verify with `codesign -d --entitlements :-` on the signed build. |

## 4. Real bugs the new tests exposed (both fixed, both in `solvexo-api`)

1. **`reset-pin` accepted 5–6 digit PINs** while `pin-login`, create and update require exactly 4. An owner resetting an employee's PIN through the API (or any client that does not stop at 4) would lock that employee out with a PIN they can never enter. The app only sends 4 digits, so it was latent. Fixed: `ResetPinDto` is `Length(4,4)`; guarded by `pin-contract.spec.ts`.
2. **`forceCloseSession` was not status-guarded.** It read the open session, then updated by id with no `status:'open'` condition, so a force-close racing the cashier's own close both "succeeded" and the force-close overwrote the counted `closingCash`/`cashDifference` with `null` (and wrote two audit entries). Fixed the same way `closeSession` is: atomic `findOneAndUpdate({status:'open'})`, loser gets `SESSION_ALREADY_CLOSED`; guarded by `pos.session-close.integration.spec.ts` (race repeated 5×).

## 5. Tests added in this pass

| Repo | File | Tests |
|---|---|---|
| solvexo-api | `src/pos/dto/pin-contract.spec.ts` | 4 |
| solvexo-api | `src/pos/pos.session-close.integration.spec.ts` (real Mongo) | 3 |
| solvexo-api | `src/pos/pos.route-gating.spec.ts` | 4 |
| solvexo-api | `src/common/portal-origins.util.spec.ts` | 8 |
| pos | `test/inventory_adjust_stock_test.dart` | 4 |
| pos | `test/delete_account_unsynced_test.dart` | 3 |
| pos | `.github/workflows/ci.yml` (not a test; runs analyze + test) | — |
