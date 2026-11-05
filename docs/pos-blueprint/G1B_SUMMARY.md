# G1b — Money in minor units: steps a–e built (step f NOT built)

Status: **built and verified on the local dev stack; stopped for owner approval.** Step f (flip reads to minor) is untouched, as instructed. Branch `feature/jamibranch` in both repos; hotfix PR #19 is separate.

## Owner decisions applied
| Decision | Where |
|---|---|
| ISO 4217 exponent for every currency (PKR = 2); the storefront's "0 decimals" is display-only | `common/money-minor.util.ts` (`isoExponent`), `ENGINEERING_RULES.md` §2.3, test `money-minor.util.spec.ts` pins `isoExponent('PKR') = 2` against the storefront's `displayDecimals('PKR') = 0` and shows 12.50 → 1250 (not 13) |
| `MinorMoney` is the standard type | `common/schema-types/minor-money.ts`; rejects fractions, strings, NaN, ±Infinity and |x| > 2^53−1; stores BSON `long`; tested on a real MongoDB (also `$inc` / `$set` / queries / arrays / JSON) |
| Flip criteria (step f, later) | `scripts/pos-minor-flip-report.ts` — read-only: mismatch count, an independent re-scan, per-path counts, READY / NOT READY against ≥ 14 clean days + every path |
| Production pre-flight, no credentials shared | `pos/docs/pos-blueprint/preflight/` — aggregate counts only; refuses to run if the user can write |
| Push | `feature/jamibranch` was pushed in both repos before this round; the G1b commits are local until you approve |

## Backend (solvexo-api) — steps a, b, c, d and the server side of e
**a) Dual-write.** Every create/update path writes the decimal and its integer `...Minor` twin from the same calculation (the engine already computes in minor units), inside the G1a transactions: sales (subtotal, discount, discountValue for amount discounts, tax, total, change, shortfall, refundedAmount), items (`priceMinor`, `listPriceMinor`, **`lineTotalMinor = toMinor(price × qty)` — authoritative**), payment lines, refund records and tenders, `pospayments`/`posrefunds`, held sales (create / edit / resume / discard), shifts (opening float, counted, expected, variance, the five running counters, cash movements, card reconciliation slip / expected / variance), register default float. **Open shifts at deploy:** counters are updated by one aggregation-pipeline update that starts the minor counter from the existing decimal (`$ifNull`), so a shift already open when G1b ships stays correct (tested). Currency + exponent snapshot stays on every parent.
**b) Consistency checker** after every write: `minor == toMinor(major)`; on a mismatch it logs `[pos-minor-mismatch]`, writes an audit event `money_minor_mismatch` (own try/catch) and counts it in `PosMinorMetrics`. It **never fails or delays the sale** — tested with an injected mismatch and with a failing audit write. Float noise such as the shift counter `3.3000000000000007` is correctly *not* a mismatch (minor counter is the exact 330).
**c) Backfill** (`scripts/pos-g1b-minor-backfill.ts`): dry run → report (counts, **batch size**, off-grid values, float noise, currency inferred, read+compute rate, **estimated duration**) → real run. Idempotent (fills only missing twins), resumable (checkpoints), reversible (`down` removes only rows carrying `minorBackfilledAt`), safe under live traffic (guarded writes retried from a fresh read; hot counters via the atomic pipeline), refuses a non dev/test database unless **both** `--production` and `--i-have-a-backup` are given.
**d) API:** `...Minor` twins in responses (sales, items, payments, refunds, shifts, quote lines + totals, daily/range/session report summaries incl. per-tender `totalMinor`). Old builds ignore them.
**e, server side:** requests accept optional minor twins (`clientTotalMinor`, `amountTenderedMinor`, `discountValueMinor`, `items[].unitPriceMinor`, `payments[].amountMinor`). The server recomputes everything from its own data; if a decimal and its twin **disagree** (or a twin is malformed) the sale is **still accepted** at the server's values and the mismatch is recorded — log + `money_minor_mismatch` audit event (`source: client`, with the client's and the server's values) + metric. **A client money mismatch never rejects a sale** (owner decision: an offline sale whose cash was already taken must always sync; a client rounding bug must never stop checkout). Payloads with decimals only (old builds, **old offline queue entries**) pass untouched. (The older Phase 5B online `TOTAL_MISMATCH` guard on `clientTotal` is a separate, pre-existing rule and is unchanged; offline sales were never subject to it.)

## App (pos) — step e
* `MoneyJson.read` — every money model reads `<name>Minor` when present, else the decimal exactly as before (Dart field types and all screens unchanged).
* `withMinorTwins` — new sale payloads (and therefore the **queued offline copy**) carry the minor twins next to the decimals; added after the idempotency fingerprint so a checkout intent started by an older build keeps its key.
* Old queued payloads replay verbatim (tested: no Minor keys are injected or stripped).

