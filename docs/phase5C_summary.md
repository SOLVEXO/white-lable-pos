# Phase 5C — Offline queue hardening (+ pre-work) — Summary

## Result at a glance

| Item | Status |
|---|---|
| Pre-work 1: full backend jest no longer hangs the machine; full suite run once | ✅ — 198 suites pass; 7 failed: **5 pre-existing/unrelated (verified identical on the base commit), 2 mine (fixed)** |
| Pre-work 2: `POST /pos/sales/quote`, `settingsVersion` + history, server prices with the device's version | ✅ |
| Pre-work 3: refund UX per tender (card machine / cash), receipt rows per tender, cash slice == drawer expectation | ✅ |
| Queued sales keep `clientCreatedAt` (+ server `receivedAt` apart), original key, `settingsVersion`, `sessionId` | ✅ |
| Server validation of synced offline sales (future / too old / session period / plan at sale time) | ✅ |
| Offline stock rule documented and enforced | ✅ — **record the sale, allow negative stock, flag it** |
| Failed items never dropped; "Needs attention" list; retry; manager-only discard with reason + audit | ✅ |
| Close shift blocked while the session's queue isn't empty; sign-out blocked likewise | ✅ (client-side — see note) |
| Cart + in-flight idempotency key persisted across crash/kill/restart | ✅ |
| Catalog/settings cache with stale indicator; banner shows queue size + last sync | ✅ |
| Sync: FIFO per session, one in flight, exponential backoff, resume on connectivity + app foreground | ✅ |
| Business Tax ID in Settings (manager only) | ✅ |
| Real-Mongo backend tests; Flutter lifecycle tests; integration test on a simulator | ✅ (one older integration test fails — see below) |

## Pre-work 1 — the jest hang

**Cause.** 208 spec files on an 8-CPU / 8 GB machine: jest's default is 7 workers, each running ts-jest with full type-checking (~0.5–1 GB), plus (since 5A.1) one `mongod` per integration suite.
**Fix** (`package.json`, `test/jest-global-*.ts`, `src/pos/testing/mongo-harness.ts`):
- `maxWorkers: 2` and `workerIdleMemoryLimit: 1GB` (workers are recycled); `npm run test:full` (= `jest --maxWorkers=2`) and `npm run test:handles` (`--runInBand --detectOpenHandles`).
- **One shared `mongodb-memory-server`** for the whole run via `globalSetup`/`globalTeardown`; each suite gets its own database on it (dropped in `afterAll`, connection closed). A suite run on its own still works (falls back to its own mongod).
- I tried `isolatedModules` to cut memory — it breaks Nest/Mongoose decorator metadata (`Cannot determine a type for the "ActivityLog.category" field`), so the type-checking transform stays.
**Full run (once, `--maxWorkers=2`, ~70 min on this machine):** 208 suites — **198 passed, 3 skipped, 7 failed**; 2118 tests passed, 20 failed.
- **5 suites / 18 tests are NOT ours:** `common/slug-transliteration`, `translations/translations.service`, `themes/liquid/theme-package.compat`, `stripe-connect/stripe-connect.payouts`, `integrations/webhooks/payment-webhooks.controller`. I re-ran exactly those on a clean worktree of the original base commit (`e7c3516`): **the same 5 suites fail with the same 18 tests** — outdated expectations/incomplete mocks (e.g. Arabic transliteration output, a stub missing `storeModel`). I did not touch them.
- **2 tests were ours and are fixed:** the 5A mock-based integrity spec (my `reserveStock` now needs `.lean()` on a lookup) and the 5B money spec (the shared harness lacked the new `posSettingsVersionModel`).
- After the fixes I re-ran the affected areas (`pos`, `pos-plans`, `draft-orders`, `inventory`, `product-variants`, `markets`, `common/idempotency`): **17 suites, 294 tests pass** (44 skipped = the existing env-gated `inventory.integration.spec.ts`). **I did not repeat the 70-minute full run after those two fixes**; no non-POS module imports what changed except `database.*` (one added model) — please let CI run `npm run test:full`.

## Pre-work 2 — totals consistency

