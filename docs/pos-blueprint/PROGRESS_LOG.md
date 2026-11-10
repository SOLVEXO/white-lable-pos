# POS progress log (one short entry per sub-phase; full report at the end of each phase)

Working mode since 2026-11-10: one heavy job at a time (backend gate / full `flutter test` / simulator / build / sub-agent), only affected tests locally (jest `--maxWorkers=1`), CI is the source of truth for "all green", one simulator booted only for integration flows, stop only for decisions / unfixable CI / production-secrets-money outside the plan / a finished phase. Dev + test mongod capped at `--wiredTigerCacheSizeGB 0.25`.

| Sub-phase | Built | Commits | CI | Open items |
|---|---|---|---|---|
| G3.3 follow-ups | store-credit presentation fixes, offline loyalty exactly-once, runbook 7a, FBR open question | api 5b6a73a · app bb07119 | green | — |
| G3.4 Supply | suppliers, POs (approve/send), receipts with WAC + lots + bills, supplier returns + credit, payables + aging, supplier payments (drawer cash-out); app screens | api bef6444, 22e4273 · app 52ce64e | **green** (approved) | serial-tracked receiving stays dashboard-only (→ G3 close-out) |
| G3.4 follow-ups | direct receipt confirmed (own GRN number, stock movement, WAC, bill, no fake PO); date-picker widget tests | api (test) · app (this push) | — | — |
| G3.5 Cash & daybook (backend) | cash in/out with categories + limits + replay-safe offline movements, expenses with private receipt photos, daybook reconciling with shift close (USD/JPY/KWD) | api c47898c, bbf31b1 | pending | receipt storage verified against a fake store only |
| G3.6 Team (backend) | attendance by PIN (append-only, one open record, offline-safe), anomalies, corrections, roster, report | api 27c557b | pending | — |
| G3.5 / G3.6 app | built by sub-agent, in progress / in review | — | — | — |
