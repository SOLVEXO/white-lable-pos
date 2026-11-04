# G1b — Money in minor units: Step 0 plan (no code written; awaiting approval)

Decision in force (owner, D1): **approved.** New tables are minor-native; sales, sale items, payments, refunds, held sales and shifts get **dual-write**; **shared storefront variant prices are deferred**. All G1a rules apply: additive API, backward compatible with old builds in the field, no formatting-only diffs, ask before adding any package (this plan needs **none**).

Evidence below was gathered read-only from the code and from the **local dev database** (76 sales, 69 shifts). **Production data was not inspected** (no access), so every production number is a formula or a pre-flight check, flagged as such.

---

## 1. Inventory of money fields

Naming: every new field is the old name + `Minor` (`totalMinor`). Signed deltas keep a sign and are named `...Minor` too where the old field can be negative (`cashDifferenceMinor`, `varianceMinor`). *Source of truth* = what the app and reports read **until step f**; after the approved flip it becomes the minor field (major stays written for rollback until a later clean-up).

| Collection | Field | Now | New minor field | Truth now → after flip |
|---|---|---|---|---|
| **sales** (completed, voided, refunded, **and held / discarded** — one collection) | `subtotal` | Number (double) | `subtotalMinor` | major → minor |
| | `discount` | Number | `discountMinor` | major → minor |
| | `discountValue` | Number — **money only when `discountType = 'amount'`**; a percentage otherwise | `discountValueMinor` (only for `amount`; `percent` stays a plain number) | major → minor |
| | `tax` (the one tax line; `taxRate` is a rate, not money) | Number | `taxMinor` | major → minor |
| | `total` | Number | `totalMinor` | major → minor |
| | `changeGiven` | Number | `changeGivenMinor` | major → minor |
| | `paymentShortfall` | Number | `paymentShortfallMinor` | major → minor |
| | `refundedAmount` (cumulative, bumped by refunds) | Number | `refundedAmountMinor` | major → minor |
| sales → `items[]` | `price` (unit price charged) | Number | `priceMinor` (informational snapshot, see §6) | major → minor |
| | `listPrice` (variant list price at sale time) | Number \| null | `listPriceMinor` | major → minor |
| | `lineTotal` | Number | `lineTotalMinor` (**authoritative = `toMinor(price × qty)`**, see §6) | major → minor |
| sales → `payments[]` | `amount` (applied; cash net of change) | Number | `amountMinor` | major → minor |
| | `tendered` (cash handed over) | Number | `tenderedMinor` | major → minor |
| sales → `refunds[]` | `amount` | Number | `amountMinor` | major → minor |
| | `tenders[].amount` | Number | `tenders[].amountMinor` | major → minor |
| **pospayments** (G1a) | `amount`, `tendered` | Number | `amountMinor`, `tenderedMinor` | minor-native from the first write after step a; major kept in step with it |
| **posrefunds** (G1a) | `amount`, `tenders[].amount` | Number | `amountMinor`, `tenders[].amountMinor` | same |
| **registersessions** (shifts) | `openingCash` (the **float**) | Number | `openingCashMinor` | major → minor |
| | `closingCash` (**counted**) | Number \| null | `closingCashMinor` | major → minor |
| | `expectedCash` | Number | `expectedCashMinor` | major → minor |
| | `cashDifference` (**variance**, signed) | Number | `cashDifferenceMinor` | major → minor |
| | `cashSales`, `cardSales`, `otherSales`, `totalSales`, `totalRefunds` (running `$inc` counters) | Number | `…Minor` (integer `$inc`) | major → minor |
| | `cashAdjustments[].amount` (cash in/out, unsigned; the type says the direction) | Number | `cashAdjustments[].amountMinor` | major → minor |
| | `cardReconciliation.slipTotal`, `.expectedCard`, `.variance` (**card variance**, signed) | Number | `slipTotalMinor`, `expectedCardMinor`, `varianceMinor` | major → minor |
| **stores** (shared) → `registers[]` | `defaultFloatCash` (register's default float) | Number | `defaultFloatCashMinor` | major → minor (Store is shared with the storefront: additive field only) |
| **Offline sale payload** (sqflite queue, then `POST /pos/sales`) | `items[].unitPrice`, `discountValue` (amount type), `clientTotal`, `payments[].amount`, `amountTendered` | JSON numbers (double) | `items[].unitPriceMinor`, `discountValueMinor`, `clientTotalMinor`, `payments[].amountMinor`, `amountTenderedMinor` | server recomputes; client values are a **cross-check only** |
| Request DTOs | `openingCash`, `closingCash`, `cardTotalFromSlip`, cash-adjustment `amount`, `discount`/`discountValue`, `clientTotal`, `amountTendered`, `payments[].amount`, `defaultFloatCash` | Number | optional `…Minor` twins | additive |
| **Out of scope in G1b** | `productvariants.price / compareAtPrice / costPrice`, `variantpricehistory.price`, finance `Transaction.amount` (the ledger is fed from the sale: it keeps receiving `fromMinor(totalMinor)`), `PosSettings.taxRate` (a rate) | — | — | unchanged |

**Dev evidence for why this matters:** the exact-grid scan found **one** value that is not a whole number of minor units — a shift counter `cardSales = 3.3000000000000007`, produced by repeated `$inc` of decimals (2.2 + 1.1). Integer `$inc` on `...Minor` removes that class of drift.

## 2. Currency exponent: where it lives today
* **One table:** `common/currency-metadata.const.ts` — ISO-4217 decimals (0 for 17 codes such as JPY/KRW, 3 for 7 such as KWD/BHD, else 2; unknown → 2). `getCurrencyDecimals(code)`.
* **POS wrapper:** `pos-money.util.ts` → `exponentOf(currency)`; the maths is `toMinor`/`fromMinor`/`roundMoney`/`computeTotals` (integer minor units, half-away-from-zero, per-line then summed).
* **Resolution at request time:** `PosService.moneyContext(storeId)` = the store's `baseCurrency` + settings version → `{currency, exp, taxRate}`. `docMoney(doc)` uses a document's own snapshot, else falls back to the store's current currency.
* **Snapshots stored today:** `Sale.currency/currencyExponent` ✔, `SaleRefund.currency/currencyExponent` (embedded) ✔, `RegisterSession.currency/currencyExponent` ✔, `posrefunds`/`pospayments` ✔ (G1a). **Held sale** = a `Sale` (snapshot written at creation; **overwritten with the then-current context when the held sale is completed**, which is correct because totals are re-priced then). **Gap:** rows from before Phase 5B have `null` → the backfill will infer from the store's `baseCurrency` and flag `currencyInferred: true`.
* **App:** `Money.exponentFor(code)` / `Money.exponent` from the loaded settings; `Money.toMinor/fromMinor` mirror the server.
* ⚠ **Inconsistency to settle before the PKR flip:** the **storefront** treats **PKR as 0 decimals** (`exchange-rate.service.ts:172`, `market-price.util.ts:73`) while **POS uses the ISO table (PKR = 2)**. POS must keep ISO; the two must never meet in one calculation. The dev stack is USD-only, so this is **unverified for production PKR stores** — pre-flight query: `group sales by {currency, currencyExponent}` and confirm every PKR sale carries exponent 2.

## 3. Storage: how integers are stored and serialised (proved)
Test on a throw-away database on the dev mongod:

| Value | Mongoose `Number` | Mongoose `BigInt` | |
|---|---|---|---|
| 1999 | **int32** | long | |
| 2 147 483 647 | int32 | long | |
| 2 147 483 648 and up (a busy day's PKR total in paisa) | **double** ✗ | long | |
| 9 007 199 254 740 991 (2^53−1) | **double** ✗ | long | |

* **Plain `Number` is not acceptable:** above 2^31 MongoDB silently stores a **double**. So money must be written as **BSON `long` (int64)**.
* **`BigInt` stores `long` correctly but cannot be serialised:** `JSON.stringify` throws (`Do not know how to serialize a BigInt`), which would 500 every API response and every `.lean()` result.
* **Design (prototype-proved on the read/serialise side):** a small custom Mongoose SchemaType `MinorMoney` that **writes a 64-bit `Long`**, **reads back a plain JS integer** (the driver's `promoteLongs` turns `long ≤ 2^53−1` into a JS number, in `lean()` and in documents), serialises to JSON as a **plain number**, and **rejects** floats, strings, `NaN`, `Infinity` and `|x| > Number.MAX_SAFE_INTEGER` (2^53−1 = 9 007 199 254 740 991 minor units, i.e. 9×10^13 USD — far beyond any till). Prototype results: stored types `long, long, long`; reads `1999, 9007199254740991, −250` exactly; JSON `[1999,9007199254740991,−250]`; rejected: `19.99`, `'12.5'`, `NaN`, `2^53`, `Infinity`.
* **No precision loss, by construction:** every value that can be stored is a safe integer, exact in a JS number and in a Dart `int`; aggregation sums of longs stay long in MongoDB (`$sum` of long → long; overflow would need > 9×10^18). The write side (Mongoose value → `Long`) is **not yet built** — the prototype wrote `Long`s with the driver — and gets its own test in step a.
* JSON on the wire: integers only, never strings; the app parses them as `int`.

## 4. Conversion: one shared function, proved equal to the existing calculation
* **Plan:** move `toMinor` / `fromMinor` / `roundMoney` (unchanged bodies) to `src/common/money-minor.util.ts`; `pos-money.util.ts` re-exports them so no import changes. Add `assertSafeMinor(n)`. **No new maths.**
* **Parity run (read-only, dev DB) — `pos-money.util` engine vs the stored data:**

| Check | Result |
|---|---|
| Sales scanned | **76** (all exponent 2) |
| Money values checked "is exactly on the minor-unit grid" (sale totals, item prices/line totals, payment amount/tendered, refund and refund-tender amounts) | **913 values, 0 off-grid** |
| `computeTotals(...)` recomputation vs stored `subtotal / discount / tax / total`, in minor units | **0 differences** |
| Σ payments = total; Σ refunds = `refundedAmount` | **0 differences** |
| Shifts scanned / values on the grid | 69 shifts / 619 values / **1 off-grid** — float drift in `cardSales` (see §1), which rounds to the right cent |
| Existing `pos-money.util.spec` + the 22 G1a integration tests | pass |
| Randomised fixtures, 200 000 trials × exponents 0, 2, 3: `toMinor(price × qty)` vs `toMinor(price) × qty` for prices **on the currency grid** | **0 differences** in 600 000 |
| Same, prices with **sub-minor fractions** (e.g. 0.125) | **differ in ~89 %** → this is §6's rule |

* **Differences reported:** none between the engine and stored values; the only non-conformity is the one float-drift counter. Step a adds this parity as a permanent test (the seeded-sales golden set + the randomised fixtures) so any change to the maths fails CI.
* Production: the same parity script (read-only) runs against a restored copy before step c.

## 5. Rollout order
**a) Nullable minor fields + dual-write on every create/update path, inside the G1a transactions**
* Paths: `createSale` (sale, items, payments, `pospayments` rows, offline replay), `completeSale`, `editHeldSaleItems`, `refundSale` (sale `$inc`, `posrefunds`, session `$inc`), `voidSale` (session `$inc`), `_incrementSessionTotals`, `cashInOut`, `openSession`, `closeSession` (counted, expected, variance, card reconciliation), `forceCloseSession`, register create/update (`defaultFloatCash`), and the G1a backfill script.
* **The minor values are the primary result:** `computeTotals` already computes `subtotal/discount/tax/total` in integer minor units and derives the major figures with `fromMinor`. Dual-write stores both from that one calculation — they cannot disagree. Counters `$inc` the minor delta **and** the major delta (`fromMinor(delta)`).
* **Open shifts at deploy time** have no minor counters; an `$inc` on a missing field would start from 0 and be wrong. Counters are therefore initialised atomically in the same update from the existing major value (aggregation-pipeline update: `$set: { cashSalesMinor: { $ifNull: ['$cashSalesMinor', {$round: [{$multiply: ['$cashSales', 10^exp]}, 0]}] } }` then `$inc`), so a half-way shift is correct from its first post-deploy sale.
* Tests: every path writes both; integer-only; parity golden set; the write-side `MinorMoney` type.

**b) Consistency checker on every write:** after each dual-write, `toMinor(major, exp) === minor` (and `minor === round(major × 10^exp)`). **Never fails or delays the sale** (runs after commit, best effort): on mismatch → structured error log, an audit event `money_minor_mismatch` (store, collection, id, field, major, minor), and a counter exposed on the existing health surface. A nightly sweep compares per-store/day sums (major vs minor ÷ 10^exp) and reports.

**c) Backfill existing rows** (extends the G1a script pattern):
* **Dry run:** counts per collection, rows needing minor, rows with null currency/exponent (inferred), **off-grid values** (list with the delta), rows that would be skipped. Writes nothing.
* **Real run:** fills only rows whose minor field is absent (`$exists: false` guard) — **idempotent**, never overwrites a live dual-written value; **resumable** (cursor by `_id`, checkpoint document per collection, batch size 500); **reversible** (`down` unsets minor fields only where the row carries `minorBackfilledAt`, leaving live-written ones alone); per-row exponent from the row's snapshot, else store `baseCurrency` + `currencyInferred: true`; off-grid float noise (< 1e-9) rounds silently, a genuine off-grid value is rounded with the delta recorded in the report.
* **Refuses** any database whose name lacks `dev`/`test` unless `--production` **and** `--i-have-a-backup` are both given.
* Open shifts use the atomic pipeline from step a (not a read-modify-write), so a sale landing mid-backfill cannot be lost.

