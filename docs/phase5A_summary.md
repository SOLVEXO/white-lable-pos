# Phase 5A — Sale & Access Integrity — Summary

**Date:** 2026-10-30 · Backend `solvexo-api` branch `feature/jamibranch` · POS app `pos/` branch `feature/jamibranch` (cut from `main`).
Gap numbers refer to `phase5_production_readiness_audit.md` §3; decisions in `phase5_decisions.md`.

## Result

| Gap | Status | How |
|---|---|---|
| #1 POS-plan entitlement enforced on the backend | ✅ (backend) · app gate screen is 5E | `PosEntitlementGuard`; platform trial guard removed from POS routes |
| #2 Idempotency on every mutating POS route | ✅ | `IdempotencyInterceptor` on 7 routes + per-intent keys on the client |
| #3 Atomic sale pipeline | ✅ with documented residual windows (below) | status-guarded claims, reserve-then-record stock, unique open-session index |
| #16 Inventory `'∞ Unlimited'` contract + `unlimitedStock` in POS payloads | ✅ | typed `isUnlimited`/`stockQuantity`; `unlimitedStock` on POS variants |
| #17 Customer search store-scoped | ✅ for POS · web draft-orders route **deliberately unchanged** (decision needed) | new `GET /api/pos/customers/:storeId/search` |
| #23 Stock edit via delta route with reason, 409/400 handled | ✅ | `adjustVariantStock` + reason chips |
| #30 Commit pending fixes | ✅ | `RedisModule` fix was already upstream (`64889f0`); POS WIP committed on the feature branch |

## Test results

| Check | Result |
|---|---|
| `npm run build` | ✅ clean |
| Backend `npx jest src/pos src/common/idempotency src/inventory src/product-variants` | ✅ 9 suites passed, 81 tests passed (44 skipped = the pre-existing, env-gated `inventory.integration.spec.ts`) |
| Backend POS specs (the ones that previously could not compile) | ✅ `pos.service.spec.ts` now runs after `npm install` (`ua-parser-js` was missing locally) |
| `flutter analyze` | ✅ 4 issues, all pre-existing (1 unused `_RefreshButton`, 3 info) — none new |
| `flutter test` | ✅ **162 passed** (was 127; +35) |
| **Not run:** live end-to-end against a real backend + MongoDB, device/simulator run | ⚠️ the new rules are covered by unit tests with hand-rolled repository fakes only. Phase 4's live curl matrix was **not** repeated. Please run the staging check list in §"Verify before release". |

## Backend changes (`solvexo-api`)

Commits: `2a73bdd` guard + interceptor · `f890ec9` atomic pipeline + customer search · `e68a2fa` inventory typed fields · `7575877` adjust-route idempotency.

