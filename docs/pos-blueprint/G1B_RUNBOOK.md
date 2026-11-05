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

## Who does what
| Step | You | Me |
|---|---|---|
| 0 | merge, deploy, verify version | review the output |
| 1 | create user, run script, send JSON | review the report |
| 2 | restore snapshot, run commands, send outputs | review, advise |
| 3 | measure and pick the window | compute the window |
| 4 | backup, deploy, run backfill | on call to read output |
| 5 | run the report daily | analyse, request step f approval |
