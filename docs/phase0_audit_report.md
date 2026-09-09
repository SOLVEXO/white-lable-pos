# Solvexo POS — Phase 0 Audit & Gap Report

**Scope:** `pos/` Flutter app only (standalone GetX app, package `solvexo_pos`, extracted from the Solvexo marketplace app). Backend (`solvexo-api/`, NestJS) inspected read-only for endpoint cross-referencing — no backend changes proposed or made. No code changes were made in this phase.

**Date:** 2026-08-31

---

## 1. Architecture Map

### 1.1 Navigation
- `lib/app/routes/app_pages.dart` — flat list of 18 `GetPage`s, no nested routing. `initialRoute = Routes.posLogin`.
- Every route has a matching `Bindings` class, but **route guarding is inconsistent**: only POS-terminal screens (posHome, posOrders, posPinLogin, posOpenRegister, posHeldSales, posProducts, posSettings, posSaleDetail, reports, audit log, session history) carry `PosAccessMiddleware`. `sellerOnboarding`, `sellerStores`, `sellerHome`, `sellerPosManagement`, `sellerPosLocations` have **no middleware at all** — a direct `Get.toNamed` bypasses auth/role checks for the owner-facing screens entirely.
- No deep linking, no `onGenerateRoute`/`unknownRoute` fallback.
- **`Routes.sellerHome` and `Routes.sellerPosManagement` both point at the identical `SellerPosManagementView`/Binding** — redundant aliasing, apparent leftover from a removed dashboard.

### 1.2 State management
- Pure GetX throughout: 23 `GetxController`s, `.obs`/`Obx` used exclusively (112/41 hits), **zero** `GetBuilder` usage.
- `lib/core/base/base_controller.dart` is a well-built shared `BaseController` (loading state, toast/dialog helpers, `handleApiError`) but has **zero adopters** — every real controller extends `GetxController` directly and duplicates the same boilerplate ad hoc. Looks like an unfinished refactor.
- DI is inconsistent: most views correctly rely on `Bindings` + `Get.find`, but **10+ views** (`pos_orders_view.dart`, `pos_sale_detail_view.dart`, `pos_session_history_view.dart`, `pos_range_report_view.dart`, `pos_audit_log_view.dart`, `pos_session_report_view.dart`, `pos_products_view.dart`, `pos_settings_view.dart`, `pos_home_view.dart`, `seller_stores_view.dart`, `seller_onboarding_view.dart`) redundantly call `Get.put(...)` directly in the view even though a `Binding` already registers the controller — makes the paired `Binding` dead weight in practice. No `GetView<T>` base class used anywhere.
- One `permanent: true` singleton: `BrandingService` (white-label branding cache), set up in `main.dart`.

### 1.3 API / repository layer
- `lib/app/network/dio_service.dart` builds a fresh `Dio()` per call (no shared/pooled client), 30s connect/receive timeouts, single interceptor doing (a) Bearer-token injection when `requiresAuth`, (b) force-logout on 401-with-`requiresAuth` (wipes **all** SharedPreferences via `clearPreference()`, not just auth keys).
- `dio` is **pinned to exactly 5.9.0** — a code comment explains newer releases add `DioExceptionType` cases that break the exhaustive `switch` in `dio_exception_handler.dart`. This is a real upgrade-blocker to track.
- `lib/app/network/base_client.dart` has an inconsistent default: `get()` defaults `requiresAuth: false`, while `post/put/patch/delete` default `requiresAuth: true` — callers must know this or accidentally send/omit auth.
- `lib/app/network/dio_exception_handler.dart` is solid: unwraps backend `{success:false, message}` shape, HTML-error-page guard, per-status fallback messages (400/401/403/404/409/413/422/500/502/503), field-level validation error extraction.
- Repository error handling is consistently good — all `DioException`s are caught inside repositories and converted to failure sentinels/toasts; nothing escapes uncaught to a controller.
- **`api_constaints.dart` is 810 lines**; only ~65 of its constants are referenced anywhere in the 7 actual repository files that exist. The rest (buyer orders, refund-requests, ratings, checkout/shipping, KYC, storefront, messaging, coupons/campaigns, loyalty, subscriptions, seller analytics/finance/payouts, platform plans, **AI Studio**, SEO, bookings, promotions, banners, notifications, exchange rates) is unreferenced marketplace-era surface — contradicts the pubspec's stated goal of being "trimmed to what POS actually uses."
- Base URL: `String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.solvexo.store')` — one compile-time dart-define knob, no separate dev/staging/prod config files.

