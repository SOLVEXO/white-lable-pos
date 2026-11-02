# Phase 5D.1 fix-ups + Phase 5E (billing UX, branding, web hand-off) — Summary

Both repos on `feature/jamibranch`; nothing on `main`.

## 5D.1
1. **Legacy auth sunset** — `POS_LEGACY_AUTH_ALLOWED` (default `true`, documented in `.env.example`). When `false`, owner/staff JWTs on POS routes get **403 `POS_LEGACY_AUTH_DISABLED`** (403, not 401, so it is never read as a dead session); device tokens and owner-only routes (device registration etc.) are unaffected. The app reacts by pushing *Set up this device*; the owner session, cart snapshot, open session and the offline queue + its key are untouched (tested). Backend tests: default passes, `false` refuses owner JWT / accepts device token / doesn't block registration.
2. **Online stock ≤ 0** — new single rule `isPurchasableOnline` (unlimited/backorder always; otherwise `available > 0 && available ≥ qty`). **Gap found and fixed: add-to-cart had no stock check at all.** It now refuses physical variants at stock 0 or negative; checkout pre-flight uses the same rule. Real-Mongo tests at stock 0 and −3: add-to-cart refused (allowed again with `allowBackorder`), pre-flight rule, and the atomic reservation filter used at order placement reserves nothing. *Note:* a variant with `allowBackorder:true` is by the merchant's choice still sellable at ≤ 0.
3. **PIN lockout threshold** — **5 consecutive wrong PINs lock that employee for 15 minutes** (`POS_PIN_MAX_ATTEMPTS=5`, `POS_PIN_LOCK_MS=15 min`; the lock check runs before the hash check, a lockout also revokes the employee's live tokens). The per-device limiter is the second layer: 25 failures / 10 min → 429.

## 5E
**App** — every purchase path removed: paywall + Stripe WebView checkout modules, plan list/price model, `getPlans`/`createCheckoutSession`, their API constants/tests, the `webview_flutter` dependency, the onboarding "Upgrade" note. New: neutral **"POS plan isn't active for this store"** screen (Refresh, Sign out — owner-gated on a registered device and blocked while sales are unsynced; no prices/links/CTA), owner-only read-only **plan status** screen (plan, state, started, expires), **expiry banner** (≤ 7 days, informational, shown to the owner on management and plan status), settings "Plan status" tile. Existing restricted mode for open sessions is unchanged. A source-scan test fails the build if checkout/Stripe/WebView/plan-list code returns.
**Branding** — Solvexo POS is one product: `BrandingService`, its repository/model/cache, `StoreConfig` and the `GET /api/branding/config` call are deleted; name/theme come from `AppBrand`. Store identity on receipts still comes from POS settings.
**Backend billing** (Stripe flow kept for web; real-Mongo tests, 19): paid-only sessions (+ `async_payment_succeeded`), idempotent on session id incl. concurrent redelivery; **stacking bug fixed** (a purchase before expiry used to restart from now and lose the remaining days; now new expiry = current + plan days); **full refund / dispute takes the unused days back** exactly once (shortens the current expiry, never below now; partial refunds ignored; manual rows never touched); admin grant/extend/revoke interplay with paid plans verified (extend stacks, revoke ends all, later purchase starts from now, refund after revoke is a no-op); optional per-plan caps `maxRegisters/maxEmployees/maxLocations` enforced on create (`400 POS_PLAN_LIMIT`; none for lapsed plans/manual grants); checkout success/cancel URLs must be absolute http(s).
**Web purchase surface** — no seller/admin web code exists in the workspace, so nothing was invented: `docs/web_pos_plan_purchase_spec.md` has screens, endpoints, URLs and webhook expectations. **Until that page exists, admin manual grant is the only way to activate a store** — it must exist before `POS_ENTITLEMENT_ENFORCED=true` goes live. Consolidated list for the web team: `docs/web_dashboard_changes.md` (must-have vs nice-to-have).

## Contract / migration notes
- New Stripe webhook subscriptions needed: `checkout.session.async_payment_succeeded`, `charge.refunded`, `charge.dispute.created` (plus the existing completed event).
- `PosPurchase` gains `reversedAt/reversedReason`; `PosPlan` gains three nullable caps; `GET /api/pos-plans` returns them. No migration needed.
- Old app builds that still show the paywall keep working against the API (endpoints unchanged).

## Tests
| Check | Result |
|---|---|
| `npm run build` | ✅ |
| Backend jest (pos, pos-plans, inventory, product-variants, idempotency, draft-orders, markets, auth, cart, checkout) | ✅ 27 suites, 421 passed (2 skipped suites / 45 tests = pre-existing env-gated) |
| `flutter analyze` | ✅ 4 pre-existing issues, none new |
| `flutter test` | ✅ 295 passed (removed paywall/checkout/branding tests; +10 billing UX) |
| iOS simulator | ✅ `pos_checkout_flow_test`, ✅ `offline_sync_test` (the first run caught a real regression — the splash `Obx` lost its observable when branding went away — fixed) |
| Not run | live Stripe end-to-end (needs real keys/webhook delivery); the unrelated pre-existing backend failures |

## Staging checklist
1. Stripe test mode: buy a plan twice in a row → expiry = first expiry + 2 terms; redeliver the event → no duplicate.
2. Refund the second payment in Stripe → expiry drops back; dispute → access ends; admin extend afterwards works.
3. Store without a plan, enforcement on: app shows the neutral screen (no prices/links); Refresh after an admin grant moves to PIN login; open sessions keep running in restricted mode.
4. Active plan with ≤ 7 days: banner on management + plan status screen; none at 8+.
5. Set `POS_LEGACY_AUTH_ALLOWED=false` with an un-migrated install: app lands on device setup with the cart/queue intact.
6. Plan with `maxRegisters: 1` → second register refused with `POS_PLAN_LIMIT`.
7. Confirm the app shows "Solvexo POS" everywhere with no branding request in the network log.
