# Web dashboard & web POS terminal — changes required by Phases 5A–5E

The web code is not in this workspace, so none of this was applied. Everything below is already live in the API (`solvexo-api`, branch `feature/jamibranch`).
Base path `/api/pos` unless stated. "Terminal" = any web POS terminal that rings sales; "Dashboard" = seller/admin web.

## A. MUST HAVE before deploy

### A1. Sales totals are server-authoritative (5B) — Terminal
- Do **not** send `tax`; it is ignored. Tax = store `taxRate` × (subtotal − discount). A cashier-typed tax field must be removed.
- Price a cart with **`POST /pos/sales/quote`** `{ storeId, items:[{productId,variantId,qty}], discountType?:'amount'|'percent', discountValue?, settingsVersion? }` → `{ quote:{ subtotal, discount, tax, total, taxRate, settingsVersion, currency, currencyExponent, lineTotals[] }, … }`; show those numbers, then send the sale.
- Sale body: `discountType` + `discountValue` (legacy flat `discount` still accepted), optional `clientTotal` (mismatch > 1 minor unit → `400 TOTAL_MISMATCH {expectedTotal, subtotal, discount, tax}` — refresh and re-confirm), and `settingsVersion` returned by the quote/settings (a tax-rate change bumps it; a sale priced with an older version within 72 h keeps its old rate).
- Discount > subtotal → `400 DISCOUNT_EXCEEDS_SUBTOTAL`; % > 100 → `INVALID_DISCOUNT`. A discount requires a verified **manager** PIN session (`x-pos-employee-token`).
- Money uses the store currency's exponent (`currency`, `currencyExponent` on settings, sales, refunds, reports) — no hard-coded 2 decimals / `$`.

### A2. Split tender and `paymentMethod:'split'` (5B) — Terminal + Dashboard
- Send `payments:[{method:'cash'|'card'|'other', amount, reference?}]` (max 8) with `amountTendered` for cash change; legacy `paymentMethod` still works. Errors: `PAYMENT_SHORT`, `PAYMENT_EXCEEDS_TOTAL`, `INVALID_PAYMENT_METHOD`, `INVALID_PAYMENT_AMOUNT`, `TOO_MANY_PAYMENTS`.
- `Sale.paymentMethod` can now be **`'split'`** (details in `payments[]`, `changeGiven`); any `switch` on cash|card|other must handle it. Refunds return to non-cash tenders first, cash last; responses carry `{refundedAmount,newStatus,tenders,currency,currencyExponent}`. Reports: `partially_refunded` sales included, `byPaymentMethod` net of refunds, `netRevenue` redefined, all reports carry currency + exponent; CSV gained `Currency`, `Refunded`, `Change Given`.

### A3. Idempotency (5A) — Terminal
Every mutating POS call must send a stable `Idempotency-Key` per user intent (and `idempotencyKey` in the sale body). Retry with the **same** key after a timeout; mint a new key only for a new intent. `409 IDEMPOTENCY_IN_PROGRESS` = retry later; business 409s (`HELD_SALE_ALREADY_RESOLVED`, `SALE_CHANGED_CONCURRENTLY`, `SESSION_ALREADY_CLOSED`) are final.

### A4. Entitlement error codes (5A/5E) — Terminal + Dashboard
`403 POS_PLAN_REQUIRED` / `POS_STORE_DISABLED` on selling routes when `POS_ENTITLEMENT_ENFORCED=true`; closing shifts, refunds, voids, reports stay allowed. Show "POS plan isn't active" — no purchase text inside the *app*; on the web link to the plan page (see `web_pos_plan_purchase_spec.md`, **a purchase page must exist before enforcement is switched on**, otherwise admin grant is the only way to activate a store).

### A5. Auth for POS routes (5D/5D.1) — Terminal
POS routes accept the owner/staff JWT today; with `POS_LEGACY_AUTH_ALLOWED=false` they return `403 { code:'POS_LEGACY_AUTH_DISABLED' }`. A web terminal that uses the owner session must either keep the flag `true` or authenticate with a registered device (`POST /pos/devices` → device token as `Authorization: Bearer`). Other codes: `POS_DEVICE_REVOKED`/`POS_DEVICE_INVALID` (401), `POS_DEVICE_WRONG_STORE`/`POS_DEVICE_WRONG_REGISTER` (403), `MANAGER_PIN_REQUIRED` (reports/audit log from a device), `POS_PIN_RATE_LIMITED` (429 + `retryAfterSeconds`).

### A6. Plan limits (5E) — Dashboard
Registers / PIN employees / locations creation can fail `400 { code:'POS_PLAN_LIMIT', limit, kind }` when the plan sets a cap. Surface the message.

### A7. Customer search is store-scoped (5A) — Terminal
`GET /pos/customers/:storeId/search?q=` returns only people who ordered from, or were sold to by, that store (not the platform-wide user list).

### A8. Negative stock never shown to buyers (5C.1) — Buyer app + storefront + Dashboard
Offline POS sales can oversell. Storefront listings, `getStoreInventory`, lookup and low-stock now return **0, never a negative number**; `stockStatus` is `out_of_stock`. Cart add and checkout refuse stock ≤ 0 (`400 "This item is out of stock"` / `Insufficient stock for …`) unless the variant is unlimited or allows backorder. To *see* an oversell use the activity-log entries `inventory_oversell` (and `Sale.flags[type='oversold_on_sync']`).

## B. NICE TO HAVE

### B1. Devices page (5D) — Dashboard (seller JWT)
`GET /pos/devices/:storeId` → `{data:[{_id,name,registerId,platform,status:'active'|'revoked',lastSeenAt,revokedAt}]}`; `POST /pos/devices/:storeId/:deviceId/revoke` (immediate). Revocation keeps the device's unsynced sales; it re-registers for the same store from the app.

### B2. Auto-lock setting (5D) — Dashboard
`PATCH /pos/settings/:storeId` `{ autoLockMinutes: 1–240 }` (default 5); returned by `GET /pos/settings/:storeId`. Owner-only.

### B3. Offline-sale review (5C/5C.1) — Dashboard
- `GET /pos/sales/needs-review?storeId=` and `POST /pos/sales/:saleId/resolve-review {note}` (manager PIN). Flags to render: `price_changed_while_offline`, `payment_shortfall`, `oversold_on_sync`, **`unverified_price`**.
- Sale fields: `isOffline`, `clientCreatedAt` (device time; `createdAt` = device time too), `receivedAt`, `settingsVersion`, **`approvedBy`/`approvedAt`** (manager who authorised the discount), `items[].listPrice`, `items[].priceVerified`, `paymentShortfall`, `needsReview`, `flags[]`.
- Audit-log actions to display: `offline_approver_deactivated`, `sale_oversold_offline`, `sale_flag_unverified_price`, `device_revoked`, `device_signed_out`, `pin_locked`; manager discards of unsynced sales are recorded through `POST /pos/offline-discards`.

### B4. Plan administration (5A.1/5E) — Admin dashboard
Plans CRUD incl. `maxRegisters/maxEmployees/maxLocations`; purchases list; manual grant/extend/revoke (see the purchase spec). Purchase rows now carry `reversedAt`/`reversedReason` (`refunded`|`disputed`) — show them.

### B5. Receipt/branding (5E) — Terminal
Receipts use store identity from POS settings (`businessName`, `businessAddress`, `businessTaxId`, `receiptHeader`, `receiptFooter`); there is no app-level white-label config (`GET /api/branding/config` is no longer called by the POS app).
