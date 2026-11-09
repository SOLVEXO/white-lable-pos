# G3.0 — summary (credit-note backfill, cross-till cash refund, decision-free part of G3.0)

Branch `feature/jamibranch` (both repos). No PRs, no merges, no deploys, no admin UI. G1b runbook still on hold (its new step 6 is prepared, not run).

## 0. Which of the 10 G3 decisions G3.0 depends on
`G3_PLAN.md` §2 lists four parts of G3.0. Against the decisions (D1 roles/permissions, D2 customer-credit meaning, D3 loyalty at the till, D4 lots, D5 cost method, D6 approval limits, D7 team scope, D8 FBR buyer data, D9 order, D10 existing data):

| G3.0 part | Depends on | Built? |
|---|---|---|
| POS permission matrix + login response | **D1** (which roles, custom roles, a "receiver" role), **D6** (limits that need a manager PIN) | no |
| Till-facing route layer over inventory / purchase / loyalty / store-credit | every route has to say *who may call it*, so **D1**; the loyalty and store-credit facades also touch **D2/D3**; what is exposed first is **D9** | no |
| `StockMovement` extend-vs-new memo | **D4** (lots / FEFO change the movement shape), **D5** (cost on the movement) | no |
| Money-unit audit of inventory / PO / store-credit fields (report only) | none (it reads the code, changes nothing; **D10** only decides how urgent the findings are) | **yes — §3** |

So the route layer is **not decision-free** and was not built; the two items you moved into G3.0 (backfill, cross-till cash refund) and the decision-free audit were.

## 1. Credit-note backfill (series `CN-B`) — built, run on dev only
`src/scripts/pos-credit-note-backfill.ts` (+ `.lib.ts`, `.spec.ts`), same safety shape as the G1b backfill:
* **Marked:** number `CN-B000001…`, negative `seq` (cannot clash with the live per-store unique seq), `createdAt` = the original refund/void time, and `backfill { backfilledAt, originalType: refund|void, originalId, batchId, amountDeltaMinor? }`. The tax-invoice/credit-note screen shows a *"Backfilled <date> for an earlier refund <id> — issued after the fact"* line (app test).
* **Idempotent** (re-run writes 0; found by `refundId` / `{saleId, kind:'void'}` and the unique `uniq_cn_refund` index), **resumable** (chronological per store; `--max-docs` slices a run; a resumed run gets the same numbers as one run), **reversible** (`down` removes exactly the notes + the one audit event per store it wrote), **refuses non-dev databases** unless `--production` **and** `--i-have-a-backup`, does not read `.env`.
* **Nothing else changes:** no stock, no shift counters, no sales/refunds, and the live counter `creditNoteCounter` is untouched (test: the next real return after the backfill is `CN-000001`).
* **Pricing** = the live proration (`returnLineAmounts`) over the sale's own lines, in the order the refunds happened; a refund priced by the old rule is reconciled by putting the difference on the last line and listing it (`differs-from-proration`). Nothing is guessed: a refund of a missing sale, an unknown line or more units than were sold is listed and skipped.
* **Dry run → real run on a copy of the dev data → `down`:** copy = `mongodump`/`mongorestore` of `solvexo_dev` into `solvexo_dev_cnb_copy` (database hash `c2e7c916…` identical to the source).

| step on the copy | result |
|---|---|
| dry run | store `6ae9a2e2…`: refunds **15**, voids **6**, would write **21** (`CN-B000001 … CN-B000021`), legacy decimal-only amounts **4**, differs-from-proration **0**, skipped **0**; counts unchanged (`poscreditnotes 12`, `posauditlogs 877`) |
| `up` | written **21** → `poscreditnotes 33`, `posauditlogs 878` (one audit event) |
| `up` again | candidates **0**, written **0** |
| checks | 21 backfilled / 12 live notes; **0** notes whose lines ≠ total; **0** refund notes whose total ≠ the refund's amount; real counter untouched |
| `down --dry-run` | would remove 21 notes + 1 audit event, nothing removed |
| `down` | removed 21 + 1 → `poscreditnotes 12`, `posauditlogs 877` |
| **database hash after `down`** | **`c2e7c916378fd16890f61e8f696abdf3` = the hash before `up`** → byte-for-byte restored |
| non-dev name (`solvexo_production_copy`) | `Refusing to touch database …` |

The copy was dropped. Then, as approved ("run it on dev only"), `up` was run on the real **dev** database (`solvexo_dev`): **21 notes written**, second run 0. Spec: 7 tests. Production: **runbook step 6** in `G1B_RUNBOOK.md` (prepared, on hold; nothing to do if production has no pre-G2.5 refunds/voids — your decision D from the close-out).

## 2. Cross-till cash refund — built
**Rule:** a refund or void is booked on the shift whose drawer (terminal) physically paid it.
* The paying shift = the **open shift of the register the customer is standing at** (`registerId` in the request; the app sends it for refunds and, new, for voids). Its **expected cash, refund counters (`totalRefunds`), net sales and the paying tender's total (cash / card)** move. The **original sale's shift is left exactly as it stands or closed** — including its transaction count.
* A **cash** refund or void needs an open shift on the paying register (`OPEN_SHIFT_REQUIRED`, nothing booked). For tenders that need no drawer (card / other) with **no** open shift on the paying register: it falls back to the sale's own shift **only while that is still open**; a **closed shift is never touched** (the refund then carries no shift, only its ids).
* Same till and same shift: **exactly as before** (tested).
* **Credit note keeps both links:** `registerId`/`sessionId` = the refunding till/shift (as before for returns; now also for voids) and new `saleRegisterId`/`saleSessionId` = the original sale's. The refund record already carried `saleSessionId`; the void audit event now carries both.
* Cash-close arithmetic is unchanged (`opening + cashSales + cashIn − cashOut`): the paying shift's `cashSales` is net of the refund it paid, so its expected cash falls by exactly the refund; a shift that only paid refunds shows a negative cash-sales figure (net).

