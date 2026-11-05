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
