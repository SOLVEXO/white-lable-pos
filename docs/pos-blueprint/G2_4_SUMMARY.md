# G2.4 — Blueprint checkout rebuild (backend + app)

Branch `feature/jamibranch` in both repos. No PRs, no merges, no deploys, no admin UI.

## What was built
**Backend** (`solvexo-api`, commits `4129d26`, `3485c09`, CI `8afecef`/`bce367d`/`186f60e`)
* **Custom item** — sale line with no product (`isCustom`, `customName`, `unitPrice`, `qty`, `taxCategory` standard|exempt, `customNote`). Never touches stock. A manager must approve above `PosSettings.customItemApprovalAboveMinor` (null = always); the server answers `403 CUSTOM_ITEM_NEEDS_MANAGER` and the approving manager is stored on the line and audited (`custom_item_sold`). Reports list a "Custom item" row.
* **Coupon** — storefront `Coupon` model reused with a `posEnabled` flag; validated server-side (active, dates, usage limit, min spend, currency); usage counted **inside the sale transaction** (race-safe, 2-till test). Not combinable with a manual discount (`COUPON_WITH_DISCOUNT`), not on held sales, never offline (`COUPON_ONLINE_ONLY`). The quote returns the applied `coupon`.
* **Digital receipt** — 192-bit random token on the sale, unique partial index, public read-only HTML at `/r/:token` (store branding, items, totals, payments, refund status; **no customer name/phone/email**), generic 404 for anything else, manager-revocable (`receipt-link/revoke`, audited). `GET pos/sales/:id/receipt-link` returns the same link every time until revoked.
* **Reasons** — `reasonCode` (+ optional note) on refund, void and held-sale discard, stored and audited; codes in `pos-reasons.ts`; old builds without a code still work (`not_provided`).
* Shift close already took `cardTotalFromSlip` (D2); the app now sends it.

**App** (`pos`, commits `13f99a7`, `df39634`, `d5a843c` + this one)
* Sale screen: custom item sheet, coupon sheet (live check, applied code shown in the totals), discount sheet (managers), product detail sheet (long-press), all-categories sheet, recent searches, scan feedback (haptic + sound), manager-PIN approval sheet (server decides when).
* Success screen: receipt **QR + Share link** (offline sale: "available once it syncs"), print/share PDF as before.
* Reason picker (code + optional note) for refund, void and held discard. Shift close: card-slip total field; a variance asks for a manager PIN.
* **Offline mode** screen (More → Offline mode): what works offline (cash, recorded card, held sales, queued sync), what needs a connection (Raast QR, **coupons**, refunds/voids, the receipt QR), pending / rejected counts, last sync time, Sync now.
* **Owner Business verification (KYB)** (More → Team & security, behind the owner gate): draft/edit, documents by camera or photo library, submit, status + rejection reason. Privacy: nothing cached on the device; the picked photo is deleted right after upload; form and loaded application wiped on background / lock / leaving; Android `FLAG_SECURE` (native `MainActivity`), iOS opaque "privacy curtain" while the app is inactive (app-switcher snapshot).

## Decisions
* **Coupons are online-only** (a live check; usage is counted in the sale). A coupon sale is never queued — the cashier is told to retry online or charge without it. A held sale does not keep a coupon.
* The approval limit lives on the server; the till never knows it. It asks for a manager only when the server says so.
* A document is an image (camera / photo library). **PDF upload would need the `file_picker` package — not added (needs your approval).**

## Acceptance targets (all measured / tested)
| Target | Result |
|---|---|
| Add to cart ≤ 2 taps | 1 tap (single variant), 2 taps (variants) — `g24_acceptance_test` |
| Barcode scan feedback < 300 ms | **iOS simulator: 17–27 ms** from the on-device catalogue, **20–42 ms** via the server (3 runs); haptic + sound asserted |
| Double-submit protection | Charge, Hold, coupon apply, custom item, refund, shift close, KYB save/submit — one request each (tests) |
| Sale restored after app kill | lines, quantities, discount, customer, note, payment, custom items, coupon, checkout intent restored; another session does not inherit it |

## Verification
* Backend: `pos.g24.integration.spec` (20 tests) + the whole gate, `npm run test:di`, build with `dist/main.js` at the root — **CI green** on `3485c09` (Tests workflow).
* App: `flutter analyze` clean, `flutter test` **766 passing**; new: `g24_custom_coupon_test` (20), `g24_screens_test` (29), `g24_acceptance_test` (9), `g24_checkout_sheets_test` (16). Existing tests for refund / void / discard / hub updated for the reason picker.
* iOS simulator against the dev stack (`integration_test/g24_checkout_flow_test.dart`, 5 tests, all pass): search → variant → coupon → split cash + card → receipt QR opens the public page (404 for a guessed token, 404 after a manager revokes); custom item refused for a cashier, approved through the real PIN sheet, stock untouched, audited; shift close with a card-slip variance (refused → manager token → closed); offline sale queued → API back → synced, and a coupon sale is **not** queued; scan latency.
* Screenshots: `g2_4_screenshots/phone` (iPhone 17 Pro) and `tablet` (iPad Pro 11"), light + dark, 15 screens each (`integration_test/g24_screens_shots_test.dart`, `tool/shoot.sh`).

## Not done / not verified
* No PDF document upload (needs `file_picker`); camera capture was not exercised on a device (the simulator has no camera) — upload logic is tested with a fake picker.
* Android `FLAG_SECURE` and the iOS privacy curtain were tested at the Dart level (calls made / curtain shown on `inactive`); not verified on a physical Android device or with an actual iOS app-switcher capture.
* The legacy shift-close dialog (card-slip field) has no new screenshot; it is covered by the integration test through the repository.
* Raast QR and KYB flows against a **real** provider remain out of scope (mock provider, G2.1–G2.3).
* The slug-transliteration failures (10 tests) remain excluded in CI as before.
