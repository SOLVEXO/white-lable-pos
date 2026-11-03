# Changelog — Solvexo POS app

## 1.0.0 (build 100) — release candidate
Everything since `main` (phases 5A–5H). Details per phase: `docs/phase5*_summary.md`.

### Added
- **Sale integrity:** per-intent idempotency keys persisted across retries/restarts; atomic server pipeline wiring; typed inventory (`unlimitedStock`, `∞`); inventory stock edit via delta/adjust with reason; store-scoped customer search. (5A)
- **Money:** server-authoritative totals via quote; store currency + ISO-4217 exponent everywhere (no `toFixed(2)`/`$`); split tender with change; per-tender refunds; unified receipts (tax lines, VOID/REFUNDED/COPY). (5B)
- **Offline:** encrypted offline sale queue with original `clientCreatedAt`/key, FIFO sync with backoff, "Needs attention" list (retry / manager discard + audit), cart + in-flight key persisted across crashes, catalog/settings cache with stale indicator, manager approvals and price-change flags, **provisional `OFF-<device>-<seq>` receipt numbers mapped to the real number after sync**. (5C, 5C.1, 5H)
- **Shared-device security:** register this device (device token), employee PIN login with lockout, idle auto-lock, owner-only screens behind manager/owner PIN or re-auth, clean sign-out with queue ownership. (5D, 5D.1)
- **Billing UX:** "POS plan isn't active" screen, read-only plan status, expiry banner; **no purchase UI in the app** (web only). (5E)
- **Compliance & release config:** env files (`config/env/*.json`), Crashlytics with PII scrubbing + dSYM upload phase, privacy manifest + usage strings, account deletion (password, Google or Apple re-auth) with 30-day grace, **Sign in with Apple** (iOS), R8/ProGuard, targetSdk 36, backup exclusions, icons/splash, export-compliance key. (5F, 5F.1)
- **Printing:** Bluetooth (Android Classic, iOS LE) and **network ESC/POS (TCP 9100)** printers, paper width 58/80, auto-print, copies, drawer kick, test page, reprint, PDF share. (5F, 5F.1)
- Queue encryption now runs on OS crypto (CryptoKit / platform AES-GCM) with a versioned envelope and lossless migration. (5F.1)

### Changed
- Version `1.0.0+1` → `1.0.0+100`. Increase the build number on every store upload.
- Release builds refuse to start on a missing/non-https/local `API_BASE_URL`.

### Removed
- All plan-purchase UI (Stripe WebView, price lists, buy buttons), `webview_flutter`, unused `file_picker`, dead marketplace leftovers touched in 5A–5H.

### Tests / tooling
- `flutter test` suite (365+), iOS simulator integration tests, and **real-backend end-to-end tests** (`tool/run_real_e2e.sh`, 11 flows). CI workflow added (`.github/workflows/ci.yml`).
