# Blueprint gap audit — after G5.7

Date: 2026-11-12 (first written after G4.9, statuses updated after G5.1 and G5.7). Documents only; no code changed for this audit.

**Blueprint:** Sir Atiq's package, `Solvexo_POS_UI_Developer_Package`. It contains the README, `DEVELOPMENT_ROADMAP.md` (3 phases, 10 engineering rules, 6 acceptance targets), `app/index.html` (101 routes), the design tokens and the brand assets.

**Method:**
- Every route in the G0 audit (`GAP_AUDIT.md` §1) was re-checked against the app's current routes and the G2 / G3 / G4 close-outs.
- Where a close-out said "deferred", the code was checked to see whether a later phase finished it.

**Statuses:**
- **Done:** built and tested (real-device checks still pending; see §5).
- **Partial:** usable, with the gap named.
- **Missing:** not built.
- **Blocked:** the remaining work waits on something outside our control; the blocker is named.

**Sizes:** S ≈ ≤ 1 day, M ≈ 2–4 days, L ≈ a phase.

## 1. Summary

**101 routes:** Done 94 · Partial 1 · Missing 0 · Blocked 3 · out of scope 3.

| Area | Routes | Done | Partial | Missing | Blocked | Out of scope |
|---|---|---|---|---|---|---|
| 1. Launch & access | 9 | 7 | 0 | 0 | 0 | 2 |
| 2. Sell & checkout | 22 | 22 | 0 | 0 | 0 | 0 |
| 3. Orders & returns | 7 | 6 | 0 | 0 | 1 | 0 |
| 4. Products & pricing | 7 | 7 | 0 | 0 | 0 | 0 |
| 5. Inventory | 11 | 11 | 0 | 0 | 0 | 0 |
| 6. Customers | 5 | 4 | 0 | 0 | 0 | 1 |
| 7. Supply & purchasing | 7 | 7 | 0 | 0 | 0 | 0 |
| 8. Cash & expenses | 5 | 4 | 1 | 0 | 0 | 0 |
| 9. Reports | 9 | 9 | 0 | 0 | 0 | 0 |
| 10. Team & shifts | 6 | 5 | 0 | 0 | 1 | 0 |
| 11. Settings | 13 | 12 | 0 | 0 | 1 | 0 |

**Blocked, by blocker:** FBR 1 (fiscal adapter) · Raast provider 1 · Sir Atiq sign-off on role presets 1.

**After G4.9 → after G5.1:** Done 73 → 85 · Partial 18 → 7 · Missing 3 → 1 · Blocked 5 → 6 (role presets moved to Blocked: decision).

**After G5.1 → after G5.7:** Done 85 → 94 · Partial 7 → 1 · Missing 1 → 0 · Blocked 6 → 3 · Out of scope 2 → 3 (khata: out of scope by product decision; card on an external terminal, receipt logo, integrations done; FBR / Raast / role presets stay blocked on external inputs — see G5_CLOSEOUT "TO ADD LATER").

**Workflows (21 roadmap items):** Done 14 · Partial 4 · Blocked 3. **Engineering rules (10):** Done 8 · Partial 1 · Blocked 1. **Acceptance targets (6):** Done 4 · Partial 2.

## 2. Screen matrix — all 101 blueprint routes

### 2.1 Launch & access (9)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| splash | /splash | Done | — | — |
| welcome (onboarding) | /onboarding (admin-managed slides) | Done | — | — |
| login (mobile + password) | /pos/login (email + password) | **N/A** | Out of scope by decision (rule 2): email login kept | — |
| otp | — | **N/A** | Out of scope by decision (rule 2) | — |
| pin | /pos/pin-login | Done | — | — |
| store-select | /seller/stores (restyled with tokens — G5.1) | Done | — | — |
| device-setup | /pos/device-setup | Done | — | — |
| permissions | /pos/permissions (G2.7) | Done | — | — |
| open-shift | /pos/open-register (notes & coins, last close — G4.6) | Done | — | — |

