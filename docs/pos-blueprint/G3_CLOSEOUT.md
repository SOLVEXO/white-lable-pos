# G3 close-out (G3.0 – G3.6)

Branch `feature/jamibranch` in both repos. No PRs / merges / deploys / admin UI. Per-sub-phase detail: `G3_0_SUMMARY.md`, `G3_1_SUMMARY.md`, `G3_2_G3_3_SUMMARY.md`, `G3_4_SUMMARY.md`, `PROGRESS_LOG.md`; design: `G3_PLAN.md`, `G3_PERMISSIONS_AND_LIMITS.md`, `G3_STOCK_MOVEMENT_MEMO.md`, `G3_STORE_CREDIT_LEDGER_PLAN.md`. G4 plan: `G4_PLAN.md`.

## 1. What G3 delivered
| Sub-phase | Delivered |
|---|---|
| **G3.0** | permission matrix as data + per-store approval limits (D1/D6); money twins for the supply side; credit-note backfill `CN-B`; cross-till cash-refund attribution; currency + exponent on every money response (contract test) |
| **G3.1** | stock ledger (`StockMovement`, append-only, WAC cost snapshots on sale lines), inventory screens (overview, list, detail, adjust, counts by scan, history, limits) |
| **G3.2** | lots: FEFO at sale, expired lots blocked unless a manager approves, returns/voids back to the original lot, expiring-soon |
| **G3.3** | customers (D8 fields), loyalty (D2), store credit as tender + refund method on the new minor ledger (D3, option B, migration script, mode switch) |
| **G3.4** | suppliers, POs (draft → approved → sent → partially received → received), receipts with WAC + lots + bills, supplier returns + credit, payables + aging, supplier payments (drawer cash-out) |
| **G3.5** | cash in/out with reason categories + limits, expenses (+ private receipt photo), offline queue for cash movements and drawer expenses, daybook that reconciles with shift close (test: USD / JPY / KWD, cross-till refund, void, change, split tender, expense, supplier payment), print 58/80 mm + PDF |
| **G3.6** | attendance by PIN (append-only events, one open record per person, offline-safe, anomalies), manager corrections as new records, weekly roster with conflict checks, attendance report + PDF. No payroll (D7) |

## 2. Blueprint screens — status
done · partial · **deferred → where**

### Inventory (G3.1/G3.2)
| Screen | Status |
|---|---|
| inventory-overview, stock-list, stock-detail, adjustment, stock-count + scan, variance review, inventory-history | done |
| stock-list location filter | partial — filters low / out / expiring; per-location filter **deferred → G4.5** |
| low-stock | done as a list filter; **"create PO draft" hand-off deferred → G4.5** (the PO form exists, the link does not) |
| batch-expiry (buckets expired / ≤7 d / ≤30 d, write-off) | partial — lots + expiry on the detail and an "Expiring" filter; **dedicated bucket screen and write-off action deferred → G4.5** (matrix action `inventory.writeoff` exists) |
| transfer + transfer-detail | **deferred → G4.5** (backend transfers exist on the dashboard; the FEFO suggestion endpoint is ready) |

### Customers (G3.3)
| Screen | Status |
|---|---|
| customers list + search, customer-profile, add / edit (also inline from the picker) | done |
| loyalty (balance, earn, redeem at checkout) | done; tier display **deferred → G4.1** (tiers are stored) |
| store credit: tender, refund method, manual adjust (owner above limit) | done |
| customer-credit **on account** (credit limit, take a payment) | **not built → decision needed in G4 planning** (store credit ≠ credit sale) |

### Supply (G3.4)
| Screen | Status |
|---|---|
| suppliers, supplier-profile, purchase-orders, PO detail, new PO, receive-stock (partial, lots, no-PO receipt), supplier returns, payables, ledger, supplier-payment | done |
| profile "products supplied" list; scan-to-add on the PO form and scan-to-receive | partial → **G4.5** |
| receiving serial-tracked products | **deferred — dashboard only** (the till answers `SERIALS_NOT_SUPPORTED`) |

### Cash (G3.5)
| Screen | Status |
|---|---|
| expenses (period filter, category totals), add-expense, expense-detail (approve / reject, receipt viewer), cash-movement (categories), daybook (day picker, sections, running balance, drill-down, print, PDF) | done |
| receipt **PDF** preview in the app | **deferred → needs a PDF viewer package (ask first)**; images are shown, PDFs say "open on the web dashboard" |
| cash-movement receipt photo | not built (photos are on expenses only) |
| open-shift previous-close variance + denomination counter (G2 deferral) | **deferred → small follow-up before G4.3 (settings/hardware)** |
| expense reversal | not built (a rejection flags, it never moves cash) |

### Team (G3.6)
| Screen | Status |
|---|---|
| clock-in (+ Home card), attendance (own / everyone), correction sheet, shifts (week roster, manager edit, cashier read-only), attendance report + PDF, anomalies under Needs attention | done |
| record view shows raw punches (device vs server time, flags) + correction history (who / when / why / what changed) | done |
| staff-profile additions (last login, sales stats) | **deferred → G4.1 (cashier report)** |
| roles (read-only matrix) | **deferred → G4.2** (editable per store) |
| quick PIN re-auth for clocking | **not built** — the signed-in employee clocks; the screen says so (needs a PIN-login API change) |

