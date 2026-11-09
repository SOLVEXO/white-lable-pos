# G3 — Step 0 plan (no code written)

Status: **plan only, waiting for owner approval.** G3 = blueprint roadmap phase 2 (Retail operations).
Inputs: `GAP_AUDIT.md` §1.5–1.8, §1.10 (content specs), `G2_PLAN.md`, `G2_CLOSEOUT.md`, `ENGINEERING_RULES.md`, `FBR_PLAN.md`. Branch policy unchanged: everything on `feature/jamibranch`, no PRs / merges / deploys, no admin-panel code, additive API, minor units for every new money field, ask before packages, no formatting-only diffs.

## 0. What the code already has (checked in `solvexo-api/src`) — and the one thing that changes everything

| Area | Already on the server |
|---|---|
| Inventory | `inventory` module: stock lines, valuation, reorder suggestions, **lots** (`StockLot`, write-off), **adjustments with an approvals queue**, **locations + bins**, **transfers** (ship / shipping / receive / cancel), variant history, movements report, CSV import |
| Counts | `stock-counts` (start, enter per item, finish, cancel) |
| Supply | `purchase-orders`: suppliers CRUD + import, POs (draft → ordered → received / close-short / cancel), PDF, email, receive, **supplier returns** |
| Customers | `store-credit` (ledger per customer: balance, adjust), `loyalty` (program, tiers, members, rewards, vouchers, redeem), `StoreCustomer` data from the storefront |
| Cash | `cash-adjustment` on a register session (manager only, free-text reason) |
| Team | POS employees (cashier / manager enum, PIN), `RequirePermission` granular permissions exist for **web staff** (`inventory.view/adjust/approve`, `settings.locations.manage`, …) |
| **Missing** | Expense entity, payables ledger / supplier payments, daybook, attendance / clock-in, scheduled shifts, POS-side customer create, sale-time stock-movement rows (GAP_AUDIT R2), per-line cost on sales (profit), customer credit as a **tender** |

**Key finding.** Every one of those modules is guarded by `JwtAuthGuard + RolesGuard(seller|admin|staff) + PermissionsGuard` — the **web dashboard's** identity. The till authenticates with a **device token + employee PIN token** (`PosAuthGuard`, manager token for approvals). None of those routes accept a till. So G3 is mostly **POS-scoped facades over existing services**, not new business logic: each sub-phase adds `pos/…` routes that (1) use `PosAuthGuard`, (2) derive store / register / device / employee from the tokens, (3) map a *POS permission* to the existing service call, (4) take `Idempotency-Key`, (5) write the POS audit log, and (6) reuse the existing service so the dashboard and the till see the same data. This is the same pattern G2.6 used for the catalog.

## 1. Cross-cutting design (applies to every module)

