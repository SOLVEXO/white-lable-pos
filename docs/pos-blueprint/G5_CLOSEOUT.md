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

## G5.2–G5.7: integrations, provider-ready features, khata out of scope

All backend changes are additive. No existing response changed shape, and every provider-dependent feature is **OFF** per store until switched on. Money is in minor units with currency and exponent, ledgers and records are append-only, and audit rows are written in the same transaction. Every new route declares its tier (ROUTE_TIERS.md: 163 declared routes, plus the remaining GET routes counted separately). The cost registry, money-contract and currency guards are green.

### Commits
| Sub-phase | solvexo-api | pos | Sync conflicts |
|---|---|---|---|
| G5.2.0 (merge main, Node pin) | 87bdb76 (main merged earlier in c889af0) | f9b1d7b (docs) | none at the time. `origin/main` has since moved 27 commits (AI-studio removal, scheduler fixes): no overlap with POS files, not merged in this phase |
| G5.2.0b RECEIPT_PUBLIC_URL | 753d4d5 | f9b1d7b | — |
| G5.2 product page, serials, khata out of scope | 8f61282 | 8cb0e04 | — |
| G5.3 WhatsApp / e-mail / SMS, link lifetime | acde835 | 3bf41c4, 8880e63, e118306 (two CI guard fixes) | — |
| G5.4 card on an external terminal, Payments setup | 8915b7c (with G5.5 scaffolding: same files) | b755477, c6103c4, b36b662 | — |
| G5.5 fiscal provider (mock) | 8915b7c, 56690b7 | 353d955 | — |
| G5.6 receipt logo, role presets | 3156598 | 97c9136, 9f1b9e5 | — |
| G5.7 integrations, accounting export, API keys | 33e43a7, ba8f370 (dev stack only) | 4c677c3 | — |

### What was built
| # | Item | Backend | App |
|---|---|---|---|
| 3–6 | RECEIPT_PUBLIC_URL | Optional and boot-checked; falls back to API_PUBLIC_URL; used for every receipt QR and link; `Store.receiptBaseUrl` reserved (null) | Till config carries the base; preflight and runbook §11; web hand-off in the admin API doc |
| 7 | Khata | **Out of scope (product decision)** in the audit. The POS app has no khata entry point, placeholder or flag. Main's own `src/khata` module (Uzair's, with POS udhaar routes) is **not removed**: deleting it would change live behaviour on main and touch its ledger. This needs an explicit decision (see TO ADD LATER) | — |
| 8 | Product page / edit / photos | `GET/PATCH catalog-admin/products/:storeId/:productId`, variant SKU / cost / reorder point (cost obeys hide-costs), photos checked by content and resized, all audited | Product page with cached thumbnails, edit sheets |
| 9 | Remaining non-provider Partials | Serial numbers at receiving (unique, same transaction; older tills get `SERIALS_NOT_SUPPORTED`) | Serials field on receive |
| 10 | WhatsApp | — | wa.me with the customer's number via url_launcher (approved); falls back to the share sheet |
| 11 | E-mail / SMS receipts | Link only; consent (on file / given for this sale); 3 per sale per hour, 500 per store per day; append-only `posreceiptdeliveries` plus audit; main's mailer and the store's SMS gateway (`sendTransactional`, additive) | Shown only when the store has them on |
| 12 | PDF view | Receipt and invoice PDFs already exist and are shared (the share sheet previews them) | An in-app **viewer** needs a package: **deferred** |
| 13 | Receipt-link lifetime | Per store, at least 30 days, the return window by default; existing links keep theirs | — |
| 14 | Card on an external terminal | Approval code (required live when on), last4, terminal label; refunds and credit notes reference the code; shift close and payments report lines | Payment sheet fields, shift close line, payments report line |
| 15 | Card gateway | Interface, mock, not-configured adapter, `connectors.cardGateway` off | "Not available yet" in Payments setup |
| 16 | Raast payments setup | `raastDisabled` switch (KYB gate `disabled_by_store`), `KybGateService.status()`, PayFast / 1LINK typed TODOs | Payments setup: KYB status, test-mode badge, on / off, errors |
| 17–18 | Fiscal | Interface, mock (outage switch), not-configured adapters; append-only `posfiscalrecords` plus audit; hooks after sale, complete, refund and void; 2-minute retry sweep; the block laid over `invoice.fiscal` / `creditNote.fiscal` | "Fiscal pending" / FBR number + QR on receipt, invoice and credit note (thermal and PDF); offline receipts print "Fiscal pending" |
| 19 | Receipt logo | Owner upload / remove (content-checked, ≤ 2 MB, resized), audited | Dithered 1-bit bitmap per paper width with dart:ui (no new package), cached; printed when "Store logo" is on; designer preview shows the exact dots; app icon masters listed in APP_ICON_MASTERS.md |
| 20 | Role presets | Standard / Small shop / Strict, **proposed**; owner-only apply with preview, version guard and audit | Roles → Presets → diff → apply |
| 21 | Integrations screen | `GET /api/pos/connectors/:storeId` | Owner → Integrations |
| 22 | Accounting CSV | Store time zone; minor units with currency and exponent plus formatted amounts; cost columns only when visible; formula-safe; audited | Export → share sheet |
| 23 | API keys | Owner only; read-only scopes; shown once; SHA-256 stored; expiry ≤ 365 days; revocable; 60 per minute per key; every use audited; external API `/api/pos/ext/v1/*` (no cost data); API_KEYS.md | Create (show once, Copy), list, revoke |