### 1.4 Auth
- **Two independent login flows converging on the same session:**
  1. Owner/seller login (`pos_login`) — email/password or Google Sign-In, both hard-coded to `role: 'seller'` client-side regardless of what the server returns. Session "restore" on cold start is just "does a token exist locally" — no server re-validation.
  2. Cashier PIN login (`pos_pin_login`) — 4-digit PIN scoped to a store, layered under the seller session, used to switch cashiers / resume or open a register.
- Token storage: plaintext `shared_preferences` (`_accessTokenKey`, `_refreshTokenKey`). **`flutter_secure_storage` is not a dependency.**
- **No token refresh logic anywhere** — a refresh token is stored but never used; expiry is handled purely by full logout on the first 401.
- **Race condition in `PosAccessMiddleware.onPageCalled`**: it calls `_check()` (async) without awaiting, then returns the page immediately — the guarded screen can render before the async token/role check redirects away. Real flash-of-protected-content bug, not a style nit. (`lib/app/middleware/auth_middleware.dart`)

### 1.5 Storage / caching
- `lib/shared_prefrences/app_prefrences.dart` (note: typo baked into the actual folder/import path app-wide) — static wrapper around `SharedPreferences`. Holds auth tokens, POS employee/session/register/shift IDs, device-local prefs (sound effects, auto-lock minutes), and a branding-config JSON cache.
- **No local database** (no sqflite/hive/isar/drift dependency) and **no offline queue** — held sales, audit logs, everything is fetched live from the server. Cart state itself is in-memory only (`// ── Cart item (local only — not serialised) ──`), lost on process death.
- `flutter_secure_storage` confirmed absent from `pubspec.yaml`/`pubspec.lock`.

### 1.6 Config
- `lib/config/store_config.dart` documents a **"one store per repo" white-label model** (each deployment hardcodes its own `storeSlug`) — but this directly **contradicts** the still-fully-wired multi-store flow (`seller_stores` → pick/create one of N stores → `seller_onboarding`). Both models coexist in the code today and disagree with each other. This needs a product decision before Phase 5 polish, since it affects the login → store-selection flow shape.
- No hardcoded `"Rs."` strings found anywhere (good), **but** the one real multi-currency formatter that exists, `lib/utils/currency_formatter.dart` (PKR/USD-aware), is **dead code — zero call sites**. `PosSettingsModel.currencySymbol` and `StoreModel.baseCurrency` are also fetched/stored but never read by the checkout screen (see §2.1). Net effect: the checkout/cart/receipt UI hardcodes a literal `$` everywhere instead of using any of this existing currency infrastructure.
- Feature flags: `BrandingConfigModel.featureFlags`/`isFeatureEnabled()` exist client-side but the backend endpoint that would serve them (`GET /api/branding/config`) **does not exist yet** (confirmed both by a self-documenting code comment and by the backend cross-check — see §3). The app already degrades gracefully to compiled-in defaults.
- No global error handling: no `FlutterError.onError`, no `runZonedGuarded`, no crash reporting SDK (no Crashlytics dependency). An uncaught exception outside a repository's try/catch has no telemetry.

### Marketplace-era leftovers not fitting the "standalone single-store POS" pivot
- `seller_onboarding` — a full marketplace seller-signup wizard (seller types: creator/educator/retailer/freelancer/etc.; sells-what: digital downloads/subscriptions/bookings/etc.) where only one branch (`inPersonPos`) is relevant to this app.
- `seller_stores` — multi-store picker/creator, conflicting with `store_config.dart`'s single-store design (see above).
- `seller_pos_management` / `seller_pos_locations` — by contrast, these **are** legitimately POS-relevant (employee/register/shift management, multi-location within one store) and should be kept.
- `firebase_options.dart` still references the old marketplace Firebase project (`ecommerceapp-7f45d`) and `iosBundleId: 'com.example.bookStoreApp'` — not regenerated for the standalone POS package.

