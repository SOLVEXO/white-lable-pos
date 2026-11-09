# Store credit (D3): the new minor-unit ledger and how the existing float balances move into it

Status: **plan only — nothing built, nothing migrated** (the ledger itself is G3.3). Dev has **0** `storecredittransactions` and 0 loyalty members, so on dev the migration is a no-op; the plan matters for production.

## 1. What exists today (`src/store-credit`)
* `StoreCreditTransaction`: one row per event, **float major units** (`amount`, `balanceAfter`, `remaining`), per `(storeId, customerId, currency)`. Credits are **lots** (`remaining` = still spendable, optional `expiresAt`); a debit lists the lots it `consumed` so a restore is exact. Balance = Σ `remaining` of non-expired lots (no balance document).
* Used by the **storefront checkout** (`CheckoutService.applyStoreCredit` — spent automatically) and by the merchant dashboard (issue / adjust). `round()` is a fixed 2 decimals and `assertCovers` uses `±0.005` → wrong for 0- and 3-decimal currencies (see the money audit in `G3_0_SUMMARY.md`).

## 2. The new ledger (decision D3: new, append-only, minor-only, tender + refund method, online-only spending)
`store_credit_entries` (append-only, `makeAppendOnly`), shaped like the stock ledger:
`storeId, customerId, currency, currencyExponent, type (opening_balance | issue | refund_credit | spend | spend_reversal | adjust | expire), amountMinor (signed), refType/refId (sale, credit note, refund, adjustment), reasonCode, note, employeeId, approvedBy, deviceId, registerId, sessionId, dedupeKey (unique per logical event), createdAt`, all money `MinorMoney`.
`store_credit_accounts` `{storeId, customerId, balanceMinor}` — a **cached** balance changed with `$inc` **in the same transaction** as the entry, guarded `balanceMinor >= amount` for a spend (the same race-proof pattern as stock). A nightly reconcile compares Σ entries with the cached balance and reports drift (never silently fixes).
* **Tender:** `POST pos/sales` payment line `{method:'store_credit', customerId, amountMinor}` — the spend entry + the sale commit together; insufficient → 409; **offline sales cannot use it** (balance unknown). **Refund method:** the Return flow offers "to store credit" → the credit note carries tender `store_credit` and an `issue`/`refund_credit` entry is written in the same transaction; above the `storeCreditRefundMinor` limit (matrix action `storeCredit.refundIssue`, D6) a manager's PIN is required.
* Customers come from the POS customer directory (G3.3); credit follows the customer, not the device.

## 3. Migration of the existing float balances (the decision this needs from you)
The hard fact: the storefront still spends the **old** ledger. If the old lots are copied into the new ledger and left alone, the same money is spendable twice (once online, once at the till). Three ways out:

| Option | What happens | Cost / risk |
|---|---|---|
| **A. Two pools (no migration)** | the till's credit is a separate balance ("POS credit"); the web keeps its own | simplest, zero data risk; customers can hold two balances; no cross-channel spending |
| **B. Bridge = new ledger becomes the single source (recommended for the end state)** | migration writes one `opening_balance` entry per customer (= Σ `remaining` of non-expired lots, converted with the store's exponent) and **marks the old lots `migratedToLedger`**; the storefront checkout/dashboard are switched to read/write the new ledger | a **shared-module change** (storefront + web dashboard) — needs its own approval, `buyer_app_changes.md` entry and release order (server before apps); expiry handling needs a rule (below) |
| **C. Dual-write period** | both ledgers are written for a while, reconciled nightly, old one retired later | more code, longest period of drift risk |

**Recommendation:** B, done in this order: (1) build the new ledger + till tender/refund (G3.3) with **no** old-ledger access; (2) ship the migration script (below) and run it on dev; (3) after your approval, switch the storefront reads/writes in a separate, reviewed change and only then run the migration on production. Until then the two pools are independent (A) — which is also safe.

### The migration script (design, dev-only until approved)
Same safety shape as the G1b / G3.0 backfills: dry run first, idempotent (an `opening_balance` entry has `dedupeKey = migrate:<customerId>:<currency>`), resumable, **reversible** (`down` deletes exactly the `opening_balance` entries it wrote and clears the `migratedToLedger` marks), refuses non-dev databases without `--production --i-have-a-backup`, does not read `.env`.
* Source: lots with `remaining > 0` and not expired and `expiredHandled = false`; amount = `toMinor(remaining, exponentOf(currency))`. A lot **off the currency grid** (e.g. 0.005 in a 2-decimal currency) is **listed, rounded down, never rounded up** — the store never owes more than the old ledger said.
* **Expiry:** the new ledger has no per-entry expiry (D3 is silent and an append-only ledger cannot track "remaining per lot"). Lots with a **future** `expiresAt` are reported (count + amount); decision for you: (a) migrate them as non-expiring (customer-friendly), or (b) leave them in the old ledger until they expire (they stay spendable on the web only). Already-expired lots are never migrated.
* Customers that exist in the old ledger but not in the POS directory get a directory entry (name from the user record) so the opening balance has an owner; reported.
* Report: customers, lots, total in minor units per currency, off-grid, expiring, skipped (with reasons). After `up`, Σ `opening_balance` entries = Σ old spendable `remaining` (converted), asserted by the script before it commits.

## 4. Decisions needed (restated)
1. Migration option A / B / C (above). Recommendation: B, in the stated order.
2. Expiring lots: migrate as non-expiring, or leave to expire in the old ledger?
3. Does store credit need an expiry in the new ledger at all (a later feature), or never?
