# G1b production pre-flight (read-only, aggregate counts only)

You run this yourself with a **read-only** database user and paste the output back. No production credentials are ever shared.

```bash
cd solvexo-api            # uses that folder's node_modules/mongodb — nothing to install
MONGO_URI='mongodb+srv://<read-only-user>:<password>@<cluster>/<database>?authSource=<db>' \
  node ../pos/docs/pos-blueprint/preflight/preflight.js > preflight_output.json
```

**What it will not do**
* It **refuses to run** if the connected user can write anything (insert, update, remove, create/drop collection or index, user/role management, `anyAction`, …). Create the user with only the built-in `read` role on the database.
* It **refuses** an unauthenticated connection (an unauthenticated connection has every privilege).
* It only calls `connectionStatus`, `listCollections` (names only), `estimatedDocumentCount`, `countDocuments` and `aggregate` — never `$out` / `$merge`, never a write.
* The output has **no personal data**: only counts keyed by currency code or field name. No names, phones, e-mails, ids, store names, document contents, connection string or database name.

**What it reports**
documents per collection · stores by base currency · sales and shifts by (currency, exponent snapshot) including rows with **no snapshot** (written before Phase 5B) · refunds missing a snapshot · PKR sales by exponent (confirms POS used exponent 2) · rows already dual-written · **variants whose price / compare-at / cost are not a whole number of minor units of their store's currency** (ISO exponent) · sales / shifts with a money value off the minor-unit grid · open shifts.

**How it was tested:** against a throw-away auth-enabled mongod — a `read` user gets the report; a `readWrite` user, `root`, and an unauthenticated connection are all refused (with the list of write actions found); the `--allow-unauthenticated-localhost` flag (local dev trial only) does not bypass the check for an authenticated user.

Create a read-only user (MongoDB shell, as an admin):
```js
db.getSiblingDB('<database>').createUser({ user: 'preflight_ro', pwd: '<strong password>', roles: [{ role: 'read', db: '<database>' }] })
```

## G3 section (counts only)
Since G3 the report has a `g3` block: documents in `purchaseorders`, `supplierreturns`, `stocklots`, `storecredittransactions`, `loyaltymembers`, `stockadjustments`; variants with a cost set (and how many still lack the minor twin); purchase orders by currency; lots with units remaining / with an expiry; and for store credit **only counts**: customers with a spendable balance per currency, lots with spendable remaining, lots with a future expiry, lots whose remaining amount is off the currency's minor-unit grid, and rows by type. No amounts per customer, no customer ids, no names.

## G5.1 section — `API_PUBLIC_URL`
Run the script with the production API origin in the environment too: `API_PUBLIC_URL='https://api.solvexo.store' MONGO_URI=… node …/preflight.js`. The report's `g51.apiPublicUrl` says `ok: true`, or gives the reason it isn't. The reasons are: not set, not https, a local or private address, credentials in the URL, or more than an origin. The value itself is never printed. From G5.1 on, **the API refuses to start outside development when this check fails**, because every receipt QR carries this origin.

## G5.2.0b section — `RECEIPT_PUBLIC_URL`
Optional. Pass it like `API_PUBLIC_URL` (`RECEIPT_PUBLIC_URL='https://solvexo.store' …`). The report's `g52.receiptPublicUrl` says whether it is set and, if so, whether it passes the same rules. When it's set and fails, the API refuses to start. When it's unset, receipt links use `API_PUBLIC_URL`.
