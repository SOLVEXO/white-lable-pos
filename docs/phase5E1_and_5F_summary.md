# Phase 5E.1 fix-ups + Phase 5F (store compliance, release config, printing) — Summary

Both repos on `feature/jamibranch`; nothing on `main`. Full store paperwork: `docs/store_submission_checklist.md`. Buyer-app impact: `docs/buyer_app_changes.md`.

## 5E.1
1. **`charge.dispute.closed`** — a dispute opened now records exactly how many ms it took off the expiry (`reversedRemovedMs`). **Won** → exactly those days are given back once (atomic claim, audit entry `pos_plan_dispute_won_restored`; from now if access had already ended; never undoes an admin revoke). **Lost** (or any other status) → nothing changes. Added to the required Stripe events in `.env.example` and the web spec. 4 new real-Mongo tests (won stacked / won sole purchase / lost + never-disputed / revoke interplay); billing suite is 23 tests.
2. **`docs/buyer_app_changes.md`** — every 5A–5E change that touches buyer endpoints. **Only one is breaking**: add-to-cart now refuses sold-out/oversold physical variants (400 `"This item is out of stock"`, no machine code); the rest are non-breaking (stock clamped to ≥ 0 in storefront responses, unified checkout rule, `allowBackorder` unchanged, guard rejects POS token types).

## 5F
**Both platforms**
- **Environment** — `--dart-define-from-file=config/env/{dev,staging,prod}.json`; no URL in code (a test fails if one appears). Release builds refuse to start (clear error screen) on a missing, non-https, local/private-IP host or a non-staging/prod `APP_ENV`. *The staging and prod files both currently contain `https://api.solvexo.store` (the old default) — **please put the real staging URL in `staging.json`.***
- **Crashlytics** (crashes + non-fatals, release only) with **no PII**: every error is wrapped in a scrubbed message (emails, phones, JWT/Bearer, PIN/password/token values, long ids removed; tested), HTTP failures are reduced to `METHOD /path/:id → status`, no user id, only `env` as a key. `print`/`debugPrint` are silenced in release.
- **Account deletion** (backend + app, 6 + 2 tests): owner-only, owner-password gate then password again + checkbox; blocked while a shift is open or sales are unsynced; revokes all sessions, devices and staff PIN sessions at once, suspends the stores, **30-day grace** (cancel via API), then a daily cron purge **de-identifies** the owner, employees, customer names/ids/notes on sales and business text, deletes device records and **keeps sales/payments/refunds/tax records**. Google-only owners have no password → told to use the web. **The Google Play web deletion URL does not exist (no web code here) — it must be built; spec in the checklist §5.**
- **Icons + native splash** generated from one source: `assets/icon/app_icon.png` (derived from your `assets/images/logo.png`; I painted its white corner slivers orange so it is full-bleed — tell me if you have a better master) + adaptive foreground; replace and run the two generator commands.
- **`flutter analyze`: fully clean (0 issues)** — the 4 old ones fixed.
**Android**: R8 + shrink on with `proguard-rules.pro`; release signing via git-ignored `key.properties`, with an early readable failure when missing; **targetSdk/compileSdk 36** (Google requires API 36 for new apps/updates from 31 Aug 2026 — looked up today); minimal permissions (merged manifest checked; biometrics pulled in by a dependency removed; Bluetooth scan `neverForLocation`, legacy BT/location capped at API 30); backup + device-transfer exclude DB/prefs/files (`backup_rules.xml`, `data_extraction_rules.xml`); Crashlytics gradle plugin (google-services bumped to 4.4.2 as it requires); unused `file_picker` removed.
**iOS**: usage strings (camera, photo library, Bluetooth — honest, printer-only), `PrivacyInfo.xcprivacy` added to the target, deployment target aligned to 14.0, version/bundle/display name documented. Archive contains the manifests of every plugin except `print_bluetooth_thermal`/`audioplayers_darwin` (documented). **Export compliance — your call:** `ITSAppUsesNonExemptEncryption = true` because the app implements AES-GCM for the local queue (not just OS HTTPS); reasoning and the "if you judge it exempt, set false" alternative are in checklist §2.
**Printing**: Settings → *Printer settings* (managers/owner): paper 58/80 mm, auto-print, copies (1–5), cash-drawer kick on cash sales, test page + drawer test. The receipt layout is now computed per paper width (32/48 columns), long names/addresses wrap, amounts right-aligned, currency decimals per exponent, VOID/REFUNDED/COPY banners; reprint from sale detail. Connection handling: remembered printer, one automatic reconnect, plain-language errors (Bluetooth off / no permission / unreachable / rejected), and **printing is fire-and-forget after the sale is saved** (offline-queued cash sales still kick the drawer); failures only raise a notice with "reprint or share PDF". **Platform support, verified in the plugin source:** Android = Bluetooth Classic (SPP) printers; **iOS = Bluetooth Low Energy printers only** (CoreBluetooth; no Classic without MFi) — the typical cheap 58 mm Classic printer will not work on iPhone/iPad; documented in the picker and the checklist.

## Verification
| Check | Result |
|---|---|
| Backend `npm run build` + jest (pos, pos-plans, inventory, product-variants, idempotency, draft-orders, markets, auth, cart, checkout, account-deletion) | ✅ 28 suites, 431 tests (2 suites / 45 tests skipped = pre-existing env-gated) |
| `flutter analyze` | ✅ **No issues** |
| `flutter test` | ✅ 324 passed (+ printing 17, store/release 12 incl. static manifest/plist/gradle guards) |
| iOS simulator (iPhone 17 Pro) | ✅ `pos_checkout_flow_test`, ✅ `offline_sync_test` (run with `--dart-define-from-file=config/env/dev.json`) |
| `flutter build appbundle --release` (prod env) | ✅ 66 MB, R8 on |
| `flutter build apk --release` | ✅ 88 MB |
| `flutter build ipa --release --no-codesign` | ✅ `Runner.xcarchive` (no certs here; IPA export needs your signing) |
| **Not run** | Android emulator/device smoke test of the R8 build — skipped at your instruction (iOS simulator only): **please run the release APK once on a real phone**; live Crashlytics delivery; real BLE/Classic printer and drawer hardware; Play/App Store upload |

## Needs you (OWNER)
1. Real **staging** URL; confirm **prod** URL; confirm upload keystore (`~/solvexo-pos-release.jks`), bundle id and team.
2. **Export-compliance** answer in App Store Connect (checklist §2).
3. **Web deletion page**, **privacy-policy URL**, **support URL**.
4. Demo store/accounts for reviewers (checklist §7); screenshots (§8).
5. Add the Crashlytics dSYM upload build phase in Xcode.
6. Web team: purchase page (`web_pos_plan_purchase_spec.md`) before enforcement; Stripe must also deliver `charge.dispute.closed`.
