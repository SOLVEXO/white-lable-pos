# Phase 5F.1 fix-ups + Phase 5G (Solvexo Account web portal) — Summary

Repos: `solvexo-api` and `pos/` on `feature/jamibranch` (pushed); `solvexo-account-web/` is a new local repo on `main` (committed, **no remote yet**). Nothing on `main` of the API/POS repos.

Note: the test-gap work formerly planned for 5G moves to 5H with the release candidate.

## 5F.1

| # | Item | Result |
|---|---|---|
| 1 | Sign in with Apple (iOS owner login) | ✅ Button under Google, same size, iOS only; SHA-256 nonce; reuses `POST /api/auth/social-login` (`authProvider:'apple'`, `role:'seller'`). Backend: `APPLE_CLIENT_ID` is now a **comma-separated audience list** (bundle id + web Services ID); Apple email counts as verified only when `email_verified` is true; `email` in the DTO is optional. Same linking rule as Google (same verified email → same account). Entitlement `Runner.entitlements` wired for Debug/Release/Profile. **Caveat:** an Apple login whose token has no verified email can't link to an existing password account and can't create one (401); it only works if an account for that Apple id already exists. |
| 2 | Account deletion for social owners | ✅ `POST /api/seller/account-deletion` takes `{password}` **or** `{authProvider, socialId, token}` (fresh Google/Apple token, verified server-side; must match the seller by provider id or verified email). `GET` status now returns `hasPassword`, `authProvider`. Wrong identity → 403 `INVALID_REAUTH`; a passwordless account can't use an empty password. App shows password field and/or "Re-authenticate with Google/Apple". Apple-only owner on Android is told to use iOS or the web portal. |
| 3 | Export compliance | ✅ Queue crypto now runs on OS providers via `cryptography_flutter` (verified in plugin source: CryptoKit `AES.GCM` on iOS, `Cipher AES/GCM/NoPadding` on Android). Same Keychain/Keystore key. The byte layout is compatible, so old `v1:` values decrypt unchanged; new writes are `v2:`. Rows are re-encrypted per row in a transaction, only if unchanged since read (idempotent, crash-safe; a row whose key is gone stays "unreadable" and discardable). `ITSAppUsesNonExemptEncryption=false`. Reasoning in checklist §2, **marked FOR OWNER TO CONFIRM**; caveats: Flutter's HTTPS runs on BoringSSL inside the engine, and the pure-Dart AES-GCM fallback is still linked (never used on device). If your advisor is uneasy, set the key back to `true`. |
| 4 | Network printers | ✅ ESC/POS over TCP (default port 9100), both platforms, plain `dart:io` sockets with timeouts. Add by IP+port+name (validated; loopback/multicast refused); best-effort discovery probes the device's /24 (capped, cancellable, progress). Same settings as Bluetooth (paper width, auto-print, copies, drawer kick), test page, drawer test, remembered printer, one reconnect, plain-language errors, fire-and-forget after the sale is saved (offline-queued cash sales still kick the drawer). `NSLocalNetworkUsageDescription` added (no Bonjour: no mDNS). Matrix in checklist §6: **Android = Bluetooth Classic + network; iOS = Bluetooth LE + network + PDF/AirPrint.** |
| 5 | Crashlytics dSYM phase | ✅ Run Script phase added to the Runner target (after embed; `${PODS_ROOT}/FirebaseCrashlytics/run` with the FlutterFire input files). `xcodebuild -list` parses; the release archive contains dSYMs. |

## 5G — Solvexo Account web portal (`solvexo-account-web/`, commit `303a53e`)

React + Vite + TypeScript, static (Vercel), clay/terracotta tokens taken from the apps.

