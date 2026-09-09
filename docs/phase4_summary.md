# Phase 4 — RBAC, Audit Logs, Security Pass (mobile-side) — Completion Summary

Implements the Phase 4 plan (`~/.claude/plans/rosy-squishing-mccarthy.md`). As with prior phases, the backend was read directly (not assumed) to determine what's real enforcement vs. what a client-side gate can only approximate.

## What was verified against the real backend first

- **Refund/void ARE genuinely role-checked server-side** (`pos.service.ts:768-771`, `1209-1212`): when `actingEmployeeId` is sent, the backend looks the employee up and throws 403 if their role isn't `manager`. Real enforcement — but weak: the check is silently skipped if the employee lookup returns `null` (missing/invalid/wrong-store id passes through). Per an explicit scope decision with the user, RBAC gating this phase covers **refund/void only**, matching what the backend actually checks.
- **Discount entry and Cash Management have zero backend role enforcement** — confirmed, not assumed. Left open to all roles per the user's choice, flagged below rather than gated with an invented client-only rule.
- **No generic client-event audit endpoint exists anywhere**, and several categories the task wants audited aren't captured server-side at all today even as a mutation side-effect: `createSale`, `openSession`, `closeSession`, `updateEmployeeV2`, `updatePosSettings`, and PIN login (there's no PIN-logout endpoint at all). Only refund/void/employee-deactivate/PIN-reset/force-close write to the audit log. Per the task's own instruction ("flag if there's no endpoint for this yet"), **no client-side logging calls were added** — there's nowhere for them to go.
- **`GET /api/auth/getprofile` is confirmed live and JWT-guarded only** — safe to call with the seller's own token to re-verify their role.

## What changed

**Refund/void gating** — `PosSaleDetailController`/`PosOrdersController` now read the PIN-logged-in employee's role via a new small `PosRole` helper (`lib/utils/pos_role.dart`). A cashier no longer sees the Refund/Void buttons (or the partial-refund line-item steppers) — instead sees a plain-language note that a manager needs to do this. Doc comments at every call site are explicit that this mirrors the backend's real-but-weak check and is a UX improvement, not an independent security boundary — the role value is still read from local, client-writable storage.

**Role re-validation on boot** — new `AuthRepository.getProfile()`, called in the background at app start (only when a session already exists) to refresh the cached "seller" role from a live server call instead of trusting a value that, before this phase, was never re-checked after being set once. Fired non-blocking (same pattern `BrandingService` already uses for its own backend refresh), so it never adds boot latency or fails a cold start when offline.

**Token storage migrated to `flutter_secure_storage`** — access and refresh tokens now live in Keychain/Keystore-backed storage instead of plaintext `shared_preferences`, closing the Phase 0-flagged gap. Everything else in `AppPreferences` (device-local prefs, POS session/employee ids) stays where it was — no reason to move non-sensitive state. The Phase 1 synchronous in-memory cache for the auth-middleware race fix is unaffected structurally.

**Secrets re-scan** — re-ran the Phase 0 grep across all of `lib/` (including everything added in Phases 1-3). No new hardcoded secrets; only the already-known, non-secret Firebase `apiKey` in `firebase_options.dart`.

## Explicitly out of scope (per user decision / confirmed backend gaps)

- Discount entry and Cash Management role-gating — left open to all roles; backend has no enforcement either, flagged as a real gap rather than invented client-side.
- Client-side audit-event logging calls — no endpoint exists anywhere to call. Recommended fix: the backend should add `writeAuditLog`/`ActivityLogService.log` calls at the point of truth in `pos.service.ts` for the currently-uncovered mutations (sale created, session opened/closed, employee updated, settings updated), and add a PIN-logout endpoint — cleaner than inventing a generic client-POST endpoint, since both logging mechanisms already exist and are just not called from every mutation.
- A fully tamper-proof role check — not achievable client-side regardless of storage mechanism. Boot-time re-validation (this phase) narrows the trust window from "forever" to "since last cold start" — it does not eliminate it. This remains the single most important flagged item across all four phases: **every actual POS API call still requires a valid JWT, so the practical risk is scoped to unauthorized screen access, not raw data access** — but real hardening (e.g. deriving role from the JWT claim rather than a separately-stored preference, or short-lived tokens) is a broader auth-architecture decision outside a mobile-only task.

## Testing

- `pos/test/pos_role_test.dart` — the manager-role decision logic (`PosRole.isManagerRole`) and the refund/void visibility rule (`actionAllowedByStatus && isManager`), covering the manager/cashier/null/case-sensitivity cases.
- `flutter analyze`: clean (same 2 pre-existing info-level lints, unrelated).
- `flutter test`: all 47 tests pass (4 new).
- Manual: launched on iOS Simulator twice across this phase (required an automatic `pod install` for the new `flutter_secure_storage` native dependency) — boots cleanly both times, no crashes, login screen renders correctly. **Not verified interactively**: the actual refund/void gating UI with a real cashier vs. manager PIN login, or the `getProfile()` boot refresh against a live session — same credential limitation as all prior phases.
