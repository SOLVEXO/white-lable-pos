# Where Stripe is integrated (REPORT ONLY — nothing was changed)

`test:di` needed a key because `PaymentGatewayService` (`src/subscriptions/payment-gateway/payment-gateway.service.ts`) **throws at start-up when `PAYMENT_PROVIDER=stripe` (the default) and `STRIPE_SECRET_KEY` is empty**. `PAYMENT_PROVIDER=manual` is a dev/CI-only no-op stub that is refused under `NODE_ENV=production`. CI now sets `manual` for that one step (no secret used).

## Features that use Stripe
| # | Feature | Where | Flows | Currency |
|---|---|---|---|---|
| 1 | **Platform subscription billing** (sellers pay Solvexo) | `subscriptions/payment-gateway/stripe-payment.provider.ts`, `subscriptions/webhooks/stripe-webhook.service.ts` | recurring prices/subscriptions, intro-price coupons, one-time charges, setup intents, billing portal, checkout sessions, refunds; webhook → BullMQ job (`STRIPE_WEBHOOK_JOB`) | **USD** (hard-coded `'usd'`, amounts `Math.round(usd*100)`) |
| 2 | **Storefront checkout** (buyers pay sellers) | `payment/payment.service.ts`, `payment.controller.ts` (`POST api/payment/stripe-webhook`), `stripe-connect/` | card payments; **Stripe Connect** — sellers connect an account (`express` accounts created by the platform, and `standard` accounts); direct sales settle to the seller's connected account; refunds in the buyer's payment currency | the checkout "rail" is **USD** (`PaymentTransaction.currency`); refund amounts use `toStripeAmount` (zero/three-decimal aware) |
| 3 | **Gift cards**, **bookings** (appointments/packages) | `gift-cards/`, `bookings/` | pay through the seller's connected account when eligible (`StripeConnectService.getEligibleConnectAccountForStore`), else the legacy ledger path | as the rail (USD) |
| 4 | **POS plan purchase** (web portal; D2 "web-only purchase") | `pos-plans/pos-plans.service.ts`, `pos-plans/webhooks/pos-plans-webhook.controller.ts` (`POST api/pos-subscriptions/webhooks/stripe`) | one-time Stripe **Checkout Session**, `mode: 'payment'`; Solvexo's own tax added at checkout when it applies; webhook creates a `PosPurchase` (unique index on the checkout-session id, so a redelivery is a no-op); a status page reads the session | **the plan's own currency** (`plan.currency`, amount via `toStripeAmount`) |
| 5 | Admin / platform | `admin-config`, `platform-health`, `payment-provider-catalog.ts` | provider availability per country (`stripe_standard`, `stripe_own`), health checks | — |

## What is charged
* Sellers: Solvexo subscription plans and POS plans. Buyers: their orders / gift cards / bookings (money goes to the seller's connected account on the Connect path; the platform takes commission via commission rules, `commission-rules/payment-rail.ts`).

## Account and key configuration (environment only — never in code)
| Variable | Purpose |
|---|---|
| `STRIPE_SECRET_KEY` | **one** platform key; test vs live mode is decided only by the key (`sk_test_…` / `sk_live_…`). API version pinned `2025-02-24.acacia` |
| `STRIPE_WEBHOOK_SECRET`, `STRIPE_WEBHOOK_SECRET_TEST` | signing secrets of the subscription / storefront webhook endpoint(s) |
| `POS_PLANS_STRIPE_WEBHOOK_SECRET` | signing secret of the **POS-plans** endpoint (separate endpoint) |
| `STRIPE_CONNECT_COUNTRIES`, `STRIPE_ACCOUNT_COUNTRIES` | where Connect is offered |
| `PAYMENT_PROVIDER` | `stripe` (default) or `manual` (dev/CI only) |

The repository does not show **which Stripe account** (account id, country, test/live) holds the key — that lives in the deployed environment. **Owner to confirm** the account and its settlement currency.

## Does any POS path touch Stripe?
* **POS sales: no.** The till's tenders are cash, recorded card (`recorded_unverified`, nothing is processed) and Raast QR through the separate `payments-core` provider adapter (mock now; no Stripe code). `src/pos/` only mentions Stripe in two spec files (test setup).
* **POS plan purchase / entitlement: yes** (row 4): it decides whether a store's POS is active (`PosEntitlementGuard`), but the till itself never calls Stripe — plans are bought on the web portal.
* KYB (G2.2) and the receipt page: no.