---

## 2. Feature Checklist

Legend: ✅ Implemented · 🟡 Partial · ⛔ Missing · 🔴 Broken

### 2.1 POS / Checkout

| Feature | Verdict | Notes |
|---|---|---|
| Product search | 🟡 Partial | Debounced (350ms), server-backed, matches name/SKU. Does **not** match barcode. "Pagination" is really a single hardcoded 200-item fetch (`limit: 200`) in both the Quick-Sale grid and the Products tab — the repo/backend support real cursor pagination (`page`, `hasMore`), it's just never used by either screen. |
| Barcode scanning — camera | ✅ Implemented | `mobile_scanner` fully wired (scan sheet → lookup → add to cart). |
| Barcode scanning — HID/keyboard-wedge | 🟡 Partial | No purpose-built handling (no `RawKeyboardListener`/fast-input detection). Works only incidentally: the manual-entry `TextField` in the barcode sheet has `onFieldSubmitted`, so a HID scanner's trailing Enter will submit it — but only while that sheet is open and focused, not from the main product grid. |
| Cart add/remove/qty | ✅ Implemented | Straightforward, reactive, correct. |
| Hold / resume cart | 🟡 Partial | Server-persisted (creates a real `status: held` sale) — good. **Bug**: resuming rebuilds cart items by matching against the currently-loaded ≤200-item product list; if a held item's product isn't in that page (or was since removed), it's **silently dropped** with no warning. |
| Discounts | 🟡 Partial | Cart-level only, **fixed-amount only** — no percentage discount, no line-item discount, despite the Phase 1 spec asking for both. |
| Tax | 🟡 Partial | Cart-level percentage only, no per-item tax, no tax-inclusive mode. |
| Subtotal/total math | 🔴 Broken (edge case) | No clamping — a discount larger than the subtotal drives `total`/`tax` negative with no validation anywhere before submit. |
| **Monetary type** | 🔴 Broken (data-model risk, flagged not fixed) | Every price/amount field (`PosProductVariant.price`, `PosSaleItemModel.price/lineTotal`, `PosSaleModel.discount/tax/subtotal/total`) is `double`, and all cart math is plain floating-point arithmetic — **not** integer minor-units. This is a real risk for rounding drift across discount/tax operations; changing it is a data-model decision, not something to silently patch. |
| Currency | 🔴 Broken | `$` is hardcoded as a literal string in every checkout/cart/receipt widget. Real infra exists (`CurrencyFormatter`, `PosSettingsModel.currencySymbol`, `StoreModel.baseCurrency`) but none of it is wired into checkout. |
| Payments — methods | 🟡 Partial | Only `cash` / `card` / `other`. "Bank transfer" isn't a distinct method (folded into `other`, no reference-number/proof capture). No Stripe dead code found in the POS module itself. |
| Payments — split/partial | ⛔ Missing | Single `paymentMethod` field only, no multi-tender support anywhere. |
| Payments — change calculation | ⛔ Missing | No "cash tendered" input, no `changeDue` field anywhere in the code. |
| Receipts | 🟡 Partial | No PDF, no thermal/ESC-POS/Bluetooth printer package or code exists at all (no such dependency in `pubspec.yaml`). What exists: a plain-text receipt built by hand and pushed through the OS share sheet (`share_plus`). `PosSettingsModel.receiptHeader/receiptFooter` are stored/editable in Settings but **never actually used** at receipt-render time. |

### 2.2 Cash Register / Shift Management

