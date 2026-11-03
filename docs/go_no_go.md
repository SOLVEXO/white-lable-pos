# Solvexo POS 1.0.0 — Go / No-Go

Compiled from every phase summary (5A–5H), `test_gap_matrix.md`, `store_submission_checklist.md`, `web_pos_plan_purchase_spec.md`, `web_dashboard_changes.md`, `buyer_app_changes.md`.
**Blocker** = must be done/confirmed before public store release or before enforcement is switched on. **Pre-launch** = do before launch week but does not block a closed beta. **Post-launch** = tracked follow-up.

## Verdict

**GO for closed beta (TestFlight / Play internal testing) now. NO-GO for public release until the 12 blockers below are closed.**
The code side is release-candidate quality and verified as far as this workspace allows (real-backend end-to-end for the POS flows and the portal, see §A). What remains is almost entirely things only you can do (consoles, legal, hardware, real Stripe) plus verification that needs real devices.

---

## A. What *was* verified for real (no mocks)
- POS app on the iOS simulator against the real local API + MongoDB replica set + Redis: device setup, PIN login, discount (manager), split tender, partial refund/void, offline sale → reconnect → sync (one sale), idempotent retry, close shift (variance 0), plan expiry → restricted mode, device revocation, account deletion (11 flows, `integration_test/real_backend_pos_flows_test.dart`, run with `tool/run_real_e2e.sh`).
- Portal in Chromium against the same API (18 tests, `npm run e2e:real`): sign-in, reload stays signed in, cookie attributes, rotation + reuse detection, CSRF, plans, devices revoke, password deletion + cancel, public OTP deletion. This run found and fixed a real bug (cookie-mode login lacked the CSRF header).
- Backend suites on real Mongo; `flutter analyze` clean; `flutter test` green; release AAB/APK/iOS archive build (see the 5H summary for the final run).

## B. Blockers

