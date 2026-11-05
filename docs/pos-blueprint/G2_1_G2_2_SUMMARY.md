# G2.1 payment layer + G2.2 aggregator/KYB — backend built (stopped before G2.3)

Branch `feature/jamibranch` in both repos. No admin UI, no app change, no real provider, no card provider. G1b runbook items are on hold and untouched.

## Item 0 (carried over): client money mismatch never rejects a sale
Done in `07b4fd1` (`G1b: a client money mismatch is recorded, never a rejection`): the server recomputes, logs + writes a `money_minor_mismatch` audit event + counts a metric (client and server values), and accepts the sale. Tests in `pos.g1b.integration.spec.ts` (live sale with injected mismatch: accepted at server values, 4 mismatches recorded; malformed twins 5.5 / '12' / NaN / 2^60 accepted; held-resume mismatch accepted; offline NEW queue entry with a mismatch syncs and records `offline:true`) — all pass. One stale Swagger description in `create-sale.dto.ts` still said "rejected (MONEY_FIELD_MISMATCH)"; fixed in this round. Both repos' G1b commits are pushed.

## G2.1 — what exists
See `PAYMENTS_CORE_API.md` (design, rules, routes, adapter contract, config). Highlights: provider-agnostic `PaymentProvider`; append-only `paymentintents` / `paymentevents` (status derived from the latest event, `confirmed` final); G1a `allowSetFields` removed (`makeAppendOnly` has no escape hatch; payment rows are never updated); signature-verified webhook → durable inbox → processing → retry queue (always 2xx after the durable write); polling with backoff + expiry; provider refunds as events with a race-free over-refund guard; **late payment** recorded as confirmed (late), attached to the original `saleAttemptKey`, and listed as `paid_after_expiry` in *Needs attention*; orphan (`confirmed_unattached`), amount-mismatch (`anomaly`) and `refund_failed` items; mock provider with controllable outcomes; all money `MinorMoney` + currency/exponent snapshot; QR expiry configurable per provider, default 3 min, capped by the provider's QR validity.

