# Phase 5C.1 fix-ups + Phase 5D (shared-device security & RBAC) — Summary

Repos: `solvexo-api` and `pos/`, both on `feature/jamibranch`. Nothing was committed to `main`.

---

## Part 1 — 5C.1 fix-ups

| # | Item | Result |
|---|---|---|
| 1 | `pos_checkout_flow_test` failing | **Cause was the test setup, not our code** (checked against a pre-5A worktree): the test seeded a token before `app.main()`, so the splash/boot raced it, and it never replaced the entitlement service, settings/products controllers or the `quoteSale` stub. Setup fixed; passes on the iOS simulator. |
| 2 | Encrypt the offline queue at rest | ✅ AES-256-GCM per field (payload, employee token, error text, discard reason). Key is generated once and lives in Keychain/Keystore (`flutter_secure_storage`), never in the DB. Existing plaintext rows are migrated **per row, in their own transaction, idempotently** (crash mid-way safe; tested with a cipher that fails half-way). A row whose key is gone is kept as `unreadable`/failed and can still be discarded by a manager — never silently dropped. `clearPreference()` now keeps the key (see 5D). |
| 3 | Offline manager approvals | ✅ The server verifies signature + role + store **as of the sale's `clientCreatedAt`** (within the 72 h window), stores `approvedBy` / `approvedAt` on the sale, and if that manager was deactivated/removed after the sale it **accepts the sale and writes an `offline_approver_deactivated` audit entry**. The queue stores only the employee JWT, and only when a discount needs it. |
| 4 | Offline price changes | ✅ New `VariantPriceHistory` (old price + `supersededAt`, TTL 30 days) written by Mongoose hooks on every path that edits a variant `price`. The app now sends `unitPrice` (what the till charged); the server records **that** (drawer cash = money collected, no shortfall). If it equals the variant's current price or one it had since the sale was made → normal; otherwise the line is stored with `priceVerified:false`, `listPrice`, the sale gets an `unverified_price` flag + `needsReview`, and an audit entry (`sale_flag_unverified_price`) — it shows in the manager review list. Legacy queue entries without `unitPrice` behave exactly as in 5C (server price + `price_changed_while_offline`). |
| 5 | Negative stock (offline oversell) everywhere | ✅ Already safe: POS/online purchase guards, storefront `inStock`, low-stock summary. **Gaps found and fixed:** public storefront listing exposed raw negative `stock`/`variants[].stock` (clamped to 0); `getStoreInventory` returned `stock`/`stockQuantity` < 0 (clamped; `stockStatus` was already `out_of_stock`); `lookupByCode` clamped; POS inventory screen shows **"Out of stock"** for ≤ 0. Real-Mongo tests: POS online sale rejected at stock 0 and −3 (stock untouched), inventory list and low-stock never show negatives. |
| 6 | Offline UI | ✅ Complete-held-sale, Refund (selected / full) and Void are visibly disabled while offline with a message ("You're offline. Completing a held sale, refunds and voids need a connection…"). A queued sale keeps the cashier who rang it (`employeeId`/`employeeName` live in the payload; replay never consults whoever is signed in) — covered by a test with a different cashier signed in at sync time. |

### 5C.1 contract changes (other clients)
- `POST /pos/sales` items accept **`unitPrice`** (optional; only used when `offline:true`).
- `Sale` gains `approvedBy`, `approvedAt`; `Sale.items[]` gains `listPrice`, `priceVerified`; new flag type **`unverified_price`** (surfaced in `GET /pos/sales/needs-review`). New collection `variantpricehistories`.
- **Buyer app / web dashboard display impact of negative stock:** storefront listings and `getStoreInventory`/lookup now return `0` instead of a negative number; `stockStatus` unchanged. A web dashboard that wanted to *show* an oversell should read the `inventory_oversell` activity-log entries (unchanged) instead of a negative `stock`. Nothing else in buyer flows changes (they already refused `stock ≤ 0`).
- Web dashboard to-do (not in this workspace): render `approvedBy`, `priceVerified:false` lines and the `unverified_price` flag in the sale/review views.

---

## Part 2 — 5D: shared-device security & RBAC

### What changed