* **POS permissions (decision D1).** Today a POS employee is `cashier | manager`. G3 adds many sensitive actions (adjust stock, receive PO, pay supplier, record expense, approve count variance). Proposal: a fixed **permission matrix per role** in one config file (`pos-permissions.config.ts`, single source of truth, returned to the app in the login response so the UI hides what is not allowed — the server still enforces). Roles stay `cashier | manager` (+ owner implicit); *custom roles* (blueprint "roles") are **deferred to G3.6/G4** unless you want them now. Sensitive actions keep the manager-PIN approval already used for returns and catalog edits.
* **Money.** Every new amount is `*Minor` (integer) + `currency` + `currencyExponent` snapshot; existing PO / valuation fields that are major-unit today are **read through a converter, never re-written** (G3.0 audits which are which and documents it). No float arithmetic in the app: new screens use `Money`/`MinorMoney` helpers.
* **Append-only ledgers.** Stock movements, store-credit entries, loyalty entries, supplier payments, expenses' status changes and attendance punches are **events** (`makeAppendOnly`); balances are derived (or a cached balance updated in the same transaction as the event). Corrections are *reversal events*, never edits.
* **Audit.** Every write → `writeAuditLog` awaited, with actor employee, device, register, before/after for edits, reason code where a reason is required (same reason-code mechanism as G2.4).
* **Idempotency.** `Idempotency-Key` on every POS write; the app reuses keys on retry (existing `IdempotencyIntentStore`).
* **Offline model (rule for the whole phase).** Reads: cached snapshots (customers, stock, suppliers, open POs) so screens open offline, clearly marked *"as of <time>"*. Writes: **only those that are safe to replay** go through the offline queue — clock in/out, cash in/out and expenses (the amount is whatever the person says; replay is idempotent), customer create (phone is unique key → merge on conflict), count entries. Everything that **moves value or depends on live balances** is **online-only** with an honest "Needs internet" state: store-credit / loyalty redemption, supplier payments, PO receive, transfers, stock adjustments above the approval limit. Sales keep today's offline behaviour; **earning** loyalty/credit points on an offline sale is computed by the server **when the sale syncs**.
* **FBR feed.** What these modules must hold so the later FBR integration (`FBR_PLAN.md`) has the data without rework: **HS code + unit of measure** on every sellable (G2.6 added HS code; UoM added in G3.1 on the variant), **buyer identity** on the customer (name, NTN/CNIC, address, registration type — the PRAL data model lists these buyer fields; **which are mandatory for which sales must be confirmed from the owner's documents**), **supplier NTN/STRN + purchase tax** on POs (input tax; whether FBR needs purchase data at all is **unconfirmed — I will only store it, not send it**), credit notes from store-credit refunds still go through the G2.5 credit-note path (so a refund to store credit is a credit note with tender `store_credit`), and everything dated with the device time + server time (offline rule 150XC). No FBR upload is built in G3.
* **Tests (every sub-phase).** Real-Mongo integration (races, idempotency, rollback, permission matrix), widget tests per screen (phone + tablet, light + dark), simulator integration on the dev stack, backend gate + `npm run build` + `test:di`, `flutter analyze`, full `flutter test`, CI green. Each sub-phase ends with a summary doc, a push and a STOP.

## 2. Modules

### 2.1 Inventory

**Backend (mostly facades + three real gaps).**
* Facade routes `pos/inventory/…` over `InventoryService`: overview (counts + valuation), stock list (per location), stock detail (locations, lots, history), low-stock + reorder suggestions, adjust (exists via catalog stock edit in G2.6 — unify), lots list + write-off, locations/bins read, transfers (create-ship / list / detail / receive / cancel), movement history.
* **Real gap 1 — sale movements (GAP_AUDIT R2):** a sale must write a `sale` stock-movement row (and a `return` row for restocked returns) **inside the sale transaction**, so history, counts and valuation reconcile. This is a change to the hot path of `createSale` → own risk section below. Backfill is **not** attempted (history before the change is flagged "before ledger").
* **Real gap 2 — lot-aware sale:** lots exist but a sale decrements the variant total only. Proposal: **FEFO allocation on the server** (earliest expiry first) when a variant has lots, no UI lot picking at the till; expired lots are not sellable (setting). Variants without lots behave exactly as today.
* **Real gap 3 — count variance posting:** `stock-counts.finish` produces variances; posting them as adjustments needs approval above a threshold (reuse the approvals queue) and writes movement rows.
* Entities: reuse `StockAdjustment`, `StockLot`, `StockTransfer`, `Bin`, `VariantLocationStock`; add `StockMovement` (append-only: `type sale|return|adjustment|count|transfer_out|transfer_in|receive|write_off|void`, `qtyDelta`, `lotId`, `locationId`, `refType/refId`, `employeeId`, `at`) if the existing adjustment rows cannot carry sale/return types (to be confirmed by reading `stock-adjustment.schema.ts` at the start of G3.1 — the decision is "extend vs new").
* Audit: every adjust / count post / transfer step / write-off.

**App screens (GAP_AUDIT §1.5):** inventory-overview, stock-list (location filter), stock-detail, adjustment (exists as a sheet — restyle), low-stock (with "create PO draft" hand-off to G3.4), stock-count + **stock-count-scan** (reuse the barcode scanner and the camera-denied fallback from G2.7), variance review, transfer + transfer-detail, batch-expiry (buckets: expired / ≤7 d / ≤30 d, write-off), inventory-history (ledger with filters).
**Offline:** reads cached; **count entry offline** (queued per count session, replayed in order; session finish is online); adjustments / transfers / write-offs online-only.
**Permissions:** cashier — view stock only; manager — adjust (reason required), count, transfer, write-off (manager PIN above a configurable quantity/value), approve variances.

### 2.2 Customers

**Backend.**
* `pos/customers` facade: search (phone is the primary key in PK retail), create / edit (name, phone, email, address, tax ID/NTN/CNIC, group, consent flag, notes), profile (lifetime spend, order history from `sales`, loyalty tier/points, credit balance). Unique `(storeId, phone)`; create is idempotent (same phone → returns the existing customer).
* **Customer credit ledger** (decision D2): reuse `store-credit` (signed entries, balance, expiry) and add what POS needs: `credit_sale` (customer owes — "pay on account", optional `creditLimitMinor`), `payment_received`, `refund_to_credit`, `adjustment`. Whether "customer owes us" (receivable) and "store owes customer" (credit balance) share one ledger or two is **a decision** (§4 D2) — they have opposite accounting meaning.
* **Store credit as a tender:** `POST pos/sales` payment line `{method:'store_credit', customerId, amountMinor}` — server checks balance **inside the sale transaction**, writes the ledger entry linked to the sale; insufficient → 409; offline sales **cannot** use it (balance unknown). **As a refund method (G2.5 deferral):** return flow offers "to store credit" → credit-note tender `store_credit` + ledger credit in the same transaction.
* **Loyalty:** earn on completed sale (server-side, from `loyalty` rules, `earnedPoints` stored on the sale, reversed proportionally on return), redeem as a discount line/tender through the existing `redeem` service; tier shown at the till when a customer is attached.
* Audit: customer create/edit (before/after), credit adjustments (reason), redemption.

**App screens:** customers (list + search + segments), customer-profile, add-customer / edit (also **inline from the sale's customer picker**), loyalty (balance, tier, redeem), customer-credit (ledger with running balance, take payment, limit), payment sheet gains **Store credit** tender; Return flow gains **Refund to store credit**.
**Offline:** customer list/search from a cached directory; **create customer queued** (merge by phone on replay); credit/loyalty redemption and credit refunds **online-only**; points earned on offline sales appear after sync.
**Permissions:** cashier — search, attach, add customer, view balance; manager — edit tax ID/limits, adjust credit, take on-account payments, see full history.

### 2.3 Supply

**Backend.** Facades over `purchase-orders`: suppliers (list with **payable balance**, profile, create/edit), POs (list by status, detail, create/edit draft, mark ordered, cancel, close-short), **receive stock** (per-line received / damaged qty, lot + expiry, **partial receipts** → PO `partial`, idempotent per receipt, writes stock movements + lots in one transaction, optional landed-cost update).
* **Real gap — payables:** new append-only `supplier_ledger` (`invoice/receipt_value`, `payment`, `credit_note`, `adjustment`; `amountMinor`, `poId`, `method`, `reference`, `paidFrom till|bank|owner`) with derived balance; **supplier payment** `POST pos/suppliers/:id/payments` (idempotent; a till-paid supplier payment is a **cash movement** that lowers expected cash and appears in the daybook — see 2.4). Receive creates the payable (value of goods received, tax shown separately).
* Costs: receive updates `costMinor` on the variant (method: **last cost** now, weighted-average is a decision D5) and snapshots cost on sale lines **from G3.1 on** (feeds the profit report later).
* Audit: PO state changes, receives, payments.

**App screens (GAP_AUDIT §1.7):** suppliers, supplier-profile (terms, products supplied, PO history, payable), purchase-orders, purchase-order-detail, new-purchase-order (scan/search lines, expected date), **receive-stock** (scan to receive, partial), supplier-payment.
**Offline:** reads cached; drafting a PO offline is *allowed locally and queued*; **receive and payments online-only**.
**Permissions:** cashier — none (or receive-only if you want a "receiver" role, D1); manager — everything; payments above a limit need the owner (manager PIN + owner token).

### 2.4 Cash

**Backend.**
* `Expense` entity (append-only status events `recorded → approved|rejected → (reversed)`; `amountMinor`, `categoryId`, `paidFrom: till|bank|owner`, `registerSessionId` when from the till, `receiptImage` (private upload, same helpers as KYB), `note`, `date`). **A till expense lowers expected cash of the open shift** (same counters the shift-close variance uses).
* Cash in / out: replace free-text with **reason categories** (`float_topup`, `bank_deposit`, `safe_drop`, `petty`, `supplier_payment`, `owner_draw`, `other`), optional receipt photo, optional link to an expense. Existing `cash-adjustment` stays and is mapped onto the categories (old rows readable).
* **Daybook** (read model): one chronological ledger per day and per store/register: opening cash, sales by tender, refunds / voids (with credit-note numbers), cash in/out, expenses, supplier payments, closing cash vs counted — **every line links to its source document**; totals reconcile to the shift reports (a test asserts daybook totals = Σ shift reports for the day). Generated from existing tables + the new ledgers; no second source of truth.
* **Fix carried from G2.7 (G2_CLOSEOUT §6.6):** session counters attribute a cross-till cash refund to the original sale's session; the daybook needs refunds attributed to the **paying** shift → counters get an explicit `paidFromSessionId` on refunds (additive).
* Audit: every expense/movement, approvals, photo views.

**App screens:** expenses (period filter, category totals), add-expense, expense-detail (approval + audit trail), cash-movement (categories, photo), daybook (day picker, sections, drill-down to documents), open-shift gets the previous-close variance + denomination counter (G2 deferral).
**Offline:** **expenses and cash in/out are queued** (replay-safe, idempotent keys); approvals and daybook reads need the server (daybook shows cached last day + "as of").
**Permissions:** cashier — cash in/out within a limit, add expense draft; manager — approve, categories, daybook, all periods.

### 2.5 Team

**Backend.**
* **Attendance / clock-in** (distinct from register shifts — D6 in GAP_AUDIT): append-only `attendance_events` (`clock_in|break_start|break_end|clock_out`, `employeeId`, `deviceId`, `registerId`, client time + server time, `source till|manager_edit`, `reason` for manager edits). Replay-safe (client event id unique) so punches made offline are accepted with their real device time; a clock-in more than N hours in the past is flagged for manager review (same idea as the offline-sale age limit).
* **Scheduled shifts** (`work_shifts`: employee, date, start/end, register/location, status) — simple roster; attendance compares against it (late / early / missing). Not payroll: **no wages, no payroll export** unless you want it (D7).
* Roles: permission matrix (D1); staff list / profile exist (owner gate) → get last login, sales stats (existing report by employee).
* Audit: every punch edit.

**App screens:** clock-in (big button, today's punches, break), attendance (history per employee, manager sees everyone), shifts (week roster, manager edit; cashier sees own), staff-profile additions, roles (read-only matrix first).
**Offline:** punches **queued** and replayed; roster read cached; roster edits online.
**Permissions:** cashier — own punches/roster; manager — everyone, edits with reason.

## 3. Sub-phases, dependencies, sizes, risks
Sizes as in G2 (S ≈ 2–3 days, M ≈ 1 week, L ≈ 2 weeks, one engineer incl. tests).

| # | Sub-phase | Contents | Size | Depends on | Server-before-app |
|---|---|---|---|---|---|
| **G3.0** | Foundation | POS permission matrix + login response; facade pattern + shared test harness; money-unit audit of inventory / PO / store-credit fields (report); `StockMovement` decision (extend vs new) | M | — | yes |
| **G3.1** | Inventory core | sale/return stock movements in the sale transaction; overview, list, detail, low stock, history; adjustments unified; **stock count + count-by-scan** + variance posting; UoM on variant | L | G3.0 | yes |
| **G3.2** | Inventory advanced | transfers (create/ship/receive/cancel), **batches & expiry** + FEFO at sale, write-off | M–L | G3.1 | yes |
| **G3.3** | Customers & credit | POS customers (add/edit/profile/search), loyalty earn/redeem, customer credit ledger, **store credit tender + refund method**, buyer identity fields | L | G3.0 (parallel with G3.2) | yes |
| **G3.4** | Supply | suppliers, POs, **receive incl. partial**, payables ledger, supplier payments, cost update + cost snapshot on sale lines | L | G3.1 (movements, lots from G3.2 for lot/expiry on receive) | yes |
| **G3.5** | Cash & daybook | expenses, cash in/out categories, **daybook**, previous-close variance + denominations, paying-shift attribution fix | M | G3.4 (supplier payments appear in the daybook) | yes |
| **G3.6** | Team | attendance / clock-in, roster, staff profile additions, roles matrix screen | M | G3.0 (independent otherwise) | yes |

Order: **G3.0 → G3.1 → (G3.2 ∥ G3.3) → G3.4 → G3.5 → G3.6** (G3.6 can move earlier if you want attendance sooner; nothing depends on it).

**Risks**
1. *Sale hot path (G3.1):* writing movement rows and FEFO lot allocation inside `createSale` can slow or break the most critical transaction. Mitigation: same transaction, indexed append-only inserts, race tests (8 concurrent sales on the last unit — pattern from G2.5), a metric on sale latency, and a **server flag** to switch lot allocation off without a deploy.
2. *Two sources of stock truth* (variant total vs per-location vs lots) — a reconcile job/report in G3.1 that lists drift; no automatic "fixing".
3. *Store credit and loyalty are money-like:* double-spend across tills → balance check + ledger write in the sale transaction, unique ledger key per (sale, entry), concurrency test.
4. *Legacy major-unit fields* in PO/valuation → converter + tests per field; never mix units in one calculation.
5. *Permission matrix drift* between app and server → server is the only enforcer; the app only hides.
6. *Scope creep (accounting):* payables ≠ accounting; no chart of accounts, no tax filings, no payroll — explicitly out.
7. *Offline conflicts* for queued customers/expenses/punches → idempotent keys + merge rules written per entity (documented in each summary doc).
8. *Real-device verification* for scan-count and receive-by-scan (camera) — same checklist approach as G2.

## 4. Decisions I need from you
1. **D1 Permissions:** keep `cashier | manager` with a fixed matrix (recommended for G3), or build custom roles now? Do you want a "stock receiver" role that can receive POs but not adjust stock?
2. **D2 Customer credit meaning:** (a) *store credit only* — the store owes the customer (refund to credit, gift-like balance) **or** (b) also *pay on account* — the customer owes the store (receivable with credit limit). (b) doubles the accounting surface; recommend (a) in G3.3 and (b) later.
3. **D3 Loyalty at the till:** earn only, or earn + redeem as discount in G3.3? Which of the existing loyalty tiers/rules are live for POS stores?
4. **D4 Lots:** FEFO automatic at sale (recommended, server-side) vs. manual lot pick; may expired stock be sold at all (default: blocked)?
5. **D5 Cost method:** last cost (simple, recommended) or weighted average for the cost snapshot used by profit reports?
6. **D6 Approval limits:** the money / quantity thresholds that need a manager PIN (stock adjust, write-off, cash out, expense, supplier payment) — or a store setting with sane defaults I propose?
7. **D7 Team scope:** attendance + roster only, or also wages / payroll export? (Recommended: attendance + roster only.)
8. **D8 FBR buyer data:** which sales need buyer NTN/CNIC (value threshold, registered vs unregistered buyers)? I need the owner's FBR documents listed in `FBR_PLAN.md` before I make buyer fields mandatory anywhere.
9. **D9 Order:** confirm G3.0 → G3.1 first (no UI risk, unblocks everything), and whether customers (G3.3) should come **before** inventory transfers/batches (G3.2) if store credit is more urgent for you.
10. **D10 Existing data:** is there production stock/PO/customer-credit data in the current dashboard modules that the till will start showing? (Affects how carefully G3.0 must audit units and whether any backfill is needed.)

## 5. Smallest safe first deliverable
G3.0 alone: permission matrix + facade scaffolding + the money-unit audit report + the `StockMovement` decision memo. No UI, no change to the sale path, no data migration.