| # | Item | Why it blocks | Owner action |
|---|---|---|---|
| B1 | **Real Stripe test-mode Checkout** (purchase, early-renewal stacking, refund, dispute, `charge.dispute.closed`) was **not run** — no Stripe CLI installed and Stripe cannot run on the local stack (`PAYMENT_PROVIDER=manual`); I did not touch your `.env`/keys. | Paid-plan activation is the revenue path and the enforcement precondition; only unit/real-Mongo tests with a stubbed Stripe exist. | Install Stripe CLI, put **test-mode** keys in a dev `.env`, `stripe listen --forward-to …/api/pos-subscriptions/webhooks/stripe`, run the purchase/refund/dispute triggers (spec: `web_pos_plan_purchase_spec.md`). Never live keys. |
| B2 | **Apple sign-in against Apple's servers** (native + web) and token revocation at deletion — only stubbed tests. | App Store 4.8 + 5.1.1(v) rejection risk. | Apple Developer setup (summary 5F.1 §Apple), then test on a real iPhone incl. "Hide My Email", then delete that account after the 30-day grace (or force-purge on staging) and confirm the app disappears from Settings → Apple ID → Sign-In. Set `APPLE_*` env. |
| B3 | **Google sign-in with the release keystore / Play App Signing SHA-1** (#12). | Google login fails on the production build otherwise. | Add the upload **and** Play-signing SHA-1/256 in Firebase/Google Cloud; test the release APK. |
| B4 | **Release APK/AAB never run on a real Android phone** (R8 build). | R8/ProGuard can break at runtime in ways builds don't show. | Install the release APK, smoke-test login, sale, printing, camera scan, offline. |
| B5 | **Real printers and cash drawer** (Bluetooth Classic on Android, BLE on iOS, network 9100, drawer kick) untested. | Core POS function; printer firmware varies. | Test the models you will recommend; update the printer matrix (checklist §6). |
| B6 | **Real staging URL** (`config/env/staging.json` still holds the prod URL) and confirmation that `https://api.solvexo.store` is production. | Release builds refuse to start on wrong env; staging builds would hit prod. | Provide URLs. |
| B7 | **Legal**: Privacy Policy and Terms are *drafts*; placeholders `[COMPANY LEGAL NAME]`, `[ADDRESS]`, `[SUPPORT EMAIL]`, `[JURISDICTION]`, retention periods, refund policy, processor list. | Both stores require a real privacy policy URL. | Legal review + fill-ins in the portal. |
| B8 | **Portal domain + Safari cookie check in production.** Cookie sessions need portal and API on one registrable domain; only tested on `localhost` in Chromium. | Otherwise sign-in does not survive a reload in Safari; also the Play deletion URL must be live. | Choose domain, deploy, run the runbook step-5 check in Safari. |
| B9 | **Play account-deletion URL** and App Store/Play privacy/support URLs set to the portal (`/delete-account`, `/privacy`, `/support`). | Play rejects without it. | Enter in the consoles after B8. |
| B10 | **Export-compliance answer** (`ITSAppUsesNonExemptEncryption=false`) — my reasoning is in checklist §2, **for you/your advisor to confirm**. | Wrong answer is a compliance issue. | Confirm or set back to `true`. |
| B11 | **Web terminal/dashboard changes** (`web_dashboard_changes.md` §A) not applied — that code isn't in this workspace. | With enforcement on, an old web terminal that sends client tax / lacks idempotency keys / ignores `POS_PLAN_REQUIRED` breaks. | Web team implements §A **before** runbook step 8. |
| B12 | **Production rollout steps** (`deploy_runbook.md`) executed in order incl. DB backup, preflight, back-fill grants. | Enforcement without the grant locks existing POS users out. | Run the runbook. |

## C. Pre-launch (before launch week)

| # | Item | Notes |
|---|---|---|
| C1 | Reviewer demo store/accounts, reviewer notes, screenshots (checklist §7–8) | Needs a prod/staging demo store with a plan. |
| C2 | Xcode: signing, team, bundle id finalisation (`com.solvexo.solvexoPos` iOS vs `com.solvexo.solvexo_pos` Android), upload keystore `~/solvexo-pos-release.jks`, IPA export | No certs here — only unsigned archive built. |
| C3 | Crashlytics live delivery check (+ dSYM upload on a signed archive) | Phase added; delivery unverified. |
| C4 | Plan pricing/durations/limits (`maxRegisters/maxEmployees/maxLocations`) decided and created in admin | Default: no limits. |
| C5 | Apple private email relay: register the API's mail-sending domain (portal `DEPLOY.md`) | Otherwise mail to `@privaterelay.appleid.com` is dropped (receipts/OTP). |
| C6 | Seller web purchase flow smoke test in production with a real card for the smallest plan | After B1. |
| C7 | Android emulator/dev path for network printers (cleartext disabled in the manifest — correct for release) | Real devices only. |
| C8 | GitHub remotes: create `solvexo-account-web` remote and push; branch protection; CI (`.github/workflows/ci.yml` was added but has never run on GitHub) | |
| C9 | Draft-orders customer search leak on the shared web route (platform-wide user search) — decision pending (`phase5_decisions.md` §4.6) | POS route is fixed; shared route unchanged. |
| C10 | Stripe `successUrl`/`cancelUrl` accept any http(s) host — restrict to `PORTAL_ORIGINS` (shared with web dashboard, so coordinate) | Low risk; open-redirect-style. |
| C11 | Accessibility pass with VoiceOver/TalkBack (#29); English-only v1 is a documented decision | Manual. |
| C12 | Monitoring/alerts for webhook failures, oversell, Apple revocation retries, purge cron | Logs exist; alerting is yours to wire. |

## D. Post-launch

| # | Item |
|---|---|
| D1 | Disable legacy auth (`POS_LEGACY_AUTH_ALLOWED=false`) after all devices are registered (runbook step 9). |
| D2 | Localisation (deferred by decision). |
| D3 | Marketplace-leftover/dead-code prune beyond what 5H touched; BaseController decision. |
| D4 | Refresh-family absolute lifetime cap (families currently slide 7 days per rotation). |
| D5 | Per-IP throttle behaviour only asserted as metadata in tests — load-test in staging. |
| D6 | Optional: LAN printer discovery beyond best-effort /24 probe; Bonjour. |

## E. Known behaviours to accept or schedule
- Offline oversell is **accepted-and-flagged**, not rejected (decision Q7) — managers review `stockConflict`.
- Apple "Hide My Email" users get a relay address as the account email; it will not auto-link to an existing account with their real address (by design, per D-rule: linking only by verified email match).
- iOS has no Bluetooth Classic printing (CoreBluetooth LE only) — typical cheap 58 mm Classic printers need the network (Wi-Fi) model or PDF/AirPrint on iPhone.
- The portal cookie session requires the shared-registrable-domain setup.
- After deleting an owner account, a 30-day grace applies; Apple token revocation happens at purge.