- **`POST /api/pos/sales/quote`** (JWT seller + `PosEntitlementGuard`, no side effects, no stock taken): body `{storeId, items[{productId,variantId,qty}], discountType?, discountValue?, settingsVersion?}` → `{lines[{…price,qty,lineTotal}], subtotal, discount, tax, total, taxRate, currency, currencyExponent, settingsVersion, settingsVersionReplaced}`.
- **`settingsVersion`**: `PosSettings.settingsVersion` (default 1) is bumped whenever the **tax rate** changes (optimistic update; unchanged values and other settings never bump); the old values are kept in a new `PosSettingsVersion` collection (`taxRate, currency, currencyExponent, effectiveFrom, supersededAt`). Stores created before this get their version-1 row lazily on first read. `GET /pos/settings/:storeId` returns `settingsVersion`.
- **Pricing rule** (`PosService.moneyContext`): every sale/quote/held-completion carries the version it was priced with; the server prices with **that** version if it exists and was **superseded no more than the offline window ago** (72 h default); an unknown or too-old version silently falls back to the current settings (`settingsVersionReplaced:true` on a quote). So `TOTAL_MISMATCH` now means tampering or a client bug — a tax change mid-checkout or while offline no longer trips it. The sale stores the `settingsVersion` it used.
- **App:** before Charge, when online, the app calls the quote. Same total → it charges that total with the quote's `settingsVersion`. Different (stale price/tax) → the cart is **re-priced from the server's unit prices and tax**, the cashier sees "Total updated — charge $X?" and must confirm before anyone is charged. Server refusal (plan inactive) → nothing is charged. Unreachable → priced with the cached settings (cached `settingsVersion`), and the sale can use the offline queue.
- *Not covered by the version:* **catalog price changes**. A price change while a device is offline produces a real difference — see "price changed while offline" below.

### What the web POS terminal must change (web code is not in this workspace; not edited)
1. Call `POST /api/pos/sales/quote` before charging and show/charge the server's total.
2. Send `settingsVersion` (from the quote or `GET /pos/settings`) on `POST /pos/sales` and `POST /pos/sales/:id/complete`, plus `clientTotal` = the quoted total.
3. Remove any manual tax-rate entry (server ignores a client `tax` since 5B) — use the store rate returned by settings/quote.
4. Handle the new error codes: `TOTAL_MISMATCH`, `DISCOUNT_EXCEEDS_SUBTOTAL`, `PAYMENT_SHORT`, `PAYMENT_EXCEEDS_TOTAL`, `POS_PLAN_REQUIRED`, `POS_STORE_DISABLED`, business 409s (`HELD_SALE_ALREADY_RESOLVED`, `SALE_CHANGED_CONCURRENTLY`, `SESSION_ALREADY_CLOSED`) vs retryable `IDEMPOTENCY_IN_PROGRESS`; send `Idempotency-Key` on every mutating call.
5. If the web terminal has no offline mode it needs nothing for offline sync (never send `offline:true`).

## Pre-work 3 — refund UX for split tender

Refund order is unchanged and documented: **card/other first (in entry order), cash last; cash change is not refundable**.
- The refund confirm dialogs (sale detail full/partial, Orders quick-refund) now spell out per tender what the cashier must do — *"Refund $60.00 on the card machine"*, *"Give $10.00 in cash from the drawer"*, *"Return $X by bank transfer"* — computed by `posAllocateRefund`, a Dart port of the server's `allocateRefund`.
- After the server records the refund a **"Refund recorded — now do this"** dialog repeats the instructions using the **server's own per-tender split** from the response (`tenders[]`).
- The receipt prints one row per tender per refund (`Refund — to card -$30.00`, `Refund — cash returned -$28.42`).
- **The cash slice equals what the drawer report expects**: both the instruction and the server's `cashSales` deduction come from the same allocation; tests assert the Dart fixtures equal the backend's (`cash(70,0)=10`, `cash(100,0)=40`, `cash(25,50)=15`, `cash(25,75)=25`) and the backend real-Mongo suite proves `expectedCash` follows (5B).

## 5C — what the rules are

