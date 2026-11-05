# Payment layer (G2.1) — design and POS API

Backend only so far (no app change, no real provider, no card provider). Module: `solvexo-api/src/payments-core/`. The till (G2.3) builds on exactly this.

## 1. Model: append-only events, status derived
| Collection | Role | Mutable? |
|---|---|---|
| `paymentintents` | one QR payment attempt: store/register/session/shift/device/employee (server-derived), `method:'raast_qr'`, provider + `providerRef`, `qrPayload`, `subMerchantRef`, `amountMinor` (**MinorMoney**, BSON long) + `currency` + `currencyExponent`, `expiresAt`, `idempotencyKey`, `saleAttemptKey` | **never** (append-only) |
| `paymentevents` | the lifecycle: `created, presented, pending, confirmed, failed, expired, cancelled, anomaly, reconciled, consumed, refund_requested, refund_succeeded, refund_failed`; per-intent `seq`; `providerEventId` (unique per provider = webhook dedupe); `late`; `refundId`; `onceKey` | **never** |
| `paymentwebhookinboxes` | every signature-verified webhook, written durably **before** processing (unique per provider event id) | never |
| `paymentwebhookoutcomes` | processing log of an inbox row: `processed / ignored / error / dead` | never |
| `posauditlogs` | `payment_refund_requested`, `payment_reconciled` (manager actions) | never |

**Current status = the latest status event**, with one safety rule: `confirmed` is final (a later `expired`/`failed` — e.g. two servers racing — is recorded as an `anomaly`, never moves a paid payment back). The G1a `allowSetFields` hook on `PosPayment` is **removed**: payment rows are never updated after insert, so an insert-only database role works for every payment collection. Uniqueness is enforced by the database: `(intentId, seq)`, `(providerKey, providerEventId)`, and a partial unique `onceKey` (`confirmed`, `expired`, … occur at most once per intent; refund events once per `refundId`), so two servers can never both write the same fact.

## 2. Rules
* **Confirmed while open** → `confirmed`. **Confirmed after `expired` / `cancelled` / `failed`** → `confirmed` with `late:true`: recorded, attached to the original checkout attempt (`saleAttemptKey`), and raised as **`paid_after_expiry`** in *Needs attention*. Money is never lost or silently ignored (tested for expiry, cancel, and for providers without webhooks via the late-window poll).
* **Confirmed with a different amount** → `anomaly` (not confirmed); a manager decides.
* **Confirmed but never attached to a sale** after 2 minutes (app crashed after "paid") → `confirmed_unattached` in *Needs attention*.
* **Expiry** = `min(PAYMENTS_QR_TTL_SECONDS_<PROVIDER> or PAYMENTS_QR_TTL_SECONDS (default 180), provider.qrValiditySeconds)` — never longer than the provider's QR validity. Before expiring, one last provider look, so a payment made just in time is not lost. The countdown is computed from the **server** clock (`serverTime`, `expiresAt`, `secondsRemaining`).
* **Webhook**: signature over the **raw body** first (constant-time), then the timestamp window (±300 s), then the durable inbox write, then processing; always 2xx after the durable write; a processing error is an `error` outcome and the **retry queue** (`retryPending`, backoff 5 s → 10 min, 8 attempts, then `dead` + an ERROR log) tries again. Duplicate = 200 and nothing new. Bad/forged/stale = 401 and **no trace**.
* **Polling**: age-based backoff (3 s → 5 s → 10 s; webhook providers only a 30 s safety net; after expiry a 30–60 s late-payment watch for `PAYMENTS_LATE_WINDOW_MINUTES`, default 30). Several servers may poll: every write is idempotent.
* **Refunds** are events: `refund_requested` → `refund_succeeded | refund_failed`. Idempotent per `refundKey`. Over-refund is impossible even under a race (the later request in sequence order fails before the provider is called). A provider timeout leaves the request open (never guessed as failed); the poller asks again.
* **Gate**: creating a QR payment needs a KYB-`verified` store with a sub-merchant reference **at the active provider** (403 `STORE_NOT_VERIFIED`, with `reason`). Cash and card (`recorded_unverified`) never pass through this code and are unchanged for every store. A POS plan must be active to **create** a payment; refunds/reconcile still work after a plan lapses.

