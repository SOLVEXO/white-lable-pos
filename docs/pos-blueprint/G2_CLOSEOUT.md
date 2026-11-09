# G2 close-out report

Branch `feature/jamibranch` in both repos. No PRs, no merges, no deploys, no admin UI. G1b runbook / deploy / backfill remain on hold.
Last pushed: API `b8bdeb9` (seed) on top of `cae520c` (G2.7 backend); app `701f78c`. Earlier summaries: `G2_1_G2_2_SUMMARY.md`, `G2_3_SUMMARY.md`, `G2_4_SUMMARY.md`, `G2_5_G2_6_SUMMARY.md`.

## 1. Decisions from the last review — what was done

### 1.1 OFF- receipt number (decision 1)
**The old tested rule that kept it off the server**
* File `test/offline_receipt_number_test.dart`, test *"NOTHING of it leaks into what is sent to the server: the stored payload has no OFF- number"* (and `test/money_minor_json_test.dart`, which pins the exact queued payload keys).
* Reason it existed (Q7): the `OFF-<device>-<n>` number is only a *printed placeholder*. It must never become an identifier or influence the invoice sequence (which is gap-free and assigned inside the server transaction), so the queued payload — the thing the server replays and fingerprints — was kept free of it.

**How both needs are met (implemented)**
* Server: new `Sale.provisionalNumber` — a *lookup reference only*: stored upper-cased, **unique per store** (partial unique index), never used for sequencing, copied to `invoice.offlineRef` for the printed invoice. Only offline, non-held sales may set it; format `OFF-<id>-<n>` validated. If two sales of a store claim the same number the second is accepted **without** it and flagged `provisional_number_clash` for review (a sale is never refused over a placeholder).
* App: the stored/queued payload is unchanged (the old rule still holds, test reworded). At submit time `PosRepository.submitRawSale` adds `provisionalNumber` as a **separate field**, read from the queue's own record. Tests: field is sent; queued payload not modified; no field when none.
* Search: `GET pos/sales/lookup/:storeId?ref=` finds a sale **store-wide** by `OFF-…`, `INV-…`, receipt number, bare number or credit-note number (`CN-…`); Orders also accepts `search`. The Orders screen has a search box ("Find by receipt no."), which is store-wide (not limited to this shift); the Return flow opens from the result.
* Cross-till return: the return is paid from **the returning till's own open shift** (`registerId` sent by the app); a cash refund needs an open shift on that till (`OPEN_SHIFT_REQUIRED`).
* **Verified on the iOS simulator against the dev stack** (`integration_test/g27_offline_return_other_till_test.dart`): till A (register 1) rings a cash sale while the API is *stopped* → queued with `OFF-2AC9BF-0001` → API back → synced; till B (a **second register** and device) finds it by the OFF- number (also lower-case/spaced, and by `INV-…`) and returns it → `CN-000012` against `INV-000019`. (Found + fixed on the way: a search typed before the Orders screen had its store id sent an empty store → server 500.)

### 1.2 Cashier returns off by default
`cashierReturnsEnabled` defaults to **false** (approved, unchanged; tested in g25 backend + app).