| Feature | Verdict | Notes |
|---|---|---|
| Open register | ✅ Implemented | Solid; server enforces one-open-session-per-register; double-submit guarded. Minor gap: opening-cash input silently coerces invalid/garbage text to `$0.00` instead of rejecting it. |
| Close register — reconciliation | 🟡 Partial (highest-risk item in this phase) | The close dialog is a **blind close**: it asks only for a closing-cash number, with no expected-cash figure or variance shown to the cashier *before or immediately after* closing. The reconciliation math (`expected = opening + cashSales + cashIn − cashOut`, variance) is genuinely computed **server-side** and stored on the session — it's just never surfaced at the moment of closing. A cashier must separately navigate into Shift History → a specific session to discover whether they were short or over. |
| Cash in / cash out | ⛔ Missing (UI) | Full backend endpoint, repository method (`cashAdjustment`), and data model exist — but there is **zero UI entry point** anywhere in the app to actually perform one. Dead/unreachable code today. |
| Shift/session history | 🟡 Partial | Implemented as list + drilldown, but the list itself shows only date/status/total (no reconciliation at a glance), and — see next row — is not scoped to the viewer's own register. |
| Multi-register concurrency | 🟡 Partial (real correctness gap) | Register IDs are correctly threaded through open/close/report API calls, so backend data integrity is fine. But: (1) the on-device "current session" cache is a single global slot, not keyed by register; (2) PIN-login's active-session check sends **no `registerId`** to the backend, so an employee who has an open session on Register A but picks Register B in the login UI can be silently resumed onto Register A with no warning — the register-scoped check that should prevent this (`getActiveSession(storeId, registerId)`) exists in the repository but is **never called**; (3) Session History pulls all sessions store-wide with no register/employee filter applied, despite the API supporting one; (4) a manager "force-close a stuck register" repository method exists but has no UI anywhere. |

### 2.3 Inventory / Stock

| Feature | Verdict | Notes |
|---|---|---|
| Stock adjustments (manual, with reason) | ⛔ Missing | No screen/controller/repo method anywhere. Backend endpoint constants (`getStoreInventory`, `lowStockSummary`, `productVariants`) are defined in `api_constaints.dart` but **never called** from anywhere in the app. |
| Stock movement history | ⛔ Missing | No per-product ledger anywhere. The audit-log module tracks staff/session/sale events, not stock movements. |
| Low-stock alerts | 🟡 Partial | Cosmetic only: a hardcoded `stock <= 10` badge on one of the two product screens (Quick-Sale grid); absent from the Products tab entirely. No configurable threshold, no notifications, and the backend's own `lowStockSummary` endpoint is unused. |

### 2.4 Products, Categories, Brands, Variants, Barcode

| Feature | Verdict | Notes |
|---|---|---|
| Product listing | 🟡 Partial | Search is real and server-backed; pagination is scaffolded in the repo (`page`/`hasMore`) but neither product screen actually uses it — both hardcode a single 200-item fetch. |
| Categories | 🟡 Partial | Browse/read-only in the POS app. `createCategory()` exists in the repository but is dead code (no caller); `updateCategory`/`deleteCategory` are commented-out stubs, not implemented at all. No category-management screen exists. |
| Brands | ⛔ Missing | No `brand` field on any product/variant model. The only `brand=` reference anywhere is an unused query-param helper in a generic marketplace search builder. |
| Variants | ✅ Implemented | Full model (SKU, barcode, price, compareAtPrice, stock, options, isDefault, images) and a working bottom-sheet picker that auto-triggers on add-to-cart for multi-variant products. Cart keys are variant-scoped. |
| Barcode / SKU | ✅ Implemented | Real fields; dedicated barcode-lookup endpoint + scan/manual-entry UI; SKU is shown and client-searchable. (Barcode itself is exact-match-lookup only, not a general search term — see §2.1.) |

### 2.5 Purchases / Suppliers

⛔ **Missing entirely.** No module, model, controller, or backend endpoint reference found anywhere in the app for purchasing/receiving stock or managing suppliers.

### 2.6 Customers

⛔ **Missing as a module.** Sales carry only a free-text `customerName` (default "Walk-in") and optional `customerId` string typed into a plain text field at checkout — no `CustomerModel`, no customer list/search/picker/CRUD, no phone/email/address capture anywhere.

### 2.7 Sales History, Returns / Refunds

