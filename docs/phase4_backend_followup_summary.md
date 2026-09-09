# Phase 4 follow-up — Real backend RBAC enforcement + audit logging — Completion Summary

Implements the follow-up plan (`~/.claude/plans/rosy-squishing-mccarthy.md`) built after the user explicitly lifted the "mobile only" boundary for this piece of work and asked for the two things Phase 4 had deferred — discount/cash-management enforcement and audit-log coverage — to be built properly, from the backend.

## The key discovery that changed the design

Reading `pos.service.ts` in full (not just fragments) surfaced that `pinLogin` already mints a **signed employee JWT** (`employeeToken`: `employeeId`/`role`/`storeId`, 12h expiry) that nothing verified anywhere, and the mobile app never stored. The *existing* refund/void check instead trusted a client-supplied `actingEmployeeId` string looked up in the DB — spoofable by anyone holding the seller's own JWT, since `GET /pos/employees/:storeId` already lists every employee's id and role. Building this "properly" meant using the token that already existed and is cryptographically unforgeable, not further-hardening the spoofable string check.

**Design:** every privileged action sends the *currently PIN-logged-in employee's* verified JWT (not a separate "approver" — matching the Phase 4 mobile UX, where a cashier simply doesn't see gated actions). The backend verifies the token's signature and `role` claim before allowing the action.

## Backend changes (`solvexo-api/src/pos/`)

- **`pos.service.ts`**: new `verifyEmployeeToken`/`requireManagerEmployee` private helpers (JWT verify via the same `jwt`/`requireJwtSecret()` already used to mint the token).
- **`refundSale`/`voidSale`**: replaced the skippable `if (actingEmployeeId) {...}` check with a mandatory `requireManagerEmployee` call. `RefundSaleDto.actingEmployeeId` and the void body's equivalent field were removed — the token is now the sole authorization source.
- **`cashInOut`**: previously had zero role check; now manager-only, unconditionally.
- **`createSale`/`completeSale`/`editHeldSaleItems`**: previously had zero check on `discount`; now require a verified manager token whenever `discount > 0`.
- **Audit logging added** (writes to the existing `PosAuditLog` collection via the existing `writeAuditLog` helper — same mechanism already used for refund/void/employee-deactivate/PIN-reset/force-close) to the categories that had **no** coverage at all before this: `sale_created`/`sale_held`/`sale_completed`, `session_opened`, `session_closed`, `cash_in`/`cash_out`, `employee_updated`, `settings_updated`, `pin_login`.
- **New `POST /pos/pin-logout`** endpoint + service method — didn't exist before. Best-effort (logs the event, doesn't hard-fail on an already-expired token); real token revocation (a blocklist) is flagged as a further-out enhancement, not built.
- **Idempotency + stock-floor hardening** (`sales.schema.ts`, `createSale`, `completeSale`): the `idempotencyKey` index is now `unique` (was `sparse`-only — the exact gap flagged in Phase 3 as the most severe finding of the whole engagement, since a retried checkout could duplicate a sale). Stock decrements now carry a `stock: {$gte: qty}` floor guard so a race can no longer drive stock negative.

**Verification:** `npm run build` (tsc via `nest build`) passes cleanly. New `pos.service.spec.ts` (8 tests, all passing) covers the token-verification logic directly. `eslint` on the changed files reports errors, but a stash/pop comparison confirmed **637 of those errors already existed on the unmodified files** before this work — pervasive pre-existing `@typescript-eslint/no-unsafe-*` noise from this codebase's heavy Mongoose `any` usage, not something introduced here; `tsc` is the compile gate that actually matters and it's clean.

**Note:** this backend repo had substantial pre-existing uncommitted work across ~20 unrelated files/modules (address, bookings, categories, manual-payments, messaging, orders, products, promotions, rating, refund-request, search, subscriptions) when this session started — none of it was touched, and nothing was committed.

## Mobile changes (`pos/`)

