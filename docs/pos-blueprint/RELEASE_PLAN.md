# Release plan: backend release #2 and the first POS app release (G6.0)

Prepared, **nothing run**. No merge to `main`, no deploy, no upload. Every step that touches `main`, production or a store happens only on Jami's go.

Contents:
- a. Backend release #2
- b. POS app release
- c. Production data steps
- d. Real-device test plan
- e. Go / no-go

## a. Backend release #2 (`solvexo-api`)

### a.1 What changed on `feature/jamibranch` since `c889af0` (the first merge, tag `pos-backend-g5.1`)
Only the branch's own (non-merge, first-parent) commits are listed. Main's own changes reached the branch through merges and are already on `main`.

| Commit | What |
|---|---|
| `87bdb76` | G5.2.0: `engines.node` 20.x; both CI workflows read it from `package.json` |
| `753d4d5` | G5.2.0b: `RECEIPT_PUBLIC_URL`; `Store.receiptBaseUrl` reserved |
| `8f61282` | G5.2: product page and editing an existing product (details, variant SKU / cost / reorder point, photos); serial numbers at receiving |
| `acde835` | G5.3: e-mail and SMS receipts (main's mailer and the store's SMS gateway, new `sendTransactional`); connector flags; per-store receipt-link lifetime |
| `8915b7c` | G5.4 + G5.5: card on an external terminal; fiscal scaffolding (both behind store switches that default OFF) |
| `56690b7` | G5.5: the sale response and sale read show the fiscal outcome in the existing `invoice.fiscal` |
| `3156598` | G5.6: receipt logo and role presets |
| `33e43a7` | G5.7: accounting export, store API keys, read-only external API `/api/pos/ext/v1/*` |
| `ba8f370` | Dev stack only: `DEV_UPLOAD_STUB`, `RECEIPT_PUBLIC_URL` in `dev/.env.dev` |
| `2cd32a5` | G5.8: merge of `origin/main` (58 commits, no conflicts) |
| `6228558` | G5.8: main's route-auth allow-list gains the contact form's public `config` and `upload` routes |
| `fe366ed` | G5.8: the dev upload stub is fail-closed and tested to stay off in production |
| `59bb0cb` | G6.1: fiscal contract v1 (display lines, message, willRetry, logo; failed status), fiscal issues + owner retry, per-document and sweep leases, `connectors.ui` |
| `8aec473` | G6.1: `connectors.ui.fiscal.title` |
| `7cfc429` | G6.1: fiscal / card-gateway switches refuse to turn on without a usable provider (`PROVIDER_NOT_CONFIGURED`) |
| `f673775` | G6.2: `GET /api/pos/capabilities` (public, static) — the till's only feature-detection signal |

Nothing changes an existing response shape. Every new field is additive and every new switch defaults OFF. Behaviour notes:
- **Receipt links:** once `RECEIPT_PUBLIC_URL` is set, new QR and share links use that origin. The web `/r/*` proxy must be live first.
- **Extra settings read:** the sale routes read `posSettings` once more, for the fiscal switch.
- **Raast:** `KybGateService.check` refuses only when `raastDisabled` is true.
- **Serials:** a till that sends serial numbers is now accepted. One that sends none still gets `SERIALS_NOT_SUPPORTED`, with a reworded message.
- **New error code:** `CARD_APPROVAL_REQUIRED` exists only when the card-terminal switch is on.
- **G6.1:**
  - The fiscal block gains additive fields (FISCAL_CONTRACT.md). The live `not_enabled` value is unchanged.
  - New routes: `GET /api/pos/fiscal/:storeId/issues` (manager) and `POST …/retry` (owner).
  - `connectors.ui` is additive.
  - Turning on `connectors.fiscal` or `cardGateway` without a usable provider now answers `PROVIDER_NOT_CONFIGURED`. In production that means always, until a real adapter is configured. Both switches are new in this release, so no live behaviour changes.