**Server validation of a synced offline sale** (`offline:true` + `clientCreatedAt`; `src/pos/pos-offline.util.ts`, `PosService.createSale`, `PosEntitlementGuard`):
| Check | Result |
|---|---|
| no timestamp | `400 OFFLINE_SALE_NO_TIMESTAMP` |
| more than 5 min in the future (clock skew allowed) | `400 OFFLINE_SALE_FROM_FUTURE` |
| older than `POS_OFFLINE_MAX_HOURS` (default **72**) | `400 OFFLINE_SALE_TOO_OLD` |
| outside its session's open period (±5 min) | `400 OFFLINE_SALE_OUTSIDE_SESSION` |
| plan not active **at `clientCreatedAt`** | `403 POS_PLAN_REQUIRED` — but a plan that was active then and expired before the sync is **accepted** (a revoke only ends access from the revoke time) |
| store suspended/rejected **now** | blocked (not a "when it was made" question) |
| discount authority | the saved manager token is judged **as of the sale time** (`iat ≤ t ≤ exp`), so a token that expired since is fine; one that wasn't valid then is refused |
The sale is stored with `createdAt = clientCreatedAt` (so reports, shifts and receipts show when it really happened), `receivedAt` = server time, `clientCreatedAt` raw, `isOffline`, `settingsVersion`. A sale synced into a session that has **already closed** is counted into it, and the session's stored `expectedCash`/`cashDifference` are moved with it (the variance then shows exactly the cash that wasn't in the count).
*Bounded abuse note:* a malicious client could back-date `clientCreatedAt` to dodge plan expiry — limited by the 72 h window, by the session-period check, and by needing a plan that covered that earlier time.

**Stock rule (the one rule):** *an offline-synced sale is always RECORDED; stock may go negative for it only; the shortfall is flagged.* Per oversold line: `Sale.flags[{type:'oversold_on_sync', requested, available, sku}]`, `needsReview:true`, POS audit log `sale_oversold_offline`, store inventory activity `inventory_oversell`, and it appears under "Recorded, but flagged for review" in the app for a manager (`GET /pos/sales/needs-review`, `POST /pos/sales/:id/resolve-review` with a note). **Online sales keep the strict no-negative rule** (tested unchanged).

**Price changed while offline:** never a rejection (the customer already paid). Recorded at the **server's current price** with flags `price_changed_while_offline` (+ `payment_shortfall` when the device charged less), `Sale.paymentShortfall`, `needsReview`. The session counts the cash that was **really taken**; the manager sees the gap.

**Failed items:** a definite server "no" (any of the codes above, plan, etc.) → the row becomes `failed` **with the server's code and message** and stays in the queue. Retryable errors (no network, timeouts, 5xx, `IDEMPOTENCY_IN_PROGRESS`) stay `pending` with backoff.
**Discard:** manager only, **reason required**; the row becomes `discarding` and **stays on the device until `POST /pos/offline-discards`** has written the audit entry (`offline_sale_discarded`, with reason, summary, manager) — idempotent per sale key; refused if the sale already reached the server (`SALE_ALREADY_SYNCED` → the row returns to pending).
**Close shift / sign-out:** `UnsyncedGuard` first tries one immediate sync, then blocks with a dialog (count: waiting vs rejected; "Review" opens Needs attention). A manager-resolved (discarded) item no longer blocks. **This is enforced in the app because the queue exists only on the device** — the server cannot know about unsent sales. A forced logout (expired seller token) cannot be blocked, but **never deletes** queue rows (they live in their own SQLite DB, tied to store+session, and are replayed when that store is signed in again).
**Sync engine:** FIFO per session; a sale backing off gates later sales of the same session (other sessions continue); one request in flight (mutex); backoff 5 s → 10 s → 20 s … capped 15 min; resumes on reconnect, on app foreground, and on a scheduled wake-up; a manager's Retry resets it.
**Cart persistence:** the cart, discount, customer, note, payment/split entry **and** the in-flight checkout (`idempotency key` + the moment Charge was tapped) are saved (debounced) and restored for the same store + register session (≤ 24 h). A cart edit drops the key (a changed cart is a different sale); a final answer, a queued sale or `clearSale` clears it. After a kill mid-charge, charging again reuses the same key and time → the server returns the sale it already recorded.
**Catalog/settings cache:** last catalog (≤ 1000 products) and settings (tax rate, `settingsVersion`, receipt text) are cached; offline the till sells from them and shows "Offline — prices and tax from <time>" with a Refresh button. Banner: "N sales saved on this device, will sync · last sync HH:mm" / "N rejected — tap to review".

## Files

