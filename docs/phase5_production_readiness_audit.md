# Solvexo POS — Phase 5 / Phase 0: Production-Readiness Audit

**Date:** 2026-10-30 · **Mode:** read-only (only this file was created; nothing installed, committed or reverted)
**POS repo:** local folder `pos/` (remote `SOLVEXO/white-lable-pos`, branch `main`, package `solvexo_pos`) — referred to below as `pos/`. The brief calls it `white-lable-pos/`; no folder of that name exists locally, so this report lives in `pos/docs/`.
**Backend:** `solvexo-api/`, branch `feature/jamibranch` @ `e7c3516`.
**Baseline:** `docs/phase0_audit_report.md`, `phase1..4_summary.md`, `phase4_backend_followup_summary.md`. Their "deferred / not built / backend gap" items were re-verified against current code.

Legend: ✅ production-ready · 🟡 partial · ❌ missing · ⚠️ broken. Paths are `pos/lib/app/...` (`app:`) or `solvexo-api/src/...` (`api:`) unless stated. Findings come from code reading by five parallel auditors; the ones I re-checked myself are marked **(verified)**. Items I could not verify are marked *(unverified)*.

---

## 0. Working-tree state

- **pos/** has uncommitted changes (modified: `android/app/build.gradle.kts`, `pos_login_view.dart`, `app_pages.dart`, `app_routes.dart`, `main.dart`, `app_prefrences.dart`; untracked: `modules/onboarding/`, `modules/splash_screen/`, `config/onboarding_content.dart`, `components/animated_background_circles.dart`). Only 2 commits exist on `main` (`29ebdda`, `59e3783`). The release-signing config is part of the uncommitted diff.
- **solvexo-api/** uncommitted diff, `src/pos-plans/pos-plans.module.ts`:
  ```diff
  +import { RedisModule } from '../redis/redis.module';
  -  imports: [AuthModule, SubscriptionsModule],
  +  imports: [AuthModule, RedisModule, SubscriptionsModule],
  (+ an explanatory comment block)
  ```
  **Verdict: needed — keep and commit it (on `feature/jamibranch`, when you approve).** `JwtAuthGuard` injects `RedisService` (`api: auth/guards/jwt-auth.guard.ts:14-19`); `RedisModule` is not global and `AuthModule` imports but does not re-export it (`auth.module.ts:47`). Both `PosPlansController` (`pos-plans.controller.ts:12`) and `AdminPosPlansController` (`admin-pos-plans.controller.ts:17`) use `JwtAuthGuard`, so without it every authenticated pos-plans route 500s (`isConnected` of undefined) — the same bug class as the memory note on GiftCards/Metafields/Menus. Not committed or reverted.

## 1. Executive summary

**Is it shippable today? No.** The POS feature surface is broad and the core flows are real and well-tested at the controller level (127 Flutter tests pass; `flutter analyze` has 4 minor issues). But there are release-blocking defects in store compliance, in money correctness, and in server-side enforcement:

**Top blockers, in order**

1. **Paid access is not enforced by the backend.** The POS-plan paywall is client-side only. Nothing in `api: src/pos` reads `PosPurchase`; a seller with a JWT can open sessions and create sales via the API without ever buying a plan. Worse, the sale route is gated by a *different* entitlement (platform-plan `BillingAccessGuard`, `blockDuringTrial`), so a store that *did* buy a POS plan can still get 403 while trialing. (Areas 1, 5)
2. **Duplicate-sale risk on retry.** The idempotency key is minted on every Charge tap (`app: pos_home_controller.dart:497,542,562`), not once per checkout attempt; request timeouts are not treated as ambiguous. Refund, void, cash-in/out, session open/close and held-sale `complete` carry no key at all. (Area 3)
3. **Server-side sale integrity gaps:** no atomicity (sale/stock/session totals), the stock guard loses races but keeps the sale, held-sale double-complete, open-session race (no unique index), refund/void inflate *unlimited-stock* variants. (Area 3)
4. **Money correctness:** server trusts client `tax`/`discount` and does not validate discount ≤ subtotal; no currency on the sale; `toFixed(2)` everywhere (wrong for JPY/KWD); **partial cash refunds are never deducted from `expectedCash`** and `partially_refunded` sales are excluded from reports. (Area 2)
5. **App Store / Play compliance:** (a) in-app WebView Stripe checkout unlocking app features (Apple 3.1.1 / Play Billing); (b) iOS crashes on first camera scan — **no `NSCameraUsageDescription` (verified)**; (c) no `PrivacyInfo.xcprivacy` **(verified)**; (d) no in-app account deletion; (e) Google sign-in without Sign in with Apple. (Area 10)
6. **Build/release hygiene:** Gradle signing block casts `key.properties` values unconditionally (build breaks without the file) **(verified)**; R8 enabled with a missing `proguard-rules.pro` **(verified)**; no crash reporting; Android manifest declares no permissions (Bluetooth printing relies on plugin merging, no runtime request). (Area 10, 7)
7. **Offline queue exists but is unsafe:** failed sales are silently dropped from view (money loss), sale timestamps become sync time, no local receipt, cart not persisted. (Area 4)
8. **Backend verification can't run here:** `pos.service.spec.ts` fails to compile because `ua-parser-js` is declared in `package.json` but missing from local `node_modules` (environment, not logic). **(verified)**
9. **Smaller but real:** inventory screen blanks if any product is unlimited/digital (`stock` is the string `'∞ Unlimited'`) **(verified)**; customer search leaks buyers across stores (backend); `GET /api/branding/config` still 404; employee-token expiry unhandled in the client.

**What is solid:** route/DTO matching for ~60 POS calls; employee-JWT RBAC on money actions; PIN lockout (5 tries / 15 min, atomic); webhook signature + idempotency for POS plans; unique sparse idempotency index with E11000 recovery; Firebase config now consistent (the earlier stale-project finding is **fixed**); tokens in secure storage; base URL via dart-define with no dev URLs.

---

## 2. Audit areas

### Area 1 — Backend contract drift — 🟡

~60 distinct app calls were matched against controllers/DTOs. Nearly all POS routes match (method + path + required fields): auth, store, categories, upload, inventory, product-variants, activity-log, customers, all `/api/pos/*`, and all three `pos-plans` user routes (`app: pos_subscription_repository.dart:41,57,81` ↔ `api: pos-plans.controller.ts:19,24,29`; response shapes match the Dart models).

Global behaviour: `ValidationPipe({ transform: false })` (`api: main.ts:70`) — no whitelist/forbid, so extra fields are ignored (pos-plans, draft-orders, product-variants add their own `whitelist: true`). `/api/pos/*` is behind `@RequireFeature('posMode')` (`pos.controller.ts:44-45`) — if the platform flag is off, every POS call returns 503.

| # | Finding | Sev | Evidence |
|---|---|---|---|
| F1 | **Inventory list crash.** Backend returns `stock: '∞ Unlimited'` (string) for digital or unlimited-variant products; app does `json['stock'] as int? ?? 0` → `TypeError`; repository's generic `catch` returns an **empty page**, blanking the whole inventory screen. **(verified)** | High | `api: inventory/inventory.service.ts:86-98,149`; `app: data/models/inventory/inventory_models.dart:57`; `inventory_repository.dart:80-83` |
| F2 | `GET /api/branding/config` still does not exist (known gap, open). App degrades to defaults on 404. | Med | `app: branding_repository.dart:20`, `api_constaints.dart:21` |
| F3 | POS product payloads omit `unlimitedStock`; app gates "in stock" on `stock > 0`, so unlimited variants are blocked in the UI though the server accepts them. POS list filters `type:'physical'` only. | Med | `api: pos.service.ts:459,488-497,727,866`; `app: pos_home_controller.dart:710,739`, `pos_product_model.dart:79` |
| F4 | **Customer search is not store-scoped** (backend privacy leak): any seller can regex-search all buyers by name/email/phone. | Med-High | `api: draft-orders.service.ts:524-533`; used at `app: customer_repository.dart:73` |
| F5 | Stock edit semantics changed: `PATCH …/variants/:vid {stock}` now optimistic-concurrency (409 on change), 400 when stock spans multiple locations, rejects values below `committedStock`. New delta route `PATCH inventory/:storeId/variant/:variantId/adjust {delta, reason, note?, locationId?}` (supports a **reason** — closes the Phase 2 "reason-coded adjustments" gap) is unused by the app. | Med | `api: product-variants.service.ts:104-112,218-222,263-266`; `inventory.controller.ts:110` |
| F6 | `POST /pos/sales` now has `BillingAccessGuard` with `blockDuringTrial` (platform-plan entitlement) — separate from the POS-plan entitlement the app gates on; app has no specific handling of the 403. | High (see Area 5) | `api: pos.controller.ts:279-291`, `platform-plans/guards/billing-access.guard.ts:51-69` |
| F7 | Idempotency is the **body** field `idempotencyKey`; `IdempotencyInterceptor`/`Idempotency-Key` header is not applied to any POS route (only purchase-orders, ai-studio). CORS `allowedHeaders` omits `x-pos-employee-token` (matters only for Flutter web). | Low | `api: create-sale.dto.ts:95`, `common/idempotency.interceptor.ts:28`, `main.ts:138` |
| F8 | `PUT users/profile` is dead code **and** wrong for sellers (only edits the buyer model); the role-aware route is `PATCH auth/edit-profile`. | Low | `app: upload_repository.dart:173,183`; `api: users.service.ts:54`, `auth.controller.ts:191` |
| F9 | Reset-PIN accepts 4–6 digits; create/update/login require exactly 4 — a 5–6 digit reset PIN can never log in. | Low | `api: reset-pin.dto.ts` |
| F10 | `POST store/create-store` — `country` optional "for older clients"; app never sends it. | Low | `api: store.service.ts:172-177` |
| F11 | `GET api/onboarding-slides` exists (public) but the app uses static `config/onboarding_content.dart` (memory notes said dynamic — **the POS app does not use it; the buyer app does**). Not drift, a product-consistency question. | Low | `api: onboarding-slides.controller.ts:40`; `app: config/onboarding_content.dart:25` |
| F12 | Social login: backend verifies **Google ID tokens** (`GOOGLE_CLIENT_ID` audience), not Firebase ID tokens; `serverClientId` in app must equal deployed `GOOGLE_CLIENT_ID` *(unverified — local `.env:46` is empty)*. | Med | `api: auth.service.ts:436-445`; `app: social_auth_service.dart:17-19` |

**Dead constants:** `api_constaints.dart` has 329 static members (834 lines); only **66 are referenced**, **263 (~80%) are unreferenced** (buyer cart/orders/checkout, ratings, messaging, loyalty, subscriptions, AI Studio, SEO, platform-plans, KYC `storeVerification*`, etc.). Contradicts the pubspec's "trimmed to what POS uses".

**Done looks like:** F1/F3 fixed in the app, F4/F2 fixed in the API (or branding route removed from the app), contract test (Dart fixture ↔ DTO) for the live 66 constants, dead constants pruned.

### Area 2 — Money & currency — ⚠️

| Item | Status | Evidence |
|---|---|---|
| Money representation | 🟡 (🔴 for non-2-decimal currencies) | App: `double` for all money (`app: data/models/pos/pos_sale_model.dart:11-69`). API: `Number` major units, no currency/rate field on `Sale`/`SaleItem` (`api: pos/schemas/sales.schema.ts:23-81`). |
| Cart math | 🟡 | Plain double arithmetic, no rounding (`app: pos_home_controller.dart:178-192`); percent discount clamped to subtotal (`:184-188`); tax is a cashier-typed % (`:133,176`), **not** `settings.taxRate`. |
| Server recompute/validation | ❌ | `dto.tax` trusted verbatim (`api: pos.service.ts:753`); `total = subtotal - discount + tax` unrounded (`:756`); no discount ≤ subtotal check (DTO is `@Min(0)` only, `create-sale.dto.ts:60-71`) — total can go negative. |
| Refund math | 🟡 | Per-line `qty*price` with `toFixed(2)` (`pos.service.ts:1017`); tax/discount not apportioned → discounted/taxed sales mis-refunded. |
| Session cash reconciliation | ⚠️ | `expectedCash = opening + cashSales + cashIn − cashOut` (`:524-528`). Full refund and void decrement `cashSales` (`:992-996`, `:1432-1436`); **partial refund only bumps `totalRefunds` (`:1038`), so a cash partial refund never lowers `expectedCash`** → drawer reads short. `getSessionReport`/`getDailyReport` sum only `completed` sales (`:663-669`, `:1070`) and ignore `partially_refunded`. Partial then full refund also decrements `totalTransactions` incorrectly. |
| Currency per sale / Markets | ❌ | `Store.baseCurrency` exists (`api: store.schema.ts:365`); `PosSettings.currencySymbol` is **free text**, default null (`pos-settings.schema.ts:28`), not tied to `baseCurrency`/Markets. Finance ledger uses `store.baseCurrency \|\| 'USD'` (`pos.service.ts:65-84`) so ledger and sale display can disagree. Markets' frozen exchange rates live in payment/orders code, **not applied to POS sales**. |
| Decimals per currency | ❌ | `toStringAsFixed(2)` in 73 places in the app (e.g. `pos_sale_detail_view.dart:155-206`); `pos_stats_row.dart:39` uses 0. Backend already has `getCurrencyDecimals` (JPY=0, KWD=3) and `toStripeAmount` (`common/currency-metadata.const`, `common/stripe-amount.util.ts:26`) — unused by POS. |
| `CurrencyFormatter` | ❌ dead | `app: lib/utils/currency_formatter.dart` (PKR/USD only; zero call sites). Every module seeds `'$'.obs` then overrides from settings. |

**Decision framing (open question Q1):** full integer-minor-units migration is large and risky; the pragmatic production bar is: server stores `currency` + `currencyDecimals` (+ optional frozen rate) on each sale, rounds per line then sums using `getCurrencyDecimals`, and recomputes tax/discount server-side; the app uses one currency-aware formatter. Pure minor units can then be a later hardening.

**Done looks like:** sale snapshot carries currency/decimals (and base-currency rate); server recomputes + validates tax/discount; refunds pro-rate tax and discount; session totals/reports include partial refunds; one formatter; `currencySymbol` derived from `baseCurrency`.

### Area 3 — Sale integrity — ⚠️

| Item | Status | Evidence |
|---|---|---|
| createSale / holdSale key sent | 🟡 sent on every call, **not stable across retries** | `app: pos_home_controller.dart:497,542`; `_newIdempotencyKey()` = `'${employeeId}-${microsecondsSinceEpoch}'` (`:562-563`) minted per tap **(verified)**. Only `connectionError`/`connectionTimeout` are queued (`pos_repository.dart:754-760`); send/receive timeouts and 5xx → cashier re-taps → new key → duplicate sale. |
| completeSale (held), refund, void, cashInOut, open/close session | ❌ no key either side | `pos_repository.dart:496,528,631,927,1012,1048`; `api: pos.service.ts:622-625` (`$push` not idempotent) |
| Unique index + E11000 | ✅ | `api: sales.schema.ts:127` unique+sparse; key omitted not null (`pos.service.ts:792`); pre-check `:696`; E11000 refetch `:797-801`; saleNumber collision retries ×5. Caveat: index is global but lookup is `storeId`-scoped (cross-store collision would throw). |
| Floor-guarded stock decrement | 🟡 | `$gte` on available stock, `unlimitedStock:{$ne:true}` (`:815-824`) atomic per variant, **but the sale is created first and a lost guard only `console.error`s and keeps the sale** (`:836-846`) → oversell possible; pre-check is a non-atomic read (`:722-725`). |
| Atomicity | ❌ | No Mongo transactions in sale/void/refund/session paths. Multi-item sale can decrement item 1 and fail item 2; a crash after `create` and before `_incrementSessionTotals` leaves a sale missing from session totals. |
| Held-sale concurrency | ❌ | `completeSale` reads `status` then `findByIdAndUpdate` with no `status:'held'` filter (`:884-898`) → two terminals can both complete and double-decrement/double-count. |
| Refund/void stock restore | ⚠️ | Restores for **every** item including `unlimitedStock` variants (refund `:975-980`, `:1021-1025`; void `:1421-1424`) → inflates unlimited stock; non-atomic status check → concurrent double refund/void restores twice; void refuses `partially_refunded` (`:1413`). |
| One open session per register | ❌ | `findOne`→`create` (`:497-503`), only non-unique indexes (`register-session.schema.ts:99-104`) → two terminals can open two sessions on one register. |
| Role/discount enforcement | ✅ | Employee JWT verified for refund/void/cashInOut/discount (`pos.service.ts:126-130,673,711,857,971,1419`). |

**Done looks like:** key per checkout attempt, persisted, reused until success/new cart; ambiguous timeouts replay with the same key; every POS write idempotent (body key or existing `IdempotencyInterceptor`, with `{storeId,key}` unique); atomic `findOneAndUpdate` status transitions; all-or-nothing stock with transaction or compensation; skip restore for `unlimitedStock`; partial unique index `{registerId}` where `status:'open'`.

### Area 4 — Offline — 🟡 (stale in prior docs: a queue now exists)

| Item | Status | Evidence |
|---|---|---|
| sqflite store | 🟡 | `app: data/local/pending_sale_local_store.dart:40-135` — one table (idempotency key as id, payload JSON, status pending/failed, error, createdAt); no migrations. |
| Enqueue on connectivity failure | 🟡 | `pos_repository.dart:806-813` — completed and held sales both queued, returns `queued:true`; UI clears cart + snackbar (`pos_home_controller.dart:499-504,544-549`). |
| Drain on reconnect | 🟡 | `data/services/pending_sale_sync_service.dart:30-69` — on online-flip and app start, oldest first, mutex; **no periodic timer/backoff/"sync now"**. |
| Key persisted; replay safe | ✅ | Key is row id; server dedupes before session check (`api: pos.service.ts:696-699`). |
| Failed-sale handling | ❌ | Non-connectivity failure → `markFailed` (`sync_service:58-62`); nothing reads `failed`; `countPending` ignores them so the banner vanishes → **silent money loss**. No retry/discard/review UI. |
| Conflict policy | ❌ | Stock shortage, closed register, expired plan, expired employee token (403) and price change all become permanent `failed`. Server re-prices from current price (`:731`). Employee token is read fresh at sync (`pos_repository.dart:82`) — a logged-out cashier's queued sales fail. |
| Server offline support | ❌ | No `clientCreatedAt`/`offline` in `create-sale.dto.ts` or `sales.schema.ts`; `createdAt` = sync time → wrong shift reports, receipt dates and session attribution; session must still be open at sync. |
| Receipt for queued sale | ❌ | No sale returned, no local number, no print. |
| Cart persistence (crash/kill) | ❌ | `cartItems` is an in-memory `RxList` (`pos_home_controller.dart:121`). |
| Connectivity signal | 🟡 | Interface state only, no reachability (`network_status_service.dart:19-36`). |
| BaseClient retry | ✅ | GET only, 3 attempts; POST/PUT/PATCH never retried (`base_client.dart:11-60`). |

**What a safe offline queue needs**
- *Client:* pending/failed screen (retry, confirmed discard, error reason; badge counts failed too); error classification (transient → backoff; 401/403 token → pause + re-PIN, resume; 400 conflict → human review); periodic drain + manual sync; one key per checkout, ambiguous timeouts replayed; persist cart + pending checkout; snapshot shown price/total in the payload; provisional local receipt `OFF-<terminal>-<seq>` mapped to the real number after sync; bound/protect the DB.
- *Server:* accept validated `clientCreatedAt` + `offline:true` (not future, within N days) and set `createdAt` from it; attach to the session that was open at that time or flag late-synced; policy for stock (accept the completed cash sale, flag `stockConflict`); price-change flag; structured error codes (`SESSION_CLOSED`, `INSUFFICIENT_STOCK`, `PRICE_CHANGED`, `PLAN_EXPIRED`); a sale-time employee attestation so a rotated 12h token doesn't block a legitimately recorded sale.
- **Prerequisite:** Area 3 server fixes first (atomicity, all-writes idempotent) — otherwise offline multiplies the race risk.

### Area 5 — Payments & POS plans — ❌ / 🟡

| Item | Status | Evidence |
|---|---|---|
| Split tender | ❌ | Single `paymentMethod` enum `cash\|card\|other` (`api: sales.schema.ts:62-63`); no payments array in `CreateSaleDto` (`create-sale.dto.ts:73-74`). |
| Card/bank reference | 🟡 | Folded into free-text `notes` (`app: pos_home_controller.dart:~417-419`, `paymentReferenceController :140`); no field for a card auth code. |
| Cash tendered / change | ❌ persisted | Client-only (`pos_home_controller.dart:202-209`); not on the sale, so receipts can't reprint it. |
| POS-plan purchase flow | ✅ | Server-priced checkout (`toStripeAmount`, platform tax) `pos-plans.service.ts:80-114`; status derived from `expiresAt > now` (`:44-66`) so no flag drifts; purchases snapshot the plan (`pos-purchase.schema.ts`). |
| Webhook | ✅ | `constructEvent(rawBody, sig, secret)` (`pos-plans-webhook.service.ts:33-44`); idempotent via unique `stripeCheckoutSessionId` + E11000 no-op (`:67-90`). Only `checkout.session.completed` is handled — **no `charge.refunded`/dispute handling**, a refunded plan stays active. |
| Admin endpoints | 🟡 | List/create/patch plans + list purchases exist (`admin-pos-plans.controller.ts:25-45`); **no manual grant/extend/revoke**. |
| App paywall | 🟡 client-only | `SellerPosManagementController.openPosTerminal()` → `GET pos-subscriptions/:storeId`, only `active` entitles (`seller_pos_management_controller.dart:330-355`); WebView success/cancel interception + polling (`pos_subscription_checkout_controller.dart:50-90`). `PosAccessMiddleware` does **not** check the subscription (by design, mid-shift lapse is not interrupted). |
| **Backend enforcement** | ❌ **blocker** | `posPurchaseModel` is referenced only inside `pos-plans` (nothing in `src/pos`). `PosController` has only the platform `posMode` flag; `createSale` uses `BillingAccessGuard` against the **platform-plan** subscription (F6). A JWT holder can call `sessions/open`, `sales`, refund… with no POS plan; and a POS-plan buyer can be blocked by the platform-plan trial gate. |
| Per-plan limits / trial / grace | ❌ | `PosPlan` has only name, price, currency, durationInDays, description, isActive — no `maxRegisters/maxEmployees/maxLocations`; no trial/grace; status is `none/active/expired`. |

Never fake client-side what the API doesn't enforce — this is precisely the situation today, so the plan is to build the guard in the backend.

**Done looks like:** `payments:[{method, amount, reference?, tendered?, change?}]` on `CreateSaleDto`/`Sale` (sum = total; methods extended with `bank_transfer`/`wallet`; per-tender session totals; drop the `notes` hack); `PosEntitlementGuard` (active `PosPurchase` for `storeId`, configurable grace, clear 402/403 code, closing an open session always allowed) on session-open, sales, complete, pin-login; reconcile with/replace the platform-plan `blockDuringTrial` on POS routes; plan limits enforced on register/employee/location creation; webhook revokes on `charge.refunded`/dispute; admin manual grant/revoke; app treats the 402/403 as truth and the paywall is UX only.

### Area 6 — Auth & RBAC — 🟡

| Item | Status | Evidence |
|---|---|---|
| Firebase config consistency | ✅ | All platforms → project `solvexo-cec1a` (707145385701). Android app id matches `google-services.json:62-64` and `applicationId`/`namespace` `com.solvexo.solvexo_pos` (`build.gradle.kts:20,40`); iOS app id matches `GoogleService-Info.plist:34`; bundle `com.solvexo.solvexoPos` matches pbxproj:503; `Info.plist:59` URL scheme matches `REVERSED_CLIENT_ID`. The earlier stale-project finding **no longer applies**. |
| Google Sign-In client ids | 🟡 | Code `serverClientId` = `…quuhmj…` (`social_auth_service.dart:17-19`) differs from the Firebase-created web client `…24e0ir…` (`google-services.json:78`). Works only if server `GOOGLE_CLIENT_ID` equals it exactly *(unverified)*. Only one Android SHA-1 registered (`google-services.json:72`) — release and Play App Signing SHA-1 must be added or store builds fail with `DEVELOPER_ERROR`. |
| Route guards | 🟡 client-only | `PosAccessMiddleware` is now synchronous (`middleware/auth_middleware.dart:27-47`); unguarded: splash, onboarding, posLogin, sellerOnboarding, sellerStores, sellerHome, sellerPosManagement, sellerPosLocations (`app_pages.dart:60-90`). On a shared device a cashier can navigate to owner screens; server seller-JWT is the only barrier. |
| Employee JWT | 🟡 | Stored in secure storage (`app_prefrences.dart:274-281`), sent as `x-pos-employee-token` (`pos_repository.dart:84`), 12h expiry (`api: pos.service.ts:301`). Backend returns **403** (not 401) on missing/expired/wrong-store (`:111-129`) — correctly does not wipe the seller session — but the **client has no handling**: no `exp` decode/timer/auto-route to PIN; cashier sees a generic toast until manual PIN re-login. |
| Seller token | ✅ / ❌ refresh | 401 on auth'd call → `clearPreference()` (prefs + secure storage + cached flags) + force-logout (`dio_service.dart:56-61`, `app_prefrences.dart:197-204`). Refresh token stored but **never used** (no interceptor). Google `signOut` not called on logout paths. |
| PIN lockout | ✅ backend / 🟡 client | 5 attempts / 15 min, atomic, resets on success (`pos.service.ts:42-43,259-286`); spec exists (`pos.service.spec.ts:91-152`, currently not runnable). `pin-login` has no `@Throttle` beyond the global 100/min (`app.module.ts:125`); 4-digit PIN. |
| Backend RBAC | 🟡 | All POS routes `JwtAuthGuard + RolesGuard + FeatureFlagGuard` (`pos.controller.ts:44`), mostly `@Roles('seller')`. Manager-token enforced only on money actions. **Not manager-gated:** reports, audit-logs, settings PATCH, employee CRUD/reset-pin, register/shift deletion, force-close — a cashier PIN session on the owner's device has full seller power at the API level. |
| Admin 2FA / rate limiting | ✅ n/a | Not on the POS path. |

**Done looks like:** server-verified Google client id + all SHA-1s registered; client catches the employee-token 403 (or decodes `exp`) → clear POS session → PIN screen; refresh-token interceptor with single-flight lock; Google sign-out on logout; `@Throttle` on pin-login; manager token required on the routes above; middleware on owner routes (or device-mode separation — see Q6).

### Area 7 — Printing & receipts — 🟡 (iOS ❌)

| Item | Status | Evidence |
|---|---|---|
| Pairing/discovery | 🟡 | Lists **already-paired** devices only; MAC persisted (`app: data/services/thermal_printer_service.dart:30-50`, `pos_printer_picker_sheet.dart`). |
| Android permissions | ⚠️ | Manifest has **no `uses-permission`** (INTERNET only in debug/profile); no `BLUETOOTH_CONNECT/SCAN` declared or requested at runtime — picker is silently empty (`thermal_printer_service.dart:34`). Merged release manifest *(unverified)*. |
| iOS | ❌ | `Info.plist:48-51` has strings but `print_bluetooth_thermal` on iOS reaches **BLE printers only**; classic SPP units unreachable. No LAN/Wi-Fi printing on either platform. |
| Paper width / charset / logo / QR / drawer | 🟡/❌ | Builder supports `PaperSize` (default 80mm) but never passed; no codepage selection (non-Latin prints wrong); no logo/QR/barcode; no cash-drawer kick; no auto-print after sale (manual button on sale detail only). |
| Reprint | 🟡 | Print/Share PDF/Share text from sale detail (`pos_sale_detail_controller.dart:203-225`); not marked "COPY"; not available from the orders list. |
| PDF | 🟡 | Default PDF font has no Unicode glyphs (currency symbols/non-Latin names can break). |

| Receipt field | State |
|---|---|
| Business name / footer | PDF + ESC/POS yes; text share no |
| Address, tax id | missing everywhere (`businessAddress` exists in `PosSettingsModel:7`, unused; no tax id field) |
| Receipt number / date | number yes (falls back to Mongo id); date is raw `toLocal().toString()` |
| Cashier | missing (sale has `employeeId` only) |
| Lines | name × qty and total; no unit price |
| Tax | single "Tax" amount; no rate label/breakdown (`taxRate` unused) |
| Currency/decimals | symbol + `toStringAsFixed(2)` (wrong for JPY) |
| Payment | method only; no tendered/change/split |
| Refund/void | "Refunded $x" only; **voided sale prints as a normal receipt**; partial refunds don't list items |
| Consistency | three formats (PDF/ESC-POS/text) differ; text is weakest |

Backend has no receipt/document endpoint; only `receiptHeader/receiptFooter` settings (`api: pos-settings.schema.ts:16-19`).

**Done looks like:** declare + runtime-request Bluetooth permissions (API 31+ and legacy) with explanation/settings fallback; state iOS BLE-only or add TCP/LAN printing; printer settings (width, codepage, copies, test print, drawer kick, auto-print); one `ReceiptData` model rendered to PDF/ESC-POS/text incl. address, tax id, cashier, formatted date, unit price, tax breakdown, tendered/change, VOID/REFUNDED/COPY banners; Unicode PDF font; currency-aware decimals.

### Area 8 — Code health — 🟡

| Item | Status | Evidence |
|---|---|---|
| BaseController adoption | ❌ | 0 subclasses (only its own file); 33 files extend `GetxController` directly (29 module controllers). Its doc comment still mentions the buyer app's `MyOrdersController` (`core/base/base_controller.dart:14-18`). |
| Redundant `Get.put` in views | ⚠️ | 14 views `Get.put` in-view; redundant with bindings: `pos_home_view.dart:14`, `pos_orders_view.dart:19`, `pos_products_view.dart:18`, `pos_settings_view.dart:16`, plus `pos_audit_log_view.dart:15`, `pos_customers_view.dart:18`, `seller_onboarding_view.dart:21`; others not checked for a binding. Bare `Get.put` in `components/custom_toast.dart:23`. |
| Disposal / shared controllers | 🟡 | `permanent` only for services (`main.dart:46-51`). PosHome/PosProducts/PosSettings/PosInventory own `TextEditingController`s/`Timer`s and are not permanent — the recurring "TextEditingController disposed" bug on logout's `Get.offAllNamed` is structurally possible (see memory notes). Per-controller `onClose` verification incomplete *(unverified)*. |
| Error handling | 🟡 | One `catch (_)` (`pos_home_controller.dart:347`, contents not read); **151 `print/debugPrint`** in `lib`, incl. Dio headers/bodies logging (`dio_service.dart:41-48`) active in release; `avoid_print` off. |
| Dead code | 🟡 | `seller_onboarding` module (marketplace wizard, controller 393 lines); `_RefreshButton` unused (`seller_pos_management_view.dart:116`); `category/models/product_model.dart` buyer leftover; `Routes.sellerHome` is a legacy alias still used by splash/stores/onboarding controllers (`app_routes.dart:18`); 263 dead API constants; dead `CurrencyFormatter`. |
| Large files | 🟡 | `seller_pos_management_view.dart` 1880, `pos_repository.dart` 1254, `pos_settings_controller.dart` 907, `pos_home_controller.dart` 762. |
| Localization / a11y | ❌ | 0 `AppLocalizations`/`.tr`; ~7 `Semantics` widgets. |
| `flutter analyze` (run, read-only) | ✅ | 4 issues, 0 errors: 1 warning (`unused_element _RefreshButton`), 3 info (`curly_braces` ×2 — `pos_pin_login_view.dart:328`, `seller_stores_controller.dart:184`; `use_build_context_synchronously` — `pos_settings_controller.dart:501`). Lint config is `flutter_lints` only. |

**Done looks like:** BaseController adopted (or deleted), bindings-only DI, shared tab controllers permanent or safely disposed, logger with `kDebugMode` gating + `avoid_print`, dead modules/constants removed, big files split, analyzer clean.

### Area 9 — Tests — 🟡

- **`flutter test`: 127 passed, 0 failed.** 18 files in `test/` (repository, cart math, session reconciliation, PIN login, open register, role, held-sale resume, sale-detail actions, customers, inventory models, subscription repo/paywall/checkout controllers, retry policy, branding/auth smoke) + `integration_test/pos_checkout_flow_test.dart` (mocked repositories; needs a device/simulator; seeds a fake token; not run here).
- **Backend POS specs:** `pos.service.spec.ts` **failed to compile** (`TS2307 ua-parser-js` at `api: common/user-agent.util.ts:1`) — package is in `package.json:68` but not installed locally (stale `node_modules` after the fast-forward; `npm install` not allowed this phase). `store-locations-bulk-import.spec.ts` passed (4 tests). So **employee-token and PIN-lockout specs have not been executed this round.** `src/pos-plans` has **no spec files**; no spec for `idempotency.interceptor.ts`. Related specs exist for inventory, markets, product-variants, orders stock handling.
- **CI:** `solvexo-api/.github/workflows/{ci,deploy,staging}.yml` exist (`ci.yml`: `npm ci`, build, jest, eslint). **POS has no CI at all.**

| Critical path | Coverage |
|---|---|
| createSale idempotent replay / concurrent same-key race | ❌ |
| Stock floor / oversell on POS path | ❌ (order-path only) |
| Refund/void stock restoration (server) | ❌ |
| Split tender | ❌ (not built) |
| Session-close reconciliation math | 🟡 client only; no server test |
| PIN lockout / employee-token | 🟡 written, blocked by dependency |
| Offline queue + sync | ❌ |
| pos-plans webhook + entitlement | ❌ |
| Receipt/printer builders | ❌ |
| Money rounding | 🟡 client cart only |
| Route middleware | ❌ |

**Done looks like:** backend suites compile and run in CI; server specs for createSale (replay/race/floor), refund/void restoration, session math, interceptor, pos-plans webhook + entitlement guard; Flutter tests for queue/sync, receipt builders, middleware; Flutter CI running analyze + test.

### Area 10 — Release readiness — ❌

| Item | Status | Evidence |
|---|---|---|
| App name | ✅ | "Solvexo POS" (manifest label, `CFBundleDisplayName`); in-app title also composed from `BrandingService` + " POS". |
| IDs | ✅ | Android `com.solvexo.solvexo_pos`; iOS `com.solvexo.solvexoPos` (consistent with Firebase). |
| Android signing | 🟡 | Release uses a release `signingConfig`, but the block does `keystoreProperties[...] as String` unconditionally (`build.gradle.kts:34-41`) — **Gradle config fails if `android/key.properties` is absent** (CI, new machines), even for debug **(verified)**. `key.properties` is gitignored; exists locally. Part of the uncommitted diff. |
| Versioning | 🟡 | `1.0.0+1` (`pubspec.yaml:5`) — fine for first upload; process needed. `targetSdk` was changed to a hard-coded 35 *(per audit; verify against the current Play requirement)*. |
| R8/ProGuard | ⚠️ | `isMinifyEnabled/isShrinkResources = true` with `proguard-rules.pro`, which **does not exist** **(verified)** — no keep rules for printer, secure-storage, WebView plugins. Release build never run in this audit. |
| Android permissions | ⚠️ | No `uses-permission` in the main manifest; plugin merge only; unused ones (location/storage) not stripped; no runtime Bluetooth request. |
| iOS usage strings | ❌ | Only Bluetooth strings (`Info.plist:48-51`). **No `NSCameraUsageDescription`** although `mobile_scanner` is used (`pos_scan_camera_view.dart`) → iOS crash on first scan; no `NSPhotoLibraryUsageDescription` although `image_picker` is used (`app_image_picker.dart`) **(verified: usage present, strings absent)**. |
| iOS privacy manifest | ❌ | `ios/Runner/PrivacyInfo.xcprivacy` missing **(verified)**; required for UserDefaults (`shared_preferences`) etc. |
| Crash reporting / logging | ❌ | No `FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`, Crashlytics/Sentry; `debugPrint` of Dio headers/bodies reaches release logs. |
| Base URL / env | 🟡 | `String.fromEnvironment('API_BASE_URL', default 'https://api.solvexo.store')` (`api_constaints.dart:6-9`); no localhost/10.0.2.2/192.168 in `lib`; no Stripe keys in app. Comment says "staging" while the default looks like production — confirm which. |
| Icons / splash | 🟡 | `flutter_launcher_icons` configured from `assets/images/logo.png`; no `flutter_native_splash` → native white flash before the new Flutter splash route (uncommitted). |
| Account deletion | ❌ | Backend `DELETE /users/profile` exists (soft delete, `users.controller.ts:43-47`); no in-app UI (App Store 5.1.1(v)). Note F8: the users route is buyer-model-based — verify it works for seller accounts. |
| Sign in with Apple | ❌ | Google only; backend already supports Apple (`auth.service.ts:462`). Guideline 4.8 risk (arguable for B2B). |
| Subscription billing policy | ❌ risk | Stripe Checkout in an in-app WebView unlocks app features (`pos_subscription_checkout_controller.dart:42-58`) → Apple 3.1.1 rejection risk, Play Billing policy for digital features; exemptions (3.1.3 multiplatform/enterprise) are narrow and do not cover in-app purchase UI. Needs a policy decision (Q3). |
| Data-safety declarations | 🟡 | Name, email, Google profile photo, phone, customer data, Bluetooth, camera — must be declared accurately in App Privacy / Data Safety; no analytics SDK found. |

**Done looks like:** guarded signing + ProGuard rules + verified release build/AAB; manifest permission set reviewed and declared; camera/photo strings + privacy manifest; crash reporting + error hooks + `kDebugMode` logging; native splash; account deletion; Apple parity decision; billing-model decision implemented; store listing/privacy forms.

---

## 3. Prioritized gap list

Tags: [POS] / [API] / [BOTH]; severity: blocker / high / medium / low; size: S/M/L.

| # | Gap | Tag | Sev | Size |
|---|---|---|---|---|
| 1 | `PosEntitlementGuard` — enforce active POS plan on session-open/sales/complete/pin-login; align with platform-plan `BillingAccessGuard`; app treats 402/403 as truth | BOTH | blocker | M |
| 2 | Idempotency key per checkout attempt, persisted; ambiguous timeouts replayed; keys on all POS writes (server + client) | BOTH | blocker | M |
| 3 | Atomic sale pipeline: status-guarded transitions, transaction/compensation for sale+stock+session totals, all-or-nothing stock, held-sale double-complete, unlimited-stock restore skip, open-session partial unique index | API | blocker | L |
| 4 | Server-side tax/discount recompute + validation (discount ≤ subtotal, tax from settings), per-currency rounding | API | blocker | M |
| 5 | Sale currency snapshot (currency, decimals, frozen rate); app currency-aware formatter replacing `toStringAsFixed(2)`/`$` | BOTH | high | L |
| 6 | Partial-refund reconciliation (`cashSales`/`expectedCash`), reports include `partially_refunded`, refund tax/discount pro-rating | API | blocker | M |
| 7 | iOS: `NSCameraUsageDescription`, photo strings, `PrivacyInfo.xcprivacy` | POS | blocker | S |
| 8 | Billing-model decision for iOS/Android (WebView Stripe vs IAP/web-only/B2B) and implementation | BOTH | blocker | L |
| 9 | Account deletion UI (+ verify seller-compatible endpoint); Sign in with Apple decision | BOTH | high | M |
| 10 | Release hygiene: guarded signing block, `proguard-rules.pro`, verified release build, permission set | POS | blocker | S–M |
| 11 | Crash reporting, global error hooks, `kDebugMode` log gating, logger | POS | high | S |
| 12 | Register Play/release SHA-1s; confirm server `GOOGLE_CLIENT_ID` == app `serverClientId` | BOTH | high | S |
| 13 | Fix backend test env (`ua-parser-js`), run POS spec; add specs for createSale/refund/void/interceptor/pos-plans | API | high | M |
| 14 | Split tender: `payments[]` on DTO/schema/session totals + app UI; persist tendered/change & card/bank reference | BOTH | high | L |
| 15 | Offline hardening: failed-sale screen + error classification + periodic sync; server `clientCreatedAt`/`offline`, structured error codes, stock-conflict policy; local provisional receipt; cart persistence | BOTH | high | L |
| 16 | Inventory screen crash on `'∞ Unlimited'`; surface `unlimitedStock` in POS product payload | BOTH | high | S |
| 17 | Customer search store-scoping (privacy leak) | API | high | S |
| 18 | Employee-token 403 handling → PIN screen; refresh-token interceptor; Google sign-out on logout | POS | high | M |
| 19 | Manager-token gating for reports/settings/employee CRUD/force-close; `@Throttle` on pin-login | API | medium | M |
| 20 | Printing: Bluetooth permissions + runtime request, paper width/codepage/drawer/auto-print, iOS stance | POS | high | M |
| 21 | Unified `ReceiptData` (address, tax id, cashier, tax breakdown, tendered/change, VOID/REFUNDED/COPY, Unicode font) | POS (+API for tax id/cashier name) | high | M |
| 22 | Pos-plan webhook refund/dispute revoke; admin grant/revoke; plan limits (registers/employees/locations) | API | medium | M |
| 23 | Use delta `inventory/:storeId/variant/:variantId/adjust` with reason; handle 409/400 stock-edit responses | POS | medium | S |
| 24 | Owner-route middleware / device-mode separation | POS | medium | M |
| 25 | Branding route: implement `GET /api/branding/config` or remove client call | BOTH | low | S |
| 26 | Prune 263 dead API constants; delete `seller_onboarding`, `_RefreshButton`, buyer `product_model.dart`; BaseController adopt/delete; redundant `Get.put`; split large files; analyzer clean | POS | low | M |
| 27 | Flutter CI (analyze + test); integration test on device | POS | medium | S |
| 28 | Reset-PIN vs login PIN length mismatch; `create-store` `country`; CORS header | BOTH | low | S |
| 29 | Localization / accessibility pass | POS | low | L |
| 30 | Commit pending `pos-plans.module.ts` fix; commit/review pending POS onboarding/splash/signing work | BOTH | medium | S |

---

## 4. Proposed phase plan

Each phase ends with `pos/docs/phase5X_summary.md` and stops for approval. Backend work is on `solvexo-api` `feature/jamibranch`; POS work on a new `feature/jamibranch` cut from `main` in the POS repo.

| Phase | Scope | Repos | Gaps | Acceptance criteria |
|---|---|---|---|---|
| **5A — Store-blocking hygiene** | Camera/photo strings, privacy manifest, guarded signing, ProGuard rules, Bluetooth permission declaration + runtime request, crash reporting + error hooks + log gating, SHA-1/serverClientId verification checklist, commit pending diffs | POS (+API commit of `pos-plans.module.ts`) | 7, 10, 11, 12, 20 (perm part), 30 | Release AAB + iOS archive build without `key.properties`-less crash; scan works on a real iPhone; privacy manifest present; crash events visible in the chosen tool; Google sign-in works on a store-signed build. |
| **5B — Backend sale integrity** | Idempotent POS writes, atomic transitions, transaction/compensation, session-open unique index, unlimited-stock restore skip, held-sale guard, `ua-parser-js` env fix + specs | API | 2 (server), 3, 13 | New specs pass: replay, concurrent same-key race, oversell race, double-complete, double-refund, double-open. `npm run build` + POS specs green. |
| **5C — Money & currency** | Server recompute/validation, per-currency rounding, sale currency snapshot, partial-refund reconciliation, reports incl. `partially_refunded`; app formatter/decimals | BOTH | 4, 5, 6 | JPY/KWD/USD fixtures round correctly end-to-end; drawer reconciles after partial cash refund; discount > subtotal rejected; app has no hardcoded `$`/`toStringAsFixed(2)`. |
| **5D — Client sale safety** | Stable key per checkout, ambiguous-timeout replay, keys on all writes, employee-token 403 handling, refresh interceptor, Google sign-out, inventory crash fix, `unlimitedStock` in POS products, delta-adjust with reason | POS (+small API for unlimitedStock) | 2 (client), 16, 18, 23 | Simulated lost-response retry creates exactly one sale; expired employee token returns to PIN; inventory renders unlimited products. |
| **5E — POS plan enforcement & compliance** | `PosEntitlementGuard`, plan limits, webhook refund/dispute revoke, admin grant/revoke; billing-model implementation per decision; account deletion; Apple parity per decision | BOTH | 1, 8, 9, 22 | Sale API returns 402/403 without an active plan; webhook-refund revokes; chosen billing path passes a TestFlight/Play internal review checklist; account deletion works in-app. |
| **5F — Split tender & receipts** | `payments[]`, tendered/change/reference, per-tender session totals, `ReceiptData` unification, printer settings/drawer/iOS stance | BOTH | 14, 20, 21 | A cash+card sale reconciles in session report; one receipt model renders PDF/ESC-POS/text identically incl. VOID/REFUNDED/COPY; 58/80mm verified on hardware. |
| **5G — Offline hardening** | Failed-sale screen, error classification, periodic sync, server `clientCreatedAt`/`offline`/error codes/stock-conflict policy, provisional receipt, cart persistence | BOTH | 15 | Airplane-mode sale syncs with original timestamp into the right session; a conflicting sale surfaces for review, never disappears; kill-and-relaunch restores the cart. *(Requires 5B.)* |
| **5H — RBAC/privacy/cleanup** | Manager gating on reports/settings/employees, pin-login throttle, customer-search scoping, owner-route middleware/device mode, branding route decision, dead-code and constants prune, BaseController decision, Flutter CI | BOTH | 17, 19, 24, 25, 26, 27, 28, 29 | Cashier token cannot reach manager-only endpoints; cross-store customer search returns only the store's customers; CI green; dead constants removed. |

Order rationale: 5A is cheap and unblocks real-device testing; 5B must precede 5C/5G (server correctness before client/offline); 5E can be reordered earlier if monetization is the priority.

## 5. Open questions (need your decision)

1. **Money model:** accept "currency snapshot + per-currency rounding + server recompute" for now, or do the full integer-minor-units migration (touches every model, schema and report)?
2. **Which currency is authoritative for POS sales:** the store's `baseCurrency` only, or can a POS sale be priced in a Market currency (and then needs a frozen rate)? Should `currencySymbol` become derived/read-only?
3. **Plan billing on mobile:** (a) keep Stripe-in-WebView and seek a B2B/enterprise determination, (b) web-only purchase with no in-app purchase UI, or (c) StoreKit/Play Billing (e.g. RevenueCat)? This changes 5E substantially.
4. **POS plan vs platform plan:** should POS sales be gated only by the POS plan (remove `BillingAccessGuard` `blockDuringTrial` from POS routes), or by both? Is there a trial/grace period, and what happens to an open register at expiry?
5. **Plan limits:** which limits (registers/employees/locations) per plan?
6. **Device model:** is the terminal device owner-controlled (owner screens must be hidden/locked behind a manager PIN) or a shared cashier device?
7. **Offline policy:** on a stock conflict for an already-completed offline cash sale — accept and flag (my recommendation) or reject? Max offline age? Is a provisional receipt number scheme acceptable?
8. **Printers:** supported hardware (BLE vs classic SPP vs LAN)? Is iOS thermal printing required (would need LAN/BLE-only units)?
9. **Sign in with Apple / account deletion:** add Apple sign-in, or rely on a B2B argument? Confirm seller account deletion semantics (data retention for financial records).
10. **Crash reporting vendor** (Firebase Crashlytics vs Sentry) and analytics policy (affects privacy declarations).
11. **Which environment is `api.solvexo.store`** (staging vs production), and do you want separate flavors/dart-define files?
12. **Marketplace leftovers:** delete the `seller_onboarding` wizard and unused constants now (5H), or keep until the store-selection model (multi-store vs `store_config.dart` single-store) is decided? The Phase 0 conflict is still unresolved.
13. **Onboarding slides:** POS uses static content while the backend has a public `onboarding-slides` module — use the dynamic one?
14. **Uncommitted POS work** (onboarding, splash, signing, login view): review and commit as part of 5A, or separately?

---

## 6. Rules acknowledged for later phases

- Backend changes only on `solvexo-api` branch `feature/jamibranch`. POS changes only on a new `feature/jamibranch` branch in the POS repo created from `main`. Never commit to `main` in either repo.
- Inspect existing code before writing anything new; reuse patterns (BaseClient → Repository → Controller → View, GetX bindings, existing `IdempotencyInterceptor`, `writeAuditLog`).
- Never fake a capability client-side that the backend doesn't enforce; build it in the backend.
- Each phase ends with a summary doc in `pos/docs/` (the local folder for the `white-lable-pos` repo) and stops for approval.
- Memory-note reminders that apply: new modules using `JwtAuthGuard` must import `RedisModule` alongside `AuthModule`; new stock logic must check `unlimitedStock` alongside `type === 'physical'`; shared GetX controllers should be permanent to avoid the disposed-`TextEditingController` crash.

**Phase 0 complete. Stopping for your approval before any change.**