- **Employee token capture/storage**: `PosRepository.pinLogin()` now parses `employeeToken`; `AppPreferences.setPosEmployeeToken`/`getPosEmployeeToken` store it in the same secure storage the Phase 4 auth-token migration set up (it's the same category of bearer credential).
- **Sent as `x-pos-employee-token`** on every privileged call: `refundSale`, `voidSale`, `cashAdjustment`, `createSale`, `completeSale`, `editHeldSaleItems` — via a new `_employeeAuthHeaders()` helper in `PosRepository`.
- **`actingEmployeeId` removed** from `refundSale`/`voidSale`'s Dart signatures and call sites (`pos_sale_detail_controller.dart`, `pos_orders_controller.dart`) — the token is now the real authorization source, so the old client-supplied id no longer does anything meaningful.
- **`pinLogout()`** added to `PosRepository`, called fire-and-forget from `PosSettingsController._closeShift()`'s success path — the one place the app already treats a PIN session as ending.
- **Discount gating extended to match the new backend enforcement**: `PosHomeController.isDiscountBlocked`/`canCharge` block a cashier from completing or holding a sale with a discount; `pos_cart_sheet.dart`'s discount field is visibly disabled (with a "managers only" hint) for a cashier.
- **Cash Management gating extended**: `PosSettingsController.isManager` gates `showCashAdjustmentDialog` — a cashier sees a "Managers only" trailing label and a clear explanatory message instead of the dialog, matching the refund/void treatment from Phase 4.
- Doc comments across `pos_role.dart`, `pos_sale_detail_view.dart`, `pos_transaction_card.dart` updated — they previously (correctly, at the time) described the backend check as "weak"; that's no longer accurate, so the comments now describe the real, signed-token-verified enforcement.

## Explicitly not built (flagged, per the plan)

- A manager-PIN-reentry "override" flow for a cashier to get an approval without switching accounts — not asked for; the existing design (token == currently logged-in employee) doesn't need it, matching what Phase 4 already shipped.
- Employee-token revocation/blocklist on logout — the 12h expiry is the bound in the meantime.
- Wrapping `createSale`'s check+create+decrement in a database transaction — the floor-guarded `$inc` closes the concrete oversell path without introducing Mongo transactions to this codebase in this pass.

## Testing

- Backend: `npm run build` clean; `pos.service.spec.ts` (8 new tests) covers `verifyEmployeeToken`/`requireManagerEmployee` directly (wrong secret, wrong store, wrong token type, cashier vs. manager role).
- Mobile: `flutter analyze` clean (same 2 pre-existing info-level lints); `flutter test` — all 51 tests pass (4 new: 3 discount-gating scenarios extending `pos_cart_math_test.dart`, 2 Cash Management visibility scenarios extending `pos_role_test.dart`).
- Manual: launched on iOS Simulator, boots cleanly, no crash, login screen renders correctly.

## Live end-to-end verification (2026-08-31)

Ran the real backend against a fully isolated local MongoDB + Redis (separate ports, separate data directories — never touched the shared/staging database referenced in the committed `.env`), and drove the entire flow with real HTTP requests: registered/verified a seller, created a store, a manager employee, a cashier employee, a product with stock, a register, and a register session, then exercised every gated action as both roles via curl.

**Everything in the RBAC/audit matrix passed exactly as designed:**
- Discount on `createSale`: no token → 403 ("A valid employee PIN session is required..."); cashier token → 403 ("Only managers can apply a discount"); manager token → 201, sale created.
- `cashInOut`: same three-way result (no token / cashier / manager) with the matching manager-only messages.
- `refundSale` / `voidSale`: same three-way result; a manager successfully refunded and voided real sales, restoring stock each time.
- Idempotency: two identical `createSale` requests with the same `idempotencyKey` (simulating a retried checkout) returned the exact same sale ID — verified only one document exists in Mongo and stock was decremented exactly once.
- Stock floor guard: an oversell attempt (qty far beyond available stock) was rejected with a clean 400, no negative stock.
- Audit log (`GET /pos/audit-logs/:storeId`) captured all ten targeted categories with correct `employeeId`/`metadata`: `pin_login`, `session_opened`, `sale_created`, `cash_in`, `sale_refunded_full`, `sale_voided`, `session_closed`, `pin_logout`, `employee_updated`, `settings_updated`.

**One real bug found and fixed by this testing:** the `idempotencyKey` unique+sparse index (added in this same follow-up) broke the very next key-less sale after the first one. `createSale` was writing `idempotencyKey: dto.idempotencyKey ?? null`, and the schema also declared `@Prop({ default: null })` on that field — so every sale without a client-supplied key got an *explicit* `null` written, and Mongo's `sparse` option only excludes documents where the field is truly absent, not ones where it's `null`. The second key-less sale hit `E11000 duplicate key error ... idempotencyKey: null` and 500'd. Fixed by (1) removing the schema's `default: null` (`sales.schema.ts`) and (2) only including `idempotencyKey` in the `.create()` payload when a real key is supplied (`pos.service.ts`, `createSale`) — so the field is genuinely omitted from the document, not nulled, when the client doesn't send one. Verified the fix by recreating a key-less sale after the change (succeeded) and re-confirming the retried-key case still dedupes correctly. This is exactly the kind of gap `npm run build`/unit tests couldn't have caught — it only surfaces once you write two real documents to a real unique index.

Not covered in this pass: multi-terminal concurrent-retry racing (two simultaneous requests with the same key, both losing the pre-check race) and the buyer-facing storefront/checkout flows, which are outside this follow-up's scope.
