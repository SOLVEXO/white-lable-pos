# Solvexo POS — store submission checklist

Everything below is based on what the app actually does today (code of Phase 5F). Items marked **OWNER** need a decision or an account action from you.

## 0. Build commands
| | Command |
|---|---|
| Config | `config/env/{dev,staging,prod}.json` hold `APP_ENV` + `API_BASE_URL`; there is **no URL in code**. Release builds refuse to start (they show a "Build configuration error" screen) unless the URL is `https`, non-local and `APP_ENV` is `staging`/`prod`. |
| Android | `flutter build appbundle --release --dart-define-from-file=config/env/prod.json` |
| iOS | `flutter build ipa --release --dart-define-from-file=config/env/prod.json` (needs your signing identity; `--no-codesign` produces the `.xcarchive` only — verified) |
| Version | `pubspec.yaml` `version: MAJOR.MINOR.PATCH+BUILD` → store version name + build number. Increase **BUILD on every upload** (Play `versionCode`, App Store `CFBundleVersion`). |
| Icons / splash | One source: `assets/icon/app_icon.png` (1024×1024, opaque, full-bleed — derived from `assets/images/logo.png` with its white corner slivers painted orange) and `assets/icon/app_icon_foreground.png` (Android adaptive foreground, 660 px mark on transparent). Replace them, then `dart run flutter_launcher_icons && dart run flutter_native_splash:create`. Splash = brand orange `#F06839` + `assets/icon/splash_logo.png`. |

