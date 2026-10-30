# Solvexo POS — Phase 5 Decisions

**Date:** 2026-10-30 · Follows `phase5_production_readiness_audit.md` (gap numbers #1–#30 below refer to its §3 table).
Repos: backend `solvexo-api` (branch `feature/jamibranch`), POS app `pos/` (remote `white-lable-pos`, branch `feature/jamibranch` cut from `main`).

Decision principles, in order: (1) never lose or duplicate money/stock, (2) backend is the source of truth and enforces every rule, (3) pass App Store / Play review, (4) don't change shared storefront/buyer behaviour, (5) simplest production-safe solution, (6) match Shopify POS / Square when in doubt.

---

## 1. Final decisions from the owner

**D1 — Money.** Currency snapshot + per-currency rounding + server-authoritative totals. Every sale/refund/session record stores its currency code and ISO 4217 minor-unit exponent (JPY 0, PKR/USD 2, KWD 3…). The server recomputes subtotal, tax, discount and total from line items + store/POS settings, ignores client totals, and rejects with a clear error if the client total differs beyond rounding. Every `toFixed(2)`/2-decimal assumption is replaced with exponent-based rounding on both sides. **No** full minor-units migration; order/storefront money storage is untouched. *(Phase 5B.)*

**D2 — POS plan billing.** Web-only purchase. All purchase UI is removed from the mobile app (no Stripe WebView, prices, buy buttons or links). The app only checks entitlement; with no active plan it shows a neutral "POS plan not active for this store" screen with Refresh and Sign out. The backend Stripe Checkout/webhook flow stays working for the web. *(Phase 5E.)*
- **Web purchase surface — FLAGGED:** no seller web dashboard exists in this workspace (searched `pos/`, `solvexo-api/`, `solvexowhitelable-app/`, `ecommerce_store/`, `book_store_app/` for `pos-subscriptions`/`pos-plans`; hits are only the API and the POS app itself). The backend contract a web surface needs is in place — `GET /api/pos-plans`, `GET /api/pos-subscriptions/:storeId`, `POST /api/pos-subscriptions/:storeId/checkout-session` (takes `planId`, `successUrl`, `cancelUrl`) — but I could not verify that a web page calls it. **Nothing is being invented**; if the seller web panel does not yet have a "Buy POS plan" page, sellers cannot buy a plan once the in-app purchase UI is removed. This must be confirmed before 5E ships to users (see §4).

**D3 — Gating.** POS features are gated by an active POS plan only (plus the store existing and not suspended/rejected). The platform-plan trial guard (`BillingAccessGuard`/`blockDuringTrial`) is removed from POS routes. Enforced on the backend by a guard; the app's gate is UX only. *(Phase 5A.)*

**D4 — Device model.** Shared cashier device. Owner login is for device setup only; daily use is employee PIN login; idle auto-lock back to the PIN screen (configurable, sensible default); owner-only screens (settings, employees, locations, plan status) require a manager/owner PIN or owner re-auth; full sign-out clears all tokens, employee JWT, cached data and queued-sale ownership correctly. *(Phase 5D.)*

---

## 2. Remaining open questions — resolved

| # | Question | Decision | Reason |
|---|---|---|---|
| Q1 | Money model | Resolved by D1. | — |
| Q2 | Authoritative sale currency | The store's `baseCurrency` only; POS sales are never priced in a Market currency and need no frozen FX rate. `currencySymbol` becomes derived from the currency code (read-only in the UI); the sale stores `currency` + `currencyExponent`. | POS settles at the counter in the shop's own currency; Markets/FX apply to online checkout. Simplest, matches Square. |
| Q3 | Mobile billing path | Resolved by D2 (web-only). | — |
| Q4 | POS plan vs platform plan | Resolved by D3. Open register at expiry: allowed to **close** (and refund/void/read) after expiry; cannot open a session or create/complete sales. No grace period in v1 (status is already derived from `expiresAt`). | Never trap cash in an open drawer; Shopify/Square lock selling, not reconciliation. |
| Q5 | Per-plan limits | No limits enforced in v1. `PosPlan` gets optional `maxRegisters/maxEmployees/maxLocations` (null = unlimited) in 5E and the backend enforces them on create when set. | Limit values are pricing decisions (listed in §4); the mechanism is cheap and backend-enforced. |
| Q6 | Device model | Resolved by D4. | — |
| Q7 | Offline stock conflict & policy | Accept the already-completed cash sale and flag it `stockConflict` for manager review (never silently reject money already taken); for a *non-completed* hold the server rejects. Max offline age 72 h (older → server rejects with a clear code, manager reviews). Provisional receipt number `OFF-<deviceShort>-<seq>`, mapped to the real number after sync. Structured error codes (`SESSION_CLOSED`, `INSUFFICIENT_STOCK`, `PLAN_NOT_ACTIVE`, …). *(Phase 5C.)* | Customer already has the goods; Square offline mode behaves the same. The user's 5C brief also asks for "explicit server rejection shown to the user" on oversell — implemented as: reject only when the sale cannot be honoured (closed/expired session, plan inactive, >72 h), accept-and-flag for stock shortfall on completed sales. **If you want hard rejection on oversell instead, say so before 5C.** |
| Q8 | Printers | Android: Bluetooth (classic + BLE) with proper permissions. iOS: BLE printers + PDF via the system share/print sheet (AirPrint); no LAN printing in v1. State the iOS limitation in-app. Paper width 58/80 setting, test print, auto-print option, cash-drawer kick on cash sales. | `print_bluetooth_thermal` is the plugin in use; LAN adds a new dependency and a new failure surface. |
| Q9 | Sign in with Apple / account deletion | Add Sign in with Apple on iOS (backend already verifies Apple tokens, `auth.service.ts:462`); keep Google. Account deletion: in-app "Delete account" for the owner using a seller-capable backend deletion endpoint (build one if `DELETE /users/profile` is buyer-model only — see audit F8), soft-delete, retaining financial/sales records as required for accounting. *(Phase 5F.)* | App Store 4.8 and 5.1.1(v); removing Google login would degrade existing users. |
| Q10 | Crash reporting | Firebase Crashlytics (already stated in 5F), with `FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`; no analytics SDK in v1. | Firebase is already in the app; keeps privacy declarations minimal. |
| Q11 | Environment | `https://api.solvexo.store` is treated as **production** (default); dev/staging via `--dart-define-from-file=env/{dev,staging,prod}.json`; the "staging" code comment is corrected. No hardcoded dev URLs. | Safest default for a store build; override is explicit. *Confirm that host is production (§4).* |
| Q12 | Marketplace leftovers / store model | Multi-store stays supported (backend supports it; `store_config.dart` single-store comment is stale). Dead constants, `_RefreshButton`, buyer `product_model.dart` and unused marketplace leftovers are pruned in 5H; the `seller_onboarding` store-creation flow stays because it is the setup path. | Deleting a live setup path is riskier than keeping it. |
| Q13 | Onboarding slides | Keep the POS app's static `onboarding_content.dart` for v1 (POS-specific copy); do not call the shared backend slides module. | Backend slides are buyer-app content; no value in coupling. Easy to switch later. |
| Q14 | Uncommitted POS work | Committed on `feature/jamibranch` as separate commits (docs, then the pending onboarding/splash/signing/login WIP) before any 5A change. The unguarded signing block is fixed in 5F. | Keeps 5A diffs reviewable. |

---

## 3. Gap → phase map (all 30; each in exactly one phase)

Phase priority order: **5A → 5B → 5C → 5D → 5E → 5F → 5G → 5H**.

| Phase | Theme | Gaps | Repos |
|---|---|---|---|
| **5A** | Sale & access integrity (backend-first, then POS wiring) | **#1** entitlement guard (backend guard + app handles `POS_PLAN_REQUIRED` — gate screen itself is 5E) · **#2** idempotency on every mutating POS route, key per user intent persisted across retries/restart · **#3** atomic sale pipeline (status-guarded transitions, stock reserve/compensate, held double-complete, open-session unique index, unlimited-stock restore) · **#16** inventory `'∞ Unlimited'` typed contract + `unlimitedStock` in POS product payload · **#17** customer-search store scoping · **#23** inventory stock edit via delta/`adjust` with reason + 409/400 handling · **#30** commit pending pos-plans fix (already committed upstream as `64889f0`) and pending POS WIP | API + POS |
| **5B** | Money correctness (D1) | **#4** server recompute/validation of totals · **#5** currency + exponent snapshot, one currency-aware formatter · **#6** partial-refund reconciliation, reports include `partially_refunded`, refund pro-rating · **#14** split tender (`payments[]`, tendered/change/reference) · **#21** unified `ReceiptData` with correct currency/decimals, tax lines, VOID/REFUNDED/COPY | API + POS |
| **5C** | Offline queue hardening | **#15** `clientCreatedAt`, same key on sync, visible "needs attention" list (retry/discard by manager + audit log), explicit server rejections, cart persistence across crash/kill | API + POS |
| **5D** | Shared-device security & RBAC (D4) | **#18** employee-token 403 handling, refresh interceptor, Google sign-out · **#19** manager-token gating on reports/settings/employees/force-close + `@Throttle` on pin-login · **#24** middleware on all owner routes + idle auto-lock + owner re-auth · **#28** PIN-length mismatch (4–6 vs 4), `create-store` country, CORS header; PIN lockout verified; token cleanup | API + POS |
| **5E** | Billing UX (D2) + branding | **#8** remove purchase UI → "POS plan not active" screen · **#22** webhook refund/dispute revoke, admin grant/revoke, optional plan limits · **#25** `GET /api/branding/config` 404 fix | API + POS |
| **5F** | Store compliance & release config | **#7** iOS usage strings + `PrivacyInfo.xcprivacy` · **#9** account deletion + Sign in with Apple · **#10** signing/ProGuard/permissions/versioning/icons/splash/env config · **#11** Crashlytics + error hooks + log gating · **#12** SHA-1/serverClientId verification · **#20** printing (Bluetooth permissions + runtime request, paper width, test print, drawer kick, iOS stance) | POS (+ API for deletion) |
| **5G** | Tests | **#13** backend spec env + specs for every 5A–5D rule · **#27** Flutter CI + integration tests (checkout→receipt→refund, offline sync). *(5A–5D each ship with their own focused tests; 5G fills the matrix and adds integration/CI.)* | API + POS |
| **5H** | Release candidate | **#26** dead-code/constants prune, analyzer clean, BaseController decision, redundant `Get.put` · **#29** accessibility pass; localization explicitly deferred post-release (English-only v1, documented) · full regression, AAB + iOS archive, data-safety notes, go/no-go checklist | POS |

**Moved from the original 5A–5H grouping:** split tender (#14) and receipts (#21) → 5B (they change what a sale stores and what receipts print, so they belong with money); printing (#20) → 5F (permissions are a compliance item); #23 → 5A (same inventory contract as #16); #28 → 5D (auth surface).

---

## 4. Business decisions only the owner can make (safe defaults chosen so work isn't blocked)

1. **Seller web "Buy POS plan" page** — does one exist in the web seller panel? Default: assume the API is sufficient and the web team adds/has the page; 5E still removes the in-app UI. **Needs confirmation before release.**
2. **Plan pricing, durations, and any per-plan limits** (registers/employees/locations). Default: no limits.
3. **Is `https://api.solvexo.store` production?** Default: yes.
4. **Legal/store-listing items:** legal entity name, privacy-policy URL, support URL, Apple team/Play developer accounts, and bundle id finalization (`com.solvexo.solvexoPos` iOS vs `com.solvexo.solvexo_pos` Android). Default: keep current ids.
5. **Offline oversell policy** (accept-and-flag vs hard reject) — default accept-and-flag; see Q7.
6. **Draft-orders customer search leak** (web seller dashboard): `GET /api/draft-orders/:storeId/customers/search` searches *all* users. POS is fixed in 5A with a store-scoped POS route; scoping the shared draft-orders route would change web-dashboard behaviour (sellers could no longer attach a customer who never ordered from them). Default: leave that route unchanged and flag it. **Needs your call.**

---

## 5. Working rules (acknowledged)

- Backend only on `solvexo-api` `feature/jamibranch`; POS only on `pos/` `feature/jamibranch` (cut from `main`). Never commit to `main`. Small focused commits; push both branches at the end of each phase once tests pass.
- Read existing code first; reuse BaseClient → Repository → Controller → View, GetX bindings, `IdempotencyInterceptor`, `writeAuditLog`.
- Never fake a rule on the client that the backend doesn't enforce. Keep shared-module changes backward compatible and call them out.
- Each phase ends with `pos/docs/phase5X_summary.md`; stop for approval after 5A.
