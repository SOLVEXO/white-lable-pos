# Solvexo POS — engineering rules (design note, no code)

Binding for every module from G2 on. They come from the roadmap's non-negotiables plus decisions taken in G1a / G1b. Where today's code differs, the gap is listed at the end of each rule.

## 1. Append-only collections and status events
**Production will get an insert-only database role on the audit, payment and refund collections** (`posauditlogs`, `pospayments`, `posrefunds`, and every audit-grade collection added later). With that role, **no document in those collections can ever be updated or deleted** — not by a bug, not by a script, not by an attacker with the API's credentials.

Consequence — **a status change is a new event, never an update**:
* Payment status (`recorded_unverified → confirmed`, or `pending → confirmed / failed / expired / cancelled` for a Raast / terminal / acquirer provider) is recorded as an **append-only event** in a separate collection (working name `pospaymentevents`): `{ paymentId, seq, fromStatus, toStatus, source ('terminal' | 'gateway' | 'raast' | 'shift_reconciliation' | 'manual'), providerRef, providerEventId, actor, storeId, registerId, sessionId, shiftId, deviceId, at, idempotencyKey }`.
* The payment row keeps the status it was **created** with and is never touched again. The **current status is derived from the latest event** (highest `seq`; none → the creation status).
* Uniqueness protects against replays: `(paymentId, providerEventId)` and `(paymentId, idempotencyKey)` unique, so a duplicated webhook or a retried request adds nothing. `seq` is assigned in the same transaction as the insert (read the last `seq` for the payment, insert `seq+1`; the unique `(paymentId, seq)` index makes two racing writers fail one of them, which retries).
* Reads that need the current status (lists, reports, shift close) use the latest event per payment (`$lookup` with a `sort + limit 1` pipeline, or a join in the report query). A convenience **read model** (a normal, updatable collection that caches "current status per payment") is allowed **only as a cache**: it must be rebuildable from the events and nothing may treat it as the source of truth.
* Refunds follow the same pattern for their own status (`provider refund pending → confirmed / failed`).
* The same applies to any other append-only record that later needs a lifecycle (expenses approval, supplier payments, credit ledger entries): lifecycle = events.
* Every event is written **in the same transaction** as the business write that caused it (G1a rule: audit and business data commit together or not at all).

**Gap today (G1a):** `makeAppendOnly(PosPaymentSchema, { allowSetFields: ['status', 'confirmationSource', 'confirmedAt'] })` lets the application `$set` those three fields. That was a placeholder for a future terminal integration and **conflicts with this rule** — it must be removed and replaced by the event collection **before** any provider (or the production role) goes live, and the payment `status` / `confirmationSource` / `confirmedAt` fields on the payment row become "creation-time" values only. Until then nothing in the code updates them.

## 2. Money is stored as integers in the smallest currency unit (G1b rule)
For **every new table / module from G2 on** (expenses, payables, customer credit ledger, loyalty, the payment layer, price books, cash movements, supplier payments, …):
1. **Minor-only money fields.** Each money amount is a **64-bit integer** in the currency's smallest unit (USD cents, PKR paisa, JPY yen, KWD fils). **No decimal "major" twin** is stored. Name it with the suffix `Minor` (`amountMinor`, `totalMinor`, `feeMinor`) so a reader can never mistake it for a decimal.
2. **Snapshot on the parent record:** `currency` (ISO 4217 code) and `currencyExponent` (decimal places of that currency **at the time of the transaction**). Child records inherit them from their parent rather than carrying their own. The snapshot is immutable — a later change of the store's currency or rounding never reinterprets old rows.
3. **No floating point anywhere in the path:** not in the database (never BSON `double` for money), not in JSON (integers only; amounts above 2^53 are rejected), not in the server or the app (Dart `int`, TypeScript `number` only while ≤ `Number.MAX_SAFE_INTEGER`, otherwise `bigint`/`NumberLong`). Rates (tax %, discount %) are the only non-integers and are applied by the shared rounding function.
4. **One conversion function** (`toMinor` / `fromMinor`, with the exponent) and one rounding rule (half away from zero, applied per line then summed — the existing `pos-money.util.ts` behaviour). Nothing else converts. The app formats from minor units with the exponent in the snapshot; it never divides by 100.
5. **API:** money fields in requests and responses are integers named `...Minor`, always accompanied by `currency` + `currencyExponent` at the parent level. The server recomputes totals and treats client-sent values only as a cross-check.
6. **Constraints in the schema:** `required`, integer validator (`Number.isSafeInteger`), non-negative where the field is not a signed delta; signed deltas (ledger entries, variances) are explicitly named `...DeltaMinor`.
7. **Tests:** every new module ships a parity test (a representative set of amounts across exponents 0, 2 and 3 round-trips exactly) and a test that a float in the request is rejected.

*Existing collections* (sales, sale items, payments, refunds, held sales, shifts, the offline payload) keep their decimal fields during G1b and gain `...Minor` twins with dual-write and a consistency checker; flipping reads to minor happens only after the owner's approval following a burn-in with zero mismatches (see the G1b plan). **Shared storefront variant prices stay in major units** until a storefront-wide decision.

## 3. Rules carried over from G1a (unchanged, for completeness)
* Every audit event is **awaited** and written in the same transaction as what it describes — no fire-and-forget.
* Every transaction record carries `storeId, registerId, sessionId, shiftId, deviceId, employeeId` — taken from the token / session / device server-side, **never from the request body**.
* Retries never duplicate: `Idempotency-Key` on every mutating route + a database unique index on the business key.
* Backward compatible API only: additive fields; old builds in the field keep working.
* Destructive actions are soft deletes with a reason, an actor, and an audit event.
* Card / other tenders are `recorded_unverified` until a provider confirms (as an **event**, rule 1); cash taken by the cashier is `confirmed`.
* Sensitive data at rest on the device (queue, cart snapshot, checkout intents, settings cache) is AES-256-GCM encrypted with the Keychain/Keystore key; the key class is first-unlock / this-device-only.
* Amounts are rendered in Manrope with tabular figures (`tnum`).
