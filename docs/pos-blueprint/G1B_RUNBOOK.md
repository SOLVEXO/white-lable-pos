# G1b production runbook (money in minor units)

Prepared, **not run**. You run every step that touches production data; nothing here needs production credentials to be shared with anyone. Each step ends with a **check** (what "good" looks like) and a **rollback**. Do not start a step until the previous check passes.

Order: 0 staging deploy → 1 pre-flight → 2 backfill dry run on a *restored copy* → 3 throughput measurement → 4 production deploy + backfill window → 5 burn-in (flip report). Step f (flip reads to minor) is **not** part of this runbook; it needs a separate approval after step 5.

Facts the steps rely on (verified in the code):
* G1b is **additive**: new nullable `...Minor` fields. Old app builds and old queued sales keep working; the server never rejects a sale on a minor mismatch.
* Backend deploys **before** any app release (`ENGINEERING_RULES.md` §4). The app change (minor twins) can ship at any time after the backend is live.
* The backfill refuses a database whose name lacks "dev" or "test" unless **both** `--production` and `--i-have-a-backup` are passed. A restored copy usually has a production-like name, so you will pass both flags there too. That is expected.
* The backfill and the flip report **do not read `.env`**: `MONGO_URI` is passed explicitly.
* `down` (rollback) updates the append-only collections, so it needs a database user that may update them (an admin/maintenance user, not the app's insert-only role).

---

## 0. Staging deploy
**Prerequisite:** the deploy pipeline works (see the deploy diagnosis; staging deploy currently fails at SSH/ownership). Merge the `/health/version` PR (#20) to `staging` first so you can prove which commit runs.

1. Merge `feature/jamibranch` into `staging` (PR, your call; no PR to `main`).
2. Deploy staging (GitHub Actions *Deploy solvexo-api Staging*, or on the server `bash scripts/deploy.sh staging solvexo-api-staging`).
3. **Check**
   * `curl -s https://<staging-host>/health/version` → `commit` equals the merge commit; `startedAt` is just now.
   * `curl -s https://<staging-host>/health/live` → `{"status":"ok"}`.
   * Ring up one cash sale and one refund on a staging register. In the staging database: that sale has `totalMinor` (e.g. `{"totalMinor": 550}` for 5.50) and `db.posauditlogs.countDocuments({action:"money_minor_mismatch"})` is `0`.
4. **Rollback:** redeploy the previous `staging` commit (`git revert -m 1 <merge>` and push, or `scripts/deploy.sh` on the previous SHA). Because G1b is additive, rolling the code back leaves harmless extra fields; no data fix needed.

## 1. Pre-flight (read-only, you run it)
Purpose: confirm production currencies, exponent snapshots, off-grid values and open shifts before touching anything.

1. In the Atlas shell (admin), create a read-only user:
   ```js
   db.getSiblingDB('<database>').createUser({ user: 'preflight_ro', pwd: '<strong password>', roles: [{ role: 'read', db: '<database>' }] })
   ```
2. From your machine:
   ```bash
   cd solvexo-api
   MONGO_URI='mongodb+srv://preflight_ro:<password>@<cluster>/<database>?authSource=<database>' \
     node ../pos/docs/pos-blueprint/preflight/preflight.js > preflight_output.json
   ```
3. Send me `preflight_output.json` (counts only, no personal data). I review: PKR sales all exponent 2, count of variants/sales off the minor grid, number of open shifts, volumes per collection (these size step 3).
4. **Check:** the script printed a report (it refuses to run if the user can write). Decision gate: any "off grid" count > 0 means we look at those rows before the backfill.
5. **Rollback:** `db.getSiblingDB('<database>').dropUser('preflight_ro')`. Nothing else changed.

## 2. Backfill dry run on a restored copy of production
**Never rehearse on production.** Use a separate cluster so a mistake cannot touch live data.

1. Atlas → the production cluster → Backup → pick the latest snapshot → **Restore** to a *new, separate* cluster (e.g. `solvexo-rehearsal`). Note the restore time; it is the age of the data.
2. Create a maintenance user on that cluster (readWrite on the restored database).
3. Dry run (writes nothing):
   ```bash
   cd solvexo-api   # on the jamibranch / staging commit that includes the script
   MONGO_URI='<rehearsal cluster uri>/<database>' \
     npx ts-node -r tsconfig-paths/register src/scripts/pos-g1b-minor-backfill.ts up --dry-run --production --i-have-a-backup
   ```
   Save the output. It lists per collection: documents, candidates, batch size, off-grid values, float noise, currency inferred, read+compute rate and estimated duration.
4. Real run on the copy:
   ```bash
   MONGO_URI='<rehearsal cluster uri>/<database>' \
     npx ts-node -r tsconfig-paths/register src/scripts/pos-g1b-minor-backfill.ts up --production --i-have-a-backup
   ```
5. **Checks**
   * Run it a second time → every collection reports `written: 0` (idempotent).
   * Run the flip report over the whole range: `MONGO_URI=… npx ts-node -r tsconfig-paths/register src/scripts/pos-minor-flip-report.ts --from <first sale date> --to <tomorrow> --json` → **0 storage mismatches**.
   * `sales.countDocuments({totalMinor:{$exists:false}, total:{$gt:0}})` is `0` (adjust per collection).
   * Spot-check 20 sales: `total*100 == totalMinor` (or the currency's exponent).
6. **Rollback (on the copy):** `... pos-g1b-minor-backfill.ts down --production --i-have-a-backup` removes only rows carrying `minorBackfilledAt`. To start over completely, delete the rehearsal cluster.
7. Send me the dry-run output, the second-run output and the flip-report JSON.

## 3. Throughput measurement (from the rehearsal)
The dry run prints an *estimate* that assumes 500 documents/second. Replace the assumption with a measurement:
1. Note the wall-clock time of step 2.4 and the total documents written → `docs/second` for your Atlas tier.
2. Production window = (production documents ÷ measured rate) × 1.5 safety factor, plus a pause for the checks. Production is larger than the snapshot by its growth since the restore.
3. Try `--batch 250` and `--batch 1000` on the copy (after `down`) and keep the faster setting. The backfill keeps 25 writes in flight; if Atlas shows replication lag or CPU > 70 %, lower `--batch`.
4. **Check:** you have a number in minutes for step 4 and agreed a window with the stores (the backfill is safe under live traffic, so a quiet hour is a comfort, not a requirement).
5. **Rollback:** none needed (read-only measurement on the copy).

## 4. Production deploy and backfill window
1. **Take a fresh backup/snapshot** and note its id. Without it, do not run with `--i-have-a-backup`.
2. Deploy the backend to production (merge `staging` → `main` per your release process, then the pipeline or `scripts/deploy.sh main solvexo-api`). Verify with `GET /health/version` that the running commit is the release commit.
3. **Smoke:** one sale and one refund on a real register: stored with `totalMinor`; no `money_minor_mismatch` events.
4. Backfill, dry run first:
   ```bash
   MONGO_URI='<production maintenance uri>/<database>' npx ts-node -r tsconfig-paths/register src/scripts/pos-g1b-minor-backfill.ts up --dry-run --production --i-have-a-backup
   MONGO_URI='<production maintenance uri>/<database>' npx ts-node -r tsconfig-paths/register src/scripts/pos-g1b-minor-backfill.ts up --production --i-have-a-backup --batch <measured best>
   ```
   If it stops (network, laptop sleep), continue with the same command plus `--resume`. Re-running from the start is also safe.
5. **Checks**
   * The second `up` writes 0 documents.
   * `pos-minor-flip-report.ts` for the full history → 0 storage mismatches.
   * Open shifts that were open at deploy still close with the right expected cash (watch the first closes).
   * App sales keep working during the run (no 5xx spike in the API log).
6. **Rollback**
   * Code: redeploy the previous commit. Extra `...Minor` fields are ignored by old code.
   * Data: `... pos-g1b-minor-backfill.ts down --production --i-have-a-backup` removes only the fields the backfill added (`minorBackfilledAt` rows). Rows written by live traffic after the deploy keep their (correct) twins; to strip those too, restore the snapshot from step 4.1 (last resort: loses sales made since).
   * Data is never read from the minor fields yet, so leaving the twins in place is safe.

## 5. Burn-in with the flip report
Goal: ≥ 14 consecutive clean days and every payment path exercised, then ask for step f.
1. Daily (or have a scheduled job), read-only:
   ```bash
   MONGO_URI='<read-only uri>/<database>' npx ts-node -r tsconfig-paths/register src/scripts/pos-minor-flip-report.ts --from <deploy date> --to <tomorrow>
   ```
2. Look at: mismatch count (must be 0), the independent re-scan, and the path table: cash, card, split, full refund, partial refund, held create/resume/discard, offline synced, shift close with card variance. **Client payload mismatches** are informational (a client rounding bug is recorded but never blocks a sale); storage mismatches must be 0.
3. **Decision gate:** `READY` after ≥ 14 clean days with every path ✔. Send me the report and ask for approval of step f. If it says NOT READY, the report names the cause; fix and restart the 14-day clock only if a storage mismatch occurred.
4. **Rollback:** nothing to roll back; reads still use the decimals until step f. If a storage mismatch appears, stop, send me the audit event (`money_minor_mismatch`, includes both values) and we fix the write path before continuing.

## 6. Credit-note backfill (pre-G2.5 refunds and voids) — separate series `CN-B`
Prepared, **not run** (on hold with the rest of this runbook). Run it **after** the production deploy of the G2.5+ backend and **only if** the dry run shows candidates: refunds and voids made before credit notes existed have no document; this gives each one a note in a **separate series `CN-B000001…`** so the live gap-free `CN-000001…` series is never disturbed.

What the script guarantees (tested, see `pos-credit-note-backfill.spec.ts`): **marked** (every note carries `backfill { backfilledAt, originalType refund|void, originalId, batchId }`, a `CN-B` number, a negative `seq`, `createdAt` = the original refund/void time, and the app shows "Backfilled …"); **idempotent** (re-run writes 0); **resumable** (numbers are chronological per store, `--max-docs N` slices a run); **reversible** (`down` removes exactly the notes and audit events it wrote; the database hash is identical before `up` and after `down`); **nothing else changes** (no stock, no shift counters, no sales/refunds, no live counters); **refuses non-dev databases** unless BOTH `--production` and `--i-have-a-backup` are given; **never guesses** (a refund of a missing sale, an unknown line or more units than were sold is listed and skipped). It does not read `.env`: `MONGO_URI` is passed explicitly. `down` deletes from an append-only collection, so it needs a maintenance user that may delete there (not the app's insert-only role).

1. **Backup/snapshot** first (note its id). Do not run with `--i-have-a-backup` without one.
2. **Dry run on a restored copy** (same copy as step 2 above):
   ```bash
   MONGO_URI='<rehearsal cluster uri>/<database>' npx ts-node -r tsconfig-paths/register src/scripts/pos-credit-note-backfill.ts up --dry-run --production --i-have-a-backup
   ```
   Output per store: refunds, voids, "would write N (CN-B000001 … CN-B00000N)", `legacy-decimal-amounts` (refunds written before the minor twins — converted with the sale's own exponent), `differs-from-proration` (a refund priced by the old rule: the difference is put on the last line and listed), `SKIPPED` (listed with a reason).
3. **Real run on the copy**, then run `up` again → `candidates 0, written 0`. **Checks:** every note's lines add up to its total; every refund note's total equals the refund's amount (a query in `G3_0_SUMMARY.md` does both); the real counter `creditNoteCounter` is unchanged.
4. **Rehearse the rollback on the copy:** `... pos-credit-note-backfill.ts down --dry-run …`, then `down …`; in the Atlas shell `db.runCommand({dbHash:1}).md5` must equal the value taken before `up`.
5. **Production:** repeat 2–3 on production in a quiet period (the run is safe under live traffic: it only inserts, and live returns use the other series). Send me the dry-run and the second-run output.
6. **Rollback:** `... pos-credit-note-backfill.ts down --production --i-have-a-backup` (restoring the step-1 snapshot is the last resort).
7. Decision for you before step 5: whether production has any real (non-test) refund/void from before G2.5. If the dry run says 0 candidates there is nothing to do.

## 7. Store-credit ledger switch (G3.3, option B) — prepared, **not run**
Order matters; the application code ships first with `STORE_CREDIT_LEDGER` unset (= `legacy`, behaviour unchanged). Details and the proof of "no dual spend at any step" are in `G3_STORE_CREDIT_LEDGER_PLAN.md` §5. Run `preflight.js` first (its `g3` section prints counts only: legacy rows, customers with spendable credit per currency, lots with a future expiry, off-grid lots).
1. Backup/snapshot. Deploy the backend (mode `legacy`). Smoke: the storefront's store-credit balance / checkout use / refund-to-credit work as before.
2. On a **restored copy**: `store-credit-migrate.ts up --dry-run --production --i-have-a-backup`, then `up`, check the self-check line, then `down` and compare the database hash before / after (`db.runCommand({dbHash:1}).md5`).
3. Production window: set `STORE_CREDIT_LEDGER=migrating` and restart the API (credit reads 0, nothing can be spent or changed). Run `up --dry-run`, `up` (self-check must print OK; any mismatch exits non-zero → stay in `migrating`, investigate or `down`). Set `STORE_CREDIT_LEDGER=new`, restart. The till's store-credit tender and refund-to-credit are available from this moment (and not before).

### 7a. Length of the `migrating` window, what customers see, go / no-go
**How long.** The migration writes in batches of 1,000 (lots → entries → markers). Measured on this Mac against a local mongod on a **synthetic 30,000-row legacy ledger** (20,000 spendable lots, 3,333 with an expiry): dry run **1.7 s**, `up` **3.5 s** (≈ 8,500 rows/s), second run 1.3 s (writes nothing), `down` 1.9 s, database hash identical after `down`. Against Atlas the per-batch round trips are slower: plan on **≈ 1,000–2,000 rows/s**. So `window ≈ rows ÷ 1,000 s` for the migration itself, **plus two API restarts (≈ 30 s each) and the checks (≈ 5 min)**. Examples: 5,000 rows ≈ 6 min · 100,000 rows ≈ 8–10 min · 1,000,000 rows ≈ 25 min. **Do not trust the estimate: step 2 (restored copy) gives the real number — book `3 × measured migration time + 10 min`.** (The 30,000-row figure is local and synthetic; production row counts come from the preflight `g3` section.)
**What storefront customers see while the mode is `migrating`.** Their store-credit balance reads **0** (checkout does not offer or apply credit; a checkout that had already applied credit fails the "balance changed" check and the buyer is asked to review it); nothing else changes — orders without credit, payments and the rest of the storefront work as normal. Refunds / cancellations that would *give credit back* during the window **are not applied** and are logged (`store credit … NOT applied: the ledger is being migrated`); after the switch, search the API log for that line and re-issue those credits from the dashboard (the order id is in the line). Choose a quiet hour and announce it if store credit is heavily used.
**Go / no-go before moving from `migrating` to `new`** (all must be true; otherwise stay in `migrating` and run `down`, or fix first):
1. `up` printed `self-check OK` (a mismatch exits non-zero) and `entries written = legacy rows` of the dry run; the second `up` says `to migrate 0`.
2. The per-currency totals / customer counts of `up` equal the dry run (which equal the preflight figures within what happened since).
3. Spot check 5 real customers (including one with an expiring lot and one in a non-2-decimal currency): their balance through the dashboard / storefront endpoint in mode `new` (switch a staging copy, not production, for this) equals the legacy balance.
4. The copy rehearsal `down` restored the database hash.
5. The off-grid list is understood (values rounded **down**; the store never owes more than before); the future-expiry lots are carried with their expiry.
6. Someone is ready to watch the API log for `store_credit_redeem_failed` / 5xx for the first hour and knows the rollback (`migrating` → `down` → `legacy`; `down` refuses if the new ledger already has activity of its own).

4. Rollback: set `migrating`, `down` (refuses if the new ledger has activity of its own — decide consciously, `--force-lose-activity` does not delete those rows but the legacy ledger will not know about them), set `legacy`.

## 8. Supply-side cost twins (G3.0 backfill) — prepared, **not run**
Fills the integer `…Minor` twins of purchase orders, supplier returns, stock lots and variant costs written before G3. **Not required to use G3.4** (new rows are written with their twins; reads fall back to the decimals converted with the store's exponent), but **required before the G4 profit report is trusted** for old stock. Safe under live traffic (it only fills missing twins), idempotent, resumable, reversible.
1. Backup/snapshot (note its id). On the **restored copy**: `MONGO_URI=… npx ts-node -r tsconfig-paths/register src/scripts/pos-g3-cost-minor-backfill.ts up --dry-run --production --i-have-a-backup`, read the counts (documents per collection, anything off the currency grid is listed), then `up`, then `up` again (must write 0), then `down --dry-run` / `down` and compare the database hash.
2. Production in a quiet period with the same commands. **Checks:** the second run writes 0; `money_minor_mismatch` / `cost_minor_mismatch` counters in the API log stay 0 for a day.
3. **Rollback:** `… pos-g3-cost-minor-backfill.ts down --production --i-have-a-backup` (removes only what `up` wrote).

## 9. G3.4 – G3.6 deploy notes (no data migration)
Order: **API first, then the apps.** Everything is additive; old app builds keep working (they simply have no Supply / Cash / Team screens).
1. **New collections and indexes** (`purchasereceipts`, `supplierledgerentries`, `posexpenses`, `posexpenseevents`, `posattendanceevents`, `posattendancestates`, `posrostershifts`) are created by Mongoose on the first start; the unique indexes build on empty collections — nothing to run. If the DB role is insert-only for ledgers, grant it on the new append-only collections as for the G1a ones (receipts, supplier ledger, expenses, expense events, attendance events).
2. **Expense receipt photos need the private storage that KYB documents already use** (Cloudinary private uploads) to be configured in the target environment; optional `EXPENSE_RECEIPT_MAX_BYTES` (default 5 MB). Without storage the receipt upload fails with a clear error and everything else works.
3. **New approval limit** `purchaseOrderMinor` (default 1,000.00 in the store currency) and new matrix actions (`supply.*`, `team.attendance.view`, `team.roster.view`; `daybook.view` is now open to cashiers for their own shifts). Stores keep their existing overrides; the defaults apply to the new keys. Tell owners (Settings → Approval limits).
4. **Smoke after deploy:** create a supplier and a draft PO; clock in / out as a test employee; record a 1.00 cash-in on an open shift and open the daybook for today — the shift must show "reconciled".
5. **Rollback:** redeploy the previous API; the new collections stay (harmless, unread). Nothing to restore.

## 10. G4.0 – G4.6 deploy notes (no data migration)
Order: **API first, then the apps.** Everything is additive; old app builds keep working without the new screens. Details: `G4_CLOSEOUT.md` §4.
1. **New collections** `posmodifiergroups`, `pospricebooks`, `posauditseals` (unique `storeId + day`) are created on first start. `posauditseals` is append-only (insert-only grant, as for the other ledgers).
2. **`POS_AUDIT_SEAL_CRON`** (optional, default `20 1 * * *` UTC): nightly seal, one instance (lease `pos:audit-seal`), each store's day in its own zone. The first night seals all past days — quiet window. Verify: `MONGO_URI=… npx ts-node -r tsconfig-paths/register src/scripts/pos-audit-verify.ts <storeId> [from] [to]` (exit 1 = changed).
3. **Store time zone** (`Store.timezone`, default from the country): reports count days in the store's zone, not the server's — "today" changes for stores off UTC. Tell owners.
4. **New matrix actions** (catalog.*, settings.permissions.*, settings.store.edit, audit.verify, inventory.transfer.*, inventory.writeoff): defaults apply.
5. **Smoke:** owner on a till changes auto-lock, previews + saves + resets a permission, sells a product with a modifier, opens / closes a shift counting notes (last-close card), runs Check this period.
6. **Rollback:** previous API; the new collections stay unread. Nothing to restore.

## Who does what
| Step | You | Me |
|---|---|---|
| 0 | merge, deploy, verify version | review the output |
| 1 | create user, run script, send JSON | review the report |
| 2 | restore snapshot, run commands, send outputs | review, advise |
| 3 | measure and pick the window | compute the window |
| 4 | backup, deploy, run backfill | on call to read output |
| 5 | run the report daily | analyse, request step f approval |
| 6 | backup, dry run + run on the copy, then production (only if candidates) | review dry-run output, confirm checks |
| 7 | store-credit switch (see 7, 7a) | on call |
| 8 | cost-twin backfill on the copy, then production | review counts |
| 9 | deploy API, then apps; smoke | review |
