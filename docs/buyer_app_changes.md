# Buyer app (`solvexo-white-lable-app`) — backend changes from Phases 5A–5E that can affect it

Only the **storefront / buyer-facing** responses and rules are listed. POS-only changes (device tokens, tender, quote, offline sync, billing…) do not touch buyer endpoints. Legend: **BREAKING** = the buyer app must change or it will mis-behave; *behavioural* = works unchanged but users may notice; *none* = FYI.

## 1. Stock rules (5C.1 / 5D.1)

### 1.1 Add-to-cart refuses sold-out items — **BREAKING (behavioural)**
`POST /api/cart/add-to-cart` previously never checked stock, so a buyer could put a sold-out (or oversold) item in the cart and only learn at checkout. Now, for **physical** products whose variant is not `unlimitedStock` and not `allowBackorder`, it fails when `available ≤ 0` or `available < quantity` (`available = stock − committed − damaged − in-transit − expired`).
- Response: **HTTP 400** `{ "statusCode": 400, "message": "This item is out of stock", "error": "Bad Request" }` — no machine code (same shape as the other cart errors).
- Suggested UI: keep the "Add to cart" button but on this 400 show *"Sorry, this item is out of stock."* and refresh the product (its `inStock` will already be false); disable the button when `inStock == false` / the selected variant's `stock <= 0` so the error is rare. Do not retry.
- Note: `quantity` greater than what is left but > 0 is also refused with the same message (it does not say how many remain; re-read the product's variant `stock` if you want to show "only N left").
- `PATCH update cart quantity` is **unchanged** (no stock check there); checkout re-validates.

### 1.2 Checkout stock errors — *none (rule unified)*
Checkout creation still returns **400** `{ "message": "Insufficient stock for: <product name>" }`; payment/order placement still returns `Insufficient stock for <name>` (and `Available: n, required: m` on some paths) or the atomic-reserve failure `Stock not available for item: <name>`. The rule is now one shared function, so behaviour only differs from before in that **stock ≤ 0 can never pass**, whatever the quantity. Suggested message: *"<name> is no longer available in the quantity you chose — please update your cart."*; on this error reload the cart and highlight the item.

### 1.3 Stock is clamped at 0 in storefront responses — *behavioural, non-breaking*
An offline POS sale can legitimately drive stock negative in the database. Public storefront listing (`GET /api/store/.../products`, the shared `variants[]` shape) now returns **`stock: 0` and `variants[].stock: 0`, never a negative number**; `inStock` is unchanged (false). If the app ever rendered `stock` directly, it can now rely on `stock >= 0`. (Seller inventory screens get the same clamp; the real oversell is visible to sellers in the activity log, not to buyers.)

### 1.4 `allowBackorder` ("continue selling when out of stock") — *none, but now explicit*
Variants with `allowBackorder: true` (and `unlimitedStock: true`) are **exempt** from the above: add-to-cart and checkout succeed at stock ≤ 0, and the order is flagged backordered server-side. The app should keep showing them as purchasable (use `inStock`, which already accounts for it) and may show *"Ships when back in stock"* if it does not already.

## 2. Other storefront-visible changes

| Change | Where | Breaking? |
|---|---|---|
| `JwtAuthGuard` now rejects tokens whose payload `type` is `pos_device` or `pos_employee` (they share the signing secret) | every guarded buyer endpoint | **No** for buyer tokens (they carry no such `type`); only matters if something else mints those types |
| `ProductVariant.price` edits are now recorded in a `variantpricehistories` collection (TTL 30 days) | internal | none — no response changed |
| POS sales take stock with the same atomic guards as online orders; stock a POS sale takes appears in the storefront listing on the next fetch | `stock`, `inStock` | none (fresher data) |
| Unlimited-stock variants are restored correctly on POS void/refund | internal | none |
| `GET /api/store/.../products` price/currency/discount shape | — | **unchanged** (storefront/order money storage was deliberately not touched by 5B) |
| New POS-only routes/errors (`POS_PLAN_REQUIRED`, `POS_DEVICE_*`, `POS_PLAN_LIMIT`, …) | `/api/pos/*` | none for the buyer app |
| Stripe plan-billing webhook changes (stacking, refund/dispute/dispute-closed) | `/api/pos-subscriptions/webhooks/stripe` | none — seller billing only, separate from buyer payments |

## 3. Checklist for the buyer-app team
1. Handle the new **400 "This item is out of stock"** from add-to-cart (BREAKING behaviour).
2. Trust `stock >= 0` and `inStock` for display; hide/disable Add-to-cart when `inStock` is false.
3. Keep treating backorder/unlimited variants as purchasable.
4. On checkout `Insufficient stock…` errors, refresh the cart rather than showing a generic failure.

## 5F.1 / 5G — auth changes that touch shared endpoints (all backward compatible)
- `POST /api/auth/social-login`: `email` in the body is now **optional** (buyer-app callers that still send it behave exactly as before; a mismatch with the provider-verified email is still rejected). Apple: `APPLE_CLIENT_ID` is a comma-separated list of accepted audiences, and Apple's email only counts as *verified* when the token says `email_verified` — an unverified Apple email no longer links to an existing password account (matched by provider id only).
- Refresh tokens now carry `typ:'refresh'` and a new `POST /api/auth/refresh` exists (buyer/seller/admin). Access-token payloads are unchanged. A refresh token can no longer be used as a bearer on other routes (JwtStrategy rejects `typ:'refresh'`). Refresh tokens issued before this change have no `typ` and are refused by `/auth/refresh` (they were never usable before).
- CORS: new env `PORTAL_ORIGINS` (exact https origins) adds the Solvexo Account portal; existing origins unchanged.