### a.2 Environment variables (all new ones are optional; nothing new is required)
| Variable | Default | Required in production? | What it does |
|---|---|---|---|
| `RECEIPT_PUBLIC_URL` | unset → receipts use `API_PUBLIC_URL` | No. **If set and invalid, the API refuses to start.** It must be https, a public host and an origin only. | Customer-facing origin of receipt QRs and links. Set it **only after** the web `/r/*` rewrite is live. |
| `FISCAL_PROVIDER` | the mock outside production; in production no provider until a real adapter exists | No | Fiscal provider. Any value other than `mock` gives the "not configured" adapter. |
| `MOCK_FISCAL_DOWN` | off | No (has no effect in production) | Test hook: simulates a fiscal outage. |
| `POS_FISCAL_SWEEP_CRON` | `*/2 * * * *` | No | Fiscal retry sweep. It does nothing unless a store has turned fiscal on. |
| `CARD_GATEWAY_PROVIDER` | the mock outside production; none in production | No | Card gateway (the status read only). |
| `API_KEY_RATE_PER_MIN` | 60 | No | External API requests per minute per key. |
| `DEV_UPLOAD_STUB` | off | **Must not be set.** It is ignored anyway unless `NODE_ENV` is exactly `development` or `test` (tested). | Dev stack only. |
| `MOCK_FISCAL_MODE` | unset | No (the mock is never built in production) | Test hook: `down` / `fail` / `reject` |

Existing, unchanged:
- `NODE_ENV=production` and `API_PUBLIC_URL` (boot-checked) are confirmed on the service (deploy log, 2026-11-12).
- `POS_AUDIT_SEAL_CRON` is optional.

### a.3 New collections and indexes
Mongoose creates all of these on first start on empty collections; there is nothing to run.

| Collection | Append-only | Indexes |
|---|---|---|
| `posreceiptdeliveries` | yes | `{storeId, saleId, channel, createdAt:-1}`, `{storeId, createdAt:-1}` |
| `posfiscalrecords` | yes | unique `{documentType, documentId, attempt}`, `{storeId, status, createdAt:-1}` |
| `job_leases` (existing) | no (lease rows) | G6.1 adds keys `pos:fiscal-sweep` and `pos:fiscal:<type>:<id>`; no new index |
| `posapikeys` | no (revoke / last used are updated) | unique `prefix`, `{storeId, createdAt:-1}` |
| `posapikeywindows` | no (rate counter) | unique `{keyId, window}`, TTL `{expireAt}` |

New fields on existing schemas, all nullable or defaulted, with no backfill:
- **PosSettings:** `receiptLogoUrl`, `connectorPrefs`, `receiptLinkDays`, `receiptLinkDaysSince`.
- **Store:** `receiptBaseUrl` (reserved).
- **Sale:** payment `terminal`; tender `approvalCodeRef` and `externalTerminal`.
- **PosPayment:** `terminal`.
- **PosRefund and PosCreditNote:** tender `approvalCodeRef` / `externalTerminal`.
- **PurchaseReceipt:** line `serialNumbers`.

### a.4 Steps before and after (on top of `G1B_RUNBOOK.md` §9–§11)
**Before:**
1. Snapshot the production database and note its id.
2. Confirm `DEV_UPLOAD_STUB` is not set on the service.
3. Leave `RECEIPT_PUBLIC_URL` unset unless the web `/r/*` rewrite is live and checked with the curl in the admin API doc (G5.2.0b).

**After:**
1. `GET /health/version` returns the release commit.
2. Smoke test:
   - one cash sale and one refund (stored with `...Minor` fields);
   - a receipt link opens;
   - Settings shows the new Connectors section, all off;
   - upload a receipt logo, which must return a real storage URL, not `dev-upload.invalid`;
   - create an API key and revoke it.
3. Give the insert-only grant on `posreceiptdeliveries` and `posfiscalrecords`, as on the other ledgers.
4. Next morning: one audit seal per store per day (section c, step 11).

**Scheduled jobs on several instances (G6.1):** every POS job that writes or calls a provider holds the shared MongoDB lease (`job_leases`).
- **Fiscal:** the sweep holds `pos:fiscal-sweep`, and each provider call (sweep and sale-time) holds `pos:fiscal:<type>:<id>`. This is new in G6.1, and tested: two runners make one call, and an expired lease is taken over.
- **Nightly seal:** `pos:audit-seal`.
- **Payments poller:** per-intent leases.
- **KYB retention:** its own lease.

The full list is in G4_8_ADMIN_API §20 and G5_CLOSEOUT (G6.1). Main's own crons use a Redis lock without renewal. That lock is not changed here; see the note in G5_CLOSEOUT.

