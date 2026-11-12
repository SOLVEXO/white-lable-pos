# Store API keys and the read-only external API (G5.7)

A store **owner** can issue API keys so the store's own systems (accounting software, a spreadsheet, BI) can **read** its data. Keys never write and never see cost.

## Managing keys (owner only)

Every key-management route is tier **owner**: the owner's own session, or a till with the owner unlocked.

| Route | What |
|---|---|
| `GET /api/pos/api-keys/:storeId` | Lists the store's keys: name, prefix, scopes, status (`active` / `expired` / `revoked`), created, expires, last used. It also returns the scope list, the active-key limit and the rate limit. **The secret is never returned here.** |
| `POST /api/pos/api-keys/:storeId` `{ name, scopes[], expiresInDays? }` | Creates a key. The response carries the full key **once** (`shownOnce: true`). `expiresInDays` is 1–365 (default 90). At most 10 active keys per store (`TOO_MANY_KEYS`). Uses Idempotency-Key. |
| `POST /api/pos/api-keys/:storeId/:keyId/revoke` | Stops the key at once. Revoking twice is harmless. |

- **Scopes** (read-only): `sales:read`, `inventory:read`, `accounting:read`.
- **Key format:** `sxk_<12-character prefix>_<43-character secret>`. Only the SHA-256 of the secret is stored, and it is compared in constant time. A lost key cannot be recovered: revoke it and create a new one.
- **Audit:** `api_key_created`, `api_key_revoked`, and **`api_key_used` for every request**, accepted or refused. The row holds the route, the HTTP status, the refusal code and the requested period.

## Using a key

Send the key in the `X-Api-Key` header. Base path: `/api/pos/ext/v1`. These routes are tier `public` (no PIN session): the key is the credential.

| Route | Scope | Returns |
|---|---|---|
| `GET /sales?from=&to=&cursor=&limit=` | `sales:read` | Sales in `[from, to)` (ISO dates or times; default the last 7 days; at most 92 days), oldest first. Each sale has its number, invoice number, status, register, customer name, `totalMinor`, `taxMinor`, payments (method, `amountMinor`) and items (ids, name, SKU, qty, refunded qty, `netMinor`, `taxMinor`). `limit` ≤ 500; page with `nextCursor`. |
| `GET /inventory?cursor=&limit=` | `inventory:read` | Products with their variants: SKU, barcode, `priceMinor`, stock (null when unlimited), committed stock, reorder point. |
| `GET /accounting-export?from=&to=` | `accounting:read` | The accounting CSV (below), **always without cost columns** through a key. |

- **Money:** every amount is in minor units, and every response states `currency` and `currencyExponent` (e.g. PKR, 2: `125000` = PKR 1,250.00).
- **Rate limit:** 60 requests a minute **per key**, shared by all API instances (env `API_KEY_RATE_PER_MIN`). Above it the answer is `429 API_KEY_RATE_LIMITED`. The platform's per-IP limit also applies.

| Refusal | HTTP | Meaning |
|---|---|---|
| `API_KEY_INVALID` | 401 | Missing, malformed, unknown or wrong secret |
| `API_KEY_REVOKED` | 401 | Revoked by the owner |
| `API_KEY_EXPIRED` | 401 | Past its expiry |
| `API_KEY_SCOPE` | 403 | The key lacks the route's scope |
| `API_KEY_RATE_LIMITED` | 429 | Over the per-minute limit |
| `RANGE_INVALID` / `RANGE_TOO_LONG` | 400 | Bad `from`/`to`, or more than 92 days |

```bash
curl -H "X-Api-Key: sxk_XXXXXXXXXXXX_…" "https://<api>/api/pos/ext/v1/sales?from=2026-11-01&to=2026-11-08"
```

## Accounting export (CSV)

The same export is available on the till at `GET /api/pos/reports/accounting-export/:storeId?from=YYYY-MM-DD&to=YYYY-MM-DD`: managers and owner, tier manager-with-limit, at most 366 days.

- **One row per document**, by its time in the **store's time zone**:
  - tax invoices (voided ones marked);
  - credit notes, negative (returns and voids);
  - expenses, negative (rejected ones left out);
  - supplier payments, negative.
- **Columns:** `date_local, time_zone, type, number, reference, party, payment_methods, currency, currency_exponent, net_minor, tax_minor, total_minor, [cost_minor], net, tax, total, [cost]`. The plain columns are the minor amount formatted with the exponent.
- **Cost columns** appear only for the owner, or for a manager when the store does **not** hide costs. They never appear through an API key. Invoice cost = Σ qty × the line's cost snapshot, left blank when any line has no cost.
- **Safety:** values that start like a spreadsheet formula (`=`, `+`, `-`, `@`) are prefixed with `'`.
- **Audited:** `accounting_export` with the period, row count, whether cost was included, and who (role, or the API key prefix).
