# G4 close-out (G4.0 – G4.6 + G4.8 hardening; G4.7 not started)

Branch `feature/jamibranch` in both repos. Nothing merged, nothing deployed, production not touched. G4.7 (customer credit / khata) waits for the owner's go-ahead (G4_PLAN §0b). FBR transmission stays out (decision 7; `FBR_PLAN.md` unchanged).

## 1. What G4 delivered
| Sub-phase | Backend (solvexo-api) | App (pos) |
|---|---|---|
| G4.0 Time zone + pulse | 26b6e21 — store time zone for every day boundary (reports, dashboard, lists, daybook, attendance, roster); business pulse | 0d00409 — pulse + Home card, store time zone screen, daybook by store day |
| G4.1 Eight reports | 26b6e21, b767fcc — sales (+ previous period's days), profit (gross + after expenses; supplier payments never subtracted), products, categories, tax (= invoices − credit notes), payment mix, cashier (+ hours), hourly; Orders by store day | 0d00409, 66fadfd — hub + 8 reports (CustomPainter charts), compare, CSV / PDF export, a day opens that store day's sales |
| G4.2 Roles & permissions | a5bbe42 — matrix editable per store (owner), pinned actions, owner never removable, preview diff, versioning, reset, audited | 66fadfd, ee7eecc — editor (preview → save with version, VERSION_CONFLICT → reload, reset), managers read, owner unlock on a till |
| G4.3 Audit seals | 11ac7ad — nightly seal per store-day over 11 append-only collections, chained, lease-protected; verify endpoint + CLI | 66fadfd — activity log filters (store days / type / person), CSV, Integrity panel |
| G4.4 Settings hub | 5aebddc — receipt options, in-app alerts, security, sync status | 66fadfd, ee7eecc — hub, receipt designer (live preview; switches drive thermal + PDF receipts), notifications, security (auto-lock + lock in background on the till), backup & sync |
| G4.5 Products & pricing | d4c7998, ddab574 — modifiers + price books priced by the server at sale / quote (offline never refused, verified), product / variant create, categories, CSV import | 8cd84e1 (sale path), 3adb714 (admin), f5c609c — modifier sheet, price book at checkout, admin screens |
| G4.6 Stock & shift | 1ac0998 — opening / closing notes & coins (DENOMINATION_MISMATCH), last close, expiry buckets + lot write-off, transfers through the matrix, low stock → draft PO | 3adb714, f5c609c — counters at open / close, last-close card, transfers, expiring lots + write-off, Draft PO |
| Contract + flows | 02b5df7 — money-contract guard on the G4.2–G4.4 responses | ee7eecc — `integration_test/g4_flow_test.dart` (real API) |

**Performance (G4.1):** 100,000 sales / 250,000 lines / 3,000 returns over 90 days: every report < 2 s locally (slowest: cashier, 1.5 s) → no rollups needed (`pos-reports.perf.spec.ts`, `RUN_PERF=1`).

**Tests:** app — 218 tests in the nine G4 files (`g40_*`, `g42_g44_admin`, `g45_sale_pricing`, `g45_catalog_admin`, `g46_stock_shift`), plus receipt-options, OwnerRoutes and fixture updates in older files; the full suite is green in CI. Backend — `pos.g40/g42/g43/g44/g45/g46.integration.spec.ts`, `pos-day.util.spec.ts`, `pos-pricing.util.spec.ts`, all green in CI. Real backend on the iOS simulator: the G4 flow (3 scenarios) and the 11 core flows pass.

**Defects found and fixed during G4** (all with a test):
1. G4.5 priced a sub-minor list price before × qty (0.125 × 3 → 39 instead of 38) — CI caught it through the G1b money test (ddab574).
2. The owner could not edit roles, store settings or the time zone from a registered till: those routes were missing from `OwnerRoutes`, so the owner's session was never sent and the server answered as the PIN-signed manager — found only by the real-backend run (ee7eecc).
3. The CSV import report read the wrong keys (always "0 failed") — the server's `BulkImportData` shape is now read (3adb714).
4. The roles editor's save bar overflowed on a phone; cash fields showed a fixed "$" whatever the store's currency (66fadfd, f5c609c).
5. The CSV import pulled in `file_picker`, which is approved for KYB only (the store-release guard test failed CI) — the import is paste-only now (f5c609c).

## 2. Blueprint screens — status
Screenshots: phone light + dark in `g4_0_g4_1_screenshots/phone` and `g4_2_g4_6_screenshots/phone`; tablet in `g4_0_g4_1_screenshots/tablet`.
- **Reports (G4.0/G4.1):** hub, pulse + Home card, 8 reports, export, time zone, a day's sales — done.
- **Roles & permissions (G4.2):** done; presets (Owner-operated / Small team / Strict) from the original plan were **not built** (reset to defaults only).
- **Activity log + integrity (G4.3):** done; a row does not drill into its document yet.
- **Settings hub (G4.4):** store profile (links to tax profile), time zone, payments setup (KYB), registers & devices, receipt designer, printer & sound (existing screen), roles, security, activity log, notifications, backup & sync, needs attention — done. **Not built:** hardware test pages, integrations (accounting export, API keys), help, about.
- **Products & pricing (G4.5):** checkout options + price books, admin hub, modifier groups, price books + assign to a customer, new product + add / archive variant, categories, CSV import (paste) — done. **Not built:** product images, editing an existing product's details beyond the existing catalog screen.
- **Stock & shift (G4.6):** open / close notes & coins, last close, transfers, expiring lots + write-off, Draft PO — done.

## 3. Open items (not finished or not verified)
1. **G4.7 customer credit (khata)** — not started; needs the owner's go-ahead.
2. **Not enforced, so not shown:** the security settings `requirePinForReprint` and `hideCostsFromManagers` are stored by the server but nothing enforces them; the app leaves them off the screen rather than fake a rule.
3. **Receipt designer:** logo, QR, receipt barcode and points-balance switches are saved but the thermal / PDF receipt does not print those elements yet (the screen says so); the paper width is the preview's only — each till keeps its printer's size.
4. **CSV import from a file** — needs the owner's approval to use `file_picker` outside KYB; until then the CSV text is pasted.
5. **Price-book dates** are picked as whole days in the **device's** time zone (midnight), not the store's; matters only when they differ.
6. **Catalog admin names:** modifier groups and price books show product / variant names from the first 300 products; beyond that they may show "Product …id" (the API returns ids only).
7. **Assign a price book:** the customer's current book is not shown (the customer model has no `priceBookId` field yet).
8. **Audit seals on the dev stack:** no sealed day existed during the real-backend run (the nightly job had not run there); the comparison (ok / changed / broken chain) is covered by the backend tests only.
9. **Draft PO in the real-backend run** returned `NOTHING_LOW` for the first supplier (the "draft created" path is covered by backend and widget tests).
10. Carried from G3: no real device run yet; Raast on the mock provider; production steps not run.

## 4. Production steps — added to `G1B_RUNBOOK.md` §10
0. API first, then the apps; additive only — old builds keep working without the new screens.
1. **New collections** `posmodifiergroups`, `pospricebooks`, `posauditseals` (unique `storeId + day`) — created by Mongoose on first start, nothing to run. `posauditseals` is append-only: grant insert-only like the other ledgers if the DB role is restricted.
2. **`POS_AUDIT_SEAL_CRON`** (optional; default `20 1 * * *`, UTC) — the nightly seal. One instance seals (lease `pos:audit-seal`); every store's day is sealed in its own time zone. The first night seals every past day since the store's first record (can take minutes on big stores — run in a quiet window). Verify a store from a shell: `MONGO_URI=… TS_NODE_BASEURL=./dist node -r tsconfig-paths/register dist/scripts/pos-audit-verify.js <storeId> [from] [to]` (the compiled script, after `npm run build`; `ts-node --transpile-only` cannot load the schemas) (exit 1 = a changed day).
3. **Store time zone:** `Store.timezone` (default from the country → `Asia/Karachi` for PK). Reports now count days in the store's zone instead of the server's clock — numbers for "today" change for stores whose zone differs from UTC. Tell owners.
4. **New matrix actions** (catalog.*, settings.permissions.*, settings.store.edit, audit.verify, inventory.transfer.*, inventory.writeoff): defaults apply; stores have no overrides yet.
5. **Smoke after deploy:** as the owner on a till: Store settings → Security → change auto-lock; Roles → preview a change → save → reset; Products & pricing → a modifier group on a test product → sell it (the receipt line names the option); open a shift counting notes, close it, open again — the last-close card shows the variance; Activity log → Check this period.
6. **Rollback:** redeploy the previous API; the new collections stay (unread). Apps: the previous build keeps working.

## 5. Real-device checklist — additions to G3_CLOSEOUT §5
**Reports (G4.0/G4.1)**
- [ ] Each report with real data; compare on / off; CSV and PDF share sheets (Android + iPhone); tablet two columns; a day of the sales report opens that day's sales.
**Roles, audit, settings (G4.2–G4.4)**
- [ ] Manager sees Roles read-only; "I am the owner: unlock to edit" → password → edit → review → save; a second device with the screen open gets "changed on another device".
- [ ] Activity log filters + CSV share; Check this period after the first nightly seal.
- [ ] Receipt designer: switch off address / tax ID / cashier / customer, add a promotion line → print a real receipt on 58 mm and 80 mm; turn back on.
- [ ] Security: auto-lock 1 min locks the till; lock when the app is left (home button / screen off) locks at once.
**Products & pricing (G4.5)**
- [ ] A product with a required size: the sheet opens on tap and on barcode scan; two sizes are two lines; the printed receipt names the options; a held sale resumes with its options.
- [ ] Price book at checkout; a customer with a book; airplane mode: options still offered from the cached copy and the sale queues.
- [ ] New product with two variants, then sell it; category rename / delete; paste a CSV of 20 products.
**Stock & shift (G4.6)**
- [ ] Open a shift counting notes (PKR set), the last-close card after a short close; close counting notes; a wrong count is refused in words.
- [ ] Transfer between two real locations: send, receive part, receive the rest; cancel another.
- [ ] Expiring lots: write off part of a lot; stock and the ledger follow. Low stock → Draft PO opens in the PO screen.

## 6. G4.8 — hardening

API details for the admin panel: [`G4_8_ADMIN_API.md`](G4_8_ADMIN_API.md). Route table: [`ROUTE_TIERS.md`](ROUTE_TIERS.md) (generated by the backend test).

| Item | Backend | App |
|---|---|---|
| Hide costs from managers | `CostVisibilityInterceptor` (one place, every `/api/pos` response) + `cost-visibility.registry.ts` (global keys, route-scoped keys, a pattern for every minor amount under supply); a scan test fails on an unclassified cost-looking key; `data.costsHidden`; owner always sees cost; setting audited | notices on reports (profit without COGS / margin / after expenses; products / categories without margins), pulse, inventory overview / detail / stock list, PO list / detail, payables — never zeros |
| PIN to reprint | `POST /api/pos/reprints/:storeId`: append-only `posreprintevents` + audit + `sale.reprintCount` in one transaction; distinct numbers for concurrent tills; cashier needs a manager approver token when the setting is on | one `ReprintGate` for receipt / invoice / credit-note prints: records first, asks for the manager PIN on `POS_APPROVAL_REQUIRED`, offline refused when a PIN is required (else "COPY"); prints "REPRINT #n" |
| Route tiers | `pos-route-tiers.ts` declares 142 routes (owner 26, manager-with-limit 68, cashier 45, public 3); the test enumerates Nest's metadata, fails on undeclared / stale routes and on a manager-PIN route declared cashier / public, and writes `ROUTE_TIERS.md` | — |
| Price books in store time | `validFrom` / `validTo` as store days; `validFromUtc` / `validToUtc` / `validFromDay` / `validToDay` / `timeZone` on every book (additive) | in force by the UTC boundaries (offline cache too); the editor sends store days |
| CSV from a file | — | `file_picker` allowed in `csv_file_picker.dart` only (guard test lists exactly two files); .csv only; ≤ 2 MB checked before reading; decoded off the UI thread; paste still works |
| Security screen | — | "Manager PIN to reprint", "Hide costs from managers" (owner edits behind the owner unlock) |
| Receipt designer | — | QR (the digital-receipt link when known), receipt-number barcode (Code 128), points earned / redeemed now print on thermal + PDF; the logo stays saved-not-printed until the masters arrive |
| Currency guard | — | test fails on a hard-coded `$`, `Rs`, ₨ € £ or code+amount in `lib/` outside the money formatter; fixed 5 places |

**Found and fixed during G4.8:**
1. **Cost interceptor crashed sale creation (500 on every sale).** It walked a hydrated Mongoose document's back-references into a stack overflow. The specs used plain objects; only the real-backend run on the simulator showed it. It now walks what the response serializes to and never follows a cycle; covered by a regression test.
2. **The payables aging buckets** (`d30Minor` / `d60Minor` / `d90Minor`) weren't hidden by the first supply key list. They're now covered by a pattern rule, so a new amount under supply can't leak.
3. **Manager-PIN routes called without the PIN token.** The legacy daily / range / register / employee reports and the activity log require a manager PIN on a till, but the app didn't send the employee token, so a manager's Home cards and the G4.3 activity log were refused on a registered till. Fixed in the app; the owner session is used there while it's live.
4. **The tier draft got some writes wrong.** Classifying from code put a few write routes (loyalty settings, approval limits, permissions save / reset, store-settings save, catalog admin, stock-count start, transfer cancel, supplier edit, team corrections) a tier too low; all corrected, and the test now cross-checks the manager-PIN guard. **No server route was found unprotected**: the apparent activity-log gap was already guarded by `@RequireManagerPin`.
5. **The cost-field scan** caught `shippingCostMinor`, `taxCostMinor` and `itemUnitCostMinor`, which weren't in the registry.
6. **The profit report still showed supplier payments (a payables amount) with costs hidden.** The screenshot pass caught it. `supplierPaymentsMinor` / `supplierPaymentsNote` are now hidden, and the app doesn't show the note then.

**Real backend (iOS simulator, dev stack, one at a time):**
- **G4.8 flow:** a past day sealed by the real nightly code verifies; a tampered record shows the day as **changed**; restored, it verifies OK again. A manager with costs hidden gets no cost key in inventory / reports / supply responses; the owner's own login still sees the stock value. Reprint with the PIN rule: cashier refused, manager PIN approves, numbers 1 → 2, a cashier's PIN isn't an approval. A price book from the store's tomorrow switches at the store's midnight (the dev store's zone is UTC while the simulator runs at UTC+5). CSV import from a file.
- **G4 flow:** integrity over 8 sealed days; Draft PO created (seeded low-stock supplier).
- **Core flows:** all 11 still pass.