**Device tokens** (`pos-device.service.ts`, `pos-auth.guard.ts`)
- `POST /api/pos/devices` (owner session): registers a terminal for **one store + one register**, returns a long-lived (365 d) JWT `type:'pos_device'`. The app stores it in the access-token slot and **discards the owner's JWT and refresh token**.
- **Revocation is instant**: the guard looks the device row up on every request (`POS_DEVICE_REVOKED` 401). `GET /pos/devices/:storeId`, `POST /pos/devices/:storeId/:deviceId/revoke` (owner session; audited), `GET /pos/devices/me`, `POST /pos/devices/me/sign-out` (device retires itself).
- **Scope**: a device is pinned to its store — any `storeId` in path/query/body that differs is `403 POS_DEVICE_WRONG_STORE`, and routes that only receive a sale/session id are covered by an async-context scope checked in `PosService.verifyStoreOwnership`. A session can only be opened on the device's own register (synced sales may name another register of the same store, so a re-registered device can still upload its queue).
- `PosAuthGuard` (extends `JwtAuthGuard`, same dependencies → no module wiring) accepts **either** the owner/staff JWT (unchanged for web) **or** a device token on the operational routes. `JwtAuthGuard` itself now **refuses `pos_device` / `pos_employee` tokens**, so a device token cannot reach anything outside the routes that opt in. Employee PIN tokens still travel in `x-pos-employee-token`; role checks are unchanged.
- Reports and the audit log, when called by a device, additionally require a **verified manager PIN session** (`@RequireManagerPin`).
- Read-only views the till needs from other modules are re-exposed under `/pos`: `GET /pos/inventory/:storeId`, `/pos/inventory/:storeId/low-stock`, `/pos/subscription/:storeId` (same services, same response shapes; the old routes still work for owner JWTs).

**Owner-only routes**: employees CRUD/reset-PIN, registers/shifts create/edit/delete, locations, settings update, force-close, devices admin, inventory adjust, product variants, activity log, plan checkout, store management all remain `JwtAuthGuard` + `@Roles('seller')` → a device token is refused by the server. In the app, the owner password (re-auth) gives a **10-minute, in-memory, sliding** owner session (`OwnerSession`) that is attached only to those routes; it ends on expiry, lock, sign-out and revocation. `OwnerAccessMiddleware` sends the user to the gate before management, locations, devices, stock-activity and customers screens; settings edits, plan purchase, auto-lock change and stock adjustment call `OwnerGate.ensure()`.