## 1. Android (Google Play)
- **Target API 36** (`targetSdk = 36`, `compileSdk = 36`). Google Play: new apps and updates must target Android 16 / API 36 from 31 Aug 2026 (checked against Google's published requirement on 2 Nov 2026).
- **R8/minify + resource shrinking ON**; rules in `android/app/proguard-rules.pro` (sqflite, flutter_secure_storage/tink, print_bluetooth_thermal, mobile_scanner/ML Kit/CameraX, Firebase/Crashlytics/Google sign-in, audioplayers, share_plus). The release AAB (66 MB) and APK (88 MB) build cleanly with R8 on. **Not run on a device/emulator at your request** — please install the release APK once on a real phone and walk through: login → device setup → PIN → sale → print → scan barcode (the plugins R8 could break are secure-storage, sqflite, Bluetooth printing and the scanner).
- **Signing**: `android/key.properties` (git-ignored, as are `*.keystore` / `*.jks`):
  ```
  storePassword=…
  keyPassword=…
  keyAlias=…
  storeFile=/absolute/path/to/upload-keystore.jks
  ```
  A release build with the file missing/incomplete or the keystore absent fails immediately with an explanatory message (debug builds are unaffected). Enrol in Play App Signing and keep the upload key backed up. **OWNER:** the current `key.properties` points at `~/solvexo-pos-release.jks` — confirm that is the real upload key.
- **Permissions (merged manifest verified)**: INTERNET, ACCESS_NETWORK_STATE, CAMERA, BLUETOOTH_SCAN (`neverForLocation`), BLUETOOTH_CONNECT; legacy BLUETOOTH, BLUETOOTH_ADMIN and location only for Android ≤ 11 (`maxSdkVersion=30`, required there for Bluetooth scanning). Biometric permissions pulled in by a dependency are removed. Camera/Bluetooth `uses-feature` are optional. Cleartext traffic is off.
- **Backup**: Auto Backup and device-to-device transfer exclude databases, shared preferences, files and external storage (`backup_rules.xml`, `data_extraction_rules.xml`) — the encrypted offline queue's key lives in the Keystore and never moves, so a restored queue would be unreadable; a registered device must be set up again on a new phone.
- Crashlytics gradle plugin uploads the R8 mapping file on release builds.

## 2. iOS (App Store)
- Display name **Solvexo POS**; bundle id `com.solvexo.solvexoPos`; deployment target **iOS 14.0**; team `55484V7RTR` (automatic signing; distribution profile created in Xcode/App Store Connect). **OWNER:** confirm the bundle id and team.
- **Usage strings** (Info.plist): Camera (barcode scanning; store logo / verification photo), Photo Library (only a photo the user picks), Bluetooth (printer only, not location). No location/microphone/contacts keys — none are used. Unused `file_picker` was removed.
- **Privacy manifest**: `ios/Runner/PrivacyInfo.xcprivacy` (no tracking; collected-data declarations below; required-reason APIs: UserDefaults `CA92.1` and file timestamp `C617.1`, used through shared_preferences/path/sqflite). The archive contains the manifests shipped by Firebase, Flutter, sqflite, shared_preferences, secure storage, image_picker, mobile_scanner, permission_handler, share_plus, connectivity_plus, google_sign_in, path_provider, native_splash. **Not shipping their own:** `print_bluetooth_thermal`, `audioplayers_darwin` (and `firebase_crashlytics` itself, covered by FirebaseCrashlytics' bundle) — the app-level manifest covers the APIs they could touch.
- **Export compliance — please confirm in App Store Connect.** `ITSAppUsesNonExemptEncryption = true`. Reasoning: beyond HTTPS (OS-provided, exempt) the app encrypts its offline sale queue on the device with **AES-256-GCM** via the Dart `cryptography` package — i.e. encryption implemented by the app, used only to protect data stored on the device (not to build a communications service). Apple treats such encryption as *not* automatically exempt; it normally qualifies under the US "mass-market" self-classification (ECCN 5D992.c), which needs the encryption question answered "Yes → standard/proprietary algorithms → qualifies for exemption", and may require a French encryption declaration if you distribute in France. If your legal read is that it is exempt (e.g. only authentication/data-protection of the user's own data), flip the key to `false`. **OWNER decision.**
- **Crash symbolication**: add the Firebase "upload dSYM" Run Script build phase (or `flutterfire`'s) in Xcode before the first TestFlight build.
- **Printing on iOS**: BLE printers only (see §6).

## 3. App Store privacy labels ("App Privacy") — answers
Data is linked to the user's account, **not** used for tracking, **not** sold. Tracking = **No**.
| Data type | Collected | Purpose | Linked | Notes |
|---|---|---|---|---|
| Contact info — name, email, phone | Yes | App functionality | Yes | owner/employee account; **customer** name/phone attached to a sale by the seller |
| Purchases | Yes | App functionality | Yes | sales/refund records of the seller's own business |
| User content — photos | Yes (optional) | App functionality | Yes | store logo / verification documents, uploaded only when submitted |
| Identifiers — device ID | Yes | App functionality | Yes | registered-device record (name, platform, last seen); no advertising ID |
| Diagnostics — crash data, other diagnostics | Yes | App functionality (stability) | **No** | Crashlytics; PII is scrubbed before sending |
| Financial info | **No** | — | — | card payments are recorded as "card" + an optional reference; no card numbers are collected or stored |
| Location, contacts, health, browsing, search, advertising data | No | — | — | |

## 4. Google Play "Data safety" — answers
- Data collected: **Personal info** (name, email address, phone number), **Financial info → purchase history** (the seller's own sales), **Photos** (optional upload), **App info & performance → crash logs, diagnostics**, **Device or other IDs** (registered-device id).
- Shared with third parties: **No** (Firebase/Crashlytics and Google sign-in act as service providers; Stripe is used by the *web* plan checkout, not this app).
- Collected data is **encrypted in transit** (HTTPS only). The offline queue is encrypted at rest.
- **Users can request deletion**: **Yes** — in-app (Settings → Delete account, owner password required) **and** a web URL (below).
- Data is **required** for the app's core function except photos (optional) and crash logs.
- Ads: none. Data not sold.

## 5. Account deletion (both stores require it)
- **In-app**: Settings → *Delete account* (owner-only: owner-password gate, then password again + explicit confirmation). Effect: all sessions, devices and staff PIN sessions revoked immediately; stores suspended; **30-day grace** (cancel by signing in on the web → `POST /api/seller/account-deletion/cancel`); then the daily purge de-identifies the owner, employees (names/emails/PINs), customers on sales and receipt/business text, deletes device records — and **keeps sales, payments, refunds and tax figures** (legal record-keeping) with the people removed. Blocked while a shift is open or sales are unsynced. Not refundable: the POS plan.
- **Backend**: `GET/POST /api/seller/account-deletion`, `POST …/cancel` (owner JWT). Accounts that sign in only with Google have no password to confirm with → the API answers `PASSWORD_REQUIRED_FOR_DELETION` and the app points them to the web.
- **Web deletion URL — OWNER / web team.** Google Play requires a public web page where a user can request deletion *without installing the app*. No web dashboard exists in this workspace, so **a page must be created** (e.g. `https://<site>/account/delete`) that signs the seller in (password **or** Google) and calls the endpoints above, and states the same consequences. Enter that URL in Play Console → App content → Data safety / Account deletion. Until it exists the Play submission will be flagged.

## 6. Printing — exactly what is supported
| | Android | iOS |
|---|---|---|
| Printer type | Bluetooth **Classic** (SPP) ESC/POS printers paired in system settings | Bluetooth **Low Energy** ESC/POS printers only (CoreBluetooth; no "paired" list — the picker shows nearby devices) |
| Typical cheap 58 mm Classic printers | ✅ | ❌ (iOS cannot use Classic/SPP without Apple's MFi programme) — use a BLE model or the PDF/Share receipt |
| Paper | 58 mm (32 cols) / 80 mm (48 cols), long names wrap | same |
| Copies, auto-print, cash-drawer kick (ESC p), test page | ✅ | ✅ (drawer must be wired to the printer) |
| Failure behaviour | sale is never blocked or lost; notice + reprint from Orders; PDF/share always available | same |
Settings are per device (Settings → Printer settings; manager/owner edit). Receipts show VOID / REFUNDED / COPY banners and use the sale's own currency decimals.

## 7. Reviewer notes (paste into App Store Connect "Notes" / Play "App access")
> Solvexo POS is a business tool for store owners and their staff. The **POS plan is purchased outside the app, on the web, by business customers** (or granted by Solvexo staff); the app contains no purchase, no prices and no links to buy. If a store has no active plan the app shows "POS plan isn't active for this store".
> **Demo access:** owner sign-in `<email>` / `<password>` (a store with an active plan, 1 register, employees below). Setting up the device: sign in → select store → "Open POS" → *Set up this device* → pick the register. Staff PIN login: `manager@…` PIN `<pin>`; `cashier@…` PIN `<pin>`. Owner-only areas (settings, employees, locations, devices, plan, delete account) ask for the owner password again.
> The app needs a camera (barcode scan; optional) and Bluetooth (receipt printer; optional). Neither is required to review the app.
- **OWNER:** create a dedicated demo store with an **active** plan that never expires (admin manual grant with a long term), 3–5 products with barcodes, one manager and one cashier, and keep the credentials valid for the whole review. Do **not** use a real merchant's store. The demo owner must have a **password** (not Google-only).

## 8. Screenshots needed
Play (phone 16:9 ≥ 2 × up to 8, 7" and 10" tablet if you list tablets) and App Store (6.9"/6.7" iPhone required; 13" iPad if universal — the app is iPhone + iPad): 1) PIN login, 2) product grid / cart, 3) payment with split tender, 4) receipt/print, 5) orders & refund, 6) shift close/report, 7) inventory, 8) offline "will sync" state. Use the demo store; no real customer data; both themes not needed. Feature graphic (Play, 1024×500) and the 1024 icon (`assets/icon/app_icon.png`).

## 9. Other store-listing items
Privacy policy URL and support URL (**OWNER** — must exist and mention Firebase Crashlytics, Google sign-in and the data above); age rating (no user-generated public content → 4+/Everyone); content-rights; target audience = businesses (not for children).