| File | Change |
|---|---|
| `src/pos/guards/pos-entitlement.guard.ts` (new) | Requires an active POS plan (latest `PosPurchase` by `purchasedAt` with `expiresAt > now` — identical to `PosPlansService.getStatus`) and a store that exists and is not `suspended`/`rejected` (`pending` KYC stores may trade). **Fails closed** when the store can't be resolved (unlike `BillingAccessGuard`). Resolves the store from `:storeId`/body/query, or from the session/sale a `:sessionId`/`:saleId` belongs to. Errors: `403 {code:'POS_PLAN_REQUIRED'}` / `403 {code:'POS_STORE_DISABLED'}`. |
| `src/pos/pos.controller.ts` | Guard on: `pin-login`, `sessions/open`, `sessions/:id/cash-adjustment`, `sales` (create/hold), `sales/:id/complete`, `sales/:id/items`, `products/search`, `products/:storeId`, `products/barcode/…`. **Not** gated (by design): `sessions/close`, `force-close`, refund, void, discard, all reads/reports, and setup routes (employees/registers/shifts/locations/settings) — an expired plan stops selling but never traps an open drawer or blocks a customer refund. `BillingAccessGuard`/`@RequireActiveBilling` removed from `POST sales` (D3). `IdempotencyInterceptor` on session open/close, cash-adjustment, sale create, complete, refund, void, discard. New `GET customers/:storeId/search`. |
| `src/pos/pos.service.ts` | **createSale:** session must belong to the sale's store; stock is **reserved all-or-nothing before the sale is written** (floor-guarded `$gte`, unlimited variants skipped) and **released** if the sale can't be recorded; the idempotency-key race loser releases its stock and returns the winner's sale. A lost stock race now **rejects** the sale (400) instead of keeping an oversold one. **completeSale:** reserve stock, then claim `held → completed` with a status-guarded `findOneAndUpdate`; loser releases stock and gets 409 (no double decrement/double count). **refundSale:** optimistic-concurrency claim on `{status, refundedAmount}` (+ per-line `refundedQty` in one atomic update with `arrayFilters`) — a concurrent second refund gets 409 and restores nothing. **voidSale:** claim `completed → voided` first. **discardHeldSale:** status-guarded delete. **closeSession:** status-guarded. **openSession:** unique-index violation → clear 400. **Refund/void no longer restore stock on `unlimitedStock` variants** (new `restoreSoldStock`). New `searchStoreCustomers`. `unlimitedStock` added to all three POS product payloads. |
| `src/pos/schemas/register-session.schema.ts` | Unique **partial** index `{registerId, status}` where `status:'open'` — one open session per register, enforced by the database. |
| `src/common/idempotency.interceptor.ts` | An `in_progress` claim older than 2 min is atomically taken over, so a request that died mid-flight no longer locks the client's retry out for the 24 h TTL. |
| `src/inventory/inventory.service.ts` | Product list adds `isUnlimited` and `stockQuantity` (number or null); `stock` keeps its historical mixed type (additive). |
| `src/inventory/inventory.controller.ts` | `IdempotencyInterceptor` on `PATCH :storeId/variant/:variantId/adjust` (a delta isn't retry-safe by nature). |
| Tests (new) | `pos.service.integrity.spec.ts` (19), `guards/pos-entitlement.guard.spec.ts` (11), `common/idempotency.interceptor.spec.ts` (5) |

**Design choice — atomic guards, not Mongo transactions.** Nothing else in this codebase's sale/stock paths uses a transaction (the repo's own `drainLocationStock` takes an optional session but no caller passes one), and transactions require a replica set. The decision (per the brief: "transactions or equivalent atomic guards") is reserve-then-record with compensation plus status-guarded claims. **Residual windows (fail in the safe direction — never duplicate money/stock):**
- a process crash *after* a sale is written but *before* the session counters are incremented leaves the sale correct but the drawer counters one sale short (logged with the sale id);
- a crash *after* a refund/void claim but *before* stock is restored leaves stock un-restored (never double-restored);
- a crash between stock reservation and sale creation leaves stock taken without a sale.
A reconciliation job or true transactions (replica-set confirmation needed) would close these; flagged for 5G/5H.

## POS app changes (`pos/`)

Commits: `366b584` idempotency · `20856cb` unlimited stock / adjust / customer search.

| File | Change |
|---|---|
| `lib/app/data/local/idempotency_intent_store.dart` (new) | One key per **user intent** (fingerprint = action + target + canonical parameters), persisted in `SharedPreferences` so it **survives an app restart**; reused on every retry until released on success or a definite 4xx rejection; 15-min TTL so a stale key can never dedupe an unrelated identical action later; storage failure falls back to an in-process key rather than blocking a sale. |
| `lib/app/data/repositories/pos_repository.dart` | `Idempotency-Key` header on `createSale`/hold, `completeSale`, `refundSale`, `voidSale`, `cashAdjustment`, `openSession`, `closeSession`, and queue replays. **Ambiguous failures** (no response, send/receive timeout, 5xx, 408/409/429) keep the key; **definite rejections** (other 4xx) release it. An ambiguous failure on a sale is **queued under the same key** and a sync is scheduled — the cashier is never told to ring it up again; the server returns the original sale if it was recorded and creates it exactly once if not. `submitRawSale` now reports `retryable`/`code`. |
| `lib/app/data/services/pending_sale_sync_service.dart` | `scheduleSync()` (one-shot retry — needed because an online-but-failed sale has no reconnect event); retryable failures stay queued and re-try every 30 s instead of being marked `failed`; only definite rejections become `failed`. |
| `lib/app/modules/pos_home/controllers/pos_home_controller.dart` | No longer mints a key per tap; queued-sale messages updated ("do not ring it up again"). |
| `lib/app/data/models/inventory/inventory_models.dart`, `pos_product_model.dart` | Parse `isUnlimited`/`stockQuantity`/`unlimitedStock` defensively (legacy string `'∞ Unlimited'` no longer throws); unlimited variants are addable at stock 0, never "low stock". |
| `pos_stock_badge.dart`, `pos_product_tile.dart`, `pos_inventory_view.dart`, home variant picker, inventory controller | "∞ / Unlimited" display. |
| `lib/app/data/repositories/inventory_repository.dart`, `pos_inventory_controller.dart` | Replaced absolute `PATCH …/variants/:id {stock}` with `adjustVariantStock` → `PATCH /api/inventory/:storeId/variant/:variantId/adjust {delta, reason, note?}` with `Idempotency-Key`; reason chips (count correction, restocked, damaged, customer return, other); unlimited variants are refused with a clear message; the backend's 400/409 text is shown and the list is reloaded. |
| `lib/app/network/api_constaints.dart` | `customerSearch` → `/api/pos/customers/:storeId/search`; `inventoryAdjustStock`. |
| Tests (new/updated) | `idempotency_intent_store_test.dart` (7), `pos_repository_idempotency_test.dart` (18), `unlimited_stock_parsing_test.dart` (10); `pos_repository_test.dart` adjusted (its fake `badResponse` had no status code, which real Dio never produces). |

