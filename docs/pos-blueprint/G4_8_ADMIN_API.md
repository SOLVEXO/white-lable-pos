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

Removed everywhere: `costPrice(Minor)`, `cost(Minor)`, `unitCost(Minor)`, `wac`, `averageCost(Minor)`, `stockValue(Minor)`, `stockAdjustValueMinor`, `expiredValue`, `totalValue`, `variantsWithoutCost`, `grossMargin(Minor)`, `margin`, `marginPercent`, `profit`, `grossProfit(Minor)`, `afterExpenses(Minor)`, `costOfGoodsSoldMinor`, `cogs(Minor)`, `netWithCostMinor`, `netNoCostMinor`, `costUnknownNetMinor`, `costCoveragePercent`, `shippingCostMinor`, `taxCostMinor`, `itemUnitCostMinor`.

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
