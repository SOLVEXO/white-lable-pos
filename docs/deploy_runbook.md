# Solvexo POS — Production deploy runbook (v1.0.0)

Run the steps **in this order**. Every step has a *verify* and a *rollback*. Stop at the first failed verify.
Hosts below are placeholders: API `https://api.<domain>`, portal `https://account.<domain>` (**must share the registrable domain** — see the portal's `DEPLOY.md`). Commands run from `solvexo-api/` with production `MONGO_URI` in the environment unless stated.

Safe-by-default flags for the whole rollout: `POS_ENTITLEMENT_ENFORCED=false` and `POS_LEGACY_AUTH_ALLOWED=true` until steps 8 and 9. Nothing in steps 1–7 can lock an existing seller out.

---

## 0. Before you start
- [ ] Owner decisions closed (see `go_no_go.md` blockers): prod/staging URLs, domain, legal pages, Apple/Google consoles.
- [ ] `feature/jamibranch` of `solvexo-api` reviewed and merged by you (never auto-merged to `main`); same for `pos/`.
- [ ] A maintenance window is **not** required (all changes are backward compatible, see `buyer_app_changes.md`), but pick a low-traffic hour.

## 1. Back up the database
```
mongodump --uri "$MONGO_URI" --gzip --archive=solvexo-pre-pos-1.0.0-$(date +%F).gz
```
(or an Atlas snapshot). **Verify:** the archive exists, is non-trivial in size, and `mongorestore --dryRun --gzip --archive=…` lists the collections.
**Rollback:** n/a (this *is* the rollback point). Keep it until step 10 is stable for a week.

## 2. Preflight: open sessions (blocks a unique index)
```
npx ts-node -r tsconfig-paths/register src/scripts/pos-preflight-open-sessions.ts
```
Read-only. Exit 0 = safe. Exit 2 = a register has more than one open session: close all but one (Shift History → force-close, or admin tooling), re-run until exit 0. **Why:** the API builds the unique partial index `uniq_open_session_per_register` on boot; with duplicates present the index build fails.
**Rollback:** n/a (read-only).

## 3. Deploy the API with the safe flags
Set (or confirm) in the production environment **before** the new build starts:
```
POS_ENTITLEMENT_ENFORCED=false
POS_LEGACY_AUTH_ALLOWED=true
```
Deploy the `feature/jamibranch` build (Railway/your host). **Verify:** `GET /health` 200; boot log shows no index-build error; `GET /api/pos-plans` returns the catalog; an existing owner can still sign in and an existing POS session still sells (flags are permissive).
**Rollback:** redeploy the previous API image. New indexes/fields are additive and ignored by the old build; no data migration is applied in this step. (If the unique index was created, the old build still runs; drop it only if you need to: `db.registersessions.dropIndex('uniq_open_session_per_register')`.)

## 4. Set the remaining API environment variables, then redeploy
| Variable | Value / note |
|---|---|
| `APPLE_CLIENT_ID` | comma-separated: iOS bundle id `com.solvexo.solvexoPos` + the portal's Apple **Services ID** |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | Sign in with Apple key (.p8 contents) — needed to exchange/revoke Apple tokens |
| `APPLE_TOKEN_ENC_KEY` | 32 random bytes, base64 (`openssl rand -base64 32`) — encrypts stored Apple refresh tokens. **Back it up; losing it makes stored tokens unrevocable.** |
| `GOOGLE_CLIENT_ID` | already set; confirm it covers the portal's web client |
| `PORTAL_ORIGINS` | `https://account.<domain>` (exact https origins, comma-separated, no wildcard) |
| `AUTH_COOKIE_DOMAIN` | `.<domain>` (shared registrable domain; required for Safari — see portal `DEPLOY.md`) |
| `CSRF_SECRET` | random secret (else derived from `JWT_SECRET`) |
| `POS_PLANS_STRIPE_WEBHOOK_SECRET` | signing secret of the **POS-plans** webhook endpoint (step 4b) |
| `STRIPE_SECRET_KEY` | live key (never used in dev/tests) |
| `NODE_ENV=production` | also disables the dev OTP log / throttle switches |
| `DEV_OTP_LOG`, `DEV_DISABLE_THROTTLE` | must be **unset** in production |

**4b. Stripe webhook endpoint:** `POST https://api.<domain>/api/pos-subscriptions/webhooks/stripe`, events: `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `charge.refunded`, `charge.dispute.created`, **`charge.dispute.closed`**.
**Verify:** Stripe Dashboard → send test event → 200; `GET /api/auth/csrf` with `Origin: https://account.<domain>` returns a token and a `solvexo_csrf` cookie; with a foreign Origin → 403/blocked.
**Rollback:** revert the variable(s) and redeploy; removing `PORTAL_ORIGINS`/`AUTH_COOKIE_DOMAIN` only disables the portal's cookie sessions (apps unaffected).

## 5. Deploy the portal (Vercel)
Follow `solvexo-account-web/DEPLOY.md`: import repo, env (`VITE_API_URL=https://api.<domain>`, `VITE_GOOGLE_CLIENT_ID`, `VITE_APPLE_SERVICES_ID`, `VITE_APPLE_REDIRECT_URI`, `VITE_SUPPORT_EMAIL`), domain `account.<domain>`, `connect-src` in `vercel.json` if the API host differs; Google authorised origin; Apple Services ID domain + return URL; register the API's mail-sending domain for Apple's private email relay.
**Verify (production, real browser incl. **Safari**):** sign in → reload stays signed in → DevTools → Cookies shows `solvexo_rt` (HttpOnly, Secure, Path `/api/auth/refresh`) → `/privacy`, `/terms`, `/support`, `/delete-account` load signed out. If Safari asks you to sign in after each reload, the domains do not share a registrable domain — fix before continuing.
**Rollback:** Vercel → Deployments → promote the previous deployment (or remove the domain). No backend change needed.

## 6. Back-fill / grant POS plans to existing POS users
Dry run first (changes nothing):
```
npx ts-node -r tsconfig-paths/register src/scripts/pos-plan-backfill.ts
```
Review the list of stores that **used POS but have no active plan**. Then grant a transition period (INSERT-only, idempotent, audited):
```
npx ts-node -r tsconfig-paths/register src/scripts/pos-plan-backfill.ts --grant --days 30 --reason "POS 1.0 launch transition"
```
**Verify:** re-run the dry run → lists nothing. **Rollback:** granted rows are manual `PosPurchase` documents (`source:'manual'`, `grantedByAdminId:'script:pos-plan-backfill'`); revoke via `POST /api/admin/pos-purchases/revoke` or delete those rows.

## 7. Update the other clients per the change docs
- Web dashboard / web terminal: `web_dashboard_changes.md` (section A items are **must-have before step 8**: server-authoritative totals, split tender, idempotency keys, entitlement codes, device auth or keep `POS_LEGACY_AUTH_ALLOWED=true`).
- Buyer app / storefront: `buyer_app_changes.md` — only breaking change: add-to-cart refuses sold-out physical variants (400 "This item is out of stock").
- Publish the POS app builds to TestFlight / Play internal testing (checklist: `store_submission_checklist.md`).
**Verify:** web terminal rings a sale against production staging store; buyer add-to-cart on an out-of-stock variant shows the message.
**Rollback:** each client is independently revertible; the API remains compatible with the old clients while flags are permissive.

## 8. Enable entitlement enforcement
Preconditions: step 6 done, portal purchase page live (step 5), web terminal handles `POS_PLAN_REQUIRED` (step 7), Stripe webhook verified (step 4b).
Set `POS_ENTITLEMENT_ENFORCED=true` and redeploy/restart.
**Verify:** a store with an active plan sells; a store without one gets `403 POS_PLAN_REQUIRED` on selling routes but can still close a shift, refund and read reports; the app shows "POS plan isn't active for this store".
**Rollback:** set `POS_ENTITLEMENT_ENFORCED=false` and restart — immediate, no data change.

## 9. Later: disable legacy auth (separate change, days/weeks after)
Precondition: every shared device is registered (Settings → devices page shows them active) and no web terminal depends on owner JWTs on POS routes.
Set `POS_LEGACY_AUTH_ALLOWED=false`. **Verify:** owner JWT on a POS route → `403 POS_LEGACY_AUTH_DISABLED`; registered devices keep selling; an old app build shows "Set up this device" without losing its queue.
**Rollback:** set `POS_LEGACY_AUTH_ALLOWED=true`.

## 10. After go-live
- Watch Crashlytics (release builds), API logs (`inventory_oversell`, `Apple revocation` retries, webhook failures) and the offline "needs attention" counts for the first 48 h.
- Scheduled jobs that must be running: the daily account-purge cron (de-identification + Apple token revocation retries).
- Keep the step-1 backup for at least a week.

## Emergency switches (no deploy of code needed)
| Problem | Switch |
|---|---|
| POS sellers locked out by plan problems | `POS_ENTITLEMENT_ENFORCED=false` |
| Devices/employees can't sign in after the legacy-auth change | `POS_LEGACY_AUTH_ALLOWED=true` |
| Portal cookie sessions misbehave | remove `PORTAL_ORIGINS` / `AUTH_COOKIE_DOMAIN` (apps unaffected) |
| Bad API build | redeploy previous image (all schema changes are additive) |
