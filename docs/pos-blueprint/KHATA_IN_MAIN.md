# Khata in main: facts for the owner / Uzair discussion

Read-only note (G5.8). Nothing in `src/khata` was changed. Facts are from `solvexo-api` at the G5.8 merge of `origin/main`.

## What it is
A per-store **customer ledger** ("khata" / udhaar) for sellers, written by Muhammad Uzair (3 commits on 2026-11-06):
- `6ba087f` core: append-only entries, limits, aging, statements
- `0917997` mirrors wholesale (B2B) terms receivables into the ledger
- `97bd6f5` POS udhaar (a POS sale put on account) and SMS balance reminders

What it does:
- One **account** per store + customer, with a balance, an optional credit limit, and a currency.
- Each change is an appended **entry** (`sale`, `payment`, `adjustment`, `reversal`), posted in one transaction together with one atomic update of the balance. Entries are corrected by a reversal entry, never edited.
- Aging report, per-account statement (JSON and CSV), credit-limit check.
- **B2B**: when a wholesale terms order's receivable changes, the ledger mirrors it (hook `b2bOrderChanged`, set in `KhataService.onModuleInit`; never throws into the order flow).
- **POS sale on account**: a *completed* POS sale taken with payment type `other` can be put on an account (idempotent per sale, key `pos:<saleId>`; the credit limit applies). A voided or fully refunded sale can be taken back with a reversal.
- **SMS reminder**: only to a customer who opted in to SMS from the store, only with the store's SMS gateway on, at most one per 24 hours per account.
- Amounts are stored as **decimal numbers** (`round2`), not minor units.

## Routes
All under `api/khata/:storeId`, guarded by `JwtAuthGuard + RolesGuard + PermissionsGuard`, roles `seller` / `staff`, with a store-ownership check. Permissions are `khata.view` and `khata.manage`.

| Method | Path | Permission |
|---|---|---|
| GET | `accounts` | view |
| POST | `accounts` | manage |
| GET | `report/aging` | view |
| GET | `accounts/:accountId` | view |
| GET | `accounts/:accountId/entries` | view |
| GET | `accounts/:accountId/aging` | view |
| GET | `accounts/:accountId/statement` | view |
| GET | `accounts/:accountId/statement.csv` | view |
| POST | `accounts/:accountId/entries` | manage |
| POST | `entries/:entryId/reverse` | manage |
| POST | `accounts/:accountId/pos-sales/:saleId` | manage |
| POST | `pos-sales/:saleId/release` | manage |
| POST | `accounts/:accountId/remind` | manage (throttled 10/min) |
| PATCH | `accounts/:accountId/limit` | manage |

## Collections and indexes
- **`khata_accounts`**: unique `(storeId, customerKey)`.
- **`khata_entries`**:
  - unique `(accountId, seq)`;
  - unique partial `(storeId, sourceKey)` (one entry per source, e.g. `pos:<saleId>`);
  - unique partial `(storeId, reversesEntryId)` (one reversal per entry).
- **It reads:**
  - the **POS sales collection** (`saleModel` = `src/pos/schemas/sales.schema.ts`), read-only, selecting `status paymentMethod total currency customerId saleNumber`;
  - stores (name, for the SMS text);
  - the SMS consent and gateway (`messaging-channels`).
- **It writes:**
  - nothing in POS collections;
  - activity log category `khata`.

## Who calls it
- **Backend:**
  - `app.module.ts` registers it;
  - `b2b-order.util.ts` holds the hook;
  - `staff/role.service.ts` grants `khata.view` / `khata.manage` (Store Manager: both; Support Staff: view).
- **Clients:**
  - no reference in the POS app (`pos/lib`);
  - no reference in `solvexo-account-web`;
  - no reference in `solvexowhitelable-app`.
  
  The seller web dashboard is not in this workspace, so I can't confirm whether it calls these routes. Ask the web team or Uzair.

## Does any POS code path touch it?
**No.**
- Nothing under `solvexo-api/src/pos` imports or calls khata.
- The POS app has no khata screen, entry point, flag or placeholder; the gap audit marks khata out of scope by product decision.
- The only link is one-way: khata **reads** POS sales when a seller puts a sale on an account through the khata routes. POS behaviour is the same whether khata exists or not.

## Points for the discussion
1. **Keep, retire, or adopt into POS?** Removing it would change live behaviour on main (routes, permissions, B2B mirroring) and drop ledger data. That decision belongs to the owner, with Uzair.
2. **If POS ever adopts udhaar:**
   - khata amounts are decimals, while POS money is minor units with currency and exponent;
   - POS writes go through the POS permission matrix, ROUTE_TIERS, and audit-in-transaction, whereas khata uses staff permissions and the activity log.
   
   Both would need aligning first.
3. **A sale "on account" must be taken as payment type `other`** at the till today. Shift close and reports would count it as `other`, not as credit.