## API contract changes other clients must know about

1. **POS routes now require an active POS plan** (`403 {code:'POS_PLAN_REQUIRED', message}`) — this applies to the **web POS terminal** too (same endpoints). **Every existing store without a `PosPurchase` can no longer start a session, ring sales, or PIN-log-in until it buys a plan.** Coordinate rollout / grandfathering with the admin team (the admin POS-plan endpoints have no manual grant — gap #22, Phase 5E).
2. The platform-plan trial block (`blockDuringTrial`) no longer applies to `POST /api/pos/sales`.
3. `Idempotency-Key` header is accepted (optional, no-op when absent) on session open/close, cash-adjustment, sales create/complete/refund/void/discard and inventory adjust; an exact retry replays the first response; a concurrent duplicate gets `409`. Sales additionally dedupe on the body `idempotencyKey` as before.
4. **New `409 Conflict`** where there was silence or a generic 400: double-complete/discard of a held sale, concurrent refund/void ("changed by another refund or terminal"), closing an already-closed session. A sale whose stock guard loses a race is now **rejected (400)** instead of created.
5. New `GET /api/pos/customers/:storeId/search?q=` (≥2 chars; people who ordered from, or were sold to by, that store). Response shape matches the draft-orders search (`{success, data:[{id,name,email,phone}]}`).
6. Product list (`GET inventory/getStoreInventory/:storeId`) adds `isUnlimited` and `stockQuantity`; `stock` is unchanged (web dashboard unaffected).
7. POS product payloads add `unlimitedStock` per variant.
8. One open session per register is now a DB constraint (`uniq_open_session_per_register`). **Building it fails on any database that already holds two `open` sessions for one register** (Mongo logs it; the app keeps running without the constraint) — close the duplicates first.
9. `IdempotencyInterceptor` (shared with purchase-orders, ai-studio, subscriptions): a stale `in_progress` claim (>2 min) can now be re-claimed. Backward compatible; previously it blocked until the 24 h TTL.
10. Refund/void no longer add stock back to `unlimitedStock` variants.

## Deferred / not done, and why

- **Paywall screen / purchase UI removal** (D2) — Phase 5E. In 5A the app only surfaces the backend's `POS_PLAN_REQUIRED` message; the existing in-app purchase flow is untouched until 5E.
- **Draft-orders customer search leak** (`GET /api/draft-orders/:storeId/customers/search` searches all users): *not changed* — scoping it would stop web sellers attaching a customer who never ordered from them (shared-module behaviour change, rule 4). POS no longer uses it. **Your decision needed.**
- **"Needs attention" UI for failed queued sales, `clientCreatedAt`, cart persistence** — 5C. (5A already stops retryable failures from being silently marked failed.)
- **Not covered by keys:** `editHeldSaleItems` (an absolute replace — naturally idempotent), `discardHeldSale` (server-side status guard + interceptor, no client key), `forceCloseSession`, `pin-login`/`pin-logout`.
- **Plan semantics note:** "active" follows `getStatus` (the *latest* purchase's `expiresAt`). If a store buys a second, shorter plan while a longer one runs, it is judged by the newer one's expiry. Existing behaviour of the webhook (expiry computed from purchase time, no stacking) — flagged for 5E.
- **True Mongo transactions / reconciliation job** — residual windows above; needs a replica-set decision.
- **Backend test debt** (5G): no test for concurrent *real* double submits against a live Mongo (race tests here use fakes).

## Verify before release (staging, ~15 min)

1. Store **without** a POS plan: PIN login → 403 `POS_PLAN_REQUIRED`; buy a plan on the web → works; let it expire → can't open a session but **can close** the open one and refund.
2. Ring a sale, kill the app mid-request (airplane mode right after tap), relaunch, re-ring the same cart → exactly one sale, exactly one stock decrement.
3. Two devices: complete the same held sale at once → one wins, the other gets 409.
4. Open the same register from two devices at once → one fails with "already has an open session".
5. Refund the same line twice quickly → second is rejected; stock restored once; refund an *unlimited* item → stock unchanged.
6. Inventory screen with a digital/unlimited product → list renders, shows "Unlimited".
7. Search a customer name that exists only in another store → no result.

## Next

Phase 5B (money correctness, D1). Stopping here for your approval.