| Feature | Verdict | Notes |
|---|---|---|
| Sales history list | 🟡 Partial | Real server-backed pagination (infinite scroll) — good. Payment-method and status filters exist in the UI but are applied **client-side only over whatever pages are already in memory**, not sent to the server, so they silently miss matches on unloaded pages. A date-range filter exists in the controller but has **no UI** anywhere (dead code) — no date picker in the screen. **No text/keyword search at all.** The "Sales/Avg/Cash" stat cards on this screen are computed from the same partial in-memory set and read as full totals but aren't. |
| Sale detail view | ✅ Implemented | Full line items, refunded-qty annotations, payment breakdown, void/refund metadata. Customer info is name-only (no phone/email/address, since none is captured — see §2.6). |
| Export | 🟡 Partial / 🔴 Broken as wired | Only one CSV export endpoint exists (daily report). The **Range Report screen's export button always exports "today," ignoring the user-selected date range** — a concrete, fixable bug. No export exists anywhere on sales history, sale detail, or session report. |
| **Returns / Refunds** | ✅ Implemented | Contrary to the common assumption that this is missing in early-stage POS apps — it is not. Full and partial refund, plus void, all tied to the original sale ID; partial refunds target specific line items capped at remaining refundable quantity; duplicate refunds/voids are prevented via status-derived guards (`canRefund`/`canVoid`) plus in-flight-request locks. Stock-restoration is explicitly claimed in UI copy for **void** ("stock restored") but is **not** asserted anywhere for partial/full refund — worth a backend confirmation, not a client fix. A separate, older `createRefundRequest`/`approve`/`reject` endpoint set exists in `api_constaints.dart` but is entirely unused — likely vestigial. |

### 2.8 Reports / Dashboard

