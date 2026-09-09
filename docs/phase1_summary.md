# Phase 1 — Core POS / Checkout Screen — Completion Summary

Implements the Phase 1 plan (`~/.claude/plans/rosy-squishing-mccarthy.md`) against the gaps flagged in `phase0_audit_report.md`. All changes are mobile-only (`pos/`); the NestJS backend was read-only for reference (`create-sale.dto.ts`, `sales.schema.ts`) to confirm what the client can safely build against.

## What changed

**Currency** — replaced hardcoded `$` with the store's `PosSettingsModel.currencySymbol` throughout checkout, cart, held sales, products, sales history, and receipts (`PosHomeController`, `PosProductsController`, `PosOrdersController`, `PosSaleDetailController`, `PosHeldSalesController`).

**Cart pricing** — added a %/$ discount-type toggle (percent converts to a flat amount before submit, since the backend's `discount` field is flat-only); clamped discount/tax/total so a discount can never exceed the subtotal or drive totals negative.

**Payments** — added cash-tendered input with live change-due display and an under-tendered guard on the Charge button (client-side only — the sale schema has no tendered/change field); relabeled "Other" to "Bank / Other" with an optional reference field folded into the sale's `notes`.

**Receipts** — added PDF generation (`pdf` package, `ReceiptPdfBuilder`) using the store's receipt header/footer/business name and resolved currency, shared via the existing `share_plus` flow, alongside (not replacing) the existing plain-text share.

**Product search/pagination** — Quick Sale grid and Products tab now page through the catalog via the repository's existing cursor pagination instead of a hardcoded 200-item fetch; local search also matches variant barcodes.

**HID barcode scanning** — new `HidScanDetector` (timing-heuristic fast-keystroke-burst + Enter detection via `HardwareKeyboard`), armed only on the Quick Sale screen with no field focused and no sheet/dialog open, so it doesn't interfere with typing or double-fire against the existing manual-entry/camera flows.

**Held-sale resume** — fixed the silent-drop bug: a line item whose product isn't in the currently-loaded catalog page now falls back to a synthetic product built from the sale item's own snapshot (name/sku/price/image), instead of being dropped.

**Register close** — `showCloseShiftDialog` now fetches a live cash-flow breakdown (`getSessionReport`) before the dialog opens, shows opening/cash-sales/cash-in/cash-out/expected, and live-computes the variance as the cashier types the counted amount; a post-close summary dialog shows the final variance before returning to PIN login. Invalid/blank cash inputs are now rejected instead of silently coerced to `$0.00` (open and close).

**Cash in/out** — new "Cash Management" dialog in Settings wired to the already-existing (previously unreachable) `cashAdjustment` endpoint.

**Multi-register correctness** — PIN login now warns instead of silently resuming when an employee's open session is on a different register than the one they picked; the previously-dead `getActiveSession` race check now guards the "open a new register" path; Shift History defaults to the current register only (toggle to see all).

**Sales history filters** — payment/status filters are now sent to the server instead of applied only over whatever page happened to be loaded; added a date-range picker (the field already existed, unused); stat cards relabeled "(loaded)" since there's no filtered-aggregate endpoint to total against.

**Range Report export bug** — the export button used to always export "today" regardless of the selected range (backend only supports single-date export). Moved the export action to Daily Report, where it matches what's on screen; removed the misleading action from Range Report.

**Auth middleware race** — `PosAccessMiddleware` now checks a synchronous in-memory cache (warmed at boot, kept in sync on every token/role/session write) instead of awaiting SharedPreferences, closing the flash-of-protected-content window.

## Explicitly deferred (backend gaps, not built client-side)

- True split/partial-tender payment — needs a `payments: [{method, amount}]` array on `CreateSaleDto`/`Sale` schema.
- Item-level discounts — needs a per-line discount field on `SaleItemDto`/`SaleItem`.
- Ranged CSV export — needs a `/pos/reports/range/export` endpoint.
- Money-as-integer-minor-units — data-model decision flagged in Phase 0, not touched here.

## Testing

- `pos/test/pos_cart_math_test.dart` — subtotal, flat/percent discount clamping, tax, total, change-due/under-tender guard.
- `pos/test/pos_held_sale_resume_test.dart` — live-match and synthetic-fallback resume paths, mixed cart.
- `pos/test/pos_session_reconciliation_test.dart` — expected-cash math, variance/shortfall sign logic, rounding tolerance.
- `flutter analyze`: clean (2 pre-existing info-level lints, unrelated to this work).
- `flutter test`: all 24 tests pass (22 new + 2 pre-existing).
- Manual: launched on iOS Simulator (iPhone 17 Pro Max) — app boots cleanly, no crashes, resumed a cached session and rendered the (unrelated, pre-existing) seller-onboarding screen correctly. **Not verified**: the actual POS checkout/register/cash-management screens interactively, since that requires a live seller/store/employee login this session doesn't have credentials for. Recommend a manual pass through the flows listed in the plan's Verification section before merging.
