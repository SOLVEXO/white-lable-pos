# G4.8 API changes — for the admin panel

All changes are **additive**: existing fields and endpoints behave as before, except where a store turns a new setting on. Money is always integer minor units with the response's `currency` + `currencyExponent`. Auth is as today: the owner/staff JWT, or a POS device token plus `x-pos-employee-token` (PIN session). Errors are `{ statusCode, code, message, … }`.

## 1. Hide costs from managers

**Setting** (existing store-settings endpoint, owner only):

```
PATCH /api/pos/store/settings/:storeId
{ "security": { "hideCostsFromManagers": true } }      // default false
```
Response: the full settings (`security.hideCostsFromManagers`). Every change is audited (`store_settings_changed`, before / after).

**Effect.** When the setting is on and the caller is **not the owner**, every `/api/pos/...` response has its cost fields removed, and `data.costsHidden: true` is added. Report responses (`/api/pos/reports/...`) always carry `costsHidden: true` while the setting applies, even when nothing was removed. Revenue, quantities and sale totals stay.

Removed everywhere: `costPrice(Minor)`, `cost(Minor)`, `unitCost(Minor)`, `wac`, `averageCost(Minor)`, `stockValue(Minor)`, `stockAdjustValueMinor`, `expiredValue`, `totalValue`, `variantsWithoutCost`, `grossMargin(Minor)`, `margin`, `marginPercent`, `profit`, `grossProfit(Minor)`, `afterExpenses(Minor)`, `costOfGoodsSoldMinor`, `cogs(Minor)`, `netWithCostMinor`, `netNoCostMinor`, `costUnknownNetMinor`, `costCoveragePercent`, `shippingCostMinor`, `taxCostMinor`, `itemUnitCostMinor`, and in reports the payables `supplierPaymentsMinor` / `supplierPaymentsNote`.