**d) API:** `...Minor` fields **alongside** the existing ones in responses (sales list/detail, session report, daily/range/register/employee reports, refund and close results, quote). Requests accept optional `...Minor` twins. Old builds ignore the new fields.

**e) App:** models read `xMinor` when present, else `round(x × 10^exp)`. **New offline sales include the minor fields**; queued payloads already in the field (major only) stay valid. The server recomputes everything; client values are a cross-check — if a payload carries both and they disagree, `400 MONEY_FIELD_MISMATCH` (definite rejection → Needs attention, never silently "fixed").

**f) Flip reads to minor:** **only after your approval**, after a **burn-in with zero checker mismatches** (proposal: ≥ 14 days and the nightly sweep clean), behind a flag (`POS_MINOR_READS`) that can be switched back instantly. Major keeps being written until a later clean-up phase.

## 6. Variant prices stay major — where the conversion happens
* Variant `price / compareAtPrice / costPrice` stay decimals (shared with the storefront and Markets).
* **The single point where a variant price becomes minor at sale time:** `computeTotals` in `pos-money.util.ts` → `lineM = toMinor(l.price × l.qty, exp)`. (`l.price` is the variant's current price, or the till's `unitPrice` for an offline replay that the server verified against `variantpricehistory`.) Nothing else converts a variant price.
* **Rule:** `lineTotalMinor = toMinor(price × qty)` stays **authoritative** (unchanged behaviour). `priceMinor = toMinor(price)` is stored as an informational snapshot. `priceMinor × qty` equals `lineTotalMinor` **whenever the price is on the currency grid** (0 differences in 600 000 trials) and can differ only for a price with sub-minor decimals (e.g. 0.125 at 2 dp).
* **Proof that the parity test covers it:** the step-a parity test calls this exact function for (i) every seeded sale's lines and (ii) the randomised fixtures including **sub-minor prices**, asserting `lineTotalMinor` equals today's value. Dev variants: 4 variants, 0 off-grid price/compareAt/cost. **Pre-flight for production (read-only):** count variants whose price/compareAt/cost are not on the currency grid; if any exist they keep today's behaviour (the rule above), and the count is reported before step a ships.