**Auto-lock**: `PosSettings.autoLockMinutes` (default 5, 1–240, owner-set via settings; devices cache it, so it works offline). `IdleLockService` locks to a PIN **overlay** — every controller, the cart and the offline queue stay untouched; locking ends the owner session. Unlock re-runs PIN login for the *same* employee (another employee's PIN does not unlock; "Switch user" does a proper PIN logout). The new token replaces the old one and the old one is revoked server-side.

**PIN brute-force**: per-employee lockout (5 wrong → 15 min) was verified: the lock check runs before the hash comparison and PIN login is the **only** place a PIN is verified, so there is no side door. Added: **per-device limiter** (25 failures / 10 min → `429 POS_PIN_RATE_LIMITED` with `retryAfterSeconds`, success clears it; keyed by account for non-device callers) and **a lockout now also revokes the employee's existing tokens**.

**Employee-token revocation (Redis)**: tokens now carry `jti` + `iatMs`. `pin-logout` revokes that token; deactivation/removal, PIN reset and lockout revoke every token issued before. **5C.1 offline approvals keep working**: for an offline replay a revocation counts only if it had **already happened at the sale's time** (a manager who logs out or is deactivated after ringing the discount does not invalidate it). Redis down → fail open (same as `JwtAuthGuard`).

**Revoked device** (`POS_DEVICE_REVOKED`/`POS_DEVICE_INVALID`): the app clears credentials + employee/session context only, keeps the **queue, its encryption key, caches and the store binding**, and returns to login with an explanation. The sync queue waits (nothing sent, nothing dropped) until the owner registers the device again; re-registration is allowed for the **same store**, and for a different store only when nothing is unsynced. A generic 401 no longer wipes everything (and only counts if the request actually carried a credential).

**Sign-out / device reset**: manager/owner only, **blocked while any sale is unsynced** (reuses `UnsyncedGuard` + a second check in the service); calls `devices/me/sign-out`, clears tokens + caches, and only then drops the queue key. `clearPreference()` now preserves the queue key unless explicitly told otherwise.

### API contract changes
New: `POST/GET /pos/devices…`, `GET /pos/devices/me`, `POST /pos/devices/me/sign-out`, `GET /pos/inventory/:storeId[/low-stock]`, `GET /pos/subscription/:storeId`; `PosSettings.autoLockMinutes` (+ returned by `GET /pos/settings`, accepted by `PATCH`); error codes `POS_DEVICE_REVOKED`, `POS_DEVICE_INVALID`, `POS_DEVICE_WRONG_STORE`, `POS_DEVICE_WRONG_REGISTER`, `MANAGER_PIN_REQUIRED`, `POS_PIN_RATE_LIMITED`.
Changed (backward compatible for owner/staff JWTs): operational `/pos` routes now use `PosAuthGuard`; employee tokens gain `jti`/`iatMs`; `JwtAuthGuard` rejects device/PIN-session tokens; `PosModule` now imports `InventoryModule` and `PosPlansModule` (which now exports `PosPlansService`).
**Web dashboard (not edited — to do):** a Devices page (list/revoke via the owner JWT); an `autoLockMinutes` field in POS settings; handle the new codes if the web POS terminal uses the same routes.

### Tests
| Check | Result |
|---|---|
| `npm run build` | ✅ |
| New `pos.security.integration.spec.ts` — **real Mongo + real Redis**, 18 tests: device registration/foreign store/unknown register, forged & ghost tokens, list/revoke authorisation, instant revocation + audit, re-registration, store/register scope in path/query/body, service-level scope for id-resolved routes, `JwtAuthGuard` refusing device/PIN tokens, manager-PIN gate (cashier/other store/revoked), pin-logout/PIN-reset/deactivation/lockout revocation, offline "as of sale time" rule + end-to-end offline discount after logout+deactivation, per-device rate limit (429, other device unaffected, success resets), device self sign-out | ✅ |
| New `pos.negative-stock.integration.spec.ts`, 5C.1 price/approver tests in `pos.offline.integration.spec.ts` (38 tests) | ✅ |
| `pos.module-di.smoke.spec.ts` — boots the **whole `AppModule` graph** (needs `MONGO_URI` pointing at a local throw-away DB, otherwise skipped) | ✅ resolves |
| Backend `jest --maxWorkers=2` over `src/pos`, `pos-plans`, `inventory`, `product-variants`, `common/idempotency`, `draft-orders`, `auth` | see "Final run" below |
| Flutter `test/shared_device_security_test.dart` — 23 tests: route matrix (owner vs operational), credential selection, owner-session expiry/slide, gate screen, registration swap, revocation (queue + key + binding kept; Dio 401 handling; expired owner session ≠ device sign-out; same-store re-registration rule; queue waits then drains), sign-out blocked while unsynced / allowed when empty, `clearPreference` keeps the queue key, auto-lock (timing, reset on touch, owner minutes, only when signed in, ends owner session, unlock same employee/wrong PIN/other employee, overlay keeps the cart state), devices screen revoke | ✅ |

### Migration notes
1. **Queue encryption (v3)** migrates on first open, per row, automatically. If a device's key is lost the affected rows are kept as `unreadable` and need a manager to discard.
2. **Price history** starts empty: offline sales made *before* deploy whose price changed since will be flagged `unverified_price` once (safe — they are recorded, just reviewed). No backfill needed.
3. **Existing installed POS apps** hold an owner JWT and no device token: they keep working (legacy mode). The first time the owner taps **Open POS** they are taken to *Set up this device*; from then on the owner JWT is gone from the device. Old builds keep working against the new backend (owner JWT is still accepted everywhere it was).
4. New env: none. `JWT_SECRET` is used for device tokens (same secret as employee tokens). Redis must be reachable for revocation/rate limiting; if it is down those checks fail open.

### Staging checklist (≈30 min)
1. Fresh install → owner logs in → store → **Open POS** → *Set up this device*, pick the register → lands on PIN screen. Confirm the owner password/JWT is no longer stored (Settings → Devices requires the password).
2. Employee PIN login, ring a sale; open Settings → *Business name* → asks for the owner password; wrong password refused; right one lets you edit and Devices/Employees screens open without asking again for 10 min.
3. Idle 5 min (or set Auto-Lock to 1 min as owner): lock screen appears over the cart; wrong PIN refused; right PIN returns to the **same cart**; *Switch user* goes to PIN login.
4. 25 wrong PINs from the device → "too many attempts" even with the right PIN; another device unaffected.
5. Go offline, ring a sale with a manager discount, **log the manager out / deactivate them**, reconnect → sale syncs, shows `approvedBy`, an `offline_approver_deactivated` audit row exists.
6. Offline price edit: change a variant price on the web, then sync a sale charged at the old price (accepted, verified) and one at an arbitrary price (flagged `unverified_price`, in Needs-review, drawer cash equals what was collected).
7. Offline: sync an oversell → storefront/buyer shows 0 (never negative), POS inventory shows *Out of stock*, an online purchase is refused.
8. Owner → Settings → Devices → revoke the device while it holds **unsynced sales**: next action returns to login with the explanation; the Needs-attention count is unchanged; owner logs in and sets it up again for the same store → the queue uploads. Try a *different* store while sales are unsynced → refused.
9. Sign out this device with unsynced sales → blocked with the dialog; after they sync → signs out, owner password needed to set up again.
10. While offline: Complete (held), Refund, Void are greyed out with the message; a sale queued by cashier A and synced after cashier B logged in is attributed to A.

### Not run / known limits
- Simulator integration run results: see "Final run".
- The manager-PIN alternative to owner re-auth was **not** implemented for owner screens: the backend must authenticate owner-only routes with the owner's own session, so manager PIN can't stand in for it there (managers keep their PIN-gated reports, cash adjustments, refunds, voids and discard/review). If you want managers to edit settings from a till, that needs a new backend permission model — a product decision.
- A device token's lifetime is 365 days with no refresh; re-setup is the renewal.
- `lastSeenAt` is refreshed at most every 5 minutes per device (one write, not one per request).
- Web dashboard changes (listed above) are not part of this workspace.

## Final run
_(filled in at the end of the run)_
