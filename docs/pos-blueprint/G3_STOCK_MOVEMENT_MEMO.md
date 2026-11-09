# StockMovement memo (G3.0 → G3.1) — decisions D4 (lots) and D5 (weighted-average cost)

Status: **decided and built in G3.1** (this memo records why, and what is deliberately left).

## 1. What existed
* `StockAdjustment` — an immutable-by-convention row for every *manual* stock change (restock, damaged, correction, write-off, purchase receipt, supplier return, expiry, count posting). Its own doc comment says it is **never** written for a sale: "checkout decrements are a normal part of selling". So the history could not reconcile with stock (GAP_AUDIT R2).
* `StockLot` (+ `trackLots` flag on the variant, FEFO consumption helpers `consumeLots`, expiry refresh `refreshExpiredStock`): already optional per variant (**D4's "track lots & expiry" flag exists**); a *sale* does not consume lots (the storefront order path does).
* `ProductVariant.costPrice`: already a **weighted average** maintained by purchase receipts and supplier returns (**D5's method exists**), stored as a float.
* Sale decrement: `reserveStock` runs **before** the sale document is written and is compensated if the sale fails (no transaction spans both).

## 2. Options for the ledger
| | A. extend `StockAdjustment` with sale/return rows | **B. new append-only `StockMovement` (chosen)** |
|---|---|---|
| mutability | the schema is a plain Mongoose model (no append-only guard); sales would flood a table the dashboard reads as "manual changes" | `makeAppendOnly` (no update/delete through the model), DB role can be insert-only like the other ledgers |
| dashboard impact | the web "Stock history" would suddenly show every sale | untouched; the old table keeps its meaning |
| atomicity with the document | n/a | sale/return/void rows are inserted **inside the sale/refund/void transaction**; adjustment rows are inserted by a schema hook **in the adjustment's own session** |
| shape | would need nullable columns for sale refs | `type, qtyDelta, damagedDelta, unitCostMinor, lotId, refType/refId, employee/register/session/device, dedupeKey` |

**Choice: B**, dual-written — `StockAdjustment` keeps doing what it does; every adjustment additionally writes its `StockMovement` (hook), and every sale / return / void writes its rows. A unique `(storeId, dedupeKey)` makes a retried transaction write a row at most once.

## 3. Rules the ledger follows
* `qtyDelta` is the effect on **on-hand `stock`** (sale −qty, return +qty, void +qty, receipt +qty, count variance ±, write-off −qty). A *damaged* adjustment moves units into the damaged pool and leaves `stock` alone: `qtyDelta = 0`, `damagedDelta = +qty`; a write-off removes from both. Therefore **`opening stock + Σ qtyDelta = stock`** holds from the day the ledger starts (a test asserts it across sales, returns, voids, adjustments).
* Custom items and unlimited-stock variants never moved stock → no row. Held sales → no row (stock is taken when they are completed). A restock-less return line → no row.
* **No backfill of history.** Before the ledger existed the movements are unknown; the till shows "history starts <date>" (`ledgerStartsAt`) and never guesses.
* Unit cost snapshot (D5): `unitCostMinor` on every row and on every **sale line** (`items[].unitCostMinor`) is the variant's weighted-average cost **at that moment** (the minor twin, or the decimal converted with the store's exponent; `null` = no cost was ever recorded — not zero). A return comes back at the **sale's** snapshot, not today's cost. A purchase receipt row carries the PO line's own cost. Changing a cost later never rewrites anything (a test proves it), so profit reports are stable.
* Weighted average itself is unchanged (`(stock × cost + received × unitCost) / (stock + received)` on receipt, re-weighted on supplier returns).

## 4. D4 (lots) — what G3.1 does and does not do
* Done: the optional per-variant flag already exists; lots are listed on the variant detail (expiry-sorted), the overview counts expired / expiring-in-7 / 30 days, and the cost of a lot is shown to managers.
* **Not done (G3.2):** FEFO *allocation at sale* and *blocking an expired lot at sale unless a manager overrides* — they change the sale hot path (lot rows decremented in the sale transaction, per-lot movements) and need their own race tests. The permission action `inventory.lot.sellExpired` (manager, audited, "always needs a manager") is already in the matrix so G3.2 only has to call it. The ledger already has `lotId`.

## 5. Risks / follow-ups
* The stock decrement and the ledger row are not one transaction for a **sale** (stock is reserved before the document; the compensation path puts it back). A crash between "reserve" and "document" can leave stock lower with no row; this is the existing behaviour of the sale path, and the reconcile report (`opening + Σ = stock`) is how it would show. A reconcile job is G3.2.
* `damagedStock` is per variant (not per location) as before.