- **Public (no login):** `/privacy`, `/terms`, `/support`, `/delete-account` (email → OTP → confirm; neutral messaging), `/account-deleted`, `/signin`.
- **Signed in:** `/stores` (POS plan per store: plan, state, expiry, limits), `/stores/:id/plan` (buy/extend, prices in the plan's currency by ISO-4217 exponent, fresh `Idempotency-Key`, Stripe Checkout redirect) + `/plan/success` (polls up to 30 s for webhook delay) + `/plan/cancel`, `/devices` (list/revoke with confirm), `/account` (delete — password or Google/Apple re-auth — and cancel pending deletion).
- **Auth:** tokens **in memory only** (no localStorage/sessionStorage/cookies; tested). Silent renewal via the new `POST /api/auth/refresh` 60 s before expiry and once on a 401 (shared across concurrent requests; rotation). **Trade-off:** a page reload (or the return from Stripe) signs the user out; success/cancel pages send them to sign-in and back. The HttpOnly-cookie alternative needs backend work (cross-site cookies); documented in the portal README.
- **https only in production:** the build fails if `VITE_API_URL` is missing or not https; also checked at runtime. `vercel.json` has SPA rewrites and security headers incl. CSP (update `connect-src` if the API host is not `api.solvexo.store`).
- **Legal pages are DRAFTS** with a banner, based only on what the apps/backend collect; placeholders `[COMPANY LEGAL NAME]`, `[ADDRESS]`, `[SUPPORT EMAIL]`, `[JURISDICTION]`, `[DATE]`, retention periods, refund policy, processor list. Needs your legal review.

### Backend additions (API commits `331d795`, `74beef0`)
- `POST /api/auth/refresh {refreshToken}` → rotated `{accessToken, refreshToken}`. Refresh tokens now carry `typ:'refresh'`; refused: tokens without `typ` (old ones were never usable), POS-type tokens, `tokenVersion` mismatch, suspended/deleted/pending-deletion/soft-deleted accounts. `JwtStrategy` also rejects `typ:'refresh'` as a bearer on every other route.
- Public deletion: `POST /api/public/account-deletion/request-otp {email}` (always the same generic 200; mail only for an active seller; 10-min code, 60 s per-email cooldown, IP throttle 5/min) and `POST /api/public/account-deletion/confirm {email, otp}` (5 wrong guesses wipe the code; same rules/side effects as the in-app request — open-shift block, device/token revocation, 30-day grace, audit). A pending-deletion seller can still sign in to cancel (tested).
- CORS: `PORTAL_ORIGINS` (comma-separated exact https origins, http only for localhost, no wildcards/paths), added to the existing whitelist.
- Shared-module changes (all backward compatible) are listed in `docs/buyer_app_changes.md` §5F.1/5G.

## Verification

| Check | Result |
|---|---|
| Backend `npm run build` | ✅ |
| Backend jest (auth, account-deletion, pos, pos-plans; real Mongo; fake Redis/mailer/provider verifier) | ✅ 18 suites passed, 1 skipped (env-gated DI smoke), **314 tests** — new: 22 deletion re-auth/public OTP + 17 refresh cases |
| `flutter analyze` | ✅ No issues (re-run by me) |
| `flutter test` | ✅ **360 passed** (re-run by me) |
| iOS simulator `pos_checkout_flow_test`, `offline_sync_test` | ✅ (workstream run; dev env) |
| `flutter build ipa --release --no-codesign` / `appbundle --release` (prod env) | ✅ archive / 66.1 MB AAB |
| Portal: `npm run build`, eslint, vitest | ✅ 24 tests (re-run by me) |
| Portal Playwright e2e (API mocked) | ✅ 4 tests (public pages, sign-in validation, OTP deletion, password deletion) |
| **Not run** | Sign in with Apple against Apple's servers (needs a device + the App ID capability); any flow against the **real** backend from the app or portal (all faked/mocked); real Google/Apple sign-in on the portal; real printer/drawer hardware; the CryptoKit/Android crypto path on a device (unit tests run the pure-Dart fallback); Android release build on a phone; the entitlement in the archive (unsigned IPA — only the static test confirms the wiring); real Stripe Checkout from the portal. Portal assumptions unverified: store name read from `name`/`storeName` of `GET /api/store/my-stores`; plan limits matched to the catalog by plan name. |

## Apple Developer setup (you)
Team ID in the project: `55484V7RTR`; iOS bundle id `com.solvexo.solvexoPos`.
1. **App ID:** developer.apple.com → Identifiers → `com.solvexo.solvexoPos` → enable *Sign in with Apple*; regenerate the profile (automatic signing does this).
2. **Services ID (web portal only):** Identifiers → Services IDs → e.g. `com.solvexo.account.web` → enable Sign in with Apple → Configure: primary App ID above; Domain = the portal host (no scheme); Return URL = the portal's `VITE_APPLE_REDIRECT_URI` (default `https://<portal>/signin`). HTTPS and a verified domain are required.
3. **Key (.p8):** Keys → "+" → Sign in with Apple → primary App ID → download once, note the Key ID. Not needed for verifying identity tokens (the backend uses Apple's public keys); only if you later do a server-side code exchange.
4. **Backend env:** `APPLE_CLIENT_ID=com.solvexo.solvexoPos,<Services ID>` (comma-separated).
5. **Test on a real device.** Apple returns name/email only on the first authorisation per app (reset under Settings → Apple ID → Sign-In & Security). "Hide My Email" gives a `@privaterelay.appleid.com` address that will not match an existing account with the real address.
6. App Store review: Apple button is as prominent as Google; in-app account deletion works for Apple/Google/password owners.

## Portal deploy steps (Vercel)
1. Push `solvexo-account-web` to the GitHub remote you create; in Vercel: Add New → Project → import it (framework Vite; `vercel.json` has build, output, SPA rewrites, headers).
2. Env vars: `VITE_API_URL=https://api.solvexo.store` (must be https), `VITE_GOOGLE_CLIENT_ID`, `VITE_APPLE_SERVICES_ID`, `VITE_APPLE_REDIRECT_URI=https://<portal>/signin`, `VITE_SUPPORT_EMAIL`.
3. Domain: add the custom domain (`account.solvexo.store` is a **placeholder — confirm**).
4. If the API host differs, update `connect-src` in `vercel.json`.
5. API env: `PORTAL_ORIGINS=https://<portal>`; redeploy the API.
6. Google Cloud Console: add the portal under the Web client's authorised JavaScript origins.
7. Apple: Services ID as above; add it to `APPLE_CLIENT_ID`.
8. Stripe: no dashboard change — the portal passes success/cancel URLs per checkout; the webhook stays on the API (events from the web spec incl. `charge.dispute.closed`).
9. Store consoles: privacy-policy URL `/privacy`, support `/support`, Play account-deletion URL `/delete-account` (checklist updated with these, domain to confirm).
10. Smoke test: `/privacy` signed out; sign in; open a plan page; run a deletion with a throwaway account.

## Needs you (OWNER)
1. Create the GitHub remote for `solvexo-account-web` and push `main`; choose the portal domain.
2. Legal review + fill the placeholders in Privacy/Terms.
3. Confirm the export-compliance answer (`false`) — checklist §2.
4. Apple/Google console setup above; backend env `APPLE_CLIENT_ID`, `PORTAL_ORIGINS`.
5. Real-hardware tests: network/BLE printers + drawer, Apple sign-in on a device, release APK on an Android phone.
6. Still open from before: real staging URL, privacy/support URLs (now the portal's), reviewer demo accounts, screenshots, web purchase page is now this portal (needs the real Stripe flow tested end-to-end before enforcement).
