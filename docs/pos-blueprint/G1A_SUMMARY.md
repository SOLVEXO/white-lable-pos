# Phase G1a — Foundations that do not depend on pending decisions

Status: **built and verified; stopped for owner approval.** Branches: `solvexo-api` and `pos` are both on `feature/jamibranch`. Nothing is committed or pushed (a commit/push is outward-facing; say the word).
Not started (per instructions): G1b minor units (D1 awaits owner sign-off), D3 catalog routes (G2), new modules, Phase 3b extensions.

## What changed, in one paragraph
Every sale payment and every refund is now its own immutable record with its own id; audit events are written **in the same database transaction** as the sale / refund / void / shift close they describe (and cannot be updated or deleted through the app); sales and refunds carry the shift and device, always derived server-side; deleting a held sale is a soft delete with a reason; shift close can reconcile the terminal's card total, and a mismatch needs a manager. The app got the blueprint tokens (coral, radii, Manrope + DM Sans), the five-tab shell (Home, Sell, Orders, Stock, More) with per-role content, and a proposal for the remaining offline-storage gaps. All API changes are additive; tills on the current app build keep working.

---

## Part 1 — Backend (solvexo-api)

### 1.1 Transactions: supported everywhere that matters (evidence)
| Environment | Evidence | Transactions |
|---|---|---|
| Production / staging | `MONGO_URI` is a MongoDB **Atlas** `mongodb+srv://…mongodb.net` cluster (host type read from `.env`; credentials not used). Atlas clusters are always replica sets. Production code already depends on them: `connection.transaction()` in `finance.service.ts`, `products.service.ts`, `seller-platform-subscriptions.service.ts`. | **yes** (inferred; I did **not** connect to the Atlas database from this machine) |
| Local dev stack | `dev/up.sh` runs `mongod --replSet rsdev`; I ran a real multi-document transaction (commit and abort) against it: `setName: rsdev`, 2 collections committed, abort left nothing | **yes (proven)** |
| Jest | was `MongoMemoryServer` (standalone — no transactions). **Changed to `MongoMemoryReplSet`** so the transactional paths run for real in tests | **yes now** |
| Docker compose dev | `--replSet rsdev` | yes (file read; never run) |

**Decision:** transactions, not an outbox. `PosService.atomic()` runs the work in `connection.transaction()`; on a standalone mongod it falls back to awaited, non-atomic writes and logs a warning once (so an unexpected deployment is loud, not silent).
> ⚠ **Security finding, unrelated to this phase:** `solvexo-api/.env` contains a live-looking Atlas connection string with a plaintext password (the file is git-ignored, so it is not in the repo, but it sits on disk and was visible to my tooling). Rotate that password and move it to a secret store.

### 1.2 Durable, immutable audit
* `PosService.writeAuditLog` is now **always awaited** (the 22 fire-and-forget `.catch(() => {})` calls are gone — 0 remain) and takes the transaction session.
* In one transaction with their business write: `sale_created` / `sale_held` (+ offline flags), `sale_completed`, `sale_refunded_*`, `sale_voided`, `held_sale_discarded`, `session_closed`, `card_variance_approved`, `cash_in/out`.
* Immutability (`pos-immutable.util.ts`): audit, payment and refund models throw on `updateOne/updateMany/findOneAndUpdate/replaceOne/deleteOne/deleteMany/findOneAndDelete` and on `save()` of an existing document. The only allowed update is a payment's `status / confirmationSource / confirmedAt` (a future terminal integration).
* **Honest limit:** this is enforced in the application. Raw driver access (`model.collection.*`) bypasses it, so production should also use a database role with `insert`/`find` only on `posauditlogs`, `pospayments`, `posrefunds` (ops task, not done). Audit rows are append-only, **not** hash-chained / tamper-evident — that stays a G4 item.
* Audit rows now also carry `sessionId, registerId, shiftId, deviceId`.
* Proof (test): if the audit write fails, the sale, its payment rows and its stock reservation all roll back (and a retry succeeds exactly once); same for refund and void.

