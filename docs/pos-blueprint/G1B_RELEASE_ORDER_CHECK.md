# G1b release-order check: new app against the pre-G1b server

Server under test: a local build of `origin/staging` @ d7a7a81 (no `...Minor` support; `dist/main.js` only), own database `solvexo_dev_oldsrv`, port 3103, seeded by the same dev seed. The app: `feature/jamibranch` (with `withMinorTwins`).

## ValidationPipe (read from the code)
| Branch | `main.ts` | Effect on unknown fields |
|---|---|---|
| origin/staging | `app.useGlobalPipes(new ValidationPipe({ transform: false }))` | ignored (not stripped, not rejected) |
| origin/main | identical | ignored |

`whitelist`/`forbidNonWhitelisted` appear only on per-controller pipes (admin controllers, markets, store notification settings, pos-plans). `PosController` has none. So an old server does **not** reject `...Minor` fields.

## Run
| Payload | How | Result |
|---|---|---|
| Cash sale, 10 % manager discount, wrong `clientTotal` refused | app's real-backend suite test 3 | pass |
| Split card+cash, report | test 4 | pass |
| Partial refund (card first, then cash) + void | test 5 | pass |
| Idempotent retry | test 7 | pass |
| Shift close with variance | test 8 | pass |
| Device setup / PIN login | tests 1, 2 | pass |
| **Offline-queue replay** (`offline: true`, `clientCreatedAt`, all minor twins) | scripted `POST /api/pos/sales` with the app's queued shape | **201**, sale created |

7 of 7 suite tests passed. The stored sales had no `...Minor` fields (confirms the old code ran). Not run against the old server: offline test 6 in the suite (its sidecar stops/starts the dev API on 3102; replaced by the scripted replay above), plan-expiry, device-revoke and account-deletion tests (unrelated to money).