## 7. Rule for every module from G2 on
Minor-only money fields (64-bit integers) + `currency` / `currencyExponent` snapshot on the parent — written up in `ENGINEERING_RULES.md` §2 (expenses, payables, credit ledger, the payment layer, loyalty, price books, supplier payments). The `MinorMoney` type from step a is the mandated way to declare such a field.

## 8. Risks, effort and rollback
| Step | Effort | Main risk | Mitigation | Rollback |
|---|---|---|---|---|
| a Dual-write | M (≈ 4 d) | a write path missed; a counter `$inc` starting from 0 on a pre-existing shift | path list above + grep audit; atomic pipeline init; checker (b) catches both | redeploy the previous API — extra fields are ignored, reads were never switched |
| b Checker | S (≈ 2 d) | log/audit flood on a systemic bug | sampling + one audit event per (collection, field) per hour; never throws | disable the flag |
| c Backfill | M (≈ 3 d + run) | load on production Mongo; a wrong exponent guess on pre-5B rows | batches of 500 with a pause; dry run first on a restored copy (timed); inferred rows flagged | `down` (unsets only `minorBackfilledAt` rows) |
| d API | S–M (≈ 3 d) | payload growth (small); a client choking on new fields (none known) | additive only; contract tests with old payload fixtures | redeploy |
| e App | M–L (≈ 1.5 wk incl. tests) | old builds in the field; mixed offline queues | fall back to major when minor absent; server cross-check; both payload shapes in tests | ship the previous build; server tolerates both |
| f Flip | S (≈ 2 d) + 14 d burn-in | a reporting difference nobody noticed | nightly aggregate parity; instant flag back | flip the flag |
**Total ≈ 4–5 weeks calendar** including the burn-in; ≈ 2.5 weeks of build.