### 1.3 Payment and refund records
* `pospayments` — one row per tender line: `saleId, saleNumber, lineNo, tender, amount, tendered, currency, currencyExponent, reference, status, confirmationSource (null), confirmedAt, storeId, registerId, sessionId, shiftId, deviceId, employeeId, idempotencyKey, createdAt`.
  * **Status (D2):** cash → `confirmed`; card / other → `recorded_unverified`. `confirmationSource` is `null` today so a terminal / Raast integration can later set `confirmed` + a source.
  * Unique `(saleId, lineNo)` and unique `(storeId, idempotencyKey, lineNo)`: a retry cannot create a second row (proved by sequential and concurrent tests, and by trying to insert a duplicate directly).
* `posrefunds` — own id, human `reference` (`POS-00063-R1`), `kind, amount, tenders, items, reason, status (same rule), confirmationSource`, store, register, **the session/shift the refund happened in** (can differ from the sale's), device, the approving manager, the sale's own session/employee, `idempotencyKey`. Unique `(saleId, seq)` and `(saleId, idempotencyKey)`. A retry with the same `Idempotency-Key` returns the original refund (`replayed: true`); two concurrent refunds produce exactly one record.
* `Sale.refunds[]` keeps working (old builds read it) and now links `refundId`.
* Money is copied exactly as stored (major units + currency/exponent snapshot): **no rounding change** (minor units are G1b).
* **Migration** `src/scripts/pos-g1a-backfill.ts` (+ `.lib.ts`): `up` / `down`, each with `--dry-run`; idempotent; `down` removes only rows flagged `backfilled: true` and unsets only the markers `up` set. It does **not** load `.env`, and refuses a database whose name does not contain `dev`/`test` unless `--i-have-a-backup` is passed.
  * Run on a **copy of the local dev data** (`solvexo_dev` → `solvexo_dev_g1a_copy`, then dropped):

    | Step | sales | payments | refunds |
    |---|---:|---:|---:|
    | before | 59 | 0 | 0 |
    | `up --dry-run` (reports 73 payments + 16 refunds to insert) | 59 | 0 | 0 |
    | `up` | 59 | **73** | **16** |
    | `up` again (no-op) | 59 | 73 | 16 |
    | `down --dry-run` | 59 | 73 | 16 |
    | `down` | 59 | **0** | **0** |
    | `up` again after `down` | 59 | 73 | 16 |

    After `down`, all 59 sales documents were byte-identical to the original (0 differ). The dev sessions have no shift ids, so 0 shift ids were set (59 sales reported "missing shift"; correct).

### 1.4 Transaction context (shift + device)
* `Sale.shiftId` ← the session's `shiftId`; `Sale.deviceId` ← the authenticated device token (`currentDeviceScope()`); same for payments, refunds and audit rows. **A spoofed `deviceId` / `shiftId` in the request body is ignored** (tested). Store, register, cashier were already stored (verified). Old builds that send neither still sell (tested).

### 1.5 Held-sale delete
`DELETE pos/sales/:id/discard` is now a soft delete: `status: 'discarded'`, `deletedAt`, `deletedBy`, `deleteReason`, plus a `held_sale_discarded` audit event (reason, number, total) in the same transaction. Reason comes from the body or `?reason=`; **old builds send none → `"not provided"`**. Retrying is idempotent (one audit event). Lists (`held`, `sales`, `needs-review`) exclude `deletedAt != null`; a discarded sale cannot be completed; discard racing a completion has exactly one winner.
Not changed on purpose (not in your list): it still needs no manager token (owner/device ownership only) — my G0 audit flagged that; say if you want a manager PIN here.

### 1.6 Card reconciliation at shift close (D2)
`POST sessions/close` accepts optional `cardTotalFromSlip` and (header) the employee token. The server compares it with the net card total the till recorded (`cardSales`, net of card refunds):
* not sent (old build / skipped) → closes exactly as before, `cardReconciliation.status = "not_reconciled"`;
* equal → `matched`;
* different → **403 `CARD_VARIANCE_APPROVAL_REQUIRED`** (with `slipTotal, expectedCard, variance`) unless a **manager** PIN session is attached; with one → closes, `variance_approved`, and **two audit events** (`session_closed` + `card_variance_approved`, in the same transaction as the close).
Individual card payments stay `recorded_unverified` after a matched close (an aggregate match does not verify each payment).

### 1.7 Tests
* New `pos.g1a.integration.spec.ts`: **22 tests** on a real replica set (payments, refunds, durable audit / rollback, immutability, soft delete, card reconciliation, backfill dry-run/up/down, old payloads).
* Two existing suites encoded the old behaviour and were updated (not weakened): `pos.service.integrity.spec.ts` (hand-built fake repositories gained the new models; the discard test now asserts a status-guarded **soft** delete and that `findOneAndDelete` is never called) and `pos.integration.spec.ts` (the discard-race test now accepts the row existing as `discarded`).
* Results: POS suites 22/22 new + all existing green. Broader gate (`src/pos src/pos-plans src/inventory src/product-variants src/common src/draft-orders src/markets src/auth`): **736 passed, 10 failed, 44 skipped** — the same **10 failures in `common/slug-transliteration.util.spec.ts` occur on a clean stash of the branch** (pre-existing, unrelated). `pos.module-di.smoke.spec.ts` (loads the whole AppModule) crashes the jest worker with out-of-memory both before and after my change (the known "R4" item) and was excluded. The 44 skipped are the env-gated inventory integration tests (need `INVENTORY_IT_MONGO`).
* `npm run build` passes. **Build config fix (pre-existing bug, one line):** `tsconfig.build.json` did not exclude the committed `dev/` folder, so a fresh build emitted `dist/src/main.js` while `start:prod` runs `node dist/main` — a deploy would have run a stale or missing entry. Added `"dev"` to `exclude`.

### 1.8 End to end on the local dev stack (real HTTP, real device token + manager/cashier PIN sessions)
Rebuilt `dist`, restarted the dev API, ran `g1a_e2e.py`: cash sale, card sale (+ retry with the same key → "Duplicate request — returning existing sale"), split sale (card 3.30 + cash 2.20), refund of the card sale with reason (+ retry), held sale then delete with a reason, shift close with a wrong slip total as a cashier (403), then as a manager. Resulting rows:

```
PAYMENTS
POS-00062 line0 cash  5.5 confirmed           ref=null      shift=…4153 device=…412b cashier=…cb4df
POS-00063 line0 card  5.5 recorded_unverified ref=AUTH-4821 conf=null  (same shift/device/cashier)
POS-00064 line0 card  3.3 recorded_unverified ref=AUTH-777
POS-00064 line1 cash  2.2 confirmed
REFUNDS
POS-00063-R1 full 5.5 recorded_unverified reason="customer changed mind" tenders=[card 5.5]
             refund session …4168, shift …4153, device …412b, approved by manager …cb4dc
AUDIT (this shift)
sale_created ×3 · sale_refunded_full (refundId + reference) · sale_held ·
held_sale_discarded {"reason":"customer left the queue"} · session_closed {cardReconciliation:variance_approved, variance:-2.3} ·
card_variance_approved {slipTotal:1, expectedCard:3.3, variance:-2.3, cashierId:…}
HELD SALE   status=discarded deletedBy=<cashier> deleteReason="customer left the queue"  (row kept)
SESSION     cardReconciliation = variance_approved, slipTotal 1, expectedCard 3.3, variance -2.3, approvedBy <manager>
```
(The refund retry returned the cached original response from the HTTP idempotency layer — still one refund row; the service-level replay is covered by the integration test.)

### Deploy notes
Deploy order: **API first** (additive schema; new collections build their indexes on boot), then run `pos-g1a-backfill up --dry-run` and `up` (take a `mongodump` first, per `deploy_runbook.md`), then ship app builds. Rollback: `down`, redeploy the previous API (old code ignores the new fields/collections). Add a DB role with insert/find-only on the three append-only collections.

---

## Part 2 — Design system to the blueprint (app)

### 2.1 Fonts — verified before switching
I downloaded the official Google Fonts files into a scratch folder and parsed their OpenType tables (no packages), then confirmed on the iOS simulator's real engine.
| Font | GSUB `tnum`? | Digit widths | Result |
|---|---|---|---|
| **Manrope** (variable, wght 200–800) | **yes** — substitutes all 10 digits | proportional by default (716…1240); with `tnum` all 1240 | tabular figures work (simulator: `1111` and `8888` both 99.2 wide with `tnum`) |
| **DM Sans** (variable, opsz + wght) | **no** (no `tnum`, no `pnum`) | proportional; `tnum` has no effect (simulator: 51.8 vs 97.1) | cannot do tabular figures |

**Per your rule (not both have `tnum`): Manrope for display / headline / title, DM Sans for body, and JetBrains Mono stays for amounts only.** If you prefer, Manrope (which *has* `tnum`) could replace JetBrains Mono for amounts — your call, not done.
Other facts learned: both are variable fonts, **Flutter does not move the `wght` axis from `FontWeight`**, and Manrope's default instance is **weight 200** — so every style sets `fontVariations: wght` explicitly (tested), and each file is declared once per weight in `pubspec.yaml` so Flutter never fakes a bold. Fonts + OFL licences are bundled under `assets/app_fonts/{manrope,dm_sans}` and registered with `LicenseRegistry`; Plus Jakarta Sans files/licence/family removed (nothing used them). No new packages.

### 2.2 Tokens (all proven by test, both modes)
Blueprint hues for fills/icons; the darker text shades from the audit for anything that is text:
`accent #DC7758` (icons, highlights, selected, focus) · filled button `#B4553A` + white (**4.88:1**) · coral text `#A84B31` (5.65 on white, 5.09 on the soft tint) · `onAccent` brand ink `#15181D` on coral (5.78) · success text `#157553`, warning `#8A5A00`, danger `#B83A49`, info `#3A5BC0`, muted `#5F666E` · radii **10/14/18/24** · spacing 4/8/12/16/20/24/32 (superset kept) · tap target ≥ 44 (we keep 48; a test fails below 44).
**One deviation:** the blueprint's `#D94C5C` fails with both white (4.09) and ink (4.35) labels, so the light-mode danger *fill* is `#C23B4B` + white (5.22). Dark mode (D7): re-based on the brand ink `#15181D` (surface), `#0F1114` (background), `#F4F1EE` text; accent text `#F39072` (7.66).
`design_system_test` now checks **every text × surface pair in both modes** (neutral text on 4 surfaces; coloured text on 4 surfaces and on its own soft tint; labels on fills), the radii, spacing/tap floor, fonts and the `wght` axis. 88 design tests green.
Side effects handled: the splash view pins the **native** splash colour (`#0B1020`) explicitly, because the native splash is deliberately not regenerated — otherwise frame 0 would flash; the phase-2 test that tied it to the palette now tests that constant. Two layout regressions caused by the wider body font were found by the simulator test and fixed: the payment sheet's quick-amount chips wrapped to a second line and pushed the keypad under the Charge button (now one sideways-scrolling row), and the keypad's compact-key threshold moved to ≤ 900 px tall screens (44 px keys).

### 2.3 Logo — what I need from you (nothing regenerated yet)
* `Solvexo_logo_mark.png` is **327×316 and not square**: usable in-app only up to ~100 physical px (as instructed). For the launcher icon (1024²) and splash I need a **vector (SVG/PDF) or ≥ 1024×1024 square master of the mark**.
* `Solvexo_wordmark.png` is **black text** → invisible on dark; I need a **white/light wordmark**.
* Confirm the canonical coral: the token says `#DC7758`, the mark's pixels are `#D97757`.
* Also need: whether the Android adaptive icon background should be coral (`#DC7758`) or ink.
* Untouched (as instructed): native splash, launcher icons, `assets/icon/*`, `flutter_native_splash` and `flutter_launcher_icons` config.

### 2.4–2.5 Kept screens, gallery
Kept screens (splash, onboarding, owner login, PIN login, auto-lock, owner gate, device setup) were restyled **only through tokens** — no layout or logic edits. The `/design-gallery` and its tests were updated (stale hex text; it renders without overflow in both modes). Screenshots: see below.

---

## Part 3 — Navigation (app)
* Five tabs in blueprint order — **Home, Sell, Orders, Stock, More** — one `AppShell` (bottom bar on phones, rail on tablets), `PosBottomNavController` constants `homeTab=0 … moreTab=4`. Guards, middlewares and routes are unchanged; every row in Stock / More opens an **existing** route behind its **existing** gate.
* **The till still lands on Sell** (one constant, `PosBottomNavController.initialTab`; changing it lands on Home). Reason: a cashier's first act is a sale, and "product in ≤ 2 taps" counts from login.
* **Home** (`PosHomeTabController`, read-only, only data that exists today): cashier → "Your shift" (shift sales, cash, card, refunds, held, shift row); manager/owner → "Business pulse" (net sales today, orders, average sale, 7-day bars from the range report, low-stock, offline-queue alert). Profit, Expense, Count are **"Coming soon" placeholders shown to managers/owners only** — a cashier never sees one (tested). If the server needs a manager PIN for the numbers, a clear note replaces them, not an error. Loading / error (Try again) / empty states; pull to refresh; works at 200 % text (tiles stack).
* **Stock** (was Products): Products, Stock on hand, Stock activity (managers, lock icon), and "Coming soon" rows (count / transfers / batches) for managers.
* **More** (was Settings; keeps the unresolved-sales **badge**): Shift summary, Held sales, Sync & needs attention for everyone, Settings for everyone; managers/owners add Customers, Reports, Shift history, Team & registers, Devices, Audit log, Plan status and "Coming soon" rows (suppliers/POs, expenses/daybook, attendance).
* Role = owner session open → owner; else the PIN employee's role. It only decides what is **shown** — the server still enforces everything.
* Restricted mode (plan inactive): Sell and Stock stay off (as Sale and Products were); Home, Orders and More stay open.
* Finder updates (rule H): `integration_test/pos_checkout_flow_test.dart` — `changeTab(1)` → `PosBottomNavController.ordersTab` (the only existing finder that depended on tab order); both Phase-3 integration tests now pre-register a mocked `PosHomeTabController` (a real one would send a seeded fake token to the server). 18 new widget tests (`nav_five_tabs_test.dart`).

---

## Part 4 — Offline queue encryption: correction + proposal (needs your approval; **not implemented**)
**Correction to the premise:** the offline sale queue **is already encrypted at rest**.
* Store: sqflite (`pending_sale_local_store.dart`). Encrypted columns: the sale payload, the employee token, error text, discard reason, and the receipt snapshot.
* Cipher: **AES-256-GCM** (authenticated), via the OS provider (`cryptography_flutter`: CryptoKit on iOS, `javax.crypto` on Android). Format `v2:` + base64(nonce ‖ ciphertext ‖ mac); older `v1:` rows decrypt unchanged and are re-tagged in place (already migrated).
* Key: 256-bit, generated on the device, stored in the Keychain / Keystore (`flutter_secure_storage`, slot `pos_queue_encryption_key`), never in preferences or the database. Android backups exclude everything (`backup_rules.xml`), so a restored queue can never be unreadable ciphertext.
* **Key lost / data damaged:** the row is kept, shown as unreadable, blocks shift close and sign-out, and only a manager can discard it (audit-logged) — never silently dropped. Sign-out never deletes rows or the key.
* Idempotent reconciliation: the row id is the sale's idempotency key (unique on the server); FIFO, exponential backoff 5 s–15 min; a definite server rejection parks the row in Needs attention.

**What is still plaintext** (verified in code):
1. `pos_cart_snapshot` (SharedPreferences): the **cart in progress** — lines, discount, **customer name/id**, and the checkout idempotency intent.
2. `idempotency_intent_store` (SharedPreferences): checkout intents (keys, not content).
3. `pos_catalog_cache`, `pos_settings_cache`: product list/prices; business name, **tax id**, receipt header/footer.
4. Queue metadata columns (ids, status, timestamps, store/session id, attempts, error *code*, provisional receipt number, `discardedBy` employee id) and the sqlite file itself.

**Proposal** (no new package — it reuses `AesGcmQueueCipher` and the existing key):
* **Encrypt (1) and (2)** with the same cipher; on first read, a value without the `v2:` prefix is treated as legacy plaintext, read once and rewritten encrypted (idempotent migration, no data loss). If the key is lost, the snapshot is dropped with a visible "couldn't restore your last cart" notice (an unsent cart can be rung again; a *sale already queued* is unaffected and handled as above).
* **Encrypt the customer fields and tax id in (3)**; leave product names/prices plain (public catalogue data, rebuilt from the server).
* **Do not** add whole-database encryption (SQLCipher: a native package, adds ~2–4 MB per ABI and a build/licensing surface — my estimate, unverified). The sensitive content is already column-encrypted; the remaining metadata are opaque ids.
* Confirm the Keychain accessibility class: `flutter_secure_storage` 9.x defaults to a non-synced "when unlocked" class on iOS (from the package docs; I did not inspect the built app). If you want the queue to survive a reboot-before-unlock (a till that restarts and syncs in the background), set `first_unlock_this_device`.
* Add a test that proves an offline sale + cart snapshot contain no plaintext customer name in the stored bytes, and that a lost key never deletes a row.
Effort: **S** (≈ 2 days). Please confirm: encrypt (1)–(3)? keychain class?

---

## Verification summary
| Check | Result |
|---|---|
| `npm run build` | passes |
| Backend POS suites (real replica-set Mongo) | all green; 22 new |
| Broader backend gate | 736 pass / 10 pre-existing unrelated failures / 44 env-skipped |
| Backfill up and down on a dev copy | exact round trip (0 of 59 sales differ) |
| `flutter analyze` | no issues |
| `flutter test` | **600 passed** |
| iOS simulator integration (iPhone 17 Pro, dev stack up) | `pos_checkout_flow` ✅, `phase3_sale_flows` (park → resume → split → success, quote-changed confirm) ✅, `phase2_device_flow` ✅ (lock/unlock, switch user, PIN login), `phase2_fresh_flow` ✅, `offline_sync` ✅ |
| Real-backend suites (`tool/run_real_e2e.sh`, dev stack on the new backend build) | `real_backend_pos_flows_test` 11/11 ✅ and `real_backend_ui_test` 1/1 ✅ (the ❌ lines in the log are the expected negative cases: expired plan 403, revoked device 401, wrong password) |
| Screenshots (real iPhone 17 Pro simulator, `tool/shoot.sh`) | `docs/pos-blueprint/g1a_screenshots/`: `phone/` = Sell, Home / Stock / More for **manager and cashier**, design gallery ×4 — each **light and dark**; `kept_before/` (Phase 2) vs `kept_after/`: onboarding, login, PIN, lock — light and dark. Not captured: owner gate and device setup "after" (their route needs a seeded launch state), iPad/landscape |

## Findings to know about
* **Status-bar clock is white on cream on the kept login / onboarding screens** (visible in `kept_after`); it is an existing status-bar-style issue on those screens, not touched (kept screens are token-only). The new Home/Stock/More tabs set it correctly.
* The launcher icon and splash logo are still the old orange (`#F06839`) tile, deliberately, until the logo masters arrive.

## Not verified
Atlas itself (no connection made); the DB-level insert-only role; real card terminals / Raast; the camera barcode path; **any Android device** (emulator check was skipped at your request); VoiceOver/TalkBack; the iPad layouts of the new tabs beyond the screenshots listed; fonts on a physical device (simulator only).

## Android manual checklist — additions
1. Cold start → splash → (device mode) PIN login: text renders in Manrope/DM Sans, no fallback font, digits in JetBrains Mono; check the OFL licences appear on the licence page.
2. Bottom bar shows **Home, Sell, Orders, Stock, More**; the More badge counts unsynced sales; rotate a tablet → rail.
3. Cashier PIN: Home shows only the shift card (no "Soon"/"Coming soon" anywhere in Home, Stock, More). Manager PIN: Business pulse + placeholders.
4. Sell: quick-amount chips scroll sideways; the **0** key is reachable without scrolling on a small phone (≤ 5.5″) and a large one.
5. Card sale → "recorded" only; shift close: type a wrong card total → manager PIN prompt path (once the app sends `cardTotalFromSlip` — see G1b/G2 note).
6. Hold a sale, delete it, confirm it is gone from Held sales but present in the audit log with the reason (needs the app to send the reason — see note).
7. Airplane mode sale → Needs attention → back online → synced; payment + audit rows exist on the server.
8. Check dark mode on the new tabs; text scale 200 % does not clip.

## Notes for the next phase
* The **app does not yet send** the new optional fields (`cardTotalFromSlip` on close, `reason` on discard/refund, the `Idempotency-Key` on refund is already sent). The backend is ready for them (old builds are safe); wiring the shift-close slip total and the discard/refund reason prompts is app work for G2, with the checkout rebuild.
* G1b (minor units) is untouched; the new records store the same major units + currency snapshot, so G1b adds `amountMinor` fields without reshaping them.