### 2.2 Sell & checkout (22)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| pos (smart checkout) | /pos/home Sale tab | Done | — | — |
| category-view | category chips on Sale | Done | — | — |
| product-search | search on Sale (+ recent searches) | Done | — | — |
| scan | camera + HID scanner + torch + continuous scan (G5.1) | Done | — | — |
| product-detail | product page (G5.2): photos, details, variants, stock by location | **Done** | — (G5.2: managers edit details, a variant's SKU / cost / reorder point, photos; cost obeys hide-costs) | — |
| variants (& modifiers) | option sheet + modifier groups (G4.5) | Done | — | — |
| custom-item | custom item with manager limit (G2.4) | Done | — | — |
| cart | cart panel / phone cart | Done | — | — |
| discounts | keypad + manager token (G2.4) | Done | — | — |
| coupon | online-only coupons (G2.4) | Done | — | — |
| customer-attach | picker + inline add (G3.3) | Done | — | — |
| park-sale | Hold | Done | — | — |
| parked-sales | /pos/held-sales | Done | — | — |
| payment | payment sheet | Done | — | — |
| cash-payment | cash keypad + quick amounts | Done | — | — |
| card-payment | card on an external bank terminal with the slip's approval code (G5.4) | **Done** | Approval code required live when the store switch is on, on the shift close / payments report, referenced by refunds. In-app card acceptance (gateway) waits for a provider (interface + mock, flag off) | — |
| split-payment | split tender | Done | — | — |
| credit-payment (store credit) | store-credit tender (G3.3) | Done | — | — |
| payment-success | sale success view | Done | — | — |
| receipt | thermal / PDF receipt (QR from RECEIPT_PUBLIC_URL, barcode, points balance, store logo, fiscal block) | **Done** | — (G5.6 logo printed as a dithered bitmap; G5.5 "Fiscal pending" / FBR number + QR; G5.3 e-mail / SMS / WhatsApp) | — |
| print-share | print + share sheet + WhatsApp to the customer's number + e-mail / SMS (G5.3) | **Done** | In-app PDF *viewer* deferred (needs a package); the PDF is shared and previewed by the system share sheet | — |
| offline | queue, banner, Needs attention, encrypted queue | Done | — | — |

### 2.3 Orders & returns (7)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| orders | /pos/orders (search by receipt / OFF number; cashier / register filters — G5.1) | Done | — | — |
| order-detail | /pos/sale-detail | Done | — | — |
| invoice (tax invoice) | /pos/tax-invoice + thermal + ORIGINAL / REPRINT + fiscal block (G5.5) | **Blocked** (FBR) | Fiscal provider interface, append-only records, offline "Fiscal pending", retry sweep and the printed block work with the mock; the real PRAL / integrator adapter needs the documents in FBR_INTEGRATION_NEEDS.md | L |
| return-start | /pos/return | Done | — | — |
| return-items | by line + qty, restock flag | Done | — | — |
| refund-method | original tenders or store credit | Done | — | — |
| refund-success | return recorded + credit note | Done | — | — |

### 2.4 Products & pricing (7)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| products | /pos/products, /pos/catalog | Done | — | — |
| catalog-product | catalog edit + product page edit (G5.2) | **Done** | — (name, description, category, status; variant SKU / cost / reorder point; photos) | — |
| product-form | new product + variants (G4.5) + photos on the product page (G5.2) | **Done** | — | — |
| categories | categories CRUD (G4.5) | Done | — | — |
| modifiers | modifier groups (G4.5) | Done | — | — |
| pricebook | price books, store-day validity (G4.5/G4.8) | Done | — | — |
| bulk-import | CSV paste + file (G4.5/G4.8) | Done | — | — |

### 2.5 Inventory (11)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| inventory-overview | /pos/stock | Done | — | — |
| stock-list | /pos/stock/list (+ per-location filter — G5.1) | Done | — | — |
| stock-detail | /pos/stock/item (lots, expiry) | Done | — | — |
| stock-count | /pos/stock/count + variance review | Done | — | — |
| stock-count-scan | scan in count | Done | — | — |
| adjustment | adjust sheet + reasons | Done | — | — |
| transfer | /pos/inventory/transfers (G4.6) | Done | — | — |
| transfer-detail | send / receive part / cancel (G4.6) | Done | — | — |
| low-stock | filter + Draft PO (G4.6) | Done | — | — |
| batch-expiry | /pos/inventory/expiry + write-off (G4.6) | Done | — | — |
| inventory-history | /pos/stock/movements | Done | — | — |

### 2.6 Customers (5)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| customers | /pos/customers/directory | Done | — | — |
| customer-profile | /pos/customers/profile (balances, points, tier) | Done | — | — |
| add-customer | add / edit, inline from the picker | Done | — | — |
| loyalty | earn / redeem / reverse, tier, balance on receipt (G4.9) | Done | — | — |
| customer-credit (on account / khata) | — | **Out of scope (product decision)** | Khata removed from the POS scope permanently (G5.2 brief); store credit stays. The POS app has no khata entry point. Main's separate `src/khata` backend module (not POS) is untouched — see G5_CLOSEOUT | — |

### 2.7 Supply & purchasing (7)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| suppliers | /pos/supply/suppliers | Done | — | — |
| supplier-profile | /pos/supply/supplier (+ products supplied — G5.1) | Done | — | — |
| purchase-orders | /pos/supply/orders | Done | — | — |
| purchase-order-detail | /pos/supply/order | Done | — | — |
| new-purchase-order | /pos/supply/order-form (+ scan to add — G5.1) | Done | — | — |
| receive-stock | /pos/supply/receive (partial, lots, no-PO, scan to receive, serial numbers — G5.2) | **Done** | — (one serial per unit, unique, same transaction; an older till gets SERIALS_NOT_SUPPORTED) | — |
| supplier-payment | payables + ledger + payment | Done | — | — |

### 2.8 Cash & expenses (5)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| expenses | /pos/cash/expenses | Done | — | — |
| add-expense | with receipt photo | Done | — | — |
| expense-detail | /pos/cash/expense (approve / reject) | **Partial** | PDF receipts open only on the web (an in-app PDF viewer needs a package — ask first) | S |
| cash-movement | /pos/cash (categories, slip photo — G5.1) | Done | — | — |
| daybook | /pos/cash/daybook (print, PDF) | Done | — | — |

### 2.9 Reports (9)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| reports-home (business pulse) | /pos/pulse + Home card | Done | — | — |
| sales-report | /pos/reports | Done | — | — |
| profit-report | profit (costs hidden for managers — G4.8) | Done | — | — |
| product-report | products | Done | — | — |
| category-report | categories | Done | — | — |
| tax-report | tax | Done | — | — |
| payment-report | payments | Done | — | — |
| cashier-report | cashiers | Done | — | — |
| hourly-report | hourly | Done | — | — |

### 2.10 Team & shifts (6)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| staff | /pos/team/roster, /seller/pos-management | Done | — | — |
| staff-profile | team members → profile (last login, clocked in, sales — G5.1) | Done | — | — |
| roles | /pos/roles (editable matrix, per-store limits — G4.2) + role presets (G5.6) | **Blocked** (Sir Atiq sign-off) | Three presets built and applicable (owner, preview, audited) but labelled **proposed** — ROLE_PRESETS.md awaits sign-off | S |
| attendance | /pos/team/attendance + corrections + report | Done | — | — |
| shift-summary | /pos/session-report, history | Done | — | — |
| clock-in | /pos/team/clock + Home card; clock someone else with their PIN or a manager's (G5.4) | Done | — | — |

### 2.11 Settings (13)

| Route | App screen | Status | What is left | Size |
|---|---|---|---|---|
| settings (hub) | /pos/settings-hub | Done | — | — |
| store-profile | store profile + tax profile | Done | — | — |
| register-settings | registers & devices | Done | — | — |
| payments-settings | Payments setup (G5.4): KYB status, test-mode badge, Raast on / off, card terminal switch | **Blocked** (Raast provider) | Screen done against the mock; PayFast / 1LINK adapters are typed TODOs needing sandbox docs | M |
| tax-settings | /pos/tax-profile | Done | — | — |
| receipt-settings | receipt designer + logo upload / preview (G5.6) | **Done** | — | — |
| notifications | /pos/settings/notifications | Done | — | — |
| hardware | printer & sound + Hardware check (test page, drawer, scanner — G5.1) | Done | — | — |
| integrations | Integrations (G5.7): e-mail / SMS / fiscal switches, accounting CSV, API keys | **Done** | — (provider-backed items show their status; see TO ADD LATER) | — |
| security | /pos/settings/security (auto-lock, PIN to reprint, hide costs) | Done | — | — |
| backup-sync | /pos/settings/backup-sync + Needs attention | Done | — | — |
| help | Help (static, shipped with the app — G5.1) | Done | — | — |
| about | About (version, build, store id, environment, licences — G5.1) | Done | — | — |

## 3. Workflows — roadmap phases

| # | Workflow | Status | What is left | Size |
|---|---|---|---|---|
| 1.1 | Authentication, PIN and store / register selection | Done | (store-select restyle: §2.1) | — |
| 1.2 | Opening shift and cash float | Done | notes & coins, last close (G4.6) | — |
| 1.3 | Product search and barcode entry | Done | continuous scan (G5.1); latency on real hardware is an acceptance measurement (§3) | — |
| 1.4 | Cart, taxes, discounts and customer attachment | Done | server-priced, per-line tax, coupons, price books, modifiers | — |
| 1.5 | Cash and card payments | **Blocked** (Raast provider, card gateway) | cash, split, store credit, card on an external terminal with approval code (G5.4), Raast (mock) done; real Raast adapter + in-app card gateway need providers | M |
| 1.6 | Receipt printing and sharing | **Done** | logo, WhatsApp, e-mail / SMS, RECEIPT_PUBLIC_URL done (G5.2–G5.6); in-app PDF viewer deferred (package) | — |
| 1.7 | Orders, returns and refunds | Done | (orders filters: §2.3) | — |
| 1.8 | Basic products and stock on hand | Done | | — |
| 1.9 | Offline sale queue and reliable synchronisation | Done | encrypted queue, idempotent replay, offline receipt link (G4.9); airplane-mode run on a real device pending | — |
| 2.1 | Stock counts and adjustments | Done | | — |
| 2.2 | Transfers between locations | Done | | — |
| 2.3 | Customers, loyalty and credit ledger | **Done** | customers, loyalty and store credit done; credit on account (khata) is out of scope by product decision | — |
| 2.4 | Suppliers and purchase orders | Done | scan-to-add, products supplied (G5.1) | — |
| 2.5 | Receiving stock | **Done** | scan-to-receive (G5.1), serials at the till (G5.2) | — |
| 2.6 | Expenses and daybook | **Partial** | photo on cash movements done (G5.1); in-app PDF receipt viewer (package approval) | S |
| 2.7 | Staff shifts and attendance | Done | clocking someone else with their PIN or a manager's (G5.4) | — |
| 3.1 | Sales, profit, tax and payment reports | Done | (FBR-filed tax figures: blocked with FBR) | — |
| 3.2 | Product and category performance | Done | | — |
| 3.3 | Cashier performance | Done | | — |
| 3.4 | Roles and granular permissions | **Blocked** (Sir Atiq sign-off) | presets built as proposed (G5.6); sign-off pending | S |
| 3.5 | Hardware, integrations, audit logs and backup controls | **Done** | integrations (G5.7) | — |

**Workflows (21):** Done 14 · Partial 4 · Blocked 3 · Missing 0.

### Non-negotiable engineering rules

| Rule | Status | Note |
|---|---|---|
| Money in the smallest unit, never floating point | **Partial** | Every write path stores minor units next to the decimals, and the API answers in minor units with currency + exponent. **Reads still use the decimals until the G1b read flip (step f)**, after the 14-day burn-in on production. |
| Immutable audit reference for each sale, payment, refund, stock movement | Done | Append-only ledgers, audit rows in the same transaction, nightly sealed hash chain (G4.3) |
| Payment success from a confirmed gateway / terminal | **Blocked** (Raast provider, card provider) | Raast: confirmed by the provider, but only the mock exists. Card: recorded as unverified. |
| Retries never duplicate payments, orders or stock movements | Done | Idempotency keys end to end; unique indexes |
| Every list has loading, empty, error, offline, success states | Done | Design-system list states; checked per screen in the phase shots |
| Offline transactions encrypted locally, reconciled idempotently | Done | Queue cipher; replay by the same key |
| Cashier permissions separate from manager approvals | Done | Permission matrix + per-store limits + approver tokens; route tiers (G4.8) |
| Tax, discounting and stock deductions server-authoritative | Done | The server quotes and recomputes; the till never decides a total |
| Destructive / high-risk actions confirmed and audited | Done | |
| Branch, register, cashier and shift on every transaction | Done | |

### Acceptance targets

| Target | Status | Note |
|---|---|---|
| Common product to cart in ≤ 2 taps | Done | |
| Barcode-to-cart feedback < 300 ms on supported hardware | **Partial** | Not measured on real hardware |
| Payment button protected from double submission | Done | |
| Interrupted sale restorable after restart | Done | |
| Daily cash reconciliation traceable to every transaction | Done | Daybook |
| Core checkout usable without training | **Partial** | Needs a hallway test with a real cashier |

## 4. Proposed next phases

Ordered by value; each phase is one stop.

**G5.1 + G5.4: done (2026-11-11)** — see `G5_CLOSEOUT.md`. Left from that list: role presets (decision), WhatsApp to a number (url_launcher).

**G5.2: Catalog depth (M).**
- Product page at the till (image, stock by location);
- editing an existing product's details and variants;
- product images. Needs a decision on product media storage (the storefront's images vs till uploads).

**G5.3: Receipt delivery and documents (M).**
- E-mail / SMS / WhatsApp receipts (needs a provider decision: cost per message, templates);
- in-app PDF viewer (needs package approval).

**G5.5: Integrations (L).** Accounting export (CSV / Xero / QuickBooks?) and API keys. Needs a product decision on scope first.

**Blocked tracks**, started as soon as the blocker clears:
- **Khata:** out of scope by product decision (G5.2 brief) — not a track any more.
- **FBR:** scaffolding done (G5.5: provider interface, mock, append-only records, "Fiscal pending", retry); the real adapter waits on the documents in `FBR_INTEGRATION_NEEDS.md`.
- **Raast provider:** on sandbox docs. A real adapter replaces the mock behind the same interface.
- **Card gateway (in-app):** on a provider choice (interface + mock, flag off). Card on an external terminal is done (G5.4).
- **App icon masters:** see `APP_ICON_MASTERS.md` (receipt logo printing is done — each store uploads its own).

**G6: Release QA:**
- the real-device checklist (§5.3);
- the acceptance-target measurements (§3);
- staging deploy;
- then production per §5.

## 5. Everything still needed before production

### 5.1 The G1b read flip
Reads still use decimals.
- Step **f**: switch reads to the minor-unit twins. It isn't built yet and needs explicit approval.
- It comes after runbook step 5: **≥ 14 clean days** of the flip report on production with every path ✔.

### 5.2 Runbook (`G1B_RUNBOOK.md`): none run yet
1. **§0 Staging deploy** of the API and apps; verify the version.
2. **§1 Pre-flight** (read-only user + script) on production.
3. **§2 Backfill dry run** on a restored copy of production.
4. **§3 Throughput measurement** → agree a window.
5. **§4 Production deploy + minor-unit backfill:** fresh snapshot first; smoke one sale + one refund.
6. **§5 Burn-in:** the flip report daily for ≥ 14 days → request approval for step f.
7. **§6 Credit-note backfill** (`CN-B` series): copy first, then production, only if candidates exist.
8. **§7 Store-credit ledger switch** (option B, `migrating` window).
9. **§8 Supply cost twins backfill:** copy, then production.
10. **§9 – §11 deploy notes:**
    - new collections and insert-only grants (receipts, supplier ledger, expenses, attendance, `posauditseals`, `posreprintevents`);
    - `POS_AUDIT_SEAL_CRON` on one instance;
    - store time zone notice to owners;
    - **`API_PUBLIC_URL`** set correctly and the `/r/s/` proxy rule (G4.9);
    - private storage for expense receipts;
    - new approval limit and matrix actions;
    - smoke tests.

### 5.3 Real-device checklist (Android + iPhone): nothing ticked yet
- **G2 close-out §7 (setup, eight areas):**
  - camera barcode; KYB documents;
  - screenshot blocking; wake lock on the QR screen;
  - printing on 58 / 80 mm (Bluetooth Classic, BLE, network 9100);
  - offline → sync in airplane mode; auto-lock;
  - returns and documents.
- **G3 close-out §5 (19 items):**
  - camera + torch; thermal daybook;
  - cash drawer kick; share sheets; image picker;
  - airplane mode across every offline queue (sales, customers, lots, cash, receipt photos, clock, roster).
- **G4 close-out §5 + §6 (15 items):**
  - reports and exports; roles unlock;
  - activity log + integrity after the first nightly seal;
  - receipt designer on paper; security lock;
  - options at checkout; price books offline; new product + CSV;
  - notes & coins; transfers; write-off; Draft PO;
  - receipt QR / barcode / points on paper; reprint PIN;
  - CSV from Files; costs hidden.
- **G4.9 additions (§7 of the close-out):**
  - an offline receipt's QR scanned from another phone (syncing → receipt);
  - "Points balance" on paper;
  - ORIGINAL then REPRINT #1 on paper.
- **Acceptance measurements:** barcode-to-cart latency; a hallway test of checkout.

### 5.4 Server / CI / Atlas tasks (owner's side)
- **Deploy pipeline:** diagnose before any deploy (open since G2); staging environment with its own Atlas cluster and `API_PUBLIC_URL`.
- **Atlas:**
  - a restorable snapshot policy;
  - a restored copy of production for steps 2 / 6 / 8;
  - a read-only `preflight_ro` user;
  - insert-only grants on the append-only collections;
  - a quiet window for the backfills.
- **Secrets / config per environment:**
  - JWT secret, Redis;
  - Cloudinary private storage (KYB + expense receipts);
  - `POS_AUDIT_SEAL_CRON` on exactly one instance;
  - `STORE_CREDIT_LEDGER` (for the §7 switch);
  - mail / OTP provider.
- **CI:** stays the source of truth.
  - The 10 slug-transliteration tests are still excluded (see `NOTE_slug_transliteration_failures.md`).
  - The real-backend simulator suites run only locally; decide whether to add a macOS CI job.
- **Store submission:** `store_submission_checklist.md` (signing, privacy labels, screenshots) — not started.
- **Providers / documents:**
  - FBR documents;
  - Raast sandbox docs;
  - card provider choice;
  - app icon masters;
  - Sir Atiq's sign-off on the proposed role presets.
