# G5 close-out

## G5.1: small gaps from the blueprint audit, G5.4, receipt-link hardening

G4.7 (khata) stays parked. API details: [`G4_8_ADMIN_API.md`](G4_8_ADMIN_API.md) ("G5.1 additions"). Deploy notes: `G1B_RUNBOOK.md` §11. Audit statuses: [`BLUEPRINT_GAP_AUDIT.md`](BLUEPRINT_GAP_AUDIT.md). Scope list with blueprint references: `PROGRESS_LOG.md` ("G5.1 scope").

### Done

| # | Item | Backend | App |
|---|---|---|---|
| 16 | Receipt-link hardening | **`API_PUBLIC_URL` checked at boot:** outside development the API refuses to start if it is missing, not https, localhost / a private, loopback, link-local or CGNAT address, carries credentials, or is more than an origin. One test per refusal case. The same check is in the preflight script (`g51.apiPublicUrl`) and the runbook (§11). The till already gets the base in its cached settings (G4.9). | The printed QR comes **only** from the server-provided base + the sale's client key. With no base cached, the receipt prints without a QR and the app logs why; there is no fallback to the token link or any guessed URL. |
| 15 | G5.4: clock someone else | `POST team/clock` with `employeeId` needs `x-pos-approver-token` from **that member's PIN** or a **manager's PIN**, checked by the server. The event records actor, subject, approver and kind; the audit row is in the same transaction. Self clock-in is unchanged. **Offline:** it reuses the existing offline PIN-verification path (the approver token must have been valid *when* the event happened, as for offline sales). | Clock screen → "Clock someone else in / out": pick the person, then they type their PIN, or "use a manager's PIN" (email + PIN). The PIN login is not kept. **Offline it is refused in the app**: nobody can check a PIN without the server, so it is never queued. |
| 14 | Print notice per document | — | "Printed." belongs to the document it was printed from (invoice / credit note). |
| 1 | About | — | Version + build (constants checked against `pubspec.yaml` by a test, so no new package was needed), store id (tap to copy), API environment + host, receipt links ready / not yet, open-source licences (Flutter's own licence page). |
| 2 | Help | — | Static answers shipped with the app, grouped by task; no external service. |
| 4 | Hardware check | — | Test page, open the cash drawer, scanner test (USB / Bluetooth wedge into a box, or the camera). |
| 3 | Store-select restyle | — | Tokens throughout (light and dark); text, keys and behaviour unchanged. |
| 5 | Stock by location | `stock?locationId=`: variants at that location, bins summed, `locationStock` per row. **New `GET inventory/locations`**, because the owner-session list refuses device tokens. | Location chips on the stock list; each row shows the location's quantity and the store total. |
| 6 | Orders by cashier / register | `sales?registerId=` (cashier filter existed). | Manager-only chips; picking one makes the list store-wide. **New `GET team/members`** feeds the cashier list, because the owner-session employees list refuses device tokens. |
| 8 | Products supplied | `productsSupplied` on the supplier detail; `lastUnitCostMinor` classified **cost** in the registry (hidden from managers with costs hidden). | "Products supplied" section on the supplier profile (received / ordered, last cost when allowed). |
| 9, 10, 13 | Scan-to-add, scan-to-receive, continuous scan | — | The camera stays open and each new code is handled (the same code is ignored for 1.5 s). Sale → "Keep scanning". PO form → "Scan to add". Receive → "Scan to receive" (one more good unit per scan, never above what is due; a code not on the order is said so). |
| 11 | Photo on a cash movement | `POST/GET cash/movements/:requestId/receipt`: private storage as for expenses, new append-only `poscashattachments` + audit in one transaction; the daybook flags lines with a photo. | "Add a photo of the slip" on the cash sheet, uploaded when the movement is recorded online; a photo icon on the daybook line opens a 5-minute link. |
| 12 | Staff profile | `GET team/profile`: last PIN login (from the audit log), clocked in, sales today / 7 / 30 store days in minor units + currency. | More → Team members (managers) or My profile (cashier). |
| 17 | Share the receipt link | — | Sale detail → link icon: the share sheet with the public receipt link (the offline-built one, so it works before sync). The documents screen already shared its invoice / credit-note links. |

### Deferred, with reasons
- **Role presets (item 7):** what "Owner-operated / Small team / Strict" each allow was never defined (`G4_PLAN.md` names them only). That is a decision for Sir Atiq. Audit status: Blocked.
- **WhatsApp to the customer's number (part of item 17):** opening a `wa.me` link needs `url_launcher`, a new direct package (ask first). Sharing through the share sheet works, and WhatsApp is one of its targets; it just can't pre-fill the customer's number.
- **A photo on a cash movement made offline:** the movement queues, but the photo is not kept (the cashier is told). The cash queue only carries expense photos. Attach-later from the daybook is not built.
- **Real photo upload on the dev stack:** it would send the file to the real storage provider, so it is verified by the backend spec with a fake store only. Check it once in staging (as for expense receipts in G3).
- **Two mocked simulator flows (`pos_checkout_flow_test`, `phase3_sale_flows_test`):** known-failing harness, as their header has said since phase 5. `main.dart` fires an un-mockable `getProfile` with the seeded fake token, the real API answers 401, and the app force-logs out. Not fixed here; the real-backend core flows and the app-launch test cover the same screens.

### Found and fixed during G5.1
1. **The till could not read the team or the store's locations.** `GET /api/pos/employees` and `GET /api/pos/locations` take only the owner's session and refuse device / PIN tokens (found by the real-backend run). So on a registered till the on-behalf picker, Team members, the Orders cashier filter and the location chips would have been empty. Two POS-guarded reads were added (`team/members`, `inventory/locations`).
2. **Sign-out could throw on iOS.** Several requests answered 401 at once each trigger a forced logout, and two interleaved `clearPreference` calls raced on the keychain ("already exists", -25299). Clears now run one at a time, and a leftover queue key is replaced instead of failing.
3. **Raast e2e:** the expectation for a fresh QR now also accepts `pending` (a valid waiting status since G2.1).
4. **Dev stack:** `dev/up.sh` right after `dev/down.sh` sometimes fails the first time (mongod not ready); running it again works. Noted, not changed.

### Tests
- **Backend:**
  - `public-url.check.spec.ts` (9);
  - `pos.g51.integration.spec.ts` (10: on-behalf × 4, location filter + locations read, orders filters, products supplied + hidden cost, team members, staff profile, movement photo);
  - registry, route-tier and permission-matrix specs updated.
- **App:**
  - `g51_small_gaps_test.dart` (11) and `app_version_test.dart`;
  - QR expectations updated in `g48_hardening_test.dart` / `g49_close_out_test.dart`.
- **Real backend:** see the integration-flows table in `PROGRESS_LOG.md`.

### Real-device checklist (additions)
- [ ] Clock someone else: their PIN clocks them; a wrong person's PIN is refused; a manager's PIN works; airplane mode refuses in words.
- [ ] Hardware check: the test page prints on 58 and 80 mm; the drawer opens; a USB / Bluetooth scanner types into the box; the camera reads a barcode.
- [ ] Keep scanning on the Sale screen, Scan to add on a PO, Scan to receive.
- [ ] A cash-out with a slip photo → the photo opens from the daybook (staging storage).
- [ ] Share link from a sale → open it on another phone.
- [ ] A till that has never been online since install prints receipts without a QR; after one online start it prints the QR.
