# G4 close-out (G4.0 – G4.6; G4.7 not started)

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
2. **`POS_AUDIT_SEAL_CRON`** (optional; default `20 1 * * *`, UTC) — the nightly seal. One instance seals (lease `pos:audit-seal`); every store's day is sealed in its own time zone. The first night seals every past day since the store's first record (can take minutes on big stores — run in a quiet window). Verify a store from a shell: `MONGO_URI=… npx ts-node -r tsconfig-paths/register src/scripts/pos-audit-verify.ts <storeId> [from] [to]` (exit 1 = a changed day).
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
