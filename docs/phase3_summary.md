# Phase 3 — Offline & Network Resilience — Completion Summary

Implements the Phase 3 plan (`~/.claude/plans/rosy-squishing-mccarthy.md`). The spec required determining in writing, before building anything, whether the backend realistically supports safe offline queuing — it does not, and that finding shaped the whole phase.

## The determination (read directly from `pos.service.ts`, not assumed)

- `createSale`'s `idempotencyKey` deduplication is a plain `findOne`-then-`create` check, backed by a **sparse, not unique** schema index. Two requests carrying the same key close together — exactly what a client retry after a timeout produces — can both pass the check before either has written, creating two completed sales from one checkout.
- Stock decrement on sale creation is a plain `$inc` with **no floor guard** and no transaction around the earlier stock-sufficiency read — concurrent/retried requests can both pass and both decrement, overselling.
- Cash in/out (`cashInOut`) appends via `$push` with no idempotency check at all — a retry doubles the cash movement.
- Session open/close, refund, and void are "safe-ish" (a genuine retry after real success hits a status guard and throws a business error, rather than corrupting state) but not silently idempotent either.
- The backend already has a correct atomic idempotency pattern (`common/idempotency.interceptor.ts`, used on several other modules) — it's just never applied to the POS routes.

**Conclusion:** building local queued transactions or offline sale creation right now would make the exact failure mode the phase is meant to guard against *more* likely, not less — a network blip followed by an automatic retry is precisely the scenario that duplicates a sale and oversells stock today. So this phase stayed scoped to the "minimum bar," and the fix (apply `IdempotencyInterceptor` to the POS sales/cash-adjustment routes, or a unique index + atomic upsert, plus a floor-guarded stock decrement) is flagged as backend work, not implemented.

## What changed

**Retry-with-backoff, safe operations only** — `BaseClient` gained a small retry helper (up to 2 retries, 500ms/1s backoff) triggered only on network-level `DioException` types, never on a real server response. `GET` retries by default (reads are naturally idempotent). `PATCH` defaults to no retry, with an explicit opt-in — only `InventoryRepository.updateVariantStock` uses it, since that PATCH sets stock to an absolute value (confirmed idempotent — a retried no-op, not a double-adjustment). Nothing on `POST`/`PUT`/`DELETE` was marked retryable this phase, including `createSale` and cash adjustment specifically, per the finding above. The existing double-submit guards from Phase 1 (`isChargingOrHolding`, `isOpening`, `isClosing`, `isProcessing`) remain the defense against a cashier re-tapping; a network failure on these now surfaces as a single clear error requiring a deliberate manual retry, not a silent automatic one.

**Connectivity indicator** — new `NetworkStatusService` (connectivity_plus-backed, GetX permanent service) and `NetworkStatusBanner`, wired into `main.dart`'s existing app-wide `builder:`. Shows a slim "No internet connection" strip whenever no network interface is connected. Documented as reflecting interface state, not verified reachability — appropriately scoped for a hint, not a stronger guarantee.

## Explicitly out of scope

- Local queued transactions / offline sale creation — unsafe against the current backend (see above).
- Local cart persistence for crash/kill resilience — a separate, reasonable idea independent of the network-safety question, deferred per an explicit decision with the user to keep this phase focused.

## Testing

- `pos/test/base_client_retry_test.dart` — the retry-eligibility and backoff-delay logic, extracted as pure top-level functions specifically so they're testable without a real Dio instance.
- `flutter analyze`: clean (same 2 pre-existing info-level lints, unrelated).
- `flutter test`: all 43 tests pass (4 new).
- Manual: launched on iOS Simulator (required `pod install` for the new `connectivity_plus` native dependency, ran automatically) — boots cleanly, renders correctly, no crash. **Not verified**: the banner's actual appearance when offline — this environment has no scriptable way to toggle the iOS Simulator's network interface, so that's a manual check to do before shipping (put the simulator/device in Airplane Mode and confirm the banner shows and clears).

## Recommended next step (backend-scoped, outside this task)

Apply `IdempotencyInterceptor` to `pos.controller.ts`'s sale-creation and cash-adjustment routes (or make `idempotencyKey` a unique index with an atomic upsert), and add a floor guard to the stock decrement (`$inc` with a `stock: {$gte: qty}` filter, or wrap the check+decrement in a transaction). Once that's in place, real offline queuing becomes a safe, buildable follow-up phase.
