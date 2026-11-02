# Web spec — "Buy / extend POS plan" (seller web dashboard)

**Status:** no seller web dashboard or admin web code exists in this workspace (searched all sibling projects for `pos-plans` / `pos-subscriptions` — only the API and the POS app reference them), so this page could not be built here and nothing was invented. **Until it exists, an admin manual grant/extend (`POST /api/admin/pos-purchases/grant|extend`) is the only way to activate a store.** The mobile POS app has no purchase path at all (store-policy compliance) — it only reads the entitlement.

## Screens
1. **POS plan** (seller panel → Settings/Billing). Shows, for the selected store: status (Active / Expired / None), plan name, started, **expires**, days remaining; a banner at ≤ 7 days. Below it the plan catalog and a **Buy** / **Extend** button per plan (label "Extend" while a plan is active — a purchase made before expiry **stacks**: the new term starts when the current one ends).
2. **Success page** (`successUrl`): "Payment received — your plan updates in a few seconds", then re-polls the status endpoint (the webhook, not the redirect, grants access; poll every 2 s up to ~30 s, then show "still processing").
3. **Cancel page** (`cancelUrl`): "No charge was made", link back to the plan page.

## Endpoints (seller JWT, `role: seller`; the store must belong to the seller)
| Purpose | Request | Response |
|---|---|---|
| Plan catalog | `GET /api/pos-plans` | `{ success, data: [{ id, name, price, currency, durationInDays, description, maxRegisters, maxEmployees, maxLocations }] }` — active plans only, cheapest first; the three `max*` are `null` = unlimited |
| Current status | `GET /api/pos-subscriptions/:storeId` | `{ success, data: { status: 'active'\|'expired'\|'none', enforced: boolean, planName?, purchasedAt?, expiresAt?, daysRemaining? } }` |
| Start checkout | `POST /api/pos-subscriptions/:storeId/checkout-session` body `{ planId, successUrl, cancelUrl }` (both URLs must be absolute `http(s)`) | `{ success, data: { url } }` → redirect the browser to `url` (Stripe Checkout, `mode: payment`, price taken from the server-side plan, never from the client) |

Errors: `404` plan not found/inactive; `403` store not the seller's; `400` Stripe not configured / invalid URLs.

Suggested URLs: `successUrl = https://<panel>/pos-plan?checkout=success`, `cancelUrl = https://<panel>/pos-plan?checkout=cancelled`.

## Webhook expectations (already implemented — for whoever configures Stripe)
Endpoint `POST /api/pos-subscriptions/webhooks/stripe`, secret `POS_PLANS_STRIPE_WEBHOOK_SECRET`. Subscribe to: `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `charge.refunded`, `charge.dispute.created`.
- Paid session → one purchase row (idempotent on the session id; redeliveries are no-ops). Unpaid async sessions grant nothing until `async_payment_succeeded`.
- Buying before expiry **stacks** (new expiry = current expiry + plan days); after expiry it starts from now.
- **Full refund** or **dispute** takes the purchase's *unused* days back (shortening the current expiry, never below now); partial refunds are ignored; manual admin rows are never touched by Stripe events. A won dispute is not auto-restored — an admin can extend manually.
- Admin revoke ends all running purchases immediately; a later paid purchase starts from now.

## Admin (already in the API, `billing.manage` permission)
`GET/POST/PATCH /api/admin/pos-plans` (plans incl. optional `maxRegisters/maxEmployees/maxLocations`), `GET /api/admin/pos-purchases`, `POST /api/admin/pos-purchases/grant|extend|revoke` (`{ storeId, days?, reason, planId? }`).

## Plan limits
When the store's active plan sets a cap, creating one more register / PIN employee / location fails `400 { code: 'POS_PLAN_LIMIT', limit, kind }`. Show the message and a link to the plan page.