Removed on some routes only:
- **`/api/pos/inventory/...`:** `value`, `valueMinor` (stock value at cost).
- **`/api/pos/supply/...`:** every amount (PO line costs and totals, receipts, payables incl. the aging buckets, supplier ledger). That means **every key ending in `Minor`** (a pattern, so a new amount can't leak), plus the major-unit names `amount`, `balance`, `balanceAfter`, `total`, `subtotal`, `lineTotal`, `tax`, `shipping`, `credit`, `current`, `unit`, `prev`, `new`, `paid`, `outstanding`, `aging`, `payable`, `d30`, `d60`, `d90`.

The owner always sees everything. Cashiers never saw cost on inventory routes, and still don't. The full registry is `solvexo-api/src/pos/cost-visibility.registry.ts`; a test fails when a new cost-looking field isn't classified there.

The admin panel uses the owner's session, so it always sees costs. Show the setting as a switch under Security.

## 2. Require a PIN to reprint

**Setting:**
```
PATCH /api/pos/store/settings/:storeId
{ "security": { "requirePinForReprint": true } }       // default false
```

**Record a reprint** (any till role; idempotent with `Idempotency-Key`):
```
POST /api/pos/reprints/:storeId
headers: x-pos-employee-token (PIN session), x-pos-approver-token (a manager's PIN token — only when required)
{ "documentType": "sale" | "invoice" | "credit_note", "documentId": "<sale id or credit note id>", "reason": "optional, ≤ 200 chars" }
→ 200 { "success": true, "data": { "documentType", "documentId", "saleId", "reprintNumber": 2, "reprintCount": 2, "approvedBy": "<employeeId>|null", "createdAt" } }
```
- When the setting is on, a **cashier** needs a manager's approver token. Managers and the owner reprint directly.
- Each reprint is an append-only event (collection `posreprintevents`: who, till, approver, reason, number), written in **one transaction** with the audit row (`document_reprinted`) and, for `sale`, the sale's `reprintCount`.
- The print says **"REPRINT #n"**, where n = `reprintNumber`.

Errors:

| code | status | when |
|---|---|---|
| `POS_APPROVAL_REQUIRED` | 403 | the setting is on, the caller is a cashier, and there's no valid manager approver token (`approver: "manager"`, `reasons: ["reprint_pin"]`) |
| `POS_PIN_REQUIRED` | 403 | a device with no PIN session |
| `DOCUMENT_TYPE_INVALID` | 400 | documentType not one of the three |
| `DOCUMENT_NOT_FOUND` | 404 | not a document of this store |
| `NO_INVOICE` | 400 | `invoice` for a sale without a tax invoice |

**Counts on documents:**
- `GET /api/pos/sales/:saleId` → `reprintCount` (the receipt).
- `GET /api/pos/sales/:saleId/documents` → `invoice.reprintCount`, `creditNotes[].reprintCount`, `receiptReprintCount`.

Matrix action: `sales.reprint` (all roles; the PIN rule comes from the setting).

## 3. Route tiers

Every POS route that writes, or reads cost / settings data, declares a tier: `owner`, `manager-with-limit`, `cashier` or `public`. The full table is generated in [`ROUTE_TIERS.md`](ROUTE_TIERS.md) from `solvexo-api/src/pos/pos-route-tiers.ts`; the test fails on an undeclared route. For the admin panel: routes marked `owner` need the owner's session. Routes marked `manager-with-limit` are refused to cashiers, and some ask for the owner above a per-store limit (`POS_OWNER_REQUIRED`).

## 4. Price-book validity in the store's time zone

**Write**, either way (create `POST` / update `PATCH /api/pos/catalog-admin/price-books/:storeId[/:id]`):
- **New: store days.** `"validFrom": "2026-11-12", "validTo": "2026-11-15"` means valid from the start of 12 Nov to the **end** of 15 Nov in the **store's** time zone. `null` clears. When store days are sent, they win over instants in the same body.
- Unchanged: instants. `"startsAt": "<ISO>", "endsAt": "<ISO>"`.

**Read** (`GET /api/pos/catalog-admin/price-books/:storeId`, and the create / update responses), on every book, in addition to `startsAt` / `endsAt` / `inForce`:
```
"timeZone": "Asia/Karachi",
"validFromUtc": "2026-11-11T19:00:00.000Z",   // start of the first store day (inclusive), or null
"validToUtc":   "2026-11-15T19:00:00.000Z",   // end of the last store day (EXCLUSIVE), or null
"validFromDay": "2026-11-12", "validToDay": "2026-11-15"
```
A client decides "in force at instant t" as `active && (validFromUtc == null || t ≥ validFromUtc) && (validToUtc == null || t < validToUtc)`, comparing UTC instants (never the device's local midnight). Daylight saving is handled; for example, New York on 8 March 2026 is a 23-hour day.

Errors: `INVALID_DATE` (400) when a store day isn't `YYYY-MM-DD`, or the end isn't after the start.

---

# G4.9 additions

All additive; nothing existing changes shape.

## 5. Cost fields — final classification

The three fields the G4.8 scan caught were traced to every write and read. All three are **purchase-order amounts** (inbound), so all three are **cost**. That means they're hidden from non-owners when "hide costs from managers" is on. None of them is used for a customer amount, so nothing was renamed.

| Field | Where it comes from | Classified |
|---|---|---|
| `itemUnitCostMinor` | the PO line unit cost (`items[].unitCost` → twin `items[].unitCostMinor`); an internal helper key, never a response key on its own | cost |
| `shippingCostMinor` | the shipping the **supplier** charges on a PO (`CreatePurchaseOrderDto.shippingCost`); part of the PO total and landed cost | cost |
| `taxCostMinor` | the tax on a PO / supplier bill (`CreatePurchaseOrderDto.taxCost`); part of the PO total | cost |

The tax charged to the **customer** is the sale's `taxMinor` (and the line tax). It's a different field and stays visible. The registry records each decision with its reason (`COST_FIELD_DECISIONS` in `cost-visibility.registry.ts`), and a test holds the registry to it.

## 6. Offline-buildable receipt link (public)

```
GET /r/s/:storePublicId/:clientKey          (no auth; rate-limited 40/min per IP; no-store, noindex, strict CSP)
```
- **`storePublicId`:** the store's slug (assigned once, never changed).
- **`clientKey`:** the sale's client key, which is the idempotency key the till makes when Charge is first tapped (`pos-<µs since epoch>-<24 hex>`). The offline queue replays the sale with the same key, so the link works before and after sync.

Answers:

| Case | Status | Page |
|---|---|---|
| malformed id, unknown store, a key older than 30 days or more than a day in the future, a held / discarded sale, a link a manager revoked | 404 | the same "not available" page as every other link |
| well-formed key, sale not on the server yet | 200 | "Your receipt is syncing" (no sale or store data; refreshes itself every 30 s) |
| the sale | 200 | the same receipt as `/r/:token` |

The existing token links (`/r/:token`, `/invoice`, `/credit-note/:n`) are unchanged. All four are tier `public` in `ROUTE_TIERS.md`.

**For the till / admin:** `GET /api/pos/settings/:storeId` now also returns `storePublicId` and `receiptLinkBase` (`<API_PUBLIC_URL>/r/s/<slug>/`). The till caches them with the settings and builds the QR offline. **`API_PUBLIC_URL` must be set** in each environment (default `https://api.solvexo.store`).

## 7. Loyalty balance on the sale

`loyaltyBalanceAfterPoints` (integer points) on a sale is set when all of these hold: the sale is made **online**, it has a customer, and the store's loyalty programme is on. It's read from the points ledger inside the sale's own transaction, and also set when a held sale is completed online. Older sales, walk-ins, loyalty-off stores and offline replays don't have it. Returned by `POST /api/pos/sales`, `GET /api/pos/sales/:id` and the complete-held-sale call.

## 8. Original vs reprint

`POST /api/pos/reprints/:storeId` accepts an optional `"kind": "original" | "reprint"`: what the till expects to print. **The server decides**, and the answer says what to print:

- **Tax invoice / credit note:** the **first** print is `kind: "original"`, `reprintNumber: 0`. It needs no PIN even when "require PIN to reprint" is on, and is audited as `document_printed`. Every later print is `kind: "reprint"`, numbered 1, 2, … (audited as `document_reprinted`, PIN rule applies).
- **Receipt (`sale`):** unchanged; every recorded print is a reprint from #1.
- **Response adds:** `kind` (recorded) and `requestedKind` (what was asked). `400 PRINT_KIND_INVALID` for any other value.
- **Event records:** each event in `posreprintevents` now has `kind`. Events from before G4.9 have none and count as reprints. Nothing is backfilled: such a document carries on from its highest number.
- **Two tills printing a new document at once:** exactly one gets the original; the other gets reprint #1, and the PIN rule applies to it.

`GET /api/pos/sales/:saleId/documents` adds `invoice.printed` and `creditNotes[].printed`. `printed` is true once any print has been recorded, so the next print is a reprint.

---

# G5.1 additions

All additive; nothing existing changes shape.

| Route | Who | What |
|---|---|---|
| `POST /api/pos/team/clock/:storeId` (existing) | any PIN session | **New optional `employeeId`**: clock ANOTHER team member. It needs `x-pos-approver-token`, which is either that member's own PIN session or a manager's. Without one: `403 POS_APPROVAL_REQUIRED` (`approver: "member_or_manager"`, `reasons: ["on_behalf_clock"]`, audited `pos_approval_missing`). The event records `actorId`, `onBehalf: true`, `approvedBy` and `approval` (`member_pin` / `manager_pin`), and the audit row `attendance_clocked_on_behalf` (actor = `employeeId`, subject = `targetId`) is written in the same transaction. A late (offline-queued) event needs a token that was valid when it happened. Also `EMPLOYEE_NOT_FOUND` (404) and `EMPLOYEE_INACTIVE` (409). Matrix action `team.attendance.onBehalf` (all roles; the PIN is the control). |
| `GET /api/pos/team/members/:storeId` | any PIN session | The team list a till can read: `{ members: [{ id, name, email, role, status }] }`. No PINs. (`GET /api/pos/employees` is owner-session only and refuses device tokens.) |
| `GET /api/pos/team/profile/:storeId/:employeeId` | managers for anyone; a cashier for themself | `{ name, email, role, status, lastLoginAt, state: { clockedIn, since }, currency, currencyExponent, timeZone, sales: { today, last7Days, last30Days: { sales, totalMinor } } }`. `lastLoginAt` comes from the `pin_login` audit rows; sales are completed and partly refunded sales they rang up, counted by store days. |
| `GET /api/pos/inventory/stock/:storeId?locationId=` (existing) | `inventory.view` | **New `locationId`**: only the variants stocked at that location (bins summed). Each row gets `locationStock`; `filter=out` means none left at that location. `400 LOCATION_INVALID` for an unknown id. |
| `GET /api/pos/inventory/locations/:storeId` | `inventory.view` | `{ locations: [{ id, name, status }] }`, for the filter (the owner-session locations route refuses device tokens). |
| `GET /api/pos/sales?registerId=` (existing) | as before | **New `registerId`** filter (`employeeId` already existed). |
| `GET /api/pos/supply/suppliers/:storeId/:id` (existing) | `supply.view` | **New `productsSupplied`**: `[{ variantId, productId, name, sku, options, orderedQty, receivedQty, orders, lastOrderedAt, lastUnitCostMinor }]`, from its purchase orders (cancelled ones excluded), newest first, at most 50. `lastUnitCostMinor` is a **cost** field: removed for a manager when the owner hides costs. |
| `POST /api/pos/cash/movements/:storeId/:requestId/receipt` | the person who recorded it, or a manager | Multipart `file` (JPEG / PNG / PDF by content, size limit as for expense receipts). Append-only row in `poscashattachments`, written with the audit row `cash_movement_receipt_attached` in one transaction. Errors `MOVEMENT_NOT_FOUND`, `FILE_TYPE`, `FILE_TOO_LARGE`. |
| `GET /api/pos/cash/movements/:storeId/:requestId/receipt` | same | A 5-minute link (`Cache-Control: no-store`), audited `cash_movement_receipt_viewed`. The daybook flags cash in / out lines with `requestId` + `hasReceipt`. |

**Boot check:** outside development the API refuses to start without a valid public https `API_PUBLIC_URL` (see `G1B_RUNBOOK.md` §11). **Not built:** role presets (their contents are a decision for Sir Atiq).


---

# G5.2.0b — receipt links on the web domain (hand-off to the web team)

**API:** a new optional env var `RECEIPT_PUBLIC_URL` (the customer-facing web origin, e.g. `https://solvexo.store`). When it's set, every receipt QR and share link the API hands out is built on it:
- `receiptLinkBase` in `GET /api/pos/settings/:storeId` → `https://solvexo.store/r/s/<store slug>/`;
- the token link → `https://solvexo.store/r/<token>`, plus `/invoice` and `/credit-note/<number>` under it.

When it's unset, everything stays on `API_PUBLIC_URL`. The pages themselves are **still served by the API**.

**What the web app must do before `RECEIPT_PUBLIC_URL` is set:**
1. **Proxy, not redirect,** every path under `/r/` to `API_PUBLIC_URL`, keeping the path and query: `https://solvexo.store/r/<anything>` → `https://api.solvexo.store/r/<anything>`. A redirect would also work, but a proxy keeps the customer on the store's domain.
2. **Keep the status codes:**
   - `200` for the receipt, invoice and credit-note pages;
   - `200` for the **"Your receipt is syncing"** page;
   - `404` for the single **"not available"** page (unknown, revoked, expired or malformed).

   Don't replace the API's 404 page with the web app's own 404, and don't turn 404 into 200.
3. **Don't cache:** the API sends `Cache-Control: no-store`. Respect it at the CDN and edge, above all for the "syncing" page, which turns into the real receipt as soon as the sale syncs (the page also refreshes itself every 30 s).
4. **Pass the other headers through unchanged:** `Content-Type: text/html`, `X-Robots-Tag: noindex, nofollow`, `Referrer-Policy: no-referrer`, `Content-Security-Policy` and `X-Content-Type-Options`. Add no scripts, analytics or cookies to these pages.
5. **Rate limits:** the API limits these routes per client IP (40/min) and reads the client IP from `X-Forwarded-For` (`TRUST_PROXY_HOPS`). Forward the real client IP. If the web app adds a proxy hop, raise `TRUST_PROXY_HOPS` by one on the API.
6. **Check:** `curl -i https://solvexo.store/r/s/<slug>/pos-0000000000000-000000000000000000000000` → `404` with the "not available" page; a real sale's QR → `200`.

After the rewrite is live: set `RECEIPT_PUBLIC_URL` on the API and restart. Newly printed QR codes use the web domain; older ones keep working on the API domain.

# G5.3–G5.7 additions (for the admin panel)

All changes are **additive**: no existing response changed shape, and every new feature is **OFF** until switched on.

## 9. Connector switches (per store)
`PATCH /api/pos/store/settings/:storeId` accepts a new section `{ connectors: { <flag>: boolean } }`. It is owner only and audited as `store_settings_changed` with before and after. `GET` of the same route returns `connectors`, and `GET /api/pos/connectors/:storeId` returns the switches plus the server's provider status.

| Flag | Default | What it turns on | Works today? |
|---|---|---|---|
| `emailReceipts` | false | "E-mail receipt" on the till (link only, consent, rate-limited) | Yes, through main's mailer |
| `smsReceipts` | false | "SMS receipt" (the store's own SMS gateway, `sendTransactional`) | Yes, when the store's SMS channel is configured |
| `cardExternalTerminal` | false | The approval code becomes **required** on live card sales (offline replays are accepted and audited) | Yes |
| `cardGateway` | false | Reserved for in-app card payments | No provider yet (mock in dev) |
| `fiscal` | false | FBR fiscalisation of invoices and credit notes | **Mock only** in dev; production answers "not configured" (FBR_INTEGRATION_NEEDS.md) |
| `raastDisabled` | false | The owner switches Raast QR **off** for the store (the KYB gate answers `disabled_by_store`) | Yes |

`GET /api/pos/connectors/:storeId` returns `{ flags, cardGateway: { provider, testMode, configured, needs }, fiscal: { provider, testMode, configured }, raast: { kybStatus, enabled, reason, providerKey, testMode, disabledByStore, adaptersPending } }`. It is tier cashier and returns no secrets.

## 10. Receipt-link lifetime
`PATCH /api/pos/store/settings/:storeId { receiptLinks: { days: 30–3650 | null } }`. `null` means the return window, never less than 30 days. It applies to sales made after the change; older links keep 30 days.

## 11. Receipt delivery log
`posreceiptdeliveries` (append-only): one row per e-mail or SMS send, with the masked recipient, its hash, the consent basis, the status and the error. Limits: 3 per sale per hour and 500 per store per day.

## 12. Card on an external terminal
- Card tender lines may carry `approvalCode`, `last4` and `terminalLabel`. Stored on `sale.payments[].terminal` and `pospayments.terminal`.
- Refund and credit-note card tenders carry `approvalCodeRef` (and `externalTerminal: true` on refunds).
- Session report `summary.cardExternalTerminal { count, totalMinor, approvalCodes, terminals }` and payments report `cardExternalTerminal { payments, paidMinor, refundedMinor, netMinor }` are additive.

## 13. Fiscal records
- `posfiscalrecords` (append-only): one row per attempt (`documentType` invoice | credit_note, `attempt`, `status` confirmed | pending | rejected, `fiscalInvoiceNumber`, `qrPayload`, `error`, `providerKey`, `testMode`). Each row is audited (`fiscal_<status>`) in the same transaction.
- Responses lay the latest attempt over the **existing** `invoice.fiscal` / `creditNote.fiscal` object, with the same keys plus `testMode`.
- A 2-minute sweep retries pending attempts (env `POS_FISCAL_SWEEP_CRON`). Env `FISCAL_PROVIDER` chooses the provider.

## 14. Receipt logo (owner)
`POST /api/pos/store/settings/:storeId/receipt-logo` (multipart `file`: JPEG, PNG or WebP, ≤ 2 MB, resized to ≤ 1024 px) and `POST …/receipt-logo/remove`. Stored as `PosSettings.receiptLogoUrl` and shown as `receipt.logoUrl` (read-only in PATCH). Audited as `receipt_logo_changed` / `receipt_logo_removed`.

## 15. Role presets (proposed)
`GET /api/pos/permissions/:storeId` adds `presets [{ key, label, summary, status: 'proposed' }]`. `POST /api/pos/permissions/:storeId/preset { preset, preview?, expectedVersion? }` is owner only, version-guarded, and audited as `permissions_preset_applied` with the diff. See ROLE_PRESETS.md; the admin panel should show "proposed" until it is signed off.

## 16. Accounting export and API keys
See API_KEYS.md. Routes:
- `GET /api/pos/reports/accounting-export/:storeId` (manager-with-limit)
- `GET|POST /api/pos/api-keys/:storeId` and `POST …/:keyId/revoke` (owner)
- `GET /api/pos/ext/v1/{sales,inventory,accounting-export}` (store API key)

The admin panel can list keys per store through the owner routes, but it never sees a secret. Env: `API_KEY_RATE_PER_MIN` (default 60).

## 17. New env (all optional)
| Env | Default | Notes |
|---|---|---|
| `RECEIPT_PUBLIC_URL` | API_PUBLIC_URL | Customer-facing receipt origin (G5.2.0b) |
| `FISCAL_PROVIDER` | `mock` outside production, none in production | Any real key answers "not configured" until an adapter exists |
| `POS_FISCAL_SWEEP_CRON` | `*/2 * * * *` | |
| `CARD_GATEWAY_PROVIDER` | `mock` outside production | Same rule |
| `API_KEY_RATE_PER_MIN` | 60 | |
| `DEV_UPLOAD_STUB` | unset | **Dev stack only**; active only when `NODE_ENV` is exactly `development` or `test` (G5.8, tested) |
| `MOCK_FISCAL_MODE` | unset | Mock provider only (never in production): `down` / `fail` / `reject` to exercise every fiscal status |

## 18. Fiscal contract v1 (G6.1)
The full contract (shapes, statuses, transitions, offline and retries, a real adapter's mapping, checklist) is in **FISCAL_CONTRACT.md**. In short:
- Every `fiscal` block (sale response, sale read, documents, refund / void response) gains `displayLines` [{label, value}], `message`, `willRetry`, `logoUrl`, `contractVersion: 1`. Statuses: `not_enabled` (live value = not required, unchanged), `pending`, `confirmed`, `failed`, `rejected`.
- `GET /api/pos/fiscal/:storeId/issues` (manager-with-limit): failed / rejected / out-of-retries documents, last 30 days.
- `POST /api/pos/fiscal/:storeId/retry` (owner) `{documentType, documentId}`: one new attempt for a `failed` document, audited with who asked; `FISCAL_NOT_RETRYABLE` otherwise.
- `invoice.seller.taxIds` / `creditNote.seller.taxIds` [{label, value}] (optional): printed as given; without them the app prints the G2.6 `ntn` / `strn` as "NTN" / "STRN".

## 19. Provider-dependent wording and rules: `connectors.ui` (G6.1)
`GET /api/pos/connectors/:storeId` gains `data.ui` so a real provider needs no app update (the app falls back to the same values when absent):

| Key | Drives |
|---|---|
| `raast.customerInstructions`, `raast.pollAfterMs`, `raast.reasonText`, `raast.simulateAvailable` | QR screen text, status poll interval, why Raast is off, the dev-only "simulate paid" button (mock outside production only) |
| `cardExternalTerminal.label`, `cardExternalTerminal.fields[]` {key, label, required, pattern, maxLength, keyboard} | Which terminal fields the payment sheet shows (known keys `approvalCode`, `last4`, `terminalLabel`), their labels and rules |
| `cardGateway.statusText` | The card-gateway line in Payments setup |
| `fiscal.title` | The owner's fiscal switch name |
| `receipts.whatsapp.mode` (`link`/`api`/`off`), `receipts.minPhoneDigits`, `receipts.consentText`, `receipts.privacyNote` | The send-receipt sheet |

The till also shows the server's `message` before its own text for Raast QR errors, `CARD_APPROVAL_REQUIRED` and receipt sending.

## 20. Scheduled jobs on several instances (G6.1)
POS-owned jobs and their locks (shared MongoDB lease `JobLeaseService`, collection `job_leases`: atomic findOneAndUpdate on the database clock, owner id, expiry, heartbeat renewal every ttl/3, released on finish, taken over after expiry):

| Job | Lock | Two instances at once |
|---|---|---|
| Fiscal retry sweep (`POS_FISCAL_SWEEP_CRON`) | **G6.1:** `pos:fiscal-sweep` (10 min) + `pos:fiscal:<type>:<id>` (2 min) around every provider call, also on the sale-time path | Safe: one provider call per document; tests: two runners → one call, two sweeps → each document once, expired lease taken over |
| Nightly audit seal (`POS_AUDIT_SEAL_CRON`) | `pos:audit-seal` (30 min) + unique `{storeId, day}` | Safe (unchanged) |
| Payments poller (Raast status, every 3 s) | `payments:poll:<intentId>`, `payments:apply:<intentId>`, `payments:inbox:<id>` + unique event keys | Safe (unchanged) |
| KYB retention purge (off unless enabled) | `kyb:retention`, `kyb:purge:<storeId>` | Safe (unchanged) |

## 21. Capabilities probe (G6.2)
`GET /api/pos/capabilities`: public, throttled (60/min), no parameters, no store data.

It answers `{ success, data: { contract: 1, release: 2, features: [productPage, receiptDelivery, connectors, cardExternalTerminal, fiscal, receiptLogo, rolePresets, integrations, apiKeys, fiscalContract, fiscalIssues, connectorUi] } }`.

The till decides which release-#2 features to show **only** from this route. When the route is absent (the G5.1 backend), the till treats the backend as older. **Add a key when a new till feature needs it; never remove one while older apps rely on it.**