### a.5 Rollback
1. If `RECEIPT_PUBLIC_URL` was set, unset it first. QRs printed with that origin keep working while the web proxy points at the API.
2. On `main`: `git revert -m 1 <release merge>`, push (on Jami's go), and let the service redeploy.

Everything is additive:
- the new collections and fields stay, unread;
- the switches were off;
- no data fix is needed.

API keys created in the meantime simply stop working while the routes are gone.

### a.6 Order of steps (same process as the first merge, 2026-11-12)
1. **Backup tags:** `backup/main-pre-release-2` on `origin/main` and `backup/jamibranch-pre-release-2` on `feature/jamibranch`; push the tags.
2. **Merge `origin/main` into `feature/jamibranch` again** if main has moved since `2cd32a5` (merge, no rebase). Conflicts in money, permissions, ledgers or auth → stop and ask.
3. **CI green** on that commit (`Tests (solvexo-api, feature/jamibranch)`).
4. Locally on a clean `main` = `origin/main`: `git merge --no-ff feature/jamibranch -m "Merge feature/jamibranch: Solvexo POS backend release #2 (G5.2–G5.8)"`. Its tree must equal the CI-green branch tree (`git diff --stat feature/jamibranch HEAD` is empty).
5. **Stop. Push `main` only on Jami's "go"**, then tag `pos-backend-g5.8` and add a row to the deploy log in `G1B_RUNBOOK.md`.
6. Deploy check by Jami (the service auto-deploys from `main`), then the "after" steps in a.4.

**Note: the GitHub "Deploy solvexo-api" workflow on `main` fails at SSH** ("dial tcp … i/o timeout"; its last 3 runs failed, 2026-11-12/13). The deploy that counts is the service's own auto-deploy from `main`, as at the first merge. Jami should confirm that path, or fix the VPS runner, before release #2.

## b. POS app release (`pos`, Android and iOS)

### b.1 Version
| | Now | Next |
|---|---|---|
| `pubspec.yaml` | **`1.0.1+102`** (G6.2; G6.1 built `+101`, not uploaded; the closed-testing build was `1.0.0+100`) | `+103` and up for each later upload |
| `lib/config/app_version.dart` | `1.0.1` / `102` (a test fails if it differs from the pubspec) | bumped together |
| Android | `versionName` / `versionCode` come from the pubspec | — |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` come from the pubspec | — |

Bump the build number (`+N`) on every upload. Bump the name for a user-visible release.

### b.2 Android signing
- **Signing setup:**
  - `android/key.properties` is present on Jami's Mac with all four keys.
  - Its `storeFile` points **outside the repo**, to `~/solvexo-pos-release.jks`, which exists.
  - Both are git-ignored (`android/.gitignore`) and **not tracked**.
- **A release build without the key fails clearly.** `build.gradle.kts` stops any `*Release` assemble, bundle or package task if `key.properties` is missing or incomplete, or the keystore file is absent. It never falls back to debug signing.
- **Release build type:**
  - R8 minify and resource shrinking are on, with `proguard-rules.pro`.
  - Crashlytics mapping upload is on.
  - `compileSdk` and `targetSdk` are 36.
- **Release build (G6.0, 2026-11-13):** `flutter build appbundle --release --dart-define-from-file=config/env/prod.json` → `build/app/outputs/bundle/release/app-release.aab`, 71.3 MB, Gradle about 18 min. **Not uploaded.**
  - Signed with the release keystore, not the debug key. Certificate SHA-256 `2C:1F:C1:BE:…:76:E1`; the debug key's is different.
  - No local API URL in the bundle.
  - The certificate's owner fields are all "Unknown": the keystore was created with default names. That's valid for Play, but confirm it is the intended upload key.
  - Only warnings were Java "source/target value 8 is obsolete" from plugins.
- **Release build G6.2 (2026-11-13), the one to upload next:** same command, 71.3 MB AAB, **not uploaded**.
  - **versionName `1.0.1`, versionCode `102`** (read from the bundle's manifest).
  - **Signed with the same release key:**
    - SHA-1 `4F:78:DA:13:86:82:CC:0D:B6:B2:CE:A8:42:C5:BC:D1:4F:98:D1:58`
    - SHA-256 `2C:1F:C1:BE:3E:22:EB:E7:0F:D3:27:B7:6D:EF:06:CC:D1:58:58:07:EF:ED:8F:A8:8C:93:7E:4E:71:25:76:E1`
  - **Inside:** `https://api.solvexo.store` and the `/pos/capabilities` probe. No local or dev URL, and no `dev-upload.invalid`.
- **Release build G6.1 (2026-11-13):** `flutter build appbundle --release --dart-define-from-file=config/env/prod.json` produced a 71.3 MB AAB. **Not uploaded.**
  - **versionName `1.0.1`, versionCode `101`** (read from the bundle's manifest).
  - **Signing certificate:** the same release key as G6.0. Compare these with the upload key certificate in Play Console → App integrity:
    - **SHA-1** `4F:78:DA:13:86:82:CC:0D:B6:B2:CE:A8:42:C5:BC:D1:4F:98:D1:58`
    - **SHA-256** `2C:1F:C1:BE:3E:22:EB:E7:0F:D3:27:B7:6D:EF:06:CC:D1:58:58:07:EF:ED:8F:A8:8C:93:7E:4E:71:25:76:E1`
  - **What's inside:** `https://api.solvexo.store`; no `localhost` or `127.0.0.1` URL; no `dev-upload.invalid`.
  - No signing material was created or changed.
- **Open (Jami):** confirm this keystore is the real **upload key**, enrol the app in Play App Signing, and keep a second, offline copy of the `.jks` and its passwords. Losing it means a new listing.

### b.3 App ids and iOS signing
- **Android:** `applicationId` and `namespace` are `com.solvexo.solvexo_pos`.
- **iOS:**
  - bundle id `com.solvexo.solvexoPos` in all three configurations;
  - team `55484V7RTR`;
  - automatic signing, with no provisioning profiles pinned;
  - entitlements: Sign in with Apple.
- **No build flavors.**
- **Open (Jami):**
  - create the App Store distribution certificate and profile (the earlier archive could not be exported: no signing certificates, `phase5G1_and_5H_summary.md`);
  - finish the Sign in with Apple setup in the Apple Developer account.
- **The ids differ in form** (`solvexo_pos` vs `solvexoPos`). Both are valid and both are fixed once published. Confirm before the first upload.

### b.4 Permissions: declared vs used
| Capability | Android | iOS (usage text in `Info.plist`) | Used by |
|---|---|---|---|
| Camera | `CAMERA` (feature not required) | `NSCameraUsageDescription`: scan barcodes; photo of the store logo or verification documents | `mobile_scanner` (scanning), `image_picker` (camera) |
| Photos | not needed (system picker) | `NSPhotoLibraryUsageDescription`: a photo you choose, for the logo or a verification document | `image_picker` (gallery) |
| Bluetooth printer | `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT`; legacy `BLUETOOTH` / `BLUETOOTH_ADMIN` and location capped at API 30 | `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`: only to find and print to the receipt printer | `print_bluetooth_thermal` |
| Network printer | `INTERNET` | `NSLocalNetworkUsageDescription`: printer on the shop's network, print and open the drawer | raw TCP printer transport |
| USB | none | — | **not used** (no USB printer support in the app) |
| Files | none | — | `file_picker` (KYB PDF, CSV import): system picker, no permission |
| Location, microphone, notifications | none (location only legacy BT ≤ API 30) | none | not used |

- Nothing is declared but unused, and nothing is used but undeclared.
- Other manifest settings:
  - `usesCleartextTraffic="false"`;
  - backup rules are set;
  - biometric permissions are removed;
  - `ITSAppUsesNonExemptEncryption = false`;
  - `PrivacyInfo.xcprivacy` is present (no tracking).

**Fixed in G6.0:** `permission_handler` compiles iOS permissions out unless they're enabled in the Podfile. Without the `PERMISSION_CAMERA` and `PERMISSION_BLUETOOTH` macros, the Permissions screen would show camera and Bluetooth as denied on an iPhone. Scanning itself was not affected, because `mobile_scanner` asks for the camera on its own. The macros are now set in `ios/Podfile` (row 37 of the device plan checks it).

### b.5 Production vs staging: how the app picks its API
- **There are no flavors.** The API comes from `--dart-define-from-file=config/env/<env>.json`:
  - `API_BASE_URL` sets the API; its fallback in `ApiConstants` is `https://api.solvexo.store`;
  - `APP_ENV` is a label for the About screen and Crashlytics, default `dev`.

| File | `APP_ENV` | `API_BASE_URL` |
|---|---|---|
| `prod.json` | prod | `https://api.solvexo.store` |
| `staging.json` | staging | `https://api.solvexo.store`, **the production URL** (go_no_go B6) |
| `dev.json` | dev | `http://localhost:3000` |
| `local.json` | dev | `http://localhost:3102` |

**What stops a release build from pointing at a dev or local API:** `AppEnv.validate(release: kReleaseMode)` runs first thing in `main()`.

In a release build it refuses:
- any non-https URL;
- `localhost`, `127.*` and `10.0.2.2`;
- `*.local`, `10.*` and `192.168.*`.

The app then shows only "Build configuration error …" and **never starts or makes a request**. `test/store_release_test.dart` covers these cases, and checks that the URL appears in exactly one place and that the shipped default passes.

A release built with `dev.json` or `local.json` therefore cannot talk to a dev API, but the **build itself succeeds**. The check runs at launch, not at build time.

**What to do:**
- **Always build store uploads with `--dart-define-from-file=config/env/prod.json`.** Without it the API is still production (the fallback), but the About screen and Crashlytics say `dev`.
- **The staging build talks to production** until the web or ops team provides a real staging API URL. Until then, do the device tests (section d) with a **test store on production**, or get a staging URL first. That item is on the go/no-go list.

### b.6 Store listing: still needed
| Item | State | Who |
|---|---|---|
| App icon and splash | **Placeholders** in `assets/icon/*`; vector master and monochrome symbol not received (`APP_ICON_MASTERS.md`) | Sir Atiq / designer |
| Store screenshots (8 per platform) and the Play feature graphic 1024×500 | Not made (dev shots only); list in `store_submission_checklist.md` §8 | Jami |
| Privacy policy URL | Draft page `https://account.solvexo.store/privacy`: placeholders and legal review open | Sir Atiq (legal), web team (publish) |
| Account deletion web URL | `https://account.solvexo.store/delete-account`, domain to confirm | Web team |
| Data safety (Play) / privacy labels (App Store) | Answers drafted (`store_submission_checklist.md` §3–§5); enter them in the consoles | Jami |
| Reviewer demo store (active plan, password owner) | Not created | Jami |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` set; confirm | Jami |

Stale lines in `docs/store_submission_checklist.md`, corrected here:
- **"`file_picker` was removed":** it is used for the KYB PDF and CSV import, and a test enforces exactly that.
- **"No URL in code":** there is one production fallback.
- **"Release requires APP_ENV staging/prod":** not checked. Only the URL is checked.

### b.7 Closed testing against today's production API (G6.1, detection hardened in G6.2)
The closed-testing app talks to production, which still runs the G5.1 backend (`c889af0`) until release #2.

**How the app decides (G6.2):** one explicit probe, `GET /api/pos/capabilities`.

| Answer | Decision |
|---|---|
| 200 with `features` | Newer. Each feature is shown when it is listed |
| 200 without `features`, or the framework's own "Cannot GET" 404 (the route is absent on G5.1) | Older |
| Network error, 5xx, 401/403, a proxy page, or a 404 with our own `code` | Inconclusive: the last decision stands |

- No other request can affect the decision; an ordinary 404 never does.
- It is re-checked on every app start, when the home screen opens (after login or device setup) and on a store switch.
- The last answer is cached per API base URL for offline starts. With nothing known yet, features are shown as before.
- Once release #2 is live, the next start shows the features. No reinstall and no clearing of data are needed.

**Older backend:**
- **Hidden:** Integrations, Payments setup, the receipt logo and the product page. Role presets were already hidden, since that server sends none.
- **Falls back:** send receipt (share and WhatsApp only), the card terminal (switch absent), fiscal (nothing printed), and connector wording.

**Proven against a real G5.1 stack** (`tool/run_older_backend_e2e.sh`): 8 core flow files and 29 tests, all passed. Mocked tests: `test/older_backend_test.dart` and `test/g62_capabilities_test.dart`.

## c. Production data steps: order and timing

The commands, checks and rollbacks for each step are in `G1B_RUNBOOK.md` (section numbers below). Nothing here has been run on production yet (deploy log, 2026-11-12).

| # | Step | Runbook | When | How long | Gate before the next step |
|---|---|---|---|---|---|
| 1 | Pre-flight (read-only user, `preflight/preflight.js`) | §1 | Before release #2 | Minutes | Report reviewed; any off-grid count > 0 explained |
| 2 | **Minor-unit backfill, dry run on a restored copy** (`pos-g1b-minor-backfill.ts up --dry-run`), then a real run on the copy, then a second run (must write 0), then the flip report (0 storage mismatches) | §2 | After the pre-flight | About an hour on the copy | Outputs reviewed |
| 3 | Throughput measured on the copy (batch 250 / 1000) → production window | §3 | Same session as 2 | Minutes | Window agreed in minutes |
| 4 | **Fresh snapshot**, then production backfill (dry run, then real run with the measured batch size; `--resume` if it stops) | §4 | After release #2 is live and smoke-tested | The measured window × 1.5 | Second run writes 0; flip report clean; first shift closes correct |
| 5 | **14-day burn-in**: daily flip report, every payment path exercised (cash, card, split, full and partial refund, held, offline sync, shift close with card variance) | §5 | Day 0 = the step 4 date | ≥ 14 consecutive clean days | Report says `READY` |
| 6 | **G1b read flip (step f)**: reads switch to the minor fields. Separate approval and separate release | §5.3 | Only after step 5 is `READY` and approved | One deploy | Approved by Jami |
| 7 | **§6 credit-note backfill (`CN-B`)**: only if the dry run on the copy shows pre-G2.5 refunds or voids | §6 | Any quiet period after release #2; independent of the burn-in | Minutes | Second run `candidates 0`; hash check of the `down` rehearsal on the copy |
| 8 | **§7 store-credit ledger switch**: rehearse on the copy (`up`, `down`, hash), then production `legacy → migrating → new` | §7, §7a | After release #2, in a quiet window | Window measured at seconds for 30k rows; the API is restarted twice | All 6 go / no-go items in §7a |
| 9 | **§8 supply cost twins backfill** | §8 | Any quiet period after release #2 | Minutes | Second run writes 0; mismatch counters 0 for a day |
| 10 | **Insert-only grants** for the app's database role on every append-only collection (G1a ledgers plus `purchasereceipts`, `supplierledgerentries`, `posexpenses`, `posexpenseevents`, `posattendanceevents`, `posauditseals`, `posreprintevents`, `posreceiptdeliveries`, `posfiscalrecords`; see section a.3 for the full list of new ones) | §9–§11 | After the backfills that need update rights (2, 4, 6, 7, 8 use a maintenance user) | Minutes | One test sale and one refund still work under the restricted role |
| 11 | **Nightly seal on one instance only**: confirm one API instance runs, or that the lease `pos:audit-seal` is held by one instance per night (lease collection plus the seal log). The fiscal sweep needs the same check when fiscal is switched on (section a.5) | §10.2 | The first night after release #2, then after any scale-out | Next morning | One seal per store per day; no duplicate-key errors in the log |

Steps 7–9 do not depend on each other or on the burn-in. Run them one at a time, each with its own snapshot.

## d. Real-device test plan

All items from G3_CLOSEOUT §5, G4_CLOSEOUT §5 and §7, and G5_CLOSEOUT (G5.1 and G5.2–G5.7), merged and grouped by device. Install a release-mode build (section b.5). **The staging build currently talks to production**, so use a test store, or get a staging URL first.

- **Session 1** (about 2 h): the Android phone, the 58 mm printer and the cash drawer.
- **Session 2** (about 2 h): the iPhone, the Android tablet, the 80 mm printer and the scanner.

Mark each row P or F; for an F, write what happened.

### Any phone (run on the Android phone and repeat the ✱ rows on the iPhone)
| # | Check | Expected result | P/F |
|---|---|---|---|
| 1 ✱ | Install staging; register the device; owner login, then PIN login (manager, cashier); wrong PIN 5 times | Each login works; lock-out message in words | |
| 2 ✱ | Light and dark mode on the new screens; text scale 1.0 and 1.5; smallest phone | Nothing clipped | |
| 3 ✱ | Camera scan: add to cart, repeated scans, torch; deny the camera permission | Items added; the torch works; when denied, a fallback with a manual entry box | |
| 4 | Cash, card, split and Raast QR (mock) sales | Each completes; totals right | |
| 5 | Card on a separate bank terminal: enter the approval code from a real slip; leave it empty | Sale saved with code and last4; empty code refused in words; shift close card-terminal line matches the terminal's settlement | |
| 6 | Return, refund and void: cash from the drawer, another till paying, refund to store credit | Drawer and credit note right | |
| 7 | Stock count by scan (camera and manual); adjustment above the limit | Asks for a manager PIN | |
| 8 | Lot sale: FEFO text, expired lot blocked, manager PIN override, return goes back to the lot | As written | |
| 9 | Add a customer at checkout (same phone gives the same person); store-credit tender online (disabled offline); loyalty redeem | As written | |
| 10 | PO: create → approve (manager) → send; cashier receives part with a lot (no costs visible); expiry date in the past warns; over-receipt refused; supplier return; pay from the drawer | Shift close shows the payment | |
| 11 | Scan to add on a PO; scan to receive | Lines added and received | |
| 12 | Cash in and out per category; above the limit | Manager PIN asked | |
| 13 ✱ | Expense with a receipt photo from the camera and from the gallery; "View receipt" | Image opens; nothing left in the gallery or cache | |
| 14 ✱ | **Expense with a PDF receipt → "View PDF receipt"** (G5.8) | Opens in the in-app viewer; print and share work | |
| 15 ✱ | **Sale detail → view the receipt PDF; documents → tax invoice and credit note → View PDF** (G5.8) | Viewer opens; print dialog (AirPrint / Android print); share sheet | |
| 16 | Daybook today: line order, "reconciled", tap a sale line; share the A4 PDF | As written | |
| 17 | A cash-out with a slip photo → open it from the daybook (staging storage) | Photo opens | |
| 18 | Clock in, break, clock out; a double tap doesn't double count; Home card shows the next shift; roster week; correction needs a reason; share the attendance PDF | As written | |
| 19 | Clock someone else: their PIN works; a wrong person's PIN is refused; a manager's PIN works; airplane mode refuses in words | As written | |
| 20 | Reprint as a cashier with "Manager PIN to reprint" on | PIN sheet, then "REPRINT #n"; offline refused in words | |
| 21 | Documents: a new tax invoice prints "ORIGINAL", then "REPRINT #1"; a credit note likewise | As written | |
| 22 ✱ | CSV import: a .csv from Files (iPhone) or Downloads (Android); a 3 MB file; an .xlsx | Row count shows; the 3 MB file and the .xlsx are refused | |
| 23 | A manager with "Hide costs from managers" on: reports, inventory, POs, payables | Notice shown, never zeros | |
| 24 ✱ | Share link from a sale → open it on another phone | Receipt page opens | |
| 25 ✱ | WhatsApp: on a phone with WhatsApp; on one without | Chat opens with the customer's number and the link; without WhatsApp, the share sheet opens | |
| 26 | E-mail and SMS receipts with real credentials (store switches on) | Delivered; limits enforced (3 per sale per hour) | |
| 27 | Integrations: export the accounting CSV; open it in Excel or Numbers | Right columns; the store's time zone | |
| 28 | Integrations: create an API key (shown once, Copy), call `/api/pos/ext/v1/sales` with it, then revoke it | Works, then 401 after revoking | |
| 29 | A till never online since install prints a receipt; then one online start | No QR at first, then the QR | |

### Airplane mode (Android phone; repeat rows 30 and 31 on the iPhone)
| # | Check | Expected result | P/F |
|---|---|---|---|
| 30 ✱ | Sale offline → reconnect | Synced once; numbers continuous; points earned once | |
| 31 ✱ | Ring a sale offline, print it, scan its QR with another phone; reconnect, wait for sync, scan again | "Your receipt is syncing", then the receipt | |
| 32 | Cash in and out and a drawer expense offline | "Waiting to sync"; synced once in order; close shift blocked while any is waiting; one made in a shift that was closed meanwhile goes to Needs attention | |
| 33 | Receipt photo taken offline | Uploads after reconnect; the local file is gone afterwards | |
| 34 | Clock in and out offline; then set the device clock +1 h and −1 h | Hours right; a wrong-clock event is flagged for the manager, not lost | |
| 35 | Supply, daybook and report screens offline; PO list and roster | "Needs an internet connection"; "last synced … read only" | |

### Lifecycle
| # | Check | Expected result | P/F |
|---|---|---|---|
| 36 ✱ | Kill the app mid-sale and mid-receipt; background it for 10 min; low battery and low storage | Restored; nothing duplicated; no crash | |
| 37 | Android: the back button on every sheet; runtime permissions (camera, photos, Bluetooth) | Each behaves | |
| 38 | iPhone: share sheet, camera permission prompt text, safe areas on a Dynamic Island model | Correct text; nothing under the island | |

### Android tablet
| # | Check | Expected result | P/F |
|---|---|---|---|
| 39 | Rows 1–4 and 30 on the tablet layout; rotation and split-screen | Layout holds; no clipped text | |
| 40 | Needs-attention screen title (known issue: renders very large) | Note whether it's still there | |

### 58 mm printer (Bluetooth) and 80 mm printer (Bluetooth or USB)
| # | Check | Expected result | P/F |
|---|---|---|---|
| 41 | Hardware check: the test page on each width | Prints fully | |
| 42 | Receipt with QR, barcode and points | QR opens the digital receipt; the barcode scans as the receipt number; nothing cut off | |
| 43 | Receipt with the **store logo** (logo switch on) | Logo centred; dithering legible | |
| 44 | Tax invoice with QR at the printed size; credit note | Scans; nothing cut off | |
| 45 | Fiscal: with the fiscal switch on in test mode (mock), sale online and sale offline | "FBR …" number and QR, or "Fiscal pending"; offline prints "Fiscal pending" | |
| 46 | Daybook print | Fits the width | |

### Barcode scanner (USB or Bluetooth HID)
| # | Check | Expected result | P/F |
|---|---|---|---|
| 47 | Hardware check box; keep scanning on the Sale screen | Each scan adds once, under 300 ms (acceptance target) | |
| 48 | Scan to receive and stock count with the scanner | As with the camera | |

### Cash drawer (through the printer)
| # | Check | Expected result | P/F |
|---|---|---|---|
| 49 | Hardware check, "open drawer" | Opens | |
| 50 | A cash sale; a card sale | Opens on cash only | |

### Hallway test (acceptance target "usable without training")
| # | Check | Expected result | P/F |
|---|---|---|---|
| 51 | A real cashier, no help: ring 3 items, take cash, print, refund one item | Done without asking; note where they hesitated | |

## e. Go / no-go before the app goes to the stores

Owner: **Done** means verified in this repo, CI or the release build. **Mine** = Jami. The rest are named.

| # | Must be true | Owner |
|---|---|---|
| 1 | Backend release #2 merged to `main` and running (`/health/version` = release commit), smoke passed | Mine (go, deploy check) |
| 2 | The production deploy path confirmed (service auto-deploy; the GitHub SSH deploy job fails today) | Mine |
| 3 | Production backfill (G1b §2–4) done and burn-in started; the app does not need the read flip to ship | Mine |
| 4 | Insert-only grants on all append-only collections; one seal per store per night | Mine |
| 5 | `API_PUBLIC_URL` set and boot-checked; `DEV_UPLOAD_STUB` not set | Done (2026-11-12) / Mine (confirm the stub variable) |
| 6 | Release build: Android AAB with `prod.json`, signed with the release key, R8 on | Done (G6.1: 1.0.1 / 101, fingerprints in b.2) |
| 7 | A release build cannot run against a dev or local API | Done (`AppEnv.validate`, `store_release_test.dart`) |
| 8 | The release APK installed and used on a real Android phone (R8 never run on a device yet) | Mine |
| 9 | The upload key confirmed (compare the b.2 fingerprints with Play Console) and Play App Signing enrolled; an offline backup of the keystore | Mine |
| 10 | iOS distribution certificate and profile, archive exported, TestFlight build symbolicates; Sign in with Apple configured | Mine |
| 11 | Real-device test plan (section d) run, all P or accepted | Mine |
| 12 | A real staging API URL (today `staging.json` = production) **or** a decision to test on a production test store | Web team / Sir Atiq |
| 13 | Final app icon and splash masters | Sir Atiq (designer) |
| 14 | Store screenshots and the feature graphic | Mine |
| 15 | Privacy policy published and legally reviewed; deletion URL domain confirmed | Sir Atiq / Web team |
| 16 | Data safety and privacy labels entered; reviewer demo store and login | Mine |
| 17 | Role presets signed off (still "Proposed" in the app) | Sir Atiq |
| 18 | `RECEIPT_PUBLIC_URL` + web `/r/*` rewrite (optional: without it receipts use the API origin, which works) | Web team |
| 19 | E-mail / SMS receipts: SMTP and store SMS gateways (optional: the buttons hide when off) | Provider (SMS) / Mine (SMTP) |
| 20 | Raast real adapter (PayFast or 1LINK); until then Raast stays on the mock and should be **off** for real stores | Provider |
| 21 | FBR fiscal: route decision, then a backend adapter that fills FISCAL_CONTRACT.md (main's FBR DI client is a candidate). The app needs no change; the sweep lease is built (G6.1); the switch cannot be turned on until a provider exists | Sir Atiq + Uzair / Provider |
| 22 | Card gateway provider (optional: card on a separate terminal already works) | Sir Atiq / Provider |
| 23 | Khata decision on main's module (does not block the app) | Sir Atiq + Uzair |
| 24 | Backend CI green on the release commit; app CI green | Done (at the time of writing; recheck on the release commit) |
| 25 | The closed-testing app is safe on the G5.1 production API (release #2 features hidden, core flows pass) | Done (G6.1, b.7) |