**Backend (`solvexo-api`, commit `889b919`):** `src/pos/pos.service.ts`, `pos.controller.ts`, `pos-offline.util.ts` (new), `pos-money.util.ts` (`allowShort`), `guards/pos-entitlement.guard.ts`, `schemas/pos-settings-version.schema.ts` (new), `schemas/pos-settings.schema.ts`, `schemas/sales.schema.ts`, `dto/quote-sale.dto.ts` (new), `dto/create-sale.dto.ts`, `dto/complete-sale.dto.ts`, `database/{schema,database.module,databaseservice}.ts`, `test/jest-global-{setup,teardown}.ts`, `package.json`, `src/pos/testing/mongo-harness.ts`, tests below.
**App (`pos/`, commit `f76b4a4`):** `data/local/{pending_sale_local_store,pos_local_caches}.dart`, `data/services/pending_sale_sync_service.dart`, `data/repositories/pos_repository.dart` (quote, discard, review, replay token, `PosQuote`), models (`PosSaleFlag`, `settingsVersion`, `toJson`s), `pos_home_controller.dart` + view (persistence, quote flow, caches, stale bar), `modules/pos_needs_attention/*` (new), `network_status_banner.dart`, `utils/{unsynced_guard,refund_instructions,receipt_data}.dart`, `components/refund_done_dialog.dart`, settings (tax id tile, sync tile, close-shift guard), `stores_hero_header.dart` (sign-out guard), routes.