### Found and fixed along the way
1. **The till's connectors read broke 128 existing checkout tests.** Their mocked repositories had no stub for the new read. The read is now fail-safe (a failed read keeps what the till knew), which also protects real tills on a bad network.
2. **Two app CI guards:** an unused import, and a second URL literal in `lib/` (the store-release guard allows only the API's), so the wa.me link is now built with `Uri(...)`.
3. **The cost registry scan** flagged the export's `withCost` / `costsIncluded` flags; they are classified as not cost.
4. The tier test walks controller prototypes, so the external controller's repository getter became a method.

### Not done / deferred
- In-app PDF viewer (needs `printing` or `pdfx`).
- Daybook: card-terminal payments don't move drawer cash, so they appear on the shift close and in the payments report, not in the cash daybook.
- The real FBR / Raast / card-gateway adapters, which need external inputs (below).

### TO ADD LATER: external inputs
| Input | Needed from | Where it plugs in | Once it arrives |
|---|---|---|---|
| `RECEIPT_PUBLIC_URL` + the web `/r/*` rewrite | Web team (rewrite on solvexo.store), then ops (env on the API service) | `src/common/api-origin.ts`; hand-off in the admin API doc (G5.2.0b) | Deploy the rewrite, check it with the curl in the hand-off, set `RECEIPT_PUBLIC_URL=https://solvexo.store` on the API, run preflight `g52.receiptPublicUrl`. New receipts carry the web origin; old QRs keep working on the API origin |
| Card gateway provider | Owner: choose a provider; provider: API docs, sandbox keys | `src/pos/connectors/card-gateway.ts` (`CARD_GATEWAY_NEEDS`), `connectors.cardGateway` | Write the adapter next to the mock, set `CARD_GATEWAY_PROVIDER`, test in sandbox, then turn the flag on per store |
| Raast docs / sandbox (PayFast or 1LINK) | Provider: integration docs, sandbox merchant, webhook signing | `src/pos/connectors/raast-adapters.ts` (`RAAST_PROVIDER_NEEDS`), payments-core provider registry | Implement the adapter behind the existing payments-core interface, set `PAYMENTS_PROVIDER_POS`, run the Raast flows against sandbox |
| FBR route + documents | Owner + tax advisor (route decision), FBR / PRAL or integrator (spec, sandbox, IP whitelisting) | `src/pos/connectors/fiscal.ts`; FBR_INTEGRATION_NEEDS.md lists each item | Add the adapter, add encrypted per-store credentials, wrap the sweep in `JobLeaseService`, set `FISCAL_PROVIDER`, run a sandbox store end to end |
| App icon masters | Brand owner / designer | `assets/icon/*` (APP_ICON_MASTERS.md) | Replace the PNGs, run the two generators, check on devices |
| Role preset sign-off | Sir Atiq | `src/pos/pos-role-presets.ts`, ROLE_PRESETS.md | Adjust the overrides, set `status: 'approved'`; the app drops the "Proposed" badge |
| Messaging credentials | Ops: SMTP for the API's mailer; each store's SMS gateway in Messaging channels | main's `EmailService`, `SmsGatewayService.sendTransactional` | Configure them, then turn on `emailReceipts` / `smsReceipts` per store; the till shows the buttons |
| Deferred packages | Approval | In-app PDF viewer (`printing` or `pdfx`) | Approve, then add a viewer on sale detail / expense |
| Khata decision on main's module | Owner (with Uzair) | main's `src/khata` (not POS) | Decide whether to retire it; the POS side needs nothing |
| Real-device checks | Jami, with hardware | Logo on 58 mm and 80 mm printers; WhatsApp on a phone with WhatsApp; external card terminal slip; e-mail / SMS with real credentials | Run the checklist below and note the results |
| Merge main again | Jami (go) | 27 new main commits, no POS overlap | Merge before the next backend release; CI |

### Real-device checklist (additions)
- Print a receipt with a logo on 58 mm and on 80 mm paper. Check the logo is centred and the dithering is legible.
- WhatsApp: on a phone with WhatsApp, the chat opens with the customer's number and the link; without WhatsApp, the share sheet opens.
- Card terminal: approval code from a real slip; the shift close line matches the terminal's settlement.
- Integrations: the CSV opens in Excel / Numbers with the right columns, and the time zone is the store's.