| Feature | Verdict | Notes |
|---|---|---|
| Daily report | ✅ Implemented | Real, server-computed (revenue, refunds, avg transaction, payment-method breakdown, top products). Always "today" — no historical date navigation. |
| Range report | ✅ Implemented | Real, distinct backend endpoint (not a client-side duplicate of daily report), with an actual date-range picker. Export is broken (see §2.7). |
| Session report | ✅ Implemented | Includes the real cash-drawer reconciliation block (opening/closing/expected/variance) that close-register itself fails to surface (see §2.2). |
| Cashier-facing dashboard | ⛔ Missing | No "home" metrics screen in the cashier bottom nav (4 tabs are Sell/Orders/Products/Settings, no Dashboard). |
| Owner-facing dashboard | ✅ Implemented | `seller_pos_management` shows a small real stats row (employee count, register count, today's revenue) — all backed by live API calls, no hardcoded numbers found anywhere in any report controller. |

### 2.9 Roles & Permissions

🔴 **Broken as a security boundary; UI-only, and the UI-level check itself is spoofable.**

- App-level gate ("is this user a seller"): reads a **locally cached** role string from plaintext `shared_preferences`, never re-validated against the server or JWT on subsequent opens. The app's own login code comment states it hardcodes `role: 'seller'` locally **regardless of what the server actually returns**.
- Employee-level role (`cashier` vs `manager`, set when a store owner adds staff): stored after PIN login but **used nowhere** for any access decision — grep confirms its only consumer is a display label in Settings. Sensitive actions (void, refund) are gated purely by **sale status**, not by employee role — a cashier and a manager have identical capability in the client today. No manager-approval/PIN-override flow exists for any action.
- Server-side 403s are handled gracefully (mapped to a generic "Access denied" toast, no crash), but the client never differentiates or pre-empts a permission-denied action, because it doesn't model cashier-vs-manager capability at all.
- **This is the concrete "UI-only enforcement" case the audit brief asked to flag**: because the local role flag is what actually unlocks the terminal screens (and is trivially rewritable via local storage), while a fresh, unauthenticated user still can't call real POS APIs without a valid JWT, the practical risk is scoped to unauthorized *screen access*, not raw data access — but it's still a real defense-in-depth gap that Phase 4 needs to close, and the cashier/manager distinction needs to be actually built (today it doesn't exist at all, client or server-enforced).

### 2.10 Audit Logging

🟡 **Partial — read-only viewer only, no client-side event emission.**

- `pos_audit_log` is a paginated **viewer** of server-generated log entries (login/logout, void, refund, employee changes, session events) — solid infinite-scroll implementation.
- The client **never generates or POSTs an audit event itself** — there is no `logEvent`/`postAuditLog` method anywhere; entries are written by the backend as a side effect of the actions it processes.
- If Phase 4 work assumes client-side event instrumentation for anything not already server-logged, that's new work, not an extension of existing code.

### 2.11 Offline / Network Resilience

🔴 **Effectively zero offline capability today** — not partial-with-retry, genuinely absent:

- No connectivity detection (`connectivity_plus` etc. not a dependency).
- **No retry-with-backoff anywhere** in the Dio pipeline — only a fixed 30s connect/receive timeout. The few "retry" hits in the code are manual UI buttons a user taps after a failed load, not automatic retry.
- No local persistence of cart/transaction data for offline use — cart is in-memory only, held sales and audit logs are fetched live, no sqflite/hive/isar dependency exists (the `sqflite` reference visible in `pubspec.lock` is a transitive plugin dependency, unused by any app code).
- No queued/pending-request handling of any kind.
- This scopes Phase 3 down per the task's own instruction: **build the "minimum bar" (graceful slow-network/timeout/failure handling, retry-with-backoff, clear error states) first** — full offline queuing is realistic future work but starts from zero, not from partial infrastructure.

---

## 3. API Endpoints

Cross-checked every endpoint the Flutter app's repository layer calls against the NestJS backend's actual controllers (`solvexo-api/src/**/*.controller.ts`, not the compiled `dist/`).

**Result: the backend has a real, purpose-built, fully-registered POS module** (`@Controller('api/pos')`, wired into `app.module.ts`) covering employees, registers, shifts, sessions (open/close/cash-adjustment/force-close/report), sales (create/hold/complete/refund/void/discard/items), reports (daily/range/register/employee + CSV export), settings, audit logs, and multi-location branches. All ~30 POS-specific endpoints the app calls resolve to an exact method+path match.

Surrounding concerns (store/seller identity, auth, categories, uploads) ride on shared marketplace modules rather than POS-specific ones — a reasonable "split only what needed POS-specific semantics" extraction strategy, but it means future changes to those shared modules (driven by the buyer-facing marketplace app) can silently affect POS too, since there's no isolation layer.

### Endpoint groups in use

| Area | Repository | Backend module | Status |
|---|---|---|---|
| Auth (login, social login, logout) | `auth_repository.dart` | `src/auth/auth.controller.ts` | ✅ all match |
| Branding config | `branding_repository.dart` | — | 🔴 **no backend route exists** |
| Categories (tree, add, get by id) | `category_repository.dart` | `src/categories/categories.controller.ts` | ✅ all match |
| Store/seller (my-stores, get, create) | `seller_repository.dart` | `src/store/store.controller.ts` | ✅ all match |
| Uploads + profile | `upload_repository.dart` | `src/upload/*`, `src/users/*` | ✅ all match |
| POS core (employees, registers, shifts, sessions, products, sales, reports, settings, audit logs, locations) | `pos_repository.dart` | `src/pos/pos.controller.ts` | ✅ all ~30 match |

### Flagged gap

- **`GET /api/branding/config` — no matching backend route.** Called from `BrandingRepository.getBrandingConfig()`. This is a *known, self-documented* gap in the client code (it already treats any non-success response, including 404, as "no data" and falls back to compiled-in `StoreConfig` defaults or a cached copy) — not a newly-discovered break, but worth surfacing explicitly here since it 404s in production today and is a real dependency for the white-labeling effort. **Backend-side fix required; not something to work around further client-side.**
- No other endpoint the app calls was found without a backend match.

### Endpoints defined but never called by the app (dead code, not integration gaps)
`getStoreInventory`, `lowStockSummary`, `productVariants`/`productVariant` (inventory), `getActiveSession`, `forceCloseSession`, `getRegisterReport`, `getEmployeeReport`, `cashAdjustment` (cash in/out), `posEmployeeLegacy`, `createRefundRequest`/`approveRefundRequest`/`rejectRefundRequest`. Several of these (`getActiveSession`, `cashAdjustment`) are the exact endpoints needed to fix bugs flagged in §2.2 and just need a UI built against them — not new backend work.

---

## 4. Known Bugs / Tech Debt (prioritized)

**High priority — correctness/data-risk:**
1. Close-register is a blind close with no expected-vs-actual reconciliation shown to the cashier (§2.2).
2. `PosAccessMiddleware.onPageCalled` doesn't await its async check — real flash-of-protected-content race (§1.4).
3. Held-sale resume silently drops cart items not present in the currently-loaded product page (§2.1).
4. Range Report export button always exports "today," ignoring the selected date range (§2.7).
5. Cart totals aren't clamped — an oversized discount can drive total/tax negative with no validation (§2.1).
6. Sales-history payment/status filters and stat totals operate only over the partially-loaded page set, not the full server-side result (§2.7).
7. PIN-login's active-session check omits `registerId`, risking a silent resume onto the wrong register in multi-register stores (§2.2).
8. Monetary values are `double` throughout the model and arithmetic layers, not integer minor-units — a rounding-drift risk (§2.1, flagged for a data-model decision, not silently patched).
9. Two conflicting store models coexist: `store_config.dart`'s "one store per repo" white-label design vs. the still-fully-wired multi-store `seller_stores` flow (§1.6) — needs a product decision.

**Medium priority — UX/completeness gaps with existing backend support (fast follow):**
10. Cash-in/cash-out has a complete backend/repo/model but zero UI (§2.2).
11. Currency is hardcoded to `$` everywhere despite existing `CurrencyFormatter`/`currencySymbol`/`baseCurrency` infrastructure sitting unused (§1.6, §2.1).
12. Manual stock adjustment and stock movement history don't exist, though partial backend surface (`getStoreInventory`, `lowStockSummary`) is defined and unused (§2.3).
13. Cashier/manager role is stored but drives zero permission decisions anywhere (§2.9).

**Lower priority — dead code / cleanup candidates (do not touch without confirming no hidden dependents):**
14. `lib/core/base/base_controller.dart` — unused shared base class.
15. `lib/utils/currency_formatter.dart` — unused formatter.
16. `api_constaints.dart` — ~745 of ~810 lines are unreferenced marketplace-era endpoint constants.
17. Redundant `Get.put()` calls in ~10 views that duplicate what their `Binding` already does.
18. `Routes.sellerHome`/`Routes.sellerPosManagement` alias to the same view.
19. `CategoryRepository.createCategory()` defined but never called; `updateCategory`/`deleteCategory` are commented-out stubs.
20. Old `createRefundRequest`/`approve`/`reject` endpoint trio, superseded and unused.

**Auth/security (feeds Phase 4 directly):**
21. Auth tokens stored in plaintext `shared_preferences`, not `flutter_secure_storage`.
22. No token refresh logic — session expiry is handled only by full logout on first 401.
23. App-level role gate is a locally-cached, never-re-validated, client-writable flag (§2.9).
24. `firebase_options.dart` still points at the old marketplace Firebase project — needs its own registration for a truly standalone POS app.

---

## 5. What's Solid (worth calling out, not just gaps)

- Returns/refunds is a complete, well-guarded feature — don't rebuild it.
- Reports (daily/range/session) are real, distinct, server-computed, with no mock data found anywhere.
- Variant support (model + add-to-cart UX) is fully implemented.
- Barcode camera scanning is fully implemented.
- Repository-layer error handling is consistent and safe across the whole app — no unhandled Dio exceptions found anywhere.
- The backend POS module is purpose-built and match rates against the client are excellent (only one endpoint gap, and it's a known one).

---

## Suggested Phase 1 priorities given the above

Given this audit, the highest-leverage Phase 1 work (in addition to the spec's own checklist) is:
1. Fix the close-register blind-close UX (surface expected-vs-actual before/at close) — data and endpoint already exist.
2. Build cash-in/cash-out UI — backend/repo/model already exist.
3. Wire currency formatting into checkout/receipts using the existing (currently dead) infrastructure.
4. Decide the money-as-double vs. minor-units question explicitly before more cart/payment logic is built on top of it — this compounds the longer it's deferred.
5. Fix the middleware race and the Range Report export bug — both small, both real.

This report is the Phase 0 deliverable. Per the execution plan, stopping here for review before Phase 1 begins.