**Production backfill plan (formulas — volumes unknown):**
* **When:** step a deployed and stable ≥ 1 week first (so every new row already has minor fields); the backfill runs **after store closing hours** (PKR retail: late night local time), announced, online, no downtime.
* **How long:** throughput on the dev mongod was not measured; plan on a conservative **~1 000 documents/s** with 500-row batches and a 50 ms pause → `sales × 1 + shifts × 1 + posrefunds + pospayments` documents; e.g. **1 million sales ≈ 17 minutes**, 10 million ≈ 3 hours. A timed rehearsal on a restored production copy in staging gives the real number before the run.
* **Order:** closed shifts → sales (all statuses) → posrefunds/pospayments → open shifts (atomic pipeline) → stores' `registers[].defaultFloatCash`.
* **Sales made during the backfill:** already dual-written (step a is live), so the backfill only ever fills rows whose minor field is absent; the guarded update makes a race a no-op. Open shifts are handled by the atomic pipeline.
* **Verify:** per-store/per-day sums major vs minor, off-grid report, the checker's mismatch counter at zero; take a `mongodump` first.

## Open questions for you
1. Confirm POS stores use the **ISO exponent (PKR = 2)** — and that the storefront's "PKR = 0 decimals" never feeds a POS calculation.
2. Approve the **`MinorMoney` custom Mongoose type** (no new package) as the standard declaration for minor-unit fields.
3. Approve the flip criteria (≥ 14 days clean + flag) or give yours.
4. Can I be given a read-only copy of production (or run the read-only pre-flight queries) for: the currency/exponent distribution, the count of pre-5B rows, variants off the currency grid, and document counts for the backfill estimate?
5. Payments (G2) are unaffected: `amountMinor` on the payment and event records works unchanged for a per-store merchant or an aggregator with sub-merchants.