### 1.3 Single refund path
* Removed from order detail: *Refund Selected*, *Refund Full Sale*, *Void Sale*, the per-line refund steppers, and their controller methods. Removed from the Orders list cards: the quick Refund / Void buttons and controller methods.
* Both places now have one button — **Return or void** / **Return / void** — that opens the Return flow. The Return flow handles partial and full returns (credit note, restock choice, approval rules) and, for managers, **Void entire sale** (reason picker → credit note). `voidSale` now exposes the credit note.
* The button is shown to cashiers too: the **server** decides (cashier returns are off by default → the server's answer is shown), the app does not fake the rule.
* Tests: old refund/void controller tests replaced by Return-flow tests (double-submit, void with credit note, refused void); Orders controller no longer has the old methods.

**Did the old path create credit notes? (report only — nothing changed)**
The old buttons called the same `refundSale` / `voidSale` service code, so **since G2.5 yes**, every refund/void creates a credit note. Refunds made **before G2.5 shipped** have none. Dev DB (`solvexo_dev`, port 27118), read-only query:

| | count |
|---|---|
| refunds (`posrefunds`) | 26 |
| credit notes (`poscreditnotes`) | 11 |
| **refunds with no credit note on their sale** | **15** (ids below) |
| **voided sales with no credit note** | **6** (`POS-00019, -00030, -00041, -00052, -00069, -00089`) |

All 15 refunds are dated 2026-11-04 / 11-05, i.e. before G2.5 — test traffic from earlier phases (four of them still carry the pre-minor-unit amount `5.5`). Refund ids: `6aeb161e…8213`, `6aeb207b…475c`, `6aeb2085…d371`, `6aeb2087…d46d`, `6aeb3b41…d37a`, `6aeb3b41…d3a1`, `6aec1a6b…557a`, `6aec1a73…adf8`, `6aec1a75…aef4`, `6aec5bd4…de10`, `6aec5bdf…dff7`, `6aec5bea…e1fa`, `6aec5c34…04f1`, `6aec5c3f…0788`, `6aec5c4a…0a32` (full ids available from the query on request).

**Proposed backfill (not built, not run)** — only if production has such refunds:
1. One-off script, dry-run first, per store, in the order the refunds happened.
2. Issue credit notes in a **separate, clearly marked series** (`CN-B000001`, field `backfilled: true`, `createdAt` = the refund's own time, `fiscal` empty) so the gap-free `CN-` series of real documents is never disturbed, and the notes can be recognised by an auditor.
3. Lines from the refund's `items` (or all lines for a full refund) priced with the same cumulative-proration maths; legacy rows with major-unit amounts converted with the sale's exponent; refunds that cannot be reconstructed are listed, not guessed.
4. Append-only; script is idempotent (skips refunds that already have a note) and writes an audit event per batch.
Decision needed from you: whether any real (non-test) refunds exist before G2.5 in production. If not, no backfill is needed.

### 1.4 Cloudinary — seller verification documents only
* `StoreService.signedDocumentUrl` now uses `generateExpiringPrivateUrl(publicId, resourceType, 300, {inline:true})`; replaced documents are removed with `deletePrivateFile`. Shared helpers and every other caller untouched. Spec `store.verification-documents.spec.ts` (4 tests).
* **Orphans — count only, nothing deleted.** Cloudinary side: **16 private seller-verification files, 11.61 MB, all older than 90 days**. How many of those are *orphans* (no DB reference) **could not be counted**: that needs the database, and the only configured Mongo URI is the remote Atlas `edudeen`, which I will not read without your explicit OK. Read-only script ready: `npx ts-node src/scripts/count-orphan-seller-documents.ts --mongo-uri <uri>` (prints counts only).

## 2. G2.7 Permissions screen (done)
* Route `/pos/permissions`: shown once **after device setup** (before PIN login), and re-openable from **More → App → Permissions**. Skippable ("Continue" / "Done"); nothing here blocks selling.
* Items, each with *why* and *without it*: **Camera** (barcode scan, document photos), **Bluetooth** (receipt printer; Android asks Scan + Connect, iOS the single Bluetooth permission), **Local network** (iOS only: network printers on port 9100 — iOS never reports the answer to an app, so the row says "Asked when used" and has no button), **Notifications** — the app sends none today, so it is honestly shown as "Not used" and **nothing is requested** (adding a request for a feature that does not exist would be misleading; revisit if the blueprint's low-stock / sync-failure notifications are built).
* States: allowed · not allowed (**Allow** asks the system) · turned off / permanently denied (explanation + **Open Settings**, never asks again) · re-reads on return from Settings · a failing plugin never breaks the screen.
* Graceful degradation: the barcode scanner now shows *"Camera access is off"* with **Open Settings** and **Type it instead** instead of a black screen; printing already answers "Bluetooth is off / permission needed" and the PDF share is always the fallback; KYB documents use the file picker, so they do not need the camera.
* No new package (`permission_handler` was already present). Tests: 8 (`g27_permissions_test.dart`). Screenshots: `g2_7_screenshots/` (phone, light + dark).

## 3. Thermal printing (done on layout; real printers not verified)
* Tax invoice, credit note and **return receipt** (a short slip: what came back, the refund per tender, reason, "Keep this slip") print through the existing printer path (`ThermalPrinterService`, new `printDocument`), at **58 mm (32 columns)** and **80 mm (48 columns)** — same layout rules as the sale receipt (word-wrap, right-aligned amounts, Latin-1 safe, `CCY 1,234.00` amounts). Print buttons: Tax invoice (*Print*), Credit note (*Print credit note*, *Return receipt*), Return-complete (*Print return receipt*). PDF share stays. No printer → plain explanation + PDF route; printer refusal → its message + PDF route.
* **FBR slots reserved in the layout:** document number → *FBR Invoice No* line right under it; QR under the totals (real ESC/POS QR command); logo slot at the top (bitmap command added with the logo work). While empty they print **nothing** (a blank band on a customer's receipt would look like a fault) and move nothing; a test proves that filling them changes only those lines.
* Tests (`g27_thermal_documents_test.dart`, 17): text **snapshots** for the three documents × 58/80 mm (`test/golden_thermal/*.txt`, date/time normalised so they do not depend on the machine's time zone), no line longer than the paper, real ESC/POS bytes for both widths, FBR slots, button outcomes. Regenerate on purpose with `UPDATE_THERMAL_GOLDENS=1`.
* "Print preview" on the iOS simulator (it has no printer): `g2_7_screenshots/g27_05…07_preview_*` renders exactly the text the printer is sent, 58 and 80 mm, light/dark.

## 4. Dev seed category tree
`solvexo-api/dev/seed.ts` now creates a platform tree (storeId null, like the real one): **Beverages** (Hot drinks, Cold drinks), **Bakery** (Pastries), **Pantry** (Coffee beans). Confirmed served by `GET /api/categories/category-tree` after re-seeding. The catalog **category dropdown on the simulator** is covered by the existing catalog widget tests with a mocked category repository; I did not add a new simulator run that selects a category from the dropdown.

## 5. G2 blueprint screens — status
Blueprint routes of roadmap phase 1 (Launch & Access, Sell & Checkout, Orders & Returns, Products & Pricing). Status after G2: **done** / **partial** / **deferred → where**.

| Route | Status | Notes |
|---|---|---|
| splash, welcome, pin, device-setup | done (kept; restyled earlier) | |
| login (mobile+password), otp | out of scope (rule 2) | |
| store-select | partial → G4 (settings/restyle) | works, legacy UI |
| permissions | **done (G2.7)** | |
| open-shift | partial → G3.5 (cash) | float + open shift work; denomination counter / previous-close variance not built |
| pos (smart checkout), category-view (merged), product-search | done (recent searches: partial) | |
| scan | done in code; **camera on device not verified** | torch + continuous-scan: torch done; continuous mode deferred |
| product-detail, variants | partial → G3.1 / G4 | variant sheet only; **modifiers deferred** (no backend) → later phase |
| custom-item, discounts (keypad + manager token), coupon | done (G2.4; coupons online-only) | |
| cart, customer-attach | done / partial → G3.2 | inline "add customer" is G3.2 |
| park-sale, parked-sales | done | |
| payment, cash, split | done | |
| card-payment | done as honest "recorded, unverified" + slip at shift close | no provider by decision |
| Raast QR checkout + KYB | done on the **mock provider** (G2.1–G2.3) | real provider adapter deferred (needs sandbox docs) |
| credit-payment (store credit tender) | **deferred → G3.2** | |
| payment-success, receipt, print-share, offline | done | email/SMS/WhatsApp delivery deferred |
| orders, order-detail | done (search by receipt number added) | filters by cashier/register: deferred → G3 reports |
| invoice (tax invoice) | **done (G2.5)** + thermal (G2.7) | FBR number/QR/logo reserved |
| return-start/items, refund-success | **done (G2.5)**, single path (G2.7) | return window = approval-after-days rule |
| refund-method (store credit) | **deferred → G3.2** (needs customer credit ledger) | |
| products, catalog-product, product-form | partial: **edit** price/barcode/HS/category/stock with manager approval (G2.6); **create product, images, variants editor deferred → G4 (catalog)** | |
| categories CRUD, pricebook, modifiers, bulk-import | deferred → G4 | |
| dashboard / home pulse | done (G2.6) | |

## 6. Open items
1. Real provider adapter (Raast via PayFast / 1LINK) — needs sandbox docs; mock only so far.
2. G1b runbook / deploy / backfill on hold; G1b step f not built. Deploy pipeline needs diagnosis before any deploy.
3. Admin UI for KYB review — another agent builds it (API in `ADMIN_KYB_API.md`).
4. Orphan seller-document count needs DB access (see 1.4).
5. Pre-G2.5 refunds without credit notes: backfill only if production has any (see 1.3).
6. Cash-session counters: a cross-till cash refund is paid from the returning till's shift but the *session counters* of the original sale's session still carry it (pre-existing attribution) → to fix with the daybook in G3.5.
7. Held-sale coupons are re-validated on resume (done); coupons remain online-only.
8. Slug-transliteration tests (10) excluded in CI as before.
9. Notifications permission/feature does not exist (see 2).
10. FBR: plan in `FBR_PLAN.md`; needs documents from the owner (listed there).

## 7. Consolidated manual checklist — real Android phone and real iPhone
Run each on **both** unless marked. Tick when seen with your own eyes.

**Setup**: install the build for the dev/staging backend; sign in; register the device. □ After registration the **Permissions** screen appears; Continue goes to PIN login. □ More → Permissions shows the same states.

**1 Camera — barcode**
□ Allow → Sale → scan: a real EAN/UPC (and a QR) decodes and the product is added; torch toggles. □ Deny the camera in the system prompt → scanner shows *Camera access is off*, **Type it instead** returns to typing; selling continues. □ Turn camera off in Settings (permanently denied) → screen shows **Open Settings**; after enabling and coming back, the scanner works without restarting the app. □ Barcode of a product not in the store → "not found" message (no crash). □ HID/Bluetooth scanner wedge (if available) still adds products.

**2 Camera / files — KYB documents**
□ More → Business verification: pick a JPEG, a PNG and a PDF → uploaded; a `.txt` renamed `.pdf` is rejected (magic-byte check); a file over the size limit is rejected with a clear message. □ Documents can be re-picked after a failure. □ Android: file picker opens without storage permission prompts; iPhone: Files app and Photos both offer files.

**3 Screenshot blocking and app-switcher cover**
□ **Android:** on the payment / QR screen and on KYB / tax-profile screens, take a screenshot → blocked ("can't take screenshot"), and the recent-apps card is blank. □ **iPhone:** open the app switcher while on a sensitive screen → the privacy cover (curtain) hides the content; return → content is back, no flash of data. □ Normal screens (product grid) are *not* blocked.

**4 Wake lock on the Raast QR screen**
□ Open a Raast QR with the screen timeout at 30 s → the screen stays on for the whole QR lifetime; after paying / cancelling / leaving the screen, the normal timeout works again. □ Same with the app backgrounded and brought back before expiry.

**5 Printing** (58 mm and 80 mm printer if available; Bluetooth Classic on Android, BLE on iPhone; network printer on port 9100)
□ Settings → printer: pair, set paper width, **Test print** on 58 and on 80 → all 48/32 columns visible, nothing cut. □ Sale receipt prints. □ **Tax invoice**, **credit note**, **return receipt** print — compare with `docs/pos-blueprint/g2_7_screenshots/g27_05…07_preview_*` and `test/golden_thermal/*.txt`: wrap, right-aligned amounts, no overflow, paper cuts. □ Printer off / out of paper / Bluetooth off → a clear message and the PDF share still works. □ iPhone: network printer asks for **Local Network** once; deny → message, Bluetooth printing still works. □ Android 12+: Bluetooth permission dialog appears (Scan + Connect), no location prompt; Android ≤ 11 works.

**6 Offline → sync**
□ Airplane mode → ring a cash sale: receipt shows `OFF-…` number; banner says offline; Raast/coupon options say they need internet. □ Ring 2–3 sales offline, kill the app, reopen → still queued. □ Turn the network back → sales sync (queue empties, real receipt numbers `INV-…` assigned). □ On a **second device/register**: Orders → search the `OFF-…` number printed on the first receipt → the sale is found → Return / void → credit note issued (cash refund asks to open a shift if none). □ A sale rejected by the server appears in *Needs attention*.

**7 Auto-lock**
□ Set auto-lock to 1 minute; leave idle → PIN screen appears; the cart/held state is kept; wrong PIN is refused; the right PIN returns to the same screen. □ Backgrounding for longer than the timeout locks on return; shorter does not. □ A manager approval sheet (return above the limit) is not left open after lock.

**8 Returns & documents (quick pass)**
□ Partial return with restock, return without receipt (manager PIN asked), cashier return disabled by default, Void entire sale as manager, credit note numbers continue without gaps. □ Share PDF and Share link for invoice and credit note open the system share sheet.

## 8. Test evidence (this round)
* App: `flutter analyze` clean; full `flutter test` **852 passed** (new: permissions 8, thermal 17, orders search 3, repo/return additions, rewritten refund tests).
* Backend: g27 integration 7, g25 34, integrity, seller-documents 4 — passing locally; CI result is reported in the final message.
* iOS simulator (iPhone 17 Pro, dev stack): return at a second till using an OFF- receipt (real e2e, 1 test, passed); screenshots for permissions / documents / print previews.

## 9. Not verified
* Real printers (58 / 80 mm), camera decode, `FLAG_SECURE`, app-switcher cover, wake lock, Android permission dialogs — all need the physical-device checklist above.
* The orphan seller-document count (needs DB access you have not granted).
* The simulator category dropdown selection against the new seed tree (the seed is verified through the API only).
* CI for the last app commit — see the final message.
