# Phase 5B — Money correctness (D1), split tender, receipts — Summary

Gaps closed: **#4** server recompute/validation · **#5** currency + exponent snapshot, one formatter · **#6** partial-refund reconciliation, reports incl. partially-refunded, refund pro-rating · **#14** split tender · **#21** unified receipts. (See `phase5_decisions.md` §3.)

## Result

| Rule (D1) | Status |
|---|---|
| Server computes subtotal, tax, discount, total from lines + store settings; client totals ignored | ✅ `pos-money.util.ts`; client `tax` ignored; `clientTotal` beyond ±1 minor unit → `400 TOTAL_MISMATCH` (with the server's figures) |
| Discount > subtotal rejected (not clamped); % > 100 rejected | ✅ `DISCOUNT_EXCEEDS_SUBTOTAL` / `INVALID_DISCOUNT` |
| Sale / refund / session store currency code + ISO-4217 exponent | ✅ `Sale.currency/currencyExponent`, `Sale.refunds[].currency/currencyExponent`, `RegisterSession.currency/currencyExponent` |
| Exponent-based rounding everywhere, backend and app (no `toFixed(2)`) | ✅ integer minor-unit maths, half away from zero; 73 hard-coded 2-decimal / `$` sites replaced by `Money.format`; reports, CSV, receipts follow the exponent |
| No full minor-units migration; storefront/order money storage untouched | ✅ POS fields only (still `Number` in major units) |
| Partial cash refunds reduce expected cash | ✅ refund comes out of the right tender → `cashSales` → `expectedCash` (tested through close: variance 0) |
| Reports/receipts show correct currency and decimals | ✅ |
| Split tender (method, amount, reference), Σ == total, cash may exceed → change computed & stored server-side | ✅ |
| Refunds go back to tenders in a documented order | ✅ **non-cash (card/other, in entry order) first, then cash last; each capped at what it took; cash change is not refundable** |
| Session report breaks down by tender | ✅ net of refunds; partially-refunded sales included; `splitSales` count |
| Old single-payment sales stay readable/refundable | ✅ synthetic single line (`effectivePayments`) — tested with a raw pre-5B document |

## Tests

| Check | Result |
|---|---|
| `npm run build` | ✅ |
| Backend `jest --runInBand` over `src/pos`, `common/idempotency`, `draft-orders`, `inventory`, `product-variants`, `markets` | ✅ **16 suites, 260 passed** (44 skipped = the pre-existing env-gated `inventory.integration.spec.ts`) |
| New: `pos-money.util.spec.ts` (49) — pure rounding per exponent (JPY/PKR/KWD/USD), tampered totals, settlement, refund allocation, pro-rating | ✅ |
| New: `pos.money.integration.spec.ts` (**real Mongo**, 23) — per-currency end-to-end sales, ignored client tax, tampered total rejected with no stock taken, split tender with change, short/over payments rejected, held→complete split, refunds against split tender (card first, cash last), full refund, void, pro-rated discount+tax with exact remainder, JPY partial refund, **expected cash after a partial cash refund**, daily/range reports, JPY CSV, settings currency, legacy sale refund | ✅ |
| `flutter analyze` | ✅ 4 issues, all pre-existing, none new |
| `flutter test` | ✅ **210 passed** (was 174): `pos_totals_test` (25 — app totals identical to the server's fixtures, payment check, refund display), `receipt_data_test` (11) |
| **Not run:** live end-to-end against a deployed backend; any simulator/device run; `integration_test/pos_checkout_flow_test.dart` (needs a device — its stubs/tax setup were updated and it analyzes clean but was not executed); the *whole* backend suite (a full-repo `jest` hung this machine, so only the suites above were run); a real thermal printer / PDF visual check | ⚠️ please do the staging pass below |

> During this phase the real-Mongo run caught a bug `npm run build` did not: `Sale.discountType` (a union type) crashed Mongoose schema creation, i.e. the API would not have started. Fixed (`@Prop({ type: String, … })`).

## What changed

### Backend (`solvexo-api`) — commit `ccc00d5` (+ earlier 5A.1 commits)
- `src/pos/pos-money.util.ts` (new): `exponentOf` (from the existing ISO-4217 table), `roundMoney/toMinor/fromMinor`, `computeTotals`, `assertClientTotal`, `settlePayments`, `effectivePayments`, `refundOrder/allocateRefund/tenderNets`, `partialRefundAmount`.
- `pos.service.ts`: `createSale` / `completeSale` / `editHeldSaleItems` price on the server and settle payments; `refundSale` rewritten (pro-rated amount, tender allocation, `refunds[]` record, session `totalSales/cashSales/cardSales/otherSales` deltas, `totalTransactions` −1 exactly once when a sale becomes fully refunded — also fixes partial-then-full double decrement); `voidSale` reverses per-tender nets; session open/close/force-close/cash-adjustment round to the exponent; `getSessionReport`, `getDailyReport`, `getDateRangeReport`, register/employee reports, CSV and `getSales/getSaleById` are tender-aware, include `partially_refunded`, and return `currency`/`currencyExponent`; `getPosSettings` returns the store `currency` + `currencyExponent`.
- Schemas/DTOs: `Sale` (`currency, currencyExponent, discountType, discountValue, taxRate, paymentMethod+'split', payments[], changeGiven, employeeName, refunds[]`), `RegisterSession` (`currency, currencyExponent`), `PosSettings.businessTaxId`; `payment.dto.ts` (`PaymentLineDto`); `CreateSaleDto`/`CompleteSaleDto`/`UpdateSaleItemsDto` gain `discountType/discountValue`, `clientTotal`, `payments[]`, `amountTendered`, `paymentReference`.

### POS app (`pos/`)
- `utils/money.dart` (new, replaces the dead `currency_formatter.dart`), `utils/pos_totals.dart` (cart maths mirroring the server; payment check; refund display), `utils/receipt_data.dart` (+ rewritten `receipt_pdf_builder.dart`, `receipt_escpos_builder.dart`).
- Models: settings/sale/session carry currency, exponent, payments, change, refunds; `PosRepository.getPosSettings` configures `Money` from the backend and persists it for the next boot; `createSale`/`completeSale` send `discountType/Value`, `clientTotal`, `payments`.
- Cart: tax is the **store's rate from settings** (read-only label — a cashier-typed tax is gone because the server ignores it); discount > subtotal blocks Charge; split-payment UI (`pos_split_payment_section.dart`): rows of method + amount (+ card auth/bank reference), "fill remainder", live Remaining/Change/Fully-paid status.
- Receipts: one `ReceiptData` → PDF (bundled Inter font, so symbols/non-Latin render), thermal (amounts as `JPY 1,234`, text reduced to Latin-1, no crash on Arabic names) and share-text; includes address, tax id, cashier, receipt number, formatted date, unit price, **tax rate**, discount %, every tender with tendered/change/reference, refund rows, **VOID / REFUNDED / PARTIALLY REFUNDED banner**, **COPY** on reprints. Sale detail shows tenders, change and refunds in the sale's own currency; "Refund Selected" shows the server's pro-rated amount.
- Held-sale completion tells the cashier when the server re-priced it ("charged X, was Y when held").

## API contract changes other clients must know about
1. **Totals are server-authoritative.** Any client-sent `tax` is ignored; tax = store `taxRate` × (subtotal − discount). A web POS terminal that lets the cashier type a tax rate will no longer be honoured. `clientTotal` (optional) is validated; mismatch → `400 TOTAL_MISMATCH {expectedTotal, subtotal, discount, tax}`.
2. **Discount**: legacy flat `discount` still accepted; new `discountType` (`amount|percent`) + `discountValue`. A discount above the subtotal is now **rejected** (`DISCOUNT_EXCEEDS_SUBTOTAL`) instead of producing a negative total.
3. **Payments**: legacy `paymentMethod` (+ optional `amountTendered`, `paymentReference`) still works; `payments:[{method,amount,reference}]` enables split tender. Errors: `PAYMENT_SHORT`, `PAYMENT_EXCEEDS_TOTAL` (card/other can't exceed the total), `INVALID_PAYMENT_METHOD`, `INVALID_PAYMENT_AMOUNT`, `TOO_MANY_PAYMENTS` (max 8). `Sale.paymentMethod` can now be **`'split'`** — consumers that switch on `cash|card|other` must handle it (`payments[]` has the detail; `byPaymentMethod` in reports still keys `cash/card/other`).
4. **Sale documents** gain `currency`, `currencyExponent`, `payments[]`, `changeGiven`, `employeeName`, `refunds[]`, `discountType/Value`, `taxRate`; list/detail endpoints backfill currency for older sales.
5. **Report semantics**: `partially_refunded` sales are now included; `byPaymentMethod` is net of refunds; `refundsCount/Total` include partial refunds; **`netRevenue` changed** from `revenue − discount` (which double-counted the discount) to `revenue − partial refunds`; all report responses carry `currency` + `currencyExponent`. CSV: added `Currency`, `Refunded`, `Change Given` columns; amounts use the currency's own decimals; payment shows tenders (`card 60.00 + cash 40.00`).
6. **Refund responses** now include `{refundedAmount, newStatus, tenders, currency, currencyExponent}`; the partial-refund amount is **pro-rated** (share of what was paid: discount and tax included) — it was `price × qty` before.
7. `GET /pos/settings/:storeId` returns `currency` + `currencyExponent` (authoritative; the free-text `currencySymbol` is legacy and no longer used by the app); `businessTaxId` setting added.
8. Session open/close/cash-adjust amounts are rounded to the store currency's exponent.

## Deferred / decisions worth knowing
- **Refund order** (non-cash first) is a deliberate, documented choice (`refundOrder` in `pos-money.util.ts`). If you'd rather refund proportionally or in reverse entry order, it is one function.
- **Tender allocation is derived, not stored per line**, from the cumulative refunded amount — deterministic and what makes pre-split sales work; each refund event also stores its own tender breakdown in `refunds[]` for audit/receipts.
- **Money is still `double` in storage** by decision D1; every operation is minor-unit-exact and rounded at each step, but a future analytics query summing raw doubles could still show float noise — report code rounds.
- Receipt: printer **paper width, codepage, drawer kick, auto-print, iOS stance** are 5F (gap #20). Business tax id has a backend setting and prints when set; there is **no field for it in the app's Settings screen yet** (set via API/web).
- **Not changed:** order/storefront money, buyer app. `Money.exponentFor` in the app is a fallback only until the first settings load; the server's exponent always wins.
- The held-sale completion screen still has no split-tender picker (single method only); split is on the main cart.
- `integration_test` and device verification — see "Not run" above.

## Verify on staging (≈20 min)
1. A USD store with 8.25% tax: ring 3 × a 19.99 item with 10% manager discount → receipt total `58.42`; app and server agree (no `TOTAL_MISMATCH`).
2. A JPY store (and a KWD store if you have one): totals/receipts/reports show 0 / 3 decimals; CSV export likewise.
3. Split sale card 60 + cash 50 on a 100 total → change 10 stored; session shows cash 40 / card 60; receipt shows both tenders, tendered and change.
4. Partial refund of that sale → returns to the **card** first; drawer's expected cash unchanged; refund the rest → cash comes out; close the shift → variance 0.
5. Change the store tax rate on another device between building the cart and charging → "Prices or tax changed" and the figures refresh.
6. Reprint (thermal + PDF + share) a voided sale → VOID and COPY banners; a sale with an Arabic customer name prints without crashing.

## Next
Phase 5C (offline queue hardening). Stopping here for your approval.