## 3. Open items (everything not finished or not verified)
1. **Not verified on any real device** (simulator + widget tests only): camera scan + torch, thermal printing (receipts, tax invoice QR, daybook 58/80 mm), cash-drawer kick, share sheets (daybook PDF, attendance PDF), image picker for expense receipts, airplane-mode behaviour of every offline queue (sales, customers cache, lot preview cache, cash queue, receipt-photo queue, clock queue, roster cache). Checklist in §5.
2. **Receipt photos against real Cloudinary**: storage, expiring links and deletion verified against a fake store in tests and by reuse of the KYB code path only. Test once in staging.
3. **Production not touched** (on hold): runbook steps 1–9 below are prepared, **none run**; dev has 0 legacy store-credit rows (migration rehearsed on 30,000 synthetic rows).
4. Offline approvals are impossible by design: an offline cash-out above the limit queues, conflicts at sync (`POS_APPROVAL_REQUIRED`) and is parked under Needs attention; dismissing a refused cash entry is local only (no server audit endpoint).
5. Attendance: no quick PIN re-auth; anomaly count badge only on the More hub row; the tablet's Needs-attention app bar title renders very large (pre-existing).
6. Expense and attendance receipts / PDFs: no in-app PDF viewer.
7. Real providers: Raast is on the **mock provider** only (real adapter needs sandbox docs); FBR integration not started (`FBR_PLAN.md`, `G4_PLAN.md` §2).
8. Cost twins backfill and store-credit migration **not run on production**.
9. The dashboard's own purchase-order endpoints have no "approve" / "send" action for the new statuses (`approved`, `sent`) — they are only created from the till; the web team may want them (**no admin UI built here**).
10. Carried deferrals (outside G3): catalog create/variants editor/categories CRUD/price books/modifiers/bulk import → G4.5; orders filters by cashier/register → G4.1; email/SMS/WhatsApp receipts.

## 4. Production steps added to `G1B_RUNBOOK.md` — in the order they must run
(Every step: backup first, dry run on a restored copy, then production in a quiet period; details and rollbacks are in the runbook.)
0. Staging deploy · 1. Pre-flight (read-only; its `g3` section counts legacy store-credit rows and supply data) · 2. G1b backfill dry run on a copy · 3. Throughput measurement · 4. Production deploy + backfill window · 5. Burn-in with the flip report (≥ 14 clean days) · 6. Credit-note backfill (`CN-B`) · 7. Store-credit ledger switch (`legacy → migrating → new`; 7a length of the window, what customers see, go / no-go) · **8. Supply-side cost twins backfill** (added now; needed before the G4 profit report is trusted for old stock) · **9. G3.4–G3.6 deploy notes** (API first, then apps; new collections/indexes build on first start; private storage for receipts; new limit `purchaseOrderMinor`; smoke test; rollback).

Release order for the apps: server first, then POS builds; old builds keep working without the new screens.

## 5. Real-device checklist (Android + iPhone) — everything since G2 that was verified only in tests / on the simulator
Run each on **both** an Android phone and an iPhone (and one tablet of each if available). Tick = behaves as written.
**Basics**
- [ ] Install the staging build; device registration; owner login → PIN login (manager and cashier); PIN lock-out message.
- [ ] Light and dark mode on every new screen; text scale 1.0 and 1.5; no clipped text on a small phone.
**Selling and scanning (G2)**
- [ ] Camera barcode scan (add to cart, repeated scans), torch, camera-permission-denied fallback; an external HID scanner.
- [ ] Cash, card, split, Raast QR (mock) sale; receipt print (58 mm and 80 mm); tax invoice with QR at the printed size; cash drawer opens on a cash sale.
- [ ] Return / refund / void: cash from the drawer, another till paying, refund-to-store-credit, credit-note print.
**Inventory and lots (G3.1/G3.2)**
- [ ] Stock count by scan (camera + manual), adjustment above the limit asks for a manager PIN.
- [ ] Lot sale: FEFO text, expired lot blocked, manager PIN override, return goes back to the lot.
**Customers (G3.3)**
- [ ] Add a customer inline at checkout (same phone → same person); store-credit tender (online only, disabled offline); loyalty redeem; refund to store credit.
**Supply (G3.4)**
- [ ] Create → approve (manager) → send a PO; cashier receives part with a lot (no costs visible); date pickers (expiry in the past warns); over-receipt refused; supplier return; pay in cash from the drawer, shift close shows it.
**Cash (G3.5)**
- [ ] Cash in / out with each category; above the limit asks for a manager PIN; expense with receipt photo from the **camera and the gallery**; "View receipt" opens an image and nothing is left in the gallery / cache; PDF receipt shows the web-dashboard hint.
- [ ] Daybook for today: lines in order, "reconciled", refund / sale lines open the sale; print on 58 mm and 80 mm; share the A4 PDF (Android share sheet, iOS share sheet).
**Team (G3.6)**
- [ ] Clock in / break / clock out; double tap does not double count; Home card shows the next shift; roster week view; correction needs a reason; attendance report PDF shares.
**Offline (airplane mode) — the important one**
- [ ] Sale offline → reconnect → synced once, numbers continuous, loyalty points earned once.
- [ ] Cash in / out and a **drawer expense** offline → "Waiting to sync", reconnect → synced in order exactly once; close shift is **blocked** while any is waiting; a movement made offline whose shift was closed meanwhile lands under Needs attention.
- [ ] Receipt photo taken offline uploads after reconnect; the local file is gone afterwards.
- [ ] Clock in / out offline (with real device time) → reconnect → hours correct; an offline clock event with a wrong device clock (set the device **+1 h** and **−1 h**) is flagged for the manager, not lost.
- [ ] Offline the supply / daybook / report screens say "needs an internet connection"; the PO list and roster show "last synced … read only".
**Lifecycle**
- [ ] Kill the app mid-sale and mid-receipt → restored / nothing duplicated; background for 10 min and return; low-battery and low-storage warnings do not crash.
- [ ] Android: back button on every sheet, runtime permissions (camera, storage/photos, Bluetooth printer), split-screen / rotation on the tablet. iPhone: share sheet, camera permission prompt text, safe areas on the Dynamic Island models.
