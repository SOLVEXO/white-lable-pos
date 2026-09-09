# Phase 2 — Supporting Modules — Completion Summary

Implements the Phase 2 plan (`~/.claude/plans/rosy-squishing-mccarthy.md`). Before writing any code, I read the NestJS backend source directly (read-only) to determine what's actually buildable — this changed the scope substantially from a plain reading of the Phase 0 "Missing" verdicts.

## What changed

**Inventory** — new `InventoryRepository` wired to backend routes that already existed but were never called from Flutter (`getStoreInventory`, `low-stock-summary`, `products/:id/variants`, `PATCH` variant). New `pos_inventory` module: paginated stock list with stats header (total/in-stock/low-stock/out-of-stock), a "Low Stock Only" toggle using the store's *real* configured threshold (not the client's hardcoded `≤10`), and an "Adjust Stock" flow — tap a product, pick a variant if it has more than one, set a new quantity, `PATCH`s the backend. No reason-code capture (backend has no field for it) — flagged as a gap, not faked.

**Stock Activity** — new `pos_stock_activity` screen: a store-wide, reverse-chronological feed of stock adjustments via the real (previously unused) activity-log endpoint, filtered to `action=inventory_adjusted`. This is store-wide, not per-product — the seller-facing activity-log route has no `targetId` filter (only the admin route does), so a per-product ledger isn't efficiently buildable server-side today. Documented in the repository's doc comment, not silently limited.

**Customers** — new `CustomerModel` + `CustomerRepository` against two real endpoints: a paginated list of the store's actual past buyers (with real `orderCount`/`totalSpent`/`segment`), and a global name/email/phone search used to attach a customer to a sale. Two integration points:
- **Checkout**: the existing free-text customer name field in the cart footer now has a search icon opening a picker sheet (search or browse); selecting a customer sets both the display name and a `customerId`, which is now actually sent to `createSale`/`holdSale` — previously the repository accepted `customerId` but the controller never passed it, so every sale was anonymous even when a name was typed. Editing the name afterward clears the stale id so it's never sent alongside a mismatched name. Resuming a held sale reconstructs the customer link from the sale's own snapshot, same pattern as the Phase 1 held-item fix.
- **Browse screen** (`pos_customers`, reachable from Settings): read-only list of past buyers with their order stats — deliberately not wired back into checkout, to keep "look someone up" and "attach to this sale" as separate, unconfusing flows.

**Settings** — new "STORE" section with entry points to Inventory, Stock Activity, and Customers, matching the existing tile pattern (Shift History, Cash Management, etc.).

**Products, Sales history, Returns/Refunds, Reports** — re-reviewed against the Phase 0 findings and Phase 1 fixes; nothing new is broken, no changes made here. Re-litigating would have been a redundant audit pass, not additional value.

## Explicitly deferred (backend gaps, not built)

- **Purchases/Suppliers** — confirmed via a full-codebase grep that there is zero backend support anywhere (no supplier model, no purchase-order concept, nothing to receive stock against). Nothing was built — no screen, no model, no UI implying this feature exists. This needs backend work before any client-side implementation is possible.
- **Reason-coded stock adjustments** (damaged/lost/recount) — the variant-update DTO has no reason field.
- **Per-product stock movement history** — the seller activity-log route lacks a `targetId` filter.
- **Full customer CRUD** — only list/search/tag-metadata exist server-side; not attempted (also not needed for POS, since customers should originate from real orders, not be hand-created).

## Testing

- `pos/test/inventory_models_test.dart` — `fromJson` parsing for all new inventory models against fixtures matching the real backend field names.
- `pos/test/customer_model_test.dart` — `fromJson`/`fromSearchJson` parsing for both real customer endpoint shapes.
- `pos/test/pos_customer_selection_test.dart` — customer-selection/clear-on-edit bookkeeping, and held-sale-resume customer reconstruction (with and without a `customerId`).
- `flutter analyze`: clean (same 2 pre-existing info-level lints as Phase 1, unrelated to this work).
- `flutter test`: all tests pass (39 total — 15 new).
- Manual: launched on iOS Simulator twice (once mid-session with a cached login, once fresh) — boots cleanly both times, no crashes, no red screens, correctly rendering existing screens with the new routes/modules registered. **Not verified interactively**: the actual Inventory/Stock Activity/Customers screens and the checkout customer picker with live data, since that requires a real seller/store login this session doesn't have credentials for. Recommend a manual pass — particularly the stock-adjustment PATCH call and the two customer endpoints — against a real store before shipping.