## Tests
| Suite | Result |
|---|---|
| Backend `pos.offline.integration.spec.ts` (**real Mongo**, 30) — device timestamp kept apart from `receivedAt`; future/too-old/missing rejected; configurable window; outside-session; sale into a **closed** session moves its expected cash; **late sync after plan expiry accepted / sale after expiry refused / online after expiry refused**; revoked plan covers earlier sales; **oversell recorded + flagged + audited + inventory activity**; online strictness unchanged; **duplicate sync of the same key (concurrent and later) → one sale, stock once, incl. negative path**; price drift recorded not rejected; discount token judged at sale time; **settingsVersion pricing** (bump, history, old/current/unknown/too-old, legacy docs, held completion); quote (matches the sale, no side effects, JPY, replaced flag, empty/unknown); review resolve (manager, note, second → business 409); discard (manager, reason, audited once, refuses synced sale) | ✅ |
| Backend `pos-money.util.spec.ts` +4 (`allowShort`) | ✅ |
| Backend POS + related regression (17 suites) | ✅ 294 passed |
| Flutter `flutter analyze` | ✅ 4 pre-existing issues, none new |
| Flutter `flutter test` | ✅ **267 passed** (was 210): `pending_sale_queue_test` (20, real SQLite via ffi — FIFO, mutex, backoff, failed-kept, retry, discard-until-audited, store scoping, restart persistence, v1→v2 migration), `offline_checkout_resilience_test` (18 — retry reuses key+time, restart restores cart and reuses key, edit drops key, quote flow incl. confirm/decline/refusal/unreachable, caches), `offline_support_test` (refund instructions, `UnsyncedGuard`, repository 5C calls), `receipt_data_test` +1 |
| **iOS Simulator** (iPhone 17 Pro, native SQLite): `integration_test/offline_sync_test.dart` (new) | ✅ 2 passed — queued sales survive a queue restart, back off, sync FIFO with original `clientCreatedAt`/`settingsVersion`/`offline`, a rejected sale is kept. **"Airplane mode" is simulated at the repository seam** (an OS network toggle can't be scripted); the real network path is in the staging checklist. |
| **iOS Simulator:** older `integration_test/pos_checkout_flow_test.dart` | ❌ **fails at its first setup step** (PIN login screen: `selectedRegister` is null — registers don't load from its mocked store) **before any 5C code runs**. I did not establish whether it passed before this phase; not fixed here. |
| Not run | live staging end-to-end; real OS airplane-mode toggle; real thermal printer; the full 208-suite backend run *after* the two final test fixes |

## API contract changes (for the web POS terminal, buyer app, admin dashboard)
1. New `POST /api/pos/sales/quote`; `GET /api/pos/settings/:storeId` adds `settingsVersion`; `POST /pos/sales` and `…/complete` accept `settingsVersion` (priced with that version within the offline window) and the sale stores it.
2. `POST /pos/sales` accepts `offline: true` + `clientCreatedAt` (ISO) → offline-replay rules above. New error codes `OFFLINE_SALE_NO_TIMESTAMP | _FROM_FUTURE | _TOO_OLD | _OUTSIDE_SESSION`. Env `POS_OFFLINE_MAX_HOURS` (default 72) — document in the deploy config.
3. **Sale documents** gain `isOffline, clientCreatedAt, receivedAt, settingsVersion, flags[], needsReview, reviewedBy/At/Note, paymentShortfall`. For offline sales **`createdAt` is the device time**, not server time — anything that orders or filters by `createdAt` now sees the real time of sale; use `receivedAt` for "when did the server learn of it".
4. **Stock can now be negative** for variants oversold by an offline sync (only those) — inventory/storefront views that assume `stock ≥ 0` should tolerate it; affected sales appear in `GET /pos/sales/needs-review`.
5. New endpoints: `GET /pos/sales/needs-review?storeId=`, `POST /pos/sales/:id/resolve-review {note}` (manager token), `POST /pos/offline-discards {storeId, idempotencyKey, reason, summary?}` (manager token, idempotent).
6. New collection `PosSettingsVersion`. A **tax-rate change bumps `settingsVersion`**; other settings changes do not.
7. Entitlement guard on selling routes judges an offline replay at `clientCreatedAt` (see table); `quote` is gated like selling.
8. Refund responses already carry `tenders[]` (5B); the app now relies on it for instructions.
9. Test infrastructure only: jest `maxWorkers: 2`, shared `mongodb-memory-server` (first run downloads the mongod binary; CI needs network or a cached binary).

## Deferred / not done
- **Held-sale completion offline** and **refund/void offline** are not queued (only new sales and holds are); they need the server, and say so.
- **Queue storage is not encrypted**; it holds sale contents and, only for discounted sales, the manager's PIN-session token (needed for server-side authority at the sale's time; 12 h life, but replayable until the server's window rules reject it). Encrypting the DB (SQLCipher) is an option if the threat model needs it.
- **Catalog price change while offline** is flagged, not prevented — the price history needed to honour the device's price doesn't exist.
- Close-shift/sign-out blocking is app-side only (see above). A shared-device scenario where a *different* cashier's queued sales belong to another session is covered per session; a stolen/reset device loses its queue.
- The older `pos_checkout_flow_test` integration test needs its own repair.
- Printer settings (5F), accessibility (5H) unchanged.

## Staging verify checklist (~25 min)
1. **Quote:** change the tax rate in Settings on device B; on device A (stale cart) tap Charge → "Total updated" dialog with the new total; decline → nothing charged; accept → sale at the new total, `settingsVersion` = current.
2. **Offline sale:** airplane mode on; ring a cash sale → "saved on this device"; banner shows "1 sale saved … last sync"; turn airplane mode off → syncs; the sale in Orders shows the **original time**; the shift report counts it.
3. **Restart mid-queue:** go offline, queue 2 sales, force-quit and relaunch → both still queued; reconnect → both sync once each (check no duplicates).
4. **Kill mid-charge:** tap Charge and kill the app immediately; relaunch → cart restored; Charge again → exactly one sale.
5. **Plan expired while offline:** with a plan active, go offline, sell, let the plan lapse (or revoke from admin), reconnect → the sale still syncs; a sale rung up *after* the lapse is rejected and appears under Needs attention.
6. **Oversell:** set a variant's stock to 1 on the server, sell 3 offline, reconnect → recorded, stock −2, listed under "Recorded, but flagged for review"; mark reviewed with a note (manager).
7. **Too old / future:** set the device clock back 4 days (or +1 h) and queue a sale → rejected with the server's reason, kept in Needs attention; retry; manager discard with a reason → check the audit log entry.
8. **Blocking:** with an unsynced sale, try Close Shift and sign-out → both blocked with the count; resolve → allowed.
9. **Refund split tender:** card 60 + cash 40 sale → refund 70 → dialog says "Refund $60 on the card machine / Give $10 in cash"; shift report's expected cash drops by exactly $10.
10. **Stale data:** offline, restart the app → catalog shows with "Offline — prices and tax from …"; Refresh online clears it.

## Next
Phase 5D (shared-device security & RBAC). Stopping here for your approval.