**Tests** (`pos.g30.integration.spec.ts`, real replica-set Mongo, 8): sale on register 1 refunded in **cash** on register 2 → register 2's expected cash reduced (20 − 10), register 1's counters unchanged and **both shift-close reports correct** (till 2 expected 10, diff 0; till 1 expected 60, diff 0; credit note/refund link both shifts); original shift **already closed** → unchanged, open paying shift takes it; unknown/closed paying till → `OPEN_SHIFT_REQUIRED`, nothing booked; **card refund across tills** follows the same rule (till 2 card −10 and slip −10 → *matched*; till 1 card +10 matched); no open shift on the paying till → open sale shift only, closed shift untouched; same-shift legacy; **void** across tills and legacy void. Existing suites updated where they assumed the old attribution (none needed beyond g27's assertions, which still pass): `src/pos` + `src/scripts` all green locally (466 passed, 1 skipped).

**Dev data — closed shifts affected (report only, nothing rewritten):** of 123 closed shifts, **1** was changed after it closed by a refund: refund `6af15f28f83028c300714fbd` (sale `POS-00132`, 5.50) booked on closed shift `6af15f20f5e16038bb2ac9ee` (closed 2026-11-09 05:50:31) while the refund was paid at shift `6af15f28f83028c300714f61` (05:50:32) — that is the cross-till return of this week's G2.7 end-to-end test. No void was applied to a closed shift after its close. Before this change any such refund also left the closed shift's stored `expectedCash`/variance **stale** (counters moved, close figures did not); that can no longer happen. Production would need the same query (in the summary above: refunds whose `sessionId` ≠ the sale's session, or created after the sale shift's `closedAt`).

## 3. Money-unit audit (decision-free part of G3.0) — report only, nothing changed
What the modules G3 will expose hold today (read from the schemas/services):

| Module / field | Stored as | Currency / exponent kept? | Risk for G3 |
|---|---|---|---|
| `PurchaseOrder`: lines `unitCost`, `subtotal`, `shippingCost`, `taxCost`, `total` | float, **major units**, no minor twin | `currency` yes, **no exponent snapshot** | JPY/KWD stores: sums use 2-decimal rounding; needs `*Minor` twins before receive/payables |
| `SupplierReturn`: `unitCost`, `totalCredit` | float major | no | same |
| `StockLot.costPrice` ("immutable once received") | float major | store currency implied | cost snapshots on sale lines (profit) should be minor |
| `ProductVariant.costPrice` | float major | store currency implied | cost method decision (D5) |
| `StoreCreditTransaction`: `amount`, `balanceAfter`, `remaining` | float major (a minor twin of the default float was added in G1b for the *store's own* decimal fields — the credit ledger is **not** among them) | `currency` yes, **no exponent** | `round()` = fixed 2 decimals and `±0.005` tolerances in `assertCovers`/`consume` → wrong for 0- and 3-decimal currencies; the store-credit tender must be integer-minor |
| `Loyalty*` | points are integers; reward money fields are floats | — | redeem-as-discount must convert through the store exponent |
| Inventory valuation (`stock × costPrice`, lots FIFO) | computed from the floats above | — | read-only reports; fine until costs are minor |

Conclusion for G3.1+: new entities are minor from day one (rule already in the plan); existing floats are **read through a converter with the store's exponent**, never rewritten; store-credit amounts need a minor ledger **before** it becomes a tender (G3.3). No schema was changed in this audit.

## 4. App changes
`voidSale` sends the till's `registerId` (like refunds); credit-note model parses `backfill`; credit-note screen shows the backfilled line; 1 new test. App `flutter analyze` clean; full suite in the final message.

## 5. Files
API: `src/pos/pos.service.ts` (shift resolution for refund/void, void register, credit-note links), `src/pos/schemas/pos-credit-note.schema.ts` (`saleRegisterId`, `saleSessionId`, `backfill`), `src/pos/pos.controller.ts` (void body type), `src/pos/pos.g30.integration.spec.ts`, `src/scripts/pos-credit-note-backfill{,.lib,.spec}.ts`. App: `pos_repository.dart`, `pos_credit_note_model.dart`, `credit_note_view.dart`, `g25_returns_documents_test.dart`. Docs: `G1B_RUNBOOK.md` (step 6), this file.

## 6. Not verified
* The backfill ran on **dev data only**; production volumes/timing are unknown (the runbook step measures them on a restored copy). Legacy refunds in production may include shapes the dev data does not (e.g. split-tender refunds before `tenders` existed) — such rows are listed and skipped, never guessed.
* Cross-till behaviour was verified with the real service on a real Mongo replica set and with the iOS simulator return of an OFF- receipt (G2.7), but not with two physical tills; the cash-drawer count itself is a manual check (G2 checklist item 6, "return at the second device").
* The seller-document orphan count is yours (read-only user) — nothing done.
