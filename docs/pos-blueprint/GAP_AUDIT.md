# Solvexo POS — Blueprint Gap Audit + Full Build Plan (Phase G0)

Status: **read-only audit, awaiting owner approval.** Nothing in the app or backend was changed; this file is the only artifact.
Date: 2026-11-04. Blueprint: `Downloads/Solvexo_POS_UI_Developer_Package` (README, DEVELOPMENT_ROADMAP, design-tokens.json, `app/index.html`, brand-assets).
Phase 3b (core selling flow redesign) is **paused**; its state is at the end of this file (§8).

## 0. Headline findings

1. **The blueprint really has 101 routes** (README is right; the HTML's own placeholder text says "88", which is just a stale default). The 101st is `about` (About Solvexo), which has no explicit renderer.
2. **Only ~25 routes have a bespoke design.** The other ~76 are the generic templates (list / detail / form / settings / report / fallback) filled with demo data. Every row in §1 is marked *Designed* or *Template*, and every Template row has a proposed real content spec.
3. **The backend is further along than the old audit says.** Idempotency, split tender, currency/exponent snapshots, server-recomputed totals, partial refunds, manager-PIN gating, offline sync and POS-plan entitlement all exist in code. (`phase5_production_readiness_audit.md` is a pre-fix snapshot; I verified against code.)
4. **What is genuinely missing on the backend** (and drives most of the plan): Expense/daybook, attendance/clock-in, PriceBook, modifiers, a per-line tax/discount model, a stock-movement ledger for sale decrements, supplier payables, POS customer create/ledger/loyalty/store-credit tender, refund reasons/returns-without-receipt, a payment record that is its own entity, any card terminal/gateway confirmation, per-line cost (profit report), a tax report, granular POS permissions.
5. **Hard conflicts with the roadmap's non-negotiables:** money is float major units (not minor units); card payment success is cashier-asserted; sale stock decrements leave no movement row; audit writes are fire-and-forget and not tamper-evident; held-sale delete is an unaudited hard delete with no manager approval.
6. **Design:** the blueprint's coral `#DC7758` is **3.08:1 with white** (fails). `#B4553A` passes at **4.88:1**, but is **4.40:1 on the soft-coral tint** and 3.64:1 on dark ink, so it needs a darker text variant (`#A84B31`, 5.09:1) — numbers in §4. Our own `accentFill #C4481F` already passes (4.89:1).
7. **Catalog is shared with the storefront.** POS reads the same product/variant collections; create/edit exists only on seller-JWT storefront endpoints that device/employee tokens cannot call. This is the biggest architectural decision (§6, D3).

---

## 1. Screen matrix — all 101 blueprint routes

Legend — **Design**: *Designed* = the prototype has a specific layout; *Template* = generic placeholder template (my proposed content follows). **Status**: exists / partial / missing / out of scope (per ground rule 2: mobile/OTP/biometric login is not built; splash, onboarding, owner login, PIN login, auto-lock, owner gate and device setup are kept as-is and only restyled with tokens later). **BE** = new/changed backend needed.

"Current" names refer to the app's real routes: `/pos/home` (Sale tab), `/pos/orders`, `/pos/sale-detail`, `/pos/products`, `/pos/inventory`, `/pos/stock-activity`, `/pos/customers`, `/pos/held-sales`, `/pos/needs-attention`, `/pos/daily-report`, `/pos/range-report`, `/pos/session-report`, `/pos/session-history`, `/pos/audit-log`, `/pos/settings`, `/pos/devices`, `/pos/plan-status`, `/pos/plan-inactive`, `/pos/delete-account`, `/pos/open-register`, `/pos/pin-login`, `/pos/login`, `/pos/device-setup`, `/pos/owner-gate`, `/seller/stores`, `/seller/pos-management`, `/seller/pos-locations`.

### 1.1 Launch & Access (9)

| Route | Design | Current | Status | What's missing / notes | BE |
|---|---|---|---|---|---|
| splash | Designed | `/splash` | exists — KEEP | Light gradient + mark + wordmark + tagline; ours is dark ink. Only token/logo restyle later (§4). | no |
| welcome (Onboarding) | Designed | `/onboarding` (admin-managed slides) | exists — KEEP | Restyle only. | no |
| login (mobile + password) | Designed | `/pos/login` (email + password, Google) | out of scope | Rule 2: keep email/owner login; do **not** build mobile-number login or biometrics. | no |
| otp | Designed | — | out of scope | Rule 2. | no |
| pin | Designed | `/pos/pin-login` | exists — KEEP | Restyle only. Blueprint's "Switch user" ≈ our lock/relogin. | no |
| store-select | Designed | `/seller/stores` (legacy UI) | partial | Works but legacy `AppColors`/`CustomText` UI; needs token migration. Single-store owners skip it. | no |
| device-setup | Designed | `/pos/device-setup` | exists — KEEP | Restyle only. Blueprint adds printer name field → belongs to hardware (see `hardware`). | no |
| permissions | Designed | — (OS prompts on use) | missing | Pre-flight explainer for Camera / Notifications / Storage / Location. Optional; camera is already requested on first scan. Low value; recommend a one-time first-run screen after device setup. | no |
| open-shift | Designed | `/pos/open-register` (legacy UI) | partial | Has float + opens a session. Missing: expected-vs-counted difference vs the previous close, shift note, denomination counter. | small (previous close's `closingCash` on `sessions/active`/history; optional note field) |

### 1.2 Sell & Checkout (22)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| pos (Smart checkout) | Designed | `/pos/home` Sale tab (Phase 3a/3b redesign: grid, phone pill + cart, tablet two-pane) | exists | Blueprint's 2-column product + 115px cart rail is a phone mock; our adaptive layout supersedes it. | no |
| category-view | Designed (shares search template) | category chips on Sale tab | exists | Dedicated "browse category" page not needed; chips + search cover it. Recommend **merge**. | no |
| product-search | Designed | search bar on Sale tab (`products/search`) | exists | Add recent searches; searching by name/SKU/barcode already works. | no |
| scan | Designed | barcode sheet + camera scan + HID wedge scanner | exists | Torch toggle and "continuous scan" mode missing; check torch support in the camera view. Real camera decode never verified on device in earlier phases. | no |
| product-detail | Designed | variant picker sheet (multi-variant only) | partial | No product detail page at sale time. Proposed: bottom sheet with image, price, stock (per location), SKU/barcode, description, qty, Add. | no |
| variants (Variants & modifiers) | Designed (same layout as product-detail) | variant picker sheet | partial | **Modifiers don't exist** in the backend at all. Variants (options[]) exist. | **yes** (modifiers: new schema, price delta, required/optional groups; quote logic must price them) |
| custom-item | Template (form) | — | missing | Proposed fields: name, price, qty, taxable (y/n), note; line flagged `isCustom` (no stock). Manager-only toggle? Server must accept a line without `variantId`. | **yes** (SaleItem without product; reports must treat it) |
| cart | Designed | cart panel / phone expanded cart (steppers, swipe-undo, discount, customer, hold) | exists | Per-line discount/notes not supported (server has whole-sale discount only). | per-line discount: yes (optional, G3) |
| discounts | Designed (keypad %, fixed) | discount field in cart footer | partial | Server: any discount requires a manager token; no cap/role limit. Needs keypad UI + manager approval flow + max-discount % setting. | yes (discount limits per role in settings) |
| coupon | Designed (identical to discount screen) | — | missing | Needs real coupon-code entry + validation. Storefront `discounts`/`promotions` modules exist but aren't wired to POS. | **yes** (apply code endpoint / quote support) |
| customer-attach | Template (customer list) | customer picker sheet (search shared users) | partial | No "add new customer" inline (see `add-customer`). | yes (POS customer create) |
| park-sale | Template (form) | Hold → confirm sheet | exists | Optional note/label on the held sale is missing. | small (notes exist on the sale) |
| parked-sales | Template (orders list) | `/pos/held-sales` | exists | Restyled in Phase 2/3. Server `discardHeldSale` is a hard delete with no audit/manager approval (see §3). | yes (audit + manager token on discard) |
| payment | Designed | payment sheet | exists | Tender methods today: cash, card, other. Blueprint lists Raast/Wallet and Customer credit (see D2). | for wallet/credit: yes |
| cash-payment | Designed | payment sheet (cash keypad + quick amounts) | exists | — | no |
| card-payment | Designed ("waiting for terminal", "enter approval manually") | payment sheet "card" + reference field | partial | **Not compliant**: card is a typed reference; no terminal/gateway status. See §3 R3, D2. | **yes** |
| split-payment | Designed | payment sheet split mode | exists | — | no |
| credit-payment (Store credit) | Template (no renderer → fallback) | — | missing | Pay on account / store-credit tender. `store-credit` module exists (ledger with balance, expiry) but isn't hooked into POS. Needs ledger debit on sale completion, balance check, refund-to-credit. | **yes** |
| payment-success | Designed | sale success view | exists | — | no |
| receipt | Designed | receipt panel + print (ESC/POS) | exists | — | no |
| print-share | Designed (reuses receipt) | success view Print/Share + settings | exists | Email/SMS/WhatsApp delivery to customer missing. | optional |
| offline | Designed | offline queue, sync banner, Needs attention | exists | Blueprint "Offline selling" page = a status page listing queued sales. Ours: banners + Needs attention under Settings. Recommend a first-class **Sync status** page reachable from Home/More (merge with needs-attention). | no |

### 1.3 Orders & Returns (7)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| orders | Template (list) | `/pos/orders` (legacy UI) | partial | Needs token migration; filters: date, status, tender, cashier, register. | no |
| order-detail | Template (detail) | `/pos/sale-detail` (legacy UI) | partial | Shows void/refund; migrate UI; add timeline (created → paid → refunds), audit ref, tender breakdown, offline badge. | small |
| invoice (Tax invoice) | Template | — (receipt only) | missing | Tax invoice with business tax ID, per-line tax, buyer details (FBR/NTN style, jurisdiction unverified). Needs per-line tax data the Sale lacks. | **yes** (per-line tax; invoice numbering) |
| return-start | Template | partial refund from sale detail | partial | No dedicated return flow, no "return without receipt", no return window rule. | yes |
| return-items | Template | partial refund (by line + qty) | partial | Reason code per line, restock vs damaged choice. | yes (reason, disposition) |
| refund-method | Template | refund allocated back across original tenders | partial | No choice (store credit / cash / original). No store-credit refund tender. | yes |
| refund-success | Designed | toast / detail refresh | partial | Dedicated confirmation screen with refund reference (refund has no id today). | yes (Refund as own record with id) |

### 1.4 Products & Pricing (7)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| products | Template (list) | `/pos/products` (legacy UI, read-only list + stock badge) | partial | Create/edit not in app; token migration. | depends on D3 |
| catalog-product | Template (detail) | — | missing | Detail: image, name, category, variants table (SKU, barcode, price, cost, stock per location), price history, lots. | depends on D3 |
| product-form | Template (form) | — | missing | Fields: name, category, type (physical), images, description, variants (options, SKU, barcode, price, cost, unlimited-stock flag, reorder level), tax class, active. | depends on D3 |
| categories | Template (detail) | — | missing | Category tree CRUD. | depends on D3 |
| modifiers | Template (detail) | — | missing | Modifier groups/options with price delta, required, max select. | **yes** |
| pricebook | Template (detail) | — | missing | Named price lists (retail, wholesale, staff), per-variant price, effective dates, assign to customer group/register. | **yes** |
| bulk-import | Template (detail) | — | missing | CSV import with template, preview, error rows. Backend util files exist (product/variant/stock bulk import). | partial |

### 1.5 Inventory (11)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| inventory-overview | Designed | `/pos/inventory` (legacy UI: list + low-stock filter) | partial | Stock value (valuation endpoint exists), SKU/low/out counts, expiring batches, action tiles. | no (valuation, low-stock-summary exist) |
| stock-list | Template (products list) | `/pos/inventory` | partial | Per-location filter; migrate UI. | no |
| stock-detail | Template | tap → adjust sheet | partial | Per-location stock, lots, movement history, reorder level, cost. | no |
| stock-count | Template | — | missing | Count session: pick location/category, scan/enter counts, variance review, finish. Backend `stock-counts` exists. | no (exists) |
| stock-count-scan | Designed (scan) | — | missing | Count by scan (reuse scanner). | no |
| adjustment | Template | adjust-stock sheet in inventory | exists | Reason list matches backend (restocked/damaged/return/correction/other). Approval flow exists server-side. | no |
| transfer | Template | — | missing | New transfer: from/to location, lines, ship. Backend exists. | no |
| transfer-detail | Template | — | missing | Status timeline (ship, receive, cancel). Backend exists. | no |
| low-stock | Template (products list) | low-stock filter | partial | Reorder suggestions (endpoint exists), create PO from list. | no |
| batch-expiry | Template (products list) | — | missing | Lots per variant, expiry buckets, write-off (endpoints exist). Sale flow doesn't pick lots in the UI. | no |
| inventory-history | Template (products list) | `/pos/stock-activity` (legacy UI, owner gate) | partial | Movement ledger incomplete: **sale decrements are not recorded** (see §3 R2). | **yes** (stock-movement ledger) |

### 1.6 Customers (5)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| customers | Template (list) | `/pos/customers` (legacy UI, owner gate) | partial | Segments (tier, balance due), search, sort. | small |
| customer-profile | Template (detail) | — | missing | Contact, lifetime spend, order history, loyalty tier/points, credit balance, notes, consent. | **yes** (POS-scoped read of sales per customer; `StoreCustomerMeta` exists) |
| add-customer | Template (form) | — | missing | Name, phone (primary key in PK retail), email, address, tax ID, group. | **yes** (no POS customer create endpoint) |
| loyalty | Template (detail) | — | missing | Earn/redeem rules, tiers, balance. `loyalty` module exists, not hooked to POS. | **yes** (earn on sale, redeem as tender) |
| customer-credit | Template (detail) | — | missing | Ledger (signed entries with running balance), take payment, credit limit. `store-credit` ledger exists, not hooked. | **yes** |

### 1.7 Supply & Purchasing (7)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| suppliers | Template (list) | — | missing | Directory with due balance. Supplier CRUD exists on backend. | payables: yes |
| supplier-profile | Template (detail) | — | missing | Contact, terms, products supplied, PO history, outstanding payable. | payables: yes |
| purchase-orders | Template (list) | — | missing | List by status (draft, ordered, partial, received, closed, cancelled). Backend exists. | no |
| purchase-order-detail | Template (detail) | — | missing | Lines, receive history, PDF/email. Backend exists. | no |
| new-purchase-order | Template (form) | — | missing | Supplier, location, lines (scan/search), expected date, notes. | no |
| receive-stock | Template (detail) | — | missing | Per-line received/damaged qty, lot + expiry, idempotent receive. Backend exists. | no |
| supplier-payment | Template (detail) | — | missing | Pay supplier against PO/invoice, method, reference; shows in daybook. **No payables ledger exists.** | **yes** |

### 1.8 Cash & Expenses (5)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| expenses | Template (list) | — | missing | Period filter, category totals, list. | **yes** (Expense entity missing) |
| add-expense | Template (form) | — | missing | Amount, category, paid-from (till / bank / owner), date, receipt photo, note; till expenses affect expected cash. | **yes** |
| expense-detail | Template (detail) | — | missing | Fields + approval + audit trail. | **yes** |
| cash-movement | Template (detail) | "Cash Management" tile in Settings (cash in/out, manager only) | partial | Reason categories (not just free text), receipt photo, linked expense. | small |
| daybook | Template (detail) | — | missing | One chronological ledger per day: sales by tender, refunds, cash in/out, expenses, supplier payments, opening/closing cash. Traceable to every transaction (roadmap acceptance target). | **yes** |

### 1.9 Reports (9) — one shared report template

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| reports-home (Business pulse) | Designed (home) | none (Sale tab is the landing) | missing | Net sales, orders, avg sale, profit %, 7-day chart, needs-attention. Owner/manager only. | partial (profit needs line cost) |
| sales-report | Template | `/pos/daily-report`, `/pos/range-report` | partial | Group by day/store/register/cashier; export (daily CSV exists). Legacy UI. | small |
| profit-report | Template | — | missing | **SaleItem has no cost**; need cost snapshot per line. | **yes** |
| product-report | Template | top 10 products in daily report | partial | Full ranking, units, revenue, margin. | yes (extend) |
| category-report | Template | — | missing | Category on sale lines. | yes |
| tax-report | Template | — | missing | Tax by rate/period (needs per-line tax). | **yes** |
| payment-report | Template | `byPaymentMethod` in daily report | partial | Dedicated view. | small |
| cashier-report | Template | `reports/employee/:id` endpoint, no screen | partial | Screen. | no |
| hourly-report | Template | `hourlyBreakdown` in daily report | partial | Screen. | no |

### 1.10 Team & Shifts (6)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| staff | Template (list) | `/seller/pos-management` (owner gate, legacy UI) | partial | Employees CRUD exists (owner only). | no |
| staff-profile | Template (detail) | same screen | partial | Role, PIN reset, locations, last login, sales stats. | small |
| roles | Template (detail; spec says "explicit high-risk actions + branch-level access") | cashier/manager enum only | partial | **No granular permissions**; owner implicit. | **yes** |
| attendance | Template (detail) | — | missing | Clock in/out history. | **yes** |
| shift-summary | Template (detail) | `/pos/session-report`, `/pos/session-history` | partial | X/Z report exists; migrate UI; add cash variance, denominations. | small |
| clock-in | Template (detail) | — | missing | Distinct from register shift (see D6). | **yes** |

### 1.11 Settings (13)

| Route | Design | Current | Status | Missing | BE |
|---|---|---|---|---|---|
| settings (hub) | Designed | `/pos/settings` (legacy UI) | partial | Re-group per blueprint (Business / Experience / System). | no |
| store-profile | Template (settings) | tile edits business name/address/tax ID (manager) | partial | Logo, phone, currency (read-only), opening hours. | small |
| register-settings | Template | register name in settings; registers managed in `/seller/pos-management` | partial | Per-register config (printer, cash-drawer, default location). | small |
| payments-settings | Template | — | missing | Enabled tenders, default tender, reference rules, terminal config (D2). **No plan purchase UI (rule 3).** | **yes** |
| tax-settings | Template | flat `taxRate` in settings | partial | Tax rules (rates, inclusive/exclusive, category mapping). | **yes** |
| receipt-settings | Template | header/footer + printer settings (paper width, copies, auto-print, test) | partial | Logo on receipt, field toggles, preview. | small |
| notifications | Template | — | missing | Low-stock, sync failure, shift-close reminders (local + push). | optional |
| hardware | Template | printer picker, cash-drawer open | partial | Scanner, customer display, terminal pairing. | no |
| integrations | Template | — | missing | Accounting export, API keys. Recommend **defer** (not an MVP need). | yes |
| security | Template | auto-lock, owner gate, `/pos/audit-log` | partial | Merge screen: PIN policy, auto-lock, audit log, devices. | no |
| backup-sync | Template | sync status via Needs attention | partial | Last sync, queue size, retry now, offline data size. | no |
| help | Template | — | missing | Static help/support links. | no |
| about | Fallback template (no renderer) | — | missing | Version, licenses, legal, delete account link. | no |

### 1.12 Current screens with NO blueprint equivalent — recommendation

| Current screen | Why it exists | Recommendation |
|---|---|---|
| Needs attention (`/pos/needs-attention`) | Rejected offline sales awaiting manager retry/discard; blocks shift close and sign-out | **KEEP.** Surface inside the blueprint's Offline / Backup & sync page and as a Home alert. Mandatory for the "no data loss" rule. |
| Held sales (`/pos/held-sales`) | = blueprint `parked-sales` | **MERGE** into `parked-sales` (already equivalent). |
| Audit log (`/pos/audit-log`) | Manager-PIN gated | **MERGE** into Settings → Security (blueprint mentions "audit log" there). |
| Devices (`/pos/devices`) | Owner list + revoke | **MERGE** into Settings → Register settings / Hardware. Keep revoke confirm. |
| Plan status / plan inactive | POS plan gating, restricted mode | **KEEP** (rule 3). Show a plan chip in More; no purchase UI. |
| Delete account | Store/legal requirement | **KEEP**, move under About / Security. |
| Owner gate | Shared-device model | **KEEP** (rule 2). |
| Session history / session report | = shift-summary | **MERGE** into Shift summary. |
| Stock activity | = inventory-history | **MERGE.** |
| Range / daily report | = sales-report | **MERGE.** |
| `/seller/onboarding`, `/seller/stores`, `/seller/pos-locations`, `/seller/pos-management` | Owner setup | **KEEP**, restyle with tokens; locations → Settings; management → Team. |
| Design gallery (debug) | Dev tool | KEEP, debug-only. |
| Legacy modules `category`, `home` (unrouted) | Dead code | **REMOVE** after G1. |

---

## 2. Backend gap report (`solvexo-api`)

### 2.1 Entity comparison

| Entity | Status | Where | Needed |
|---|---|---|---|
| Business | partial | No entity; root is `Seller` → `Store`; `PosSettings` holds business name/address/taxId | Keep; no chain support. Not needed for MVP. |
| Store | exists | `src/store/schemas/store.schema.ts`; branches = `StoreLocation` (`src/pos/schemas/store-location.schema.ts`) | — |
| Register | partial | Embedded `Store.registers[]`; bound to devices via `PosDevice` | Promote to its own collection only if per-register config (printer, default location) is needed (G3). |
| User | exists (3 systems) | Seller, `StaffMember`, POS `Employee` (`employee.schema.ts`) | Document the owner/staff/employee split; no change for G1–G2. |
| Role | partial | `Employee.role` ∈ {cashier, manager}; web `Role` + `STAFF_PERMISSIONS` has no `pos.*` entries | New POS permission set + role presets; keep manager-PIN approvals separate (G4). |
| Shift | partial | `Store.shifts[]` = scheduled shifts; cash sessions = `RegisterSession` | No attendance/clock-in; no denomination count. |
| Product | exists (shared) | `src/products` | See §2.3. |
| Variant | exists (shared) | `src/product-variants` (sku, barcode, price, cost, options, unlimitedStock); `VariantLocationStock`; `StockLot` (opt-in) | — |
| Category | exists (shared) | `src/categories` | Not used in POS reports. |
| PriceBook | **missing** | Only `VariantPriceHistory`, storefront `markets`, `discounts` | New schema + quote logic. |
| InventoryBalance | exists | Variant `stock` + `VariantLocationStock` + bins/units | — |
| StockMovement | partial | `StockAdjustment` (manual only), transfers, PO receipts, supplier returns; `reports/movements` | Sale/refund/void decrements **not recorded**; unify into one immutable movement ledger. |
| Customer | partial | No POS customer schema; sale has `customerId`/`customerName`; shared users search; `StoreCustomerMeta` | POS customer CRUD, ledger link, loyalty link. |
| Supplier | exists | `src/purchase-orders/schemas/supplier.schema.ts` | Payables/ledger missing. |
| PurchaseOrder | exists | `purchase-order.schema.ts` (draft → ordered → partial → received/closed/cancelled; idempotent receive; lots) | Payment tracking against PO missing. |
| Sale | exists | `src/pos/schemas/sales.schema.ts` (store, session, register, location, employee, items, totals, payments[], refunds[], currency + exponent, idempotencyKey unique, offline flags, `approvedBy`) | No per-line tax/discount/cost; no `deviceId`; no `shiftId` stored. |
| SaleItem | exists (embedded) | productId, variantId, sku, price, listPrice, qty, lineTotal, refundedQty | + cost snapshot, tax, discount, category, `isCustom`. |
| Payment | partial | Embedded `Sale.payments[]` (cash/card/other, amount, tendered, reference) | Own entity with id, status (pending/confirmed/failed), provider ref, terminal id. |
| Refund | partial | Embedded `Sale.refunds[]` (no id) | Own entity with id/reference, reason code, disposition, session/register/employee, approving manager. |
| Expense | **missing** | Only `RegisterSession.cashAdjustments[]` (free-text reason) | New entity + categories. |
| TaxRule | partial | Single `PosSettings.taxRate`; storefront `taxRegions`/`taxOverrides` ignored by POS | Rules per category, inclusive/exclusive. |
| AuditEvent | partial | `PosAuditLog` (store, employee, action, target, metadata) | Add session/register/device ids, awaited writes, tamper evidence. |

### 2.2 Endpoints required per new module

Auth shorthand: **PA** = POS device or owner token, **MGR** = manager employee token (`x-pos-employee-token`), **OWN** = seller JWT, **ENT** = active POS plan. **Idem** = `Idempotency-Key` header required. Existing endpoints reused are noted in §2.4.

| Module | Method + path | Auth | Idem |
|---|---|---|---|
| **Payments (new entity)** | `POST pos/sales/:id/payments` (attempt) | PA, ENT | yes |
| | `GET pos/payments/:id` (status) | PA | no |
| | `POST pos/payments/:id/confirm` (terminal/gateway callback or manual-approval with MGR) | PA / webhook | yes |
| | `POST pos/payments/:id/cancel` | PA | yes |
| | `POST pos/webhooks/<provider>` | signed webhook | provider event id |
| **Refunds/returns** | `POST pos/sales/:id/returns` (items, reasons, disposition) | PA + MGR | yes |
| | `GET pos/refunds/:id`, `GET pos/refunds` | PA | no |
| **Coupons** | `POST pos/sales/quote` (extend: `couponCode`) | PA, ENT | no |
| **Custom item / modifiers / tax / per-line discount** | extend `quote` + `sales` DTOs | PA, ENT | existing |
| **Catalog (if D3 option 2)** | `POST/PATCH/DELETE pos/catalog/products`, `.../variants`, `.../categories` | PA + MGR | yes |
| **Price books** | `GET/POST/PATCH/DELETE pos/price-books`, `PUT pos/price-books/:id/entries` | PA (read) / MGR | yes on writes |
| **Modifiers** | `GET/POST/PATCH/DELETE pos/modifier-groups` | PA read / MGR write | yes |
| **Customers** | `POST pos/customers`, `PATCH pos/customers/:id`, `GET pos/customers/:id`, `GET pos/customers/:id/sales` | PA | yes on writes |
| **Customer credit** | `GET pos/customers/:id/ledger`, `POST pos/customers/:id/ledger/payment`, tender `credit` on sales | PA + MGR for limits | yes |
| **Loyalty** | `GET pos/customers/:id/loyalty`, tender `loyalty` / earn on completion | PA | yes |
| **Inventory movements** | `GET pos/inventory/:storeId/movements` (unified ledger) | PA + MGR | no |
| **Stock counts/transfers/adjustments/lots** | reuse `api/stock-counts`, `api/inventory/*` — add POS-token access (today seller-JWT with permissions) | PA + MGR | existing |
| **Suppliers/POs/receiving** | reuse `api/purchase-orders/*` — same access change | PA + MGR | receive already idem |
| **Supplier payments** | `POST purchase-orders/:storeId/suppliers/:id/payments`, `GET .../ledger` | MGR / OWN | yes |
| **Expenses** | `POST/GET/PATCH pos/expenses`, `GET pos/expense-categories`, `POST pos/expenses/:id/approve` | PA + MGR | yes on create |
| **Cash movements** | extend `sessions/:id/cash-adjustment` with category + receipt ref | PA + MGR | existing |
| **Daybook** | `GET pos/daybook?date&locationId` | PA + MGR | no |
| **Reports** | `GET pos/reports/{sales,profit,products,categories,tax,payments,cashiers,hourly}` | PA + MGR (existing `@RequireManagerPin`) | no |
| **Attendance** | `POST pos/attendance/clock-in|clock-out`, `GET pos/attendance` | PA | yes |
| **Roles/permissions** | `GET/POST/PATCH pos/roles`, `PATCH pos/employees/:id/role` | OWN | yes |
| **Shift** | extend `sessions/open|close` (denominations, previous-close variance, note) | PA | existing |
| **Audit** | `GET pos/audit-logs` (exists); add filters + export | PA + MGR | no |
| **Held sale discard** | change existing `DELETE pos/sales/:id/discard` → MGR + audit | PA + MGR | yes |
| **Hardware/terminals** | `GET/POST/PATCH pos/terminals` | OWN | yes |
| **Notifications** | `POST pos/devices/me/push-token` | PA | yes |

### 2.3 Catalog ownership — how POS gets products today

- **Same collections as the storefront.** POS reads `productModel` + variant model directly (`src/pos/pos.service.ts` ~lines 438–856; schemas `src/products/schemas/product.schema.ts`, `productVariant.schema.ts`). There is no POS product collection. POS lists filter `type: 'physical'`, `isDelete: false`.
- **POS read endpoints** (PA + ENT): `GET pos/products/:storeId`, `products/search`, `products/barcode/:storeId/:barcode`, `inventory/:storeId`, `inventory/:storeId/low-stock`.
- **Create/edit today** exists only on shared storefront endpoints guarded by seller JWT + roles + permissions (device and employee tokens are **refused**):
  - Products: `POST api/products/add-physical-product`, `.../add-digital-product`; variants: `POST|PATCH|DELETE api/products/:productId/variants/...`.
  - Categories: `POST api/categories/add-category`, `PUT|DELETE api/categories/category/:id`, `POST store/:storeId/import`.
  - Bulk: `api/products-bulk/:storeId/{status,tags,delete,edit}`; `POST api/inventory/:storeId/stock/import`.
  - Stock adjust: `PATCH api/inventory/:storeId/variant/:variantId/adjust` (idempotent) — already used by the POS app.
- **Modifiers: do not exist anywhere** (grep for modifier found nothing). **Price books: do not exist** (only `compareAtPrice`, storefront Markets, `VariantPriceHistory`). **Supported:** barcodes (indexed, sparse), lots/expiry (opt-in per variant), weighted-average cost, price history.

**Options (not a decision — see D3):**
1. **One shared catalog; app calls the seller-JWT endpoints behind an owner-gate re-auth** (what the owner can do today in principle). Fastest, but a shared device with a seller JWT can mutate the storefront catalog; no manager-PIN-only path.
2. **POS-scoped catalog routes** (PA + MGR) that wrap the same services. Clean permissions and audit; moderate backend work; keeps one catalog.
3. **Read-only POS; web dashboard is the catalog authority.** Zero backend work; blueprint's Products & Pricing module (7 screens) is then mostly view-only in the app.
4. **Option 2 + new collections for modifiers and price books** linked to variants and evaluated server-side in `pos-money.util.ts`. Needed regardless if modifiers/price books are wanted.

---

## 3. Engineering rules compliance (roadmap "non-negotiable")

| # | Rule | Verdict | Evidence | Work needed |
|---|---|---|---|---|
| R1 | Money in smallest currency unit | **Not compliant** (partly mitigated) | Every money field is `Number` in major units (`sales.schema.ts`, `register-session.schema.ts`, variant `price/costPrice`). Arithmetic **is** done in integer minor units server-side (`src/pos/pos-money.util.ts`: `toMinor`/`fromMinor`, half-away-from-zero) with exponent from `currency-metadata.const.ts`; `currency` + `currencyExponent` snapshots are stored on Sale/Refund/Session. Dart: `lib/utils/money.dart` + `pos_totals.dart` mirror it; ~57 `double` model fields; 14 `toStringAsFixed` calls remain (not each audited). | Migration estimate below. |
| R2 | Immutable audit reference for every sale, payment, refund, stock movement | **Partly** | Sale: `saleNumber` unique per store + unique sparse `idempotencyKey`. Payments and refunds are **embedded without ids**. Sale/refund/void decrements write **no movement row** (`stock-adjustment.schema.ts` comment: checkout decrements excluded). `PosAuditLog` is plain `create`, no update/delete block but no hash chain; writes are fire-and-forget `.catch(() => {})` (e.g. `pos.service.ts:1275`). | Payment + Refund entities with ids; unified movement ledger; awaited/outbox audit writes; append-only enforcement (Mongo role + schema hooks) and optional hash chain. |
| R3 | Payment success only from confirmed gateway/terminal status | **Not compliant** | `SalePayment.reference` is free text; methods `cash|card|other`; no terminal/gateway code in `src/pos`. `payment/` + `manual-payments/` are buyer-checkout flows. | Payment entity with status; provider integration or explicit "unconfirmed (manual)" state with manager approval + reconciliation (D2). |
| R4 | Retries never duplicate payments/orders/stock | **Largely compliant** | `common/idempotency.interceptor.ts` (24 h TTL, in-progress claim, stale takeover, replay cache) on sales create/complete/refund/void/discard, sessions open/close/cash-adjust, offline-discards, inventory adjust/approve/receive, stock-count finish, PO receive; `Sale.idempotencyKey` unique with E11000 recovery; held-sale double-complete guarded (`HELD_SALE_ALREADY_RESOLVED`); app mints one key per intent (`idempotency_intent_store.dart`). Gaps: `resolve-review`, `PATCH sales/:id/items`, `force-close` have no key; interceptor namespace is per **seller account**, not per device; stock decrement is atomic per variant but **not transactional across the sale** (from earlier audit, not re-verified). | Add keys to the 3 routes; scope keys by device; Mongo transaction (needs replica set — check env) or compensation for multi-variant decrements. |
| R5 | Every list has loading/empty/error/offline/success states | **Partly** | Keyword grep only (not visual): Held sales, Needs attention, Sale detail have all four; **Customers, Audit log, Stock activity, Session history, Range report, Session report lack error and offline**; Orders/Products have loading + empty + minimal error, no offline. | A shared `AsyncListScaffold` (design-system) applied to every list in G1; widget tests per state. |
| R6 | Offline transactions encrypted locally + reconciled idempotently | **Largely compliant** | `lib/app/data/local/queue_cipher.dart` AES-256-GCM (OS provider), key in secure storage; encrypted payload/token/error/discard reason; row id = idempotency key; FIFO backoff; failed rows wait for manager. **Gaps:** cart snapshot (`pos_cart_snapshot`), catalog cache and settings cache are plain SharedPreferences JSON; sqlite file itself unencrypted (only columns are). | Encrypt cart snapshot + customer data in caches; decide if product catalog cache is sensitive (probably not). |
| R7 | Cashier permissions separate from manager approvals | **Partly** | `requireManagerEmployee` (`pos.service.ts` ~164) for refund, void, cash in/out, any discount, resolve-review, offline discard; `@RequireManagerPin` on reports/audit; `approvedBy/approvedAt` on sale. **No granular permissions, no discount % cap, no refund cap, no per-role limits**; owner implicit. | Permission catalogue + presets + limits in settings (G4); keep PIN approval as a separate mechanism. |
| R8 | Destructive/high-risk actions confirmed + audit-logged | **Partly** | Void/refund: manager token + audit + idempotent (audit not awaited). **`discardHeldSale`: owner check only, hard `findOneAndDelete`, no audit, no manager token** (I verified `pos.service.ts:1286-1298`). Employee deactivate audits with `employeeId: null` (actor not recorded, `:1833`). Device revoke audited. | Manager token + audit on held discard; record actor on deactivate; soft-delete held sales; confirm dialogs consistently. |
| R9 | Branch, register, cashier, shift ids on every transaction | **Partly** | Sale has store, session, register, location, employee. **No `shiftId`, no `deviceId` on sale.** Refund has only `employeeId` (session/register come from parent sale — wrong attribution for later-session refunds). Audit rows: store + employee only. Manual stock adjustment: `adjustedBy`, location, store only. | Add `{storeId, locationId, registerId, sessionId, shiftId, deviceId, employeeId}` envelope to Sale, Payment, Refund, StockMovement, AuditEvent, Expense. |

### 3.1 Minor-units migration — estimate (decision D1)

| Area | Work | Size |
|---|---|---|
| Schemas | Add integer `*Minor` fields (dual-write) on Sale, SaleItem, SalePayment, SaleRefund, RegisterSession, CashAdjustment; variant `price/compareAtPrice/costPrice` are **shared with the storefront** and the ledger (`finance/schemas/transaction.schema.ts`, `recordPosSaleInLedger`/`Refund`) writes major units | L |
| API | Every POS DTO/response; version the contract (`apiVersion` header) so old app builds keep working; order/finance adapters | L |
| App | ~57 `double` fields in `models/pos/*.dart`, parsing, `Money`, `pos_totals.dart` mirror, receipt/printer formatting, tests; offline queue holds in-flight major-unit payloads → dual-read for a release | M–L |
| Data | Backfill `round(x · 10^exp)` per document using its `currencyExponent`; **pre-Phase-5B rows have null exponent** → guess from store `baseCurrency`; verify with sum-parity checks per store/day | M |
| Risk | **High:** shared variant price coupling with storefront/buyer apps, ledger parity, old app versions, rollback needs dual-write period | — |
| **Overall** | **L** (≈ 4–6 weeks including parity tooling) | |

**Cheaper alternative (S–M), recommended in D1:** keep stored major units (already exponent-snapshotted and server-recomputed in integer minor units), and make **every new entity minor-units-native** (Payment, Refund, Expense, PO payment, cash movement, supplier payment). Add `*Minor` dual-write only on Sale/Session/Refund. Defer variant/storefront price migration until a storefront-wide decision.

---

## 4. Design-system delta

### 4.1 Tokens

| Item | Blueprint | Ours today | Delta |
|---|---|---|---|
| Brand coral | `#DC7758` (mark pixel samples `#D97757`) | accent `#F06839` | **Brand shift** (ours is more orange/red). Switch icon/highlight accent to `#DC7758`. |
| Light soft | `#FFF0EB` | accentSoft = 12% of F06839 | Replace. |
| Canvas | `#F4F1EE` | `#F6F5F1` | Close; adopt blueprint. |
| Ink | `#15181D` | text `#1B1A17`; dark bg `#0B1020` (navy) | Blueprint has **no dark mode**; ours does. Recommend keep dark mode, re-based on `#15181D`/neutral ink so it matches the brand. |
| Semantics | success `#20976B`, warning `#E8A22B`, danger `#D94C5C`, info `#4D72DB` + soft tints | `#12B886 / #FFB547 / #FF5D6C / #5B8CFF` | Adopt blueprint hues for fills/icons; **text uses darker "fg" variants** (below). |
| Radii | 10 / 14 / 18 / 24 | 8 / 14 / 20 / 28 / full | Replace sm 8→10, lg 20→18, xl 28→24. All `Radii.*` call sites follow automatically; visual QA of sheets and cards. |
| Spacing | 4 8 12 16 20 24 32 | 0 4 8 12 16 20 24 32 40 48 64 | Ours is a superset; keep. |
| Min tap target | 44 | `Space.minTouch = 48` | Keep 48 (stricter than blueprint). |
| Text contrast | ≥ 4.5:1 | proven on current palette (Phase 1–2) | Re-prove on the new palette (script below). |
| Fonts | Manrope (display), DM Sans (body), min body 12 | Plus Jakarta Sans + JetBrains Mono | Replace; bundle Manrope + DM Sans as assets (no new packages; both OFL — add to `LicenseRegistry`); remove JetBrains Mono, Inter, Plus Jakarta files. |

### 4.2 Contrast — calculated (WCAG relative luminance, exact)

| Pair | Ratio | Verdict |
|---|---|---|
| white on `#DC7758` (blueprint primary) | **3.08** | fails 4.5 (also fails 3:1 for text < 18 pt bold only barely) |
| white on `#B4553A` (proposed fill) | **4.88** | passes |
| white on `#A84B31` | 5.65 | passes |
| white on ours `#C4481F` | 4.89 | passes |
| `#15181D` on `#DC7758` | 5.78 | passes — **alternative: keep exact brand coral with dark label** |
| `#B4553A` on white / on `#FFF0EB` / on canvas `#F4F1EE` | 4.88 / **4.40** / **4.34** | fails on tints → use text-coral `#A84B31`: 5.65 / 5.09 / 5.02 |
| `#B4553A` on `#15181D` (dark) | **3.64** | fails → dark mode accent text `#F39072` (7.66 on `#15181D`) or `#DC7758` (5.78) |
| muted `#6F7680` on white / on canvas | 4.59 / **4.08** | fails on canvas → use `#5F666E` (5.81 / 5.17) |
| success `#20976B` text on white / on tint | **3.68 / 3.33** | fails → `#157553` (5.67 / 5.12) |
| warning `#E8A22B` text on white / tint | **2.18 / 2.02** | fails badly → text `#8A5A00` on `#FFF6DF` (5.50); keep `#E8A22B` for icons/fills with dark `#15181D` text (8.16) |
| danger `#D94C5C` text on white / tint | **4.09 / 3.62** | fails → `#B83A49` (5.62 / 4.98) |
| info `#4D72DB` on white / tint | **4.43 / 3.95** | fails → `#3A5BC0` (6.11 / 5.45) |

**Recommendation:** filled primary buttons = `#B4553A` + white (4.88:1) as you asked; coral used as *text/icon on tints* = `#A84B31`; keep `#DC7758` for large icons, illustrations, chart bars and the logo only. (The existing `accentFill #C4481F` already passes; either is acceptable — `#B4553A` is closer to the blueprint hue.) I will add a contrast test that fails the build if any token pair drops below 4.5:1 (we have `brand_panel_contrast_test` as a pattern).

### 4.3 Tabular figures without JetBrains Mono

- Manrope and DM Sans are both expected to ship an OpenType `tnum` feature; Flutter enables it with `FontFeature.tabularFigures()` (`typography.dart` already does this for amounts).
- **Unverified:** I did not inspect the font files. Before committing: inspect the downloaded `.ttf` GSUB features (e.g. with `fonttools`/`ttx`) for `tnum` on **both** fonts and for the weights actually bundled. A font without `tnum` silently ignores the feature and amounts will jitter.
- Fallback plan if DM Sans lacks `tnum`: render all amounts in Manrope (has bold, tall numerals) with tnum, keep DM Sans for prose. Add a golden test that renders `1111.11` vs `8888.88` and asserts equal width.
- Remove "per-character" rendering in `AmountText` only after the golden proves tnum works (that rendering was a workaround).

### 4.4 Components that must change

All 26 in `lib/core/design/components/` pick up new tokens automatically; these need real changes:
`app_button` (fill `#B4553A`, radii), `app_card`, `app_bottom_sheet`/sheet surface (radius 24), `app_text_field` (radius 14, new borders), `status_badge`, `stat_tile`, `amount_text` (font), `receipt_panel`, `pin_pad` (re-check against light-cream), `brand_logo` + `brand_panel` (new logo), `ink_scope` (always-dark screens: PIN/gate; keep but re-base to `#15181D`), `app_toast`, `product_tile`, `quantity_stepper`, `app_shell` (5 tabs, see 4.6), `skeleton`, `empty_state`. New components needed: `AsyncListScaffold` (R5), `SegmentedTabs`/chips, `MetricTile` (hero + 3 metrics), `DateRangeStrip`, `LineChart/BarChart` (no new package → CustomPainter; confirm with you), `TimelineRow`, `ApprovalSheet` (manager PIN), `FormScaffold`, `SettingRow` + `Toggle`, `LedgerRow`.
Legacy screens still on `AppColors/CustomText/.sp` (must be migrated as they are rebuilt): pos_orders, pos_products, pos_sale_detail, pos_settings, pos_audit_log, pos_customers, pos_daily_report, pos_range_report, pos_session_report, pos_session_history, pos_inventory, pos_stock_activity, pos_needs_attention, pos_open_register, pos_plan (2), pos_device (delete account, devices), all of seller_* modules, `pos_app_bar`, `pin_legacy_theme`.

### 4.5 Logo assets and icon impact

- `brand-assets/Solvexo_logo_mark.png`: **327×316**, RGBA, **not square**, transparent. Too small for the 1024² iOS/Android launcher icon (will blur if upscaled) — **request a vector/SVG or ≥1024² master from Sir Atiq**.
- `Solvexo_wordmark.png`: 900×239, **black text**, transparent → **invisible on dark** (our dark mode, PIN/gate screens, native dark splash). Need a white/light wordmark variant.
- Mark pixel color is `#D97757`, token says `#DC7758` — confirm which is canonical.
- Impact list: `assets/icon/app_icon.png` (1024, opaque), `app_icon_foreground.png` (Android adaptive; keep within the 66% safe zone), `splash_logo.png`, `splash_logo_android12.png` (Android 12 splash icon is masked in a circle: needs padding), `assets/images/logo.png`, in-app `BrandLogo`, adaptive icon background `#F06839` → brand coral, `flutter_native_splash.color #0B1020` → decision needed (blueprint splash is a light gradient `#FFF7F4→#FFF`; rule 2 says splash is kept as-is, so I would only swap logo/colour, not layout). Regenerate with `dart run flutter_launcher_icons && dart run flutter_native_splash:create`; verify on iOS simulator and an Android device.

### 4.6 Navigation — 5 tabs and role visibility

Blueprint: **Home, Sell, Orders, Stock, More.** Ours today: **Sale, Orders, Products, Settings (badge)**.

| Blueprint tab | Maps from | Contains |
|---|---|---|
| Home | *new* | Cashier: shift status, quick actions (New sale, Scan), parked sales count, sync/needs-attention alert. Manager/Owner: Business pulse (reports-home) behind existing manager-PIN gating. |
| Sell | Sale tab | Grid, cart, payment, parked sales. |
| Orders | Orders tab | Orders, returns, refunds. |
| Stock | Products tab + Inventory | Stock on hand, low stock, counts, transfers, products (read or edit per D3). |
| More | Settings tab (+ badge) | Customers, Suppliers/POs, Cash & Expenses, Reports, Team & Shifts, Settings hub, Sync & needs attention, Devices, Plan status, About. |

| Area | Cashier | Manager | Owner (seller JWT, owner gate) |
|---|---|---|---|
| Home | shift snapshot only | + business pulse | + all stores |
| Sell | yes (no discount without manager approval) | yes + approve discounts | yes |
| Orders | own register's sales; no refund | all, refund/void with PIN | all |
| Stock | view stock/search; no adjust | adjust, count, receive, transfer | + catalog admin (D3) |
| More → Customers | pick/add | edit | edit |
| More → Suppliers/POs/Expenses/Reports | hidden | yes (PIN-gated reports) | yes |
| More → Team, Devices, Roles, Security, Plan status, Delete account | hidden | partial (view) | yes behind owner gate |
| Restricted mode (plan inactive) | Orders, Reports, Needs attention, Settings only (unchanged) | same | same |

---

## 5. Phased build plan

Rule: **backend first in every phase; each phase is shippable alone.** Sizes: S ≈ ≤ 3 days, M ≈ 1–2 weeks, L ≈ 3+ weeks (one developer). Every phase ends with: `npm run build`, POS backend suites, `flutter analyze`, `flutter test`, iOS simulator integration, a `docs/` summary, push to `feature/jamibranch`, STOP for approval.

### G1 — Foundations
**Backend**
- Transaction envelope: add `shiftId`, `deviceId` to Sale; `sessionId/registerId/deviceId` to AuditEvent, StockAdjustment, Refund (S–M, additive migration).
- Awaited/outbox audit writes; actor on employee deactivate; manager token + audit on held-sale discard, soft-delete held sales (S).
- Idempotency keys on `resolve-review`, `PATCH sales/:id/items`, `force-close`; key namespace by device (S).
- Unified `StockMovement` ledger written by sale / refund / void / adjust / transfer / receive / count (M–L). Back-fills not required; ledger starts at deploy.
- Payment and Refund as own entities (ids/references), **dual-written** with the embedded arrays (M).
- Optional: minor-units dual-write on Sale/Session (only if D1 = yes) (L).
- Tests: integration (real Mongo/Redis) for each; idempotency replay tests.

**App**
- New tokens, fonts, radii, logos, native splash + icons (M). Contrast + tnum golden tests.
- 5-tab shell (`AppShell`) with role-based visibility and restricted-mode rules; Home tab (cashier version) (M).
- `AsyncListScaffold` and migration of all legacy lists to the five states (M).
- Encrypt cart snapshot (S).
- Migrate legacy screens to tokens as touched: orders, sale-detail, products, settings hub (M).
- Dependencies: none. Risks: font tnum unverified; logo master missing; radii change touches every card.

### G2 — Transactional MVP (roadmap phase 1)
**Backend**
- Payment confirmation model: status machine + `confirm/cancel` endpoints; manual-approval fallback **labelled unverified/unconfirmed** with manager approval + reconciliation report; terminal/gateway adapter interface (M; provider work depends on D2).
- Returns: reason codes, disposition (restock/damaged), refund-to-credit option, return-without-receipt policy (M).
- Per-line tax, per-line cost snapshot, `isCustom` lines, coupon code in quote, discount limits per role (M–L).
- Open-shift: previous-close variance, note, denominations (S).
- Tests as above.

**App**
- Open shift, Home, Smart checkout (done in 3a/3b — resume), product detail sheet, custom item, discount + coupon with manager approval sheet, payment (card state machine), refund/return flow (start → items → method → success), orders + order detail + timeline, invoice, offline/sync status page (merge Needs attention), receipt print/share (M each; total L).
- Barcode: torch + continuous mode (S).
- Dependencies: G1 envelope, payment entity. Risks: terminal integration is the long pole; keep manual-approval fallback shippable first.

### G3 — Retail operations (roadmap phase 2)
**Backend**
- POS-token access (PA + MGR) to existing stock-count / transfer / PO / receive / adjust endpoints (S–M; today seller-JWT only).
- POS customers (CRUD, search by phone), ledger tender, loyalty earn/redeem hooks (L).
- Supplier payables ledger + supplier payments (M).
- Expense + categories + approvals + daybook (M–L).
- Catalog access per D3 (option 2: M; option 4 adds modifiers/price books: L).
- Attendance/clock-in (S–M).

**App**
- Stock: overview, list, detail, count (+ scan), adjustment, transfer + detail, low stock, batches/expiry, movement history (L).
- Customers: directory, profile, add, loyalty, credit (L).
- Suppliers, POs, create PO, receive stock, supplier payment (L).
- Expenses: dashboard, add, detail, cash movement, daybook (M).
- Team: staff, profile, attendance, clock-in (M).
- Products & pricing per D3 (read-only: S; full: L).
- Dependencies: G1 movement ledger, G2 payment/refund entities. Risk: stock-count/transfer UX on small phones; PO receive offline policy (recommend online-only).

### G4 — Intelligence & control (roadmap phase 3)
**Backend**
- Reports: sales, profit, product, category, tax, payment, cashier, hourly (M–L; profit/tax depend on G2 per-line fields).
- Granular roles/permissions + presets + limits; keep manager-PIN approvals separate (M–L).
- Tamper-evident audit (hash chain or append-only role) + export (M).
- Terminals/hardware registry, notifications, integrations (accounting export, API keys) (M, optional).
- Backup/sync status endpoint (S).

**App**
- Business pulse, 8 report screens with date strip, charts (CustomPainter), export (L).
- Roles & permissions editor, security, backup & sync, hardware, receipt designer, tax rules, payments setup, notifications, help, about (L).
- Dependencies: G2/G3 data. Risk: charts without a package.

### G5 — Release QA against roadmap acceptance targets
- Common product to cart ≤ 2 taps (instrumented test); barcode-to-cart < 300 ms (profile on target hardware; HID path measurable, camera path unverified); double-submit protection on Charge/Refund/Void; kill-app-mid-sale restore; offline → sync parity (incl. airplane-mode soak); daybook reconciles to transactions for a seeded day; no-training checkout usability test with an experienced cashier.
- Accessibility pass: 4.5:1 contrast re-proof, 44/48 px targets, text scale 1.0–2.0 (Phase 5 item from the redesign brief), TalkBack/VoiceOver on the checkout path.
- Real-backend e2e (`tool/run_real_e2e.sh`), Android manual checklist (the Android emulator was explicitly skipped in earlier phases; **real-device Android still unverified**), store-submission checklist refresh, go/no-go doc.

---

## 6. Decisions needed

| ID | Decision | Options | My recommendation |
|---|---|---|---|
| **D1** | Minor-units migration now? | (a) Full migration of stored money (L, high risk, shared variant price coupling). (b) New entities minor-units-native + `*Minor` dual-write on Sale/Session/Refund; defer variant/storefront. (c) Never. | **(b).** The server already computes in integer minor units with exponent snapshots; the real exposure is float storage in new tables and parity bugs. Revisit full migration after G5 with a storefront-wide plan. |
| **D2** | Card / terminal / Raast integration | (a) Keep reference-only but label **"recorded, not confirmed"**, require manager approval + daily reconciliation (manual-approval fallback — **unverified as a risk-acceptance for your merchants**). (b) Integrate a bank/acquirer POS terminal or a payment-gateway SDK (vendor, country availability and fees **unverified**; our existing Stripe use is for POS **plans**, and I did not verify Stripe merchant availability in Pakistan). (c) Raast/QR via a bank or aggregator API (**unverified**; requires a partner and likely a merchant account per store). | **Ship (a) in G2** (honest status, no fake confirmation), design the Payment entity + adapter interface so (b)/(c) slot in later; choose vendor after you pick a bank/acquirer. |
| **D3** | Catalog ownership | §2.3 options 1–4. | **Option 2 (POS-scoped routes, PA + MGR) wrapping existing services; add modifiers and price books as new collections only when you confirm they're needed.** Option 3 if you want the MVP out faster (Products stays read-only). Never option 1 on a shared device. |
| **D4** | 5-tab nav mapping | §4.6 | Adopt as written; Home tab shows only role-appropriate content; Products tab becomes part of Stock. |
| **D5** | Current-only screens | §1.12 | Keep Needs attention, plan status, delete account, owner gate; merge held/audit/devices/session/stock-activity/range reports; remove dead modules. |
| **D6** | Shift vs clock-in | Our "shift" = register cash session. Blueprint "Team & Shifts → Clock in / Attendance" = staff time. | Build attendance as a separate light feature in G3; do not overload sessions. |
| **D7** | Dark mode | Blueprint is light-only; ours has dark and an always-dark PIN/owner-gate | Keep dark mode, re-based to the brand ink; confirm. |
| **D8** | Fonts and charts | Bundle Manrope + DM Sans (verify `tnum`); charts via CustomPainter (no new packages) | Approve; revisit if charts get complex. |
| **D9** | Logo masters | Need vector/≥1024² mark and a light wordmark; confirm canonical coral (`#DC7758` vs `#D97757`) | Request from Sir Atiq before G1 icon work. |
| **D10** | Blueprint items that conflict with existing decisions (ground rule 3) | see below | see below |

**D10 — conflicts with ground rule 3 / shared-device model:**
1. **Business-pulse Home ("Good morning, Atiq", owner KPIs)** assumes a personal owner device; on a shared cashier device it must be role-gated (owner gate / manager PIN). Fine with §4.6, but it changes the "landing screen" from Sale.
2. **`payments-settings`, "Integrations", "Backup & sync"** could be read as a place to buy/upgrade plans or connect gateways — **no purchase UI in the app** (plan purchase stays web-only); plan status remains read-only.
3. **Permissions screen asks for Location** ("Branch security checks") — we have no location feature; recommend dropping it (privacy + store review).
4. **Customer credit / store credit / Raast** tenders add payment methods beyond today's cash/card/other; POS sales stay gated by **POS plan only**, and totals/tax/discount/stock stay **server-authoritative** — all new tenders must follow this (no client-side rule faking). The blueprint's "Coupon" must validate server-side.
5. **Roles & permissions / Team directory in-app** vs today's owner-only management behind the owner gate — keep it behind the owner gate/PIN (no role escalation from a cashier session).
6. **Mobile/OTP/biometric login** — excluded per rule 2.
7. **Blueprint "Register device" details (printer model field)** overlap device setup — keep our device-token flow.

---

## 7. Gaps in this audit (what I did not verify)

- Per-screen UI states (R5) are from a keyword grep of module folders, not from running every screen.
- Not read: `voidSale` stock handling, lot/batch restoration on refund, `expectedCash` after refunds in the close path, `StockLot` cost fields, storefront analytics.
- `toStringAsFixed` calls (14) were counted, not individually classified as currency-aware or not.
- Font `tnum` support for Manrope/DM Sans: **not inspected** (4.3).
- Transaction/replica-set availability in dev and prod Mongo (needed for multi-variant atomic decrements): **not checked**.
- Barcode camera decode, Android devices, and terminal hardware were never verified in the earlier phases and are still unverified.
- Prior docs under `pos/docs/` (`phase5_production_readiness_audit.md`) are partly stale; where they disagree with code, code was used.

## 8. Phase 3b status (paused)

Built and verified before the pause: read-only `lastOutcome/lastReceipt` on PosHomeController; extracted/restyled variant picker; two-pane layout ≥ 700 px; held-sales header button; quick-amount chips; swipe-to-remove undo; Hold/Charge via sheets; `AppBottomSheet.showGet`; success view. `flutter analyze` clean; full suite 573 passing (before one later fix); new iOS-simulator integration test `phase3_sale_flows_test` (park → resume → split → success, quote-changed confirm) **passing**. One bug found and fixed: the phone cart sheet stayed expanded after the cart emptied. **Not done:** re-run of `pos_checkout_flow_test` on the simulator after that fix, dev-stack manual flows, the screenshot matrix, the Android manual-checklist additions, and the 3b report. These remain on hold per your instruction; the 3b work will also need to be re-skinned with the new tokens in G1.