## Verification
| Check | Result |
|---|---|
| New backend tests | conversion exp 0/2/3, ISO exponent, MinorMoney rejections (real Mongo), checker catches an injected mismatch, shift drift 3.3000000000000007, dual-write on every path (17), backfill (9), flip report (5) |
| Backend gate (`src/pos src/pos-plans src/inventory src/product-variants src/common src/draft-orders src/markets src/auth src/scripts`) | **800 passed**, 45 skipped (env-gated), **10 failed = the known slug-transliteration failures** (separate note, untouched) |
| `npm run build` | passes; `dist/main.js` at the root, no `dist/src/main.js` |
| `npm run test:di` | passes (2 s once loaded) |
| `flutter analyze` | no issues |
| `flutter test` | **634 passed** |
| Backfill on a copy of the local dev data | dry run wrote nothing (hashes identical); `up` filled **184** documents (76 sales, 69 shifts, 19 payments, 4 refunds, 16 stores); second `up` = 0; `down` restored all five collections **byte-for-byte** (twice); read+compute 800–1,450 docs/s with 25 writes in flight; the CLI refuses a non-dev name |
| Dev-stack E2E (old and new payloads) | cash, card, split, full refund, partial refund, held (create / resume / discard), offline sync (**old and new queue entries**), shift close with card variance — all stored with major + minor; BSON type `long`; 0 checker events; a disagreeing payload → accepted at the server's values + audit event |
| Flip report on that data | every path ✔, 0 mismatches, 9 sales / 1 shift / 9 payments / 2 refunds re-scanned |
| Pre-flight script | read-only user: report; read-write user, root, unauthenticated: **refused** |
| iOS simulator integration (iPhone 17 Pro) | `pos_checkout_flow` ✅, `phase3_sale_flows` (park → resume → split → success, quote-changed confirm) ✅, `offline_sync` ✅ (first attempt stalled on the known stale-app-instance flake; passes on re-run) |
| Real-backend suites (`tool/run_real_e2e.sh`, the app's NEW payloads → the NEW backend) | 11/11 ✅ and 1/1 ✅; the 11 sales they created are all dual-written, **0** `money_minor_mismatch` events |

## Stored rows from the dev-stack run (major | minor)
```
POS-00077 cash   subtotal 5|500  tax 0.5|50  total 5.5|550  change 44.5|4450  item 2.5|250  line 5|500  pays cash 5.5|550 tendered 50|5000
POS-00081 split  total 5.5|550  pays card 3.3|330 + cash 2.2|220 (tendered 2.2|220)
POS-00079 partially_refunded  refunded 2.75|275      POS-00080 refunded  refunded 5.5|550
POS-00084/85 offline (old / new queue entry)  total 5.5|550  tendered 6|600
SHIFT opening 100.5|10050  cashSales 26.95|2695  cardSales 8.8|880  totalSales 35.75|3575  totalRefunds 8.25|825
      expected 127.45|12745  closing 120|12000  difference -7.45|-745  card slip 1|100 expected 8.8|880 variance -7.8|-780
```

## Commits (all local; nothing pushed this round except hotfix PR #19)
API: `d39e0b4` conversion + `MinorMoney`; `027902c` dual-write + checker + API + cross-check; `de90897` backfill; `db39f3c` flip report; `74c9022` refundedAmountMinor + tender minor + tests. Hotfix branch `hotfix/build-output-path` → **PR #19** (CI guard only; the tsconfig exclude was already on staging/main since 2026-11-03 17:36).
App/docs: committed together at the end of this round (see the final report).

## Migrations
`src/scripts/pos-g1b-minor-backfill.ts` (`up` / `down`, `--dry-run`, `--batch`, `--resume`, `--max-docs`, `--production --i-have-a-backup`). Schema changes are additive (new nullable fields; `MinorMoney`); the G1a `pos-g1a-backfill` is unchanged.

## Not verified
Production (no access — use the pre-flight); Atlas throughput of the backfill (measured only on the dev mongod: rehearse on a restored copy); the app's new payload against an **older server** (needs the decimal path — covered by tests, not run against an old build); Android; `completeSale` (held resume) and the quote request do not send minor twins from the app (the contract only lists `POST pos/sales`).

## Next (after your approval)
Deploy G1b to staging → run the pre-flight (you) → backfill dry run on a restored staging copy → real backfill → start the burn-in and run `pos-minor-flip-report.ts` daily → decide step f. G2 can start in parallel (new modules use `MinorMoney`, per `ENGINEERING_RULES.md`).