## 3. POS routes (`/api/pos/payments`, device token or owner JWT, POS feature flag)
| Method | Path | Who | Notes |
|---|---|---|---|
| POST | `/intents` | PIN session (any role) + active POS plan | body `{ amountMinor, sessionId, saleAttemptKey?, idempotencyKey? (or header), storeId? }` → `{success,data:<view>}`. 400 `INVALID_AMOUNT`/`AMOUNT_TOO_LARGE`/`NO_OPEN_SESSION`/`IDEMPOTENCY_KEY_REQUIRED`; 403 `STORE_NOT_VERIFIED`; 403 `EMPLOYEE_SESSION_REQUIRED`; 409 `IDEMPOTENCY_KEY_REUSED` |
| GET | `/intents/:id` | device | the view below; also applies lazy expiry |
| POST | `/intents/:id/presented` | device | the till is showing the QR (idempotent) |
| POST | `/intents/:id/cancel` | PIN session | 409 `PAYMENT_ALREADY_CONFIRMED` after payment |
| POST | `/intents/:id/refunds` | **manager PIN** | `{ amountMinor, reason, refundKey }` → 409 `PAYMENT_NOT_CONFIRMED`, `REFUND_EXCEEDS_PAID`, `IDEMPOTENCY_KEY_REUSED`; 400 `REASON_REQUIRED` |
| GET | `/attention` | device | *Needs attention* items: `paid_after_expiry`, `confirmed_unattached`, `anomaly`, `refund_failed` |
| POST | `/intents/:id/reconcile` | **manager PIN** | `{ resolution: 'sale_recorded' (+ saleId) | 'refund' | 'dismissed' (unpaid anomaly only, note ≥10 chars), note? }` |
| POST | `/api/payments/webhooks/:provider` | provider (signature) | public, raw body, 200/401/404 |
| POST | `/mock/simulate` | dev only | `PAYMENTS_MOCK_CONTROL=true`, never in production |

The view: `{ id, method, status, amountMinor, currency, currencyExponent, qrPayload, expiresAt, serverTime, secondsRemaining, confirmedAt, paidAfterExpiry, consumed, saleId, refundedMinor, refundStatus, saleAttemptKey, attention[], createdAt }`; all money is a plain integer in minor units.

## 4. Provider adapter contract
`PaymentProvider` (`payment-provider.interface.ts`): `createCharge`, `getStatus`, `cancel`, `refund`, `getRefundStatus`, `verifyWebhook` (must throw `WebhookSignatureError` / `WebhookReplayError`; constant-time), plus `key`, `qrValiditySeconds`, `supportsWebhooks`. A real adapter (PayFast / 1LINK 1GO) is one file registered in `buildProviders()` and must pass the same scenarios as the mock (`payments-core.integration.spec.ts` is the contract suite: duplicate, forged, stale, late, refund, poll). The **mock** (`providers/mock.provider.ts`) has controllable outcomes — `simulate(confirm|fail|expire)`, `mockScenario: auto_confirm | auto_fail`, refund reasons `mock:pending` / `mock:fail`, `buildWebhook` (valid / bad signature / tampered / stale / duplicate event id) — and is **not registered when `NODE_ENV=production`**; with no `PAYMENTS_PROVIDER_POS` in production there is no fallback (the create call fails closed).

## 5. Configuration
| Variable | Default | Meaning |
|---|---|---|
| `PAYMENTS_PROVIDER_POS` | `mock` outside production; **required** in production | active provider key |
| `PAYMENTS_QR_TTL_SECONDS` / `PAYMENTS_QR_TTL_SECONDS_<KEY>` | 180 | our QR expiry (capped by the provider) |
| `PAYMENTS_MAX_AMOUNT_MINOR` | 1,000,000,000 | per-payment ceiling |
| `PAYMENTS_LATE_WINDOW_MINUTES` | 30 | how long after expiry we keep watching for a late payment |
| `PAYMENTS_UNATTACHED_GRACE_SECONDS` | 120 | confirmed-without-sale becomes an attention item after this |
| `PAYMENTS_POLLER_ENABLED` | true | `false` turns the poller/retry job off on a server |
| `PAYMENTS_MOCK_WEBHOOK_SECRET`, `PAYMENTS_MOCK_WEBHOOKS`, `PAYMENTS_MOCK_CONTROL` | dev values | mock only |

## 6. Not in G2.1 (by plan)
Attaching a confirmed payment to a sale (`POST pos/sales` with a `raast_qr` tender → writes `consumed`) and the till screens are **G2.3**; the `consumed` event type and the unique `onceKey` it needs already exist. Store-credit refunds are G3.