**Dev seed additions** (`solvexo-api/dev/seed-g48.ts`): "Dev Bakery Supplier" on the low-stock croissant; a past-day record plus the real `sealStore`; `--tamper-seal` / `--untamper-seal` (dev database only, also via the e2e control server).

**Deferred / open (G4.8):**
- **Logo on printed receipts:** waits for the vector / 1024 px masters (on-screen note kept).
- **The receipt QR needs the digital-receipt link,** which the till only has online. A receipt printed at checkout before the link loads, or a reprint made offline, has no QR.
- **No customer points balance on the receipt:** a sale only knows the points earned / redeemed (the balance after the sale isn't in the sale), so those are printed instead.
- **What counts as a reprint:** a tax invoice or credit note printed from the documents screen is always treated as a reprint ("REPRINT #n"), including its first print from that screen.
- **The system file-picker dialog** isn't driven by the automated tests (the file read, the size check and the background decode are).
- **Production:** none of this is deployed. New collection `posreprintevents` (append-only); nothing to run.

**Real-device checklist (additions):**
- [ ] Receipt with QR + barcode + points on a real 58 mm and 80 mm printer: the QR scans to the digital receipt, the barcode scans as the receipt number, nothing is cut off.
- [ ] Reprint as a cashier with "Manager PIN to reprint" on: the PIN sheet, then "REPRINT #n" on paper; offline, the refusal in words.
- [ ] CSV import: pick a .csv from Files (iPhone) and Downloads (Android), a 3 MB file is refused, an .xlsx is refused, the row count shows.
- [ ] A manager with "Hide costs from managers" on: reports, inventory, purchase orders and payables show the notice, never zeros.


## 7. G4.9 — G4 close-out fixes + blueprint gap audit

G4.7 (khata) stays parked. API details: [`G4_8_ADMIN_API.md`](G4_8_ADMIN_API.md) §5–8. Deploy notes: `G1B_RUNBOOK.md` §11. Gap audit: [`BLUEPRINT_GAP_AUDIT.md`](BLUEPRINT_GAP_AUDIT.md).

| Item | Backend | App |
|---|---|---|
| The three cost fields | Traced to every write / read; **all three are purchase-order amounts → cost** (`itemUnitCostMinor`: PO line unit cost; `shippingCostMinor`: shipping the supplier charges; `taxCostMinor`: tax on the PO / supplier bill). None is used for a customer amount, so nothing renamed. `COST_FIELD_DECISIONS` records the reasons; a test holds the registry to them; the scan finds no unclassified field. | — |
| Offline-capable receipt link | `GET /r/s/:storePublicId/:clientKey`: the store slug + the sale's idempotency key. "Receipt is syncing" (no data, refreshes) until the sale arrives; the same single 404 for malformed / unknown / stale / revoked; rate-limited; tier `public` (all four `/r` routes are now declared; 146 routes, public 7). Settings return `storePublicId` + `receiptLinkBase`. The token link keeps working. | The QR on every printed receipt is the offline-built link: at checkout online or offline (queued sales too) and on reprint; the token link only for a sale without a client key |
| Loyalty balance on the sale | `loyaltyBalanceAfterPoints`, from the ledger in the sale's transaction: online customer sales and held sales completed online; absent on walk-ins, loyalty-off stores, offline replays and older sales | "Points balance" printed when present; otherwise earned / redeemed as before; designer preview updated |
| Original vs reprint | Print events get `kind`. The first print of a tax invoice / credit note is the **original** (number 0, no PIN, audited `document_printed`) from whichever screen; later prints are reprint #n; receipts unchanged; concurrent first prints → one original, one reprint; no backfill (older events continue from their highest number). Documents read-out adds `printed`. | Documents screen: the button says "Print original" until the document is printed, then "Reprint"; prints ORIGINAL / REPRINT #n as the server answers; offline: refused when the PIN is required, otherwise COPY (never ORIGINAL — it could not be recorded) |

**Tests:**
- **Backend:** `pos.g49.integration.spec.ts` (10). Updated: the registry spec (decisions), the route-tier spec (public links), and the G4.8 reprint test (the first invoice print is now the original).
- **App:** `g49_close_out_test.dart` (9); updated record shapes in `g48_hardening_test.dart` / `g27_thermal_documents_test.dart`.
- **CI:** green on both repos.

**Real backend (iOS simulator, one run at a time):**
- **Extended G4.8 flow:** all 9 pass.
  - The 5 G4.8 scenarios.
  - **Offline QR:** an offline sale's printed QR answers "Your receipt is syncing" with nothing about the sale; after the queue syncs, the same QR is the receipt; an unknown key → 404.
  - **Points balance:** a customer sale stores the balance (equal to the customer's points after the sale) and prints "Points balance"; a reprint from the sale's detail carries it too.
  - **Original vs reprint:** a new tax invoice printed from the documents screen → ORIGINAL, again → REPRINT #1, and the server's read-out agrees.
  - **Costs hidden:** a manager with costs hidden gets none of the traced PO fields on orders, a PO detail, receipts or payables; the owner sees them.
- **G4 flow:** 3 pass. **Core flows:** 11 pass.
- **Widget-level UI e2e:** passes again. It had been stale since G2.7, waiting for the PIN screen while the app shows the permissions explainer first; the test now taps Continue.

**Screenshots (phone, light + dark):** `g4_9_screenshots/phone`:
- `g49_01_invoice_print_original`;
- `g49_02_invoice_after_original_reprint`;
- `g49_03_credit_note_print_original`;
- `g49_04_receipt_designer_points_balance`.

**Resolved from the G4.8 deferrals:** the offline QR, the points balance, and the documents-screen original-vs-reprint rule.

**Open / deferred:**
- **The digital-receipt link's host comes from `API_PUBLIC_URL`.** On the dev stack it isn't set, so the printed links show the production origin (the e2e opens them by path). It must be right in every real environment (runbook §11).
- **A manager revoking a sale's token link also stops its `/r/s/` link.** It stays stopped: a new token link can be made, but the printed offline QR can't be re-issued.
- **The documents screen shares one print notice** between the invoice and its credit notes ("Printed." carries over). Cosmetic; G5.1.
- **The syncing page and the client-key link** were checked on the simulator only; scanning a printed QR from a real phone is on the checklist.
- **Production:** not deployed. No new collection; `posreprintevents` gets an optional `kind`.

**Real-device checklist (additions):**
- [ ] Airplane mode: ring a sale, print it, scan its QR with another phone → "Your receipt is syncing"; back online, wait for sync, scan again → the receipt.
- [ ] A customer sale prints "Points balance" with the customer's real balance; a walk-in prints no points.
- [ ] From the documents screen: a new tax invoice prints "ORIGINAL", again "REPRINT #1"; a credit note likewise; offline with "PIN to reprint" on, refused in words.

### 7a. Receipt links — recorded decisions and an open question (G5.1)
- **Revoking a receipt link also disables its offline QR, and printed QRs cannot be re-issued.** When a manager revokes a sale's digital-receipt link, the `/r/s/<store>/<client key>` link printed on the paper receipt stops working at once (the same "not available" page), and it stays stopped. A new token link can be created for sharing, but the QR already on paper carries the old client key and cannot be replaced.
- **Open question for Sir Atiq: should the 30-day expiry follow the store's return / warranty window?** A client-key link older than 30 days answers "not available" (`CLIENT_LINK_WINDOW_MS`). A store with a longer return or warranty period may want the printed QR to keep working as long as that period lasts. No code change until decided.