## G2.2 — what exists
See `ADMIN_KYB_API.md` (complete admin API for the UI agent) and `KYB_KEY_ROTATION.md`.
* **Decision I made, tell me if you disagree:** a **new** `store_kybs` record (draft → submitted → verified/rejected; rejected → draft when edited), **not** an extension of the marketplace "Leads" verification. Reason: approving a payment KYB must not publish a store on the marketplace, and the requirements (IBAN, CNIC/NTN) and reviewer permissions differ. The marketplace flow is untouched. It reuses the same private-document storage and signed-URL mechanism.
* Field encryption (CNIC, NTN, IBAN, account title): AES-256-GCM with Node's built-in `crypto` (no package), key **version** in every value, AAD bound to `<storeId>:<field>`, rotation script `npm run kyb:rotate-key` (dry run, idempotent), **fail closed** (503 `KYB_ENCRYPTION_UNAVAILABLE`, nothing stored in plaintext).
* Audit (`kyb_audit_events`, append-only, awaited, fail closed): every submission change, **every decrypted read, every document view and download**, sub-merchant change, retention change and purge. No sensitive value ever enters it.
* Retention: `kyb_settings` singleton; **no default period, deletion off**; settings validated (30–3650 days) and audited; purge job with `dryRun` (default), disabled unless `KYB_RETENTION_JOB_ENABLED=true` **and** `purgeEnabled`.
* Gate: `KybGateService` — QR payments only for `verified` + sub-merchant reference at the active provider; read on every call (a revoke stops payments immediately). Additive `digitalPaymentsEnabled` on `GET /api/pos/subscription/:storeId`.
* New admin permissions `kyb.review`, `kyb.settings` (`admin-permissions.ts`; the web admin's copy must be updated — see the API doc §2).
* Owner endpoints (`/api/kyb/:storeId…`) for the owner portal.

## Where owner KYB screens belong (my recommendation)
Not the POS app and not blocking G2.3 (the mock flow is driven through the admin API / seed). The existing rule is "plan purchase is web-only"; the same logic applies to filling in CNIC/IBAN and uploading documents, so build the **owner KYB form in the owner portal (`solvexo-account-web`) before go-live**, and in the app (G2.4) only a read-only status card ("Verification pending — digital payments unavailable") driven by `digitalPaymentsEnabled`. If you want the portal form earlier, it is a separate small task on the existing owner API.

## Files
New: `src/payments-core/` (interface, mock provider, schemas, status util, core / webhook / poller services, 3 controllers, module, tests, harness), `src/kyb/` (crypto, validators, schemas, requirements, audit, owner / admin / gate / maintenance services, 2 controllers, module, tests), `src/scripts/kyb-rotate-key.ts`. Changed: `pos-immutable.util.ts` (hook removed), `pos-payment.schema.ts`, `pos.g1a.integration.spec.ts` (immutability test updated), `pos.service.ts` (3 helpers made public), `pos.module.ts` (exports `PosService`, imports `KybModule`), `pos.controller.ts` (additive subscription flag), `app.module.ts`, `admin-permissions.ts`, `package.json` (script), `create-sale.dto.ts` (doc text), DI smoke test (also resolves the new controllers).

## Migrations
None required. New collections (`paymentintents`, `paymentevents`, `paymentwebhookinboxes`, `paymentwebhookoutcomes`, `store_kybs`, `kyb_audit_events`, `kyb_settings`) are created with their indexes on first start (Mongoose autoIndex, like every other collection). Existing `posPayments` rows are unchanged (cash `confirmed`, card `recorded_unverified`); no backfill of events is needed because nothing in G2.1 reads payment events for non-QR tenders. **Database role:** all new payment collections are insert-only compatible; `store_kybs` and `kyb_settings` are updated by the app (a normal read/write role).

## Verification
| Check | Result |
|---|---|
| New tests | payments-core: status derivation 7, integration 33 (gate, amounts, idempotency + race, expiry cap, webhook duplicate / invalid / tampered / malformed / replay / wrong amount / failed-after-confirmed, retry queue incl. dead, expiry, last-look, **late confirm after expiry and after cancel**, late via polling, reconcile sale/refund, unattached, polling backoff, refunds incl. race / pending / declined, append-only + DB uniqueness, minor-only), HTTP 5 (route guard map, raw-body webhook 200/401/404, mock control disabled in production). KYB: crypto + validators 7, integration 24 (ciphertext in the raw DB and no plaintext anywhere, masking, **missing key fails closed**, owner flow + locking, documents, admin list/detail, **audit row on every detail read / document view / download and no access when the audit write fails**, approve/reject/revoke, sub-merchant, gate blocking an unverified store's QR payment, **key rotation**, retention defaults/dry run/purge), HTTP 3 (**non-admin 403 on every admin endpoint**, team-admin permissions, end-to-end over HTTP) |
| Backend gate (`src/pos src/pos-plans src/inventory src/product-variants src/common src/draft-orders src/markets src/auth src/scripts src/payments-core src/kyb src/admin-team`) | **864 passed**, 45 skipped (env-gated). 10 failures = the known slug-transliteration ones (untouched). The first full run also showed `pos.offline` and two KYB/payments tests failing **only under CPU contention** (3 workers + heavy suites; timeouts); each passes when run alone/with 2 workers (offline suite, `src/kyb`, `src/payments-core`: 117/117 on a clean run) |
| `npm run build` | passes; `dist/main.js` at the root, no `dist/src/main.js` |
| `npm run test:di` | passes (AppModule + the four new controllers resolve) |
| `kyb:rotate-key` script | dry run against the dev database: reports 0 scanned; with no key it refuses with the fail-closed message |

## Not verified / limits
* No real provider exists: signature schemes, QR formats, refund semantics are the mock's. The mock suite is the contract a real adapter must pass; plan a sandbox run when PayFast / 1LINK docs arrive.
* The poller and the retention cron were exercised by calling their methods directly (the `@Cron` wiring is not run in tests); the retry queue is verified with injected clocks.
* Cloudinary uploads/signed URLs were tested with a stub storage (no real cloud calls).
* The admin web panel's permission list (`solvexo-web`) is a separate repo I did not touch.
* Not built (G2.3): the `raast_qr` tender in `POST pos/sales` that writes `consumed`, and the till screens / *Needs attention* UI.
