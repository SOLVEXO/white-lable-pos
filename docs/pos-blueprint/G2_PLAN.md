# G2 — Step 0 plan (no code written)

Status: **plan only, waiting for owner approval.** G2 = blueprint roadmap phase 1 (Transactional MVP) + the payment foundation.
Date: 2026-11-05. Inputs: GAP_AUDIT.md, ENGINEERING_RULES.md (§1 status events, §2 minor money, §4 release order), the owner's decisions below.

## 0. Owner decisions this plan is built on
| Decision | Consequence in the plan |
|---|---|
| Solvexo is an **aggregator**: onboards stores after business verification, works through a licensed Merchant Service Provider's aggregator programme | KYB is a gate for digital payments; each store gets a **provider sub-merchant reference** |
| Settlement goes **directly to each store's bank account**; Solvexo never holds customer funds | No wallet, no Solvexo balance, no payout logic. We store the store's IBAN for onboarding/reconciliation only |
| Raast via PayFast or 1LINK 1GO (undecided) | Provider-agnostic `PaymentProvider` adapter; everything is built and tested on a **mock provider**; the real provider is one adapter file later |
| Cards: **no provider is built**. Cards stay `recorded_unverified` + slip reconciliation at shift close | `cardTotalFromSlip` wired in G2.4; card payments never claim "confirmed" |
| Catalog: POS-scoped routes behind **manager approval** for price, stock, barcode, category; also visible on the storefront | G2.6 |
| Existing rules still bind: additive API, minor-only money for new entities, never commit to main, ask before packages, no formatting-only diffs, step f of G1b untouched | |

## 1. What already exists (reuse, don't rebuild)
**Backend**
* **Business verification already exists.** `Store.verificationStatus` (`not_started → pending → under_review → verified/rejected`, enforced transitions), `verificationLevel` (basic/business), `SellerVerification` (legal name, registration number, `taxId`, address, ID type, authorized contact, **documents**, **history**), requirements in `store/verification-requirements.config.ts` (single source of truth), `StoreService.submitVerification`, admin review endpoints `api/admin/marketplace/leads` (list, detail, `under-review`, `approve`, `reject`). Documents are uploaded **private** (`UploadService.uploadPrivateFile`, `publicId` only) and viewed via short-lived signed URLs. What is **missing**: bank IBAN/account title, encryption of the sensitive text fields at rest, an audit event on every document view, a `draft` state distinct from `pending`, provider sub-merchant reference, and the POS-side gate.
* **Payments table exists** but is not an event log: `PosPayment` (immutable except `status/confirmationSource/confirmedAt` via the G1a `allowSetFields` hook), `PosRefund`, split tender, idempotency, audit, `MinorMoney`, device/PIN auth, POS plan entitlement.
* `store-credit`, `loyalty`, `discounts`/`promotions`, `draft-orders`, `order-documents`, `stock-counts`, `purchase-orders` exist on the storefront side (used selectively below).

**App (Phase 3b work reused as-is)**: `lastOutcome/lastReceipt` on `PosHomeController`; the extracted variant picker; two-pane layout ≥ 700 px; held-sales header button; quick-amount chips; swipe-to-remove undo; Hold/Charge sheets; `AppBottomSheet.showGet`; the success view; design system (`core/design`), offline queue + sync, encrypted local stores, `MoneyJson`, `withMinorTwins`. G2.4 **re-skins and re-routes** these onto the blueprint navigation; it does not rewrite the selling logic.

## 2. Sub-phases (each ends with a summary doc, push of `feature/jamibranch`, STOP for approval)
Order: **G2.1 ∥ G2.2 → G2.3 → G2.4 ∥ G2.5 → G2.6 → G2.7.** Sizes: S ≈ 2–3 days, M ≈ 1 week, L ≈ 2 weeks (one engineer incl. tests).

---
### G2.1 Payment layer (backend-first) — **L**
**Backend**
* Module `payments-core` (name TBC; avoid the storefront `payment` module). `PaymentProvider` interface: `createCharge`, `getStatus`, `cancel`, `refund`, `verifyWebhook`, `parseWebhook`. Providers: `MockProvider` (deterministic, scripted outcomes incl. delay, decline, expiry, duplicate webhook, bad signature) and a registry keyed by `PAYMENT_PROVIDER_POS`. No real provider.
* **Entities** (all money `MinorMoney`, `isoExponent` snapshot):
  * `payment_intents` — `storeId, registerId, sessionId, shiftId, deviceId, employeeId` (server-side from token), `method` (`raast_qr`, later others), `amountMinor`, `currency`, `providerKey`, `providerRef`, `expiresAt`, `idempotencyKey` (unique), `saleId` (set once consumed, **unique sparse**), `qrPayload`.
  * `payment_events` — **append-only** (`makeAppendOnly`, no update path): `intentId`, `type` (`created, presented, pending, confirmed, failed, expired, cancelled, refund_requested, refund_succeeded, refund_failed`), `amountMinor`, `providerEventId` (**unique** per provider → dedupe), `source` (`webhook|poll|system|cashier`), `rawDigest`, `at`. **Current status = latest event** (a helper + a read model; never stored mutable).
* Remove the G1a `allowSetFields` hook on `PosPayment`; its status/confirmation fields become derived from events. Backfill: one `confirmed` event for every existing cash payment, `recorded_unverified` for card (no behavioural change). DB role stays insert-only.
* Endpoints (POS auth, `Idempotency-Key`): `POST pos/payments/intents`, `GET pos/payments/intents/:id` (status + countdown), `POST pos/payments/intents/:id/cancel`; **public webhook** `POST payments/webhooks/:provider` (raw body, **signature verification before any parsing**, constant-time compare, replay window, dedupe by `providerEventId`, always 200 for duplicates, never trusts the body's amount over the stored intent). **Poller** (scheduler job, existing `scheduler` module): re-checks `pending` intents every few seconds until `expiresAt`, then writes `expired`. Provider refund: `POST pos/payments/:id/refund` → `refund_requested` → provider → `refund_succeeded|failed`.
* Sale completion rule: `POST pos/sales` with a payment line `{method:'raast_qr', intentId}` succeeds **only if** the intent's latest event is `confirmed`, `amountMinor` equals the server-computed share, the intent belongs to this store/session and is unconsumed (unique `saleId`). Same transaction marks it consumed. Retries return the same sale.
* **Orphan recovery:** an intent confirmed but never attached to a sale (app crash) appears in `GET pos/payments/orphans` for the manager and in the shift-close warning; resolution is "complete the sale" or "refund" — never silent.
* **Tests:** unit (status derivation), real-Mongo integration (event ordering, duplicate/out-of-order webhooks, forged signature → 401 and no event, amount mismatch, expiry, double consumption → one sale, refund path, crash/orphan, transaction rollback), webhook fuzz on the signature parser, mock-provider contract tests that every real adapter must later pass.
**App:** none (a `PaymentRepository` + models, unit-tested). **Offline:** digital payments are **never queued**; intents need the network (see G2.3).
**Dependencies:** none external (mock). Optional new package: none expected (Node `crypto`).
**Risks:** webhook security (mitigated above); event-ordering races (mitigated by "latest event by server time + monotonic sequence"); real provider semantics differ from the mock (mitigated by the contract tests + a sandbox run before go-live).

---
### G2.2 Aggregator onboarding / KYB — **M** (parallel with G2.1)
**Backend** (extend the existing verification, no new parallel flow)
* Add to `SellerVerification`: `bankAccount { bankName, accountTitle, iban }` (IBAN validated by checksum, PK format `PK` + 22), `cnic`/`ntn` handled as explicit fields (today `taxId`/`registrationNumber`), and a `draft` status (`draft → submitted → verified/rejected`, mapped onto the existing `not_started/pending/under_review/verified/rejected` **without breaking old values**; the owner's vocabulary is exposed as `kybStatus`).
* **Encrypt sensitive text at rest** (CNIC, NTN, IBAN, account title): application-level AES-256-GCM per field with a key from env (`KYB_ENC_KEY`, versioned for rotation), only decrypted for the owner's own view and the admin review; masked everywhere else (`PK••••1234`). Documents stay on the existing **private** Cloudinary type; **every signed-URL generation and every decrypted read writes an audit event** (`kyb_document_viewed`, `kyb_field_viewed` with actor, store, document type), awaited.
* `Store.paymentAggregator { subMerchantRef, providerKey, onboardedAt, status }` set by admin after the provider confirms the sub-merchant (manual step at first; `provider.onboardMerchant()` added to the adapter interface later).
* **Gate:** `digitalPaymentsEnabled(store) = kybStatus==verified && subMerchantRef present && POS plan active`. `POST pos/payments/intents` returns `403 STORE_NOT_VERIFIED` otherwise; `GET pos/subscription/:storeId` exposes the flag (additive) so the app hides the button.
* Admin review flow: reuse `api/admin/marketplace/leads` endpoints, add: field-level reject reasons, "request changes" (→ back to draft with a note), sub-merchant reference entry, history entries for each step.
* **Where the admin review UI lives:** the endpoints are the `AdminMarketplaceController` (`api/admin/marketplace/leads…`). **The admin web panel code is not in this workspace** (`solvexo-account-web` is the owner portal; it has no verification screens, and the app has none by design). I need you to tell me which repo hosts the admin panel; I will list the exact screens/fields it needs in `web_dashboard_changes.md` (I do not build the web panel in G2 unless you say so).
* The owner's own KYB form (submit/resubmit, document upload, status timeline) belongs in the **owner portal** (web) per the existing rule "plan/verification purchase is web-only"; the POS app only shows the status ("Verification pending — digital payments unavailable") and a link.
* **Tests:** transitions, requirement validation server-side, IBAN checksum, encryption round-trip and key rotation, masked responses, audit event on every view, gating (403 vs 201), private-document URL expiry, no plaintext in DB (scan test).
**App:** read-only status in Settings → Payments. **Dependencies:** `KYB_ENC_KEY` provisioned by you (never committed). **Risks:** PII liability (encrypt + audit + retention policy to decide), provider's own KYB requirements may differ (the requirement set is a config file, one-entry change).

---
### G2.3 Raast dynamic QR checkout, end to end on the mock — **M**
**Backend:** uses G2.1/G2.2; adds QR payload generation through the adapter (mock returns a deterministic payload), amount/expiry rules (e.g. 3-minute expiry configurable), `presented` event when the app displays it.
**App (new screens per GAP_AUDIT content specs, on design tokens):** payment chooser entry "Raast QR" (hidden unless `digitalPaymentsEnabled` and online) → **QR screen**: large QR, amount in Manrope `tnum`, live countdown from the server's `expiresAt` (not the device clock), status line, Cancel → states **waiting / confirmed / expired / cancelled / failed** → confirmed completes the sale (success view) · expired offers *Generate new QR* or *Choose another method* · poll every 2 s plus push-style refresh on resume; survives app background; a mock "Simulate customer paid" button visible **only** in debug/mock builds.
**Offline behaviour:** the Raast option is disabled with "Needs internet" when offline; an in-flight intent at connection loss shows "Checking… " and resumes polling; a confirmed-but-unattached payment is reconciled by orphan recovery. No digital sale ever enters the offline queue.
**Tests:** mock outcomes drive widget + integration tests on the simulator (success, expiry, cancel, decline, network drop mid-wait, app kill + resume, double-tap confirm), real-backend suite with the mock provider.
**Risks:** a customer pays after expiry (provider must reject; mock simulates; orphan flow covers a provider that doesn't). Real Raast QR formats (merchant-presented vs. Raast P2M) belong to the adapter.

---
### G2.4 Blueprint checkout rebuild on the new nav — **L** (split into three deliverables, each reviewable)
* **G2.4a Navigation + selling screens:** blueprint bottom nav/rail; product search (recent searches), category view, product detail/variants sheet (stock, price, variant options; **modifiers stay out**, no backend), cart restyle, payment-method chooser. Reuses all Phase 3b widgets.
* **G2.4b Custom item, discount & coupon:** backend `items[].isCustom` (name, price, qty, taxable, note; no stock, manager-gated by plan setting), discount keypad (percent/fixed; existing manager-token rule stays), **coupon**: validate against the existing `discounts` module through a POS-scoped route, recorded per sale as `couponCode` + `couponDiscountMinor` (server recomputes; client value advisory). Per-line discounts stay out.
* **G2.4c Tender screens, receipt, offline screen:** cash / card (waiting-for-terminal removed; honest "Record card payment" with approval code, `recorded_unverified`) / split / QR; **payment success**; **digital receipt with QR** (receipt lookup URL, public read-only, signed/unguessable id), **print & share** (ESC/POS reuse; share sheet; email/SMS/WhatsApp out); **offline mode screen** (queued sales list + status) over the existing queue. **Wire `cardTotalFromSlip` at shift close** (variance dialog already computed server-side; app asks for the slip total) and **required reasons for discard/refund** (reason list per GAP_AUDIT, sent as `reasonCode`, server-validated, stored on the audit event).
**Offline:** everything except Raast/coupon validation works offline; coupons need the server (applied online only; an offline sale cannot use one).
**Tests:** widget tests per screen, golden checks on phone + tablet, simulator integration for the full flows, existing 634 stay green. **Risks:** nav change touches every screen → keep controllers untouched (rule from the redesign), ship behind a build flag until the owner approves.

---
### G2.5 Orders & returns — **M–L**
* Backend: `PosRefund` already a record; add `reasonCode`, per-line `disposition` (restock/damaged), `refundMethod` (original tender / cash; **store credit only if you approve it**), `refundNumber`, return window rule as a store setting, provider-refund integration (G2.1) for `raast_qr` tenders (a refund to the original QR payment goes through `refund_requested…`); tax invoice endpoint (business tax ID, per-line tax, buyer details; **FBR/NTN format unverified, I will not assume**).
* App screens: order detail (timeline created → paid → refunds, tenders, audit ref), tax invoice view/share, **partial return** (select lines + qty + reason), refund method, **refund complete** (with refund number). Orders list filters (date, status, tender, cashier, register).
* **Offline:** refunds stay online-only (as today); orders list shows cached recent history read-only.
* Tests: partial/multiple refunds sum rule, provider refund failure → refund stays `refund_requested` + manager alert, idempotency, minor-only math.

### G2.6 Home dashboard and POS catalog routes (D3) — **M–L**
* Home with real data: today's sales/tender split/open shift state/low stock count/held sales/pending-sync count from existing report endpoints (additive `...Minor` already in responses); tablet/phone layouts.
* **POS catalog routes** `POST/PATCH pos/catalog/products|variants|categories`: device/employee-token auth; **price, stock, barcode and category changes create an approval request** that a manager approves (PIN) before they apply (`catalog_change_requests`, append-only status events, applied in a transaction with audit and stock-movement row); visible on the storefront immediately after approval (same collections, `unlimitedStock` flag respected). Barcode uniqueness per store enforced. Variant `options[]` model used.
* App: products list/detail/form (create/edit with approval states), categories. **Offline:** read-only cached catalog; edits online only.
* Tests: approval gating (cashier cannot self-approve), conflicting edits, storefront visibility, stock ledger, barcode collisions.

### G2.7 Permissions screen (device setup part) — **S**
Pre-flight explainer for Camera/Notifications/Storage/Location shown during device setup with a "why" per item, skippable, re-openable from Settings. No backend.

## 3. Cross-cutting rules for every sub-phase
* New entities use `MinorMoney`, status **events**, awaited audit, `Idempotency-Key`, server-derived store/register/session/device/employee.
* Additive API; old app builds keep working (ENGINEERING_RULES §4); each sub-phase lists its server-before-app deploy order.
* Flutter: design tokens only, no controller rewrites, `flutter analyze` + `flutter test` + simulator integration; backend gate + `npm run build` + `test:di`.
* Deploy: needs the pipeline fixed first (separate diagnosis).

## 4. Dependencies and decisions I need from you
1. **Admin panel repo/location** for the KYB review UI (see G2.2).
2. `KYB_ENC_KEY` provisioning and a retention rule for KYB documents (how long after rejection/closure).
3. Provider choice (PayFast vs 1LINK 1GO) is **not** needed to start; I need their sandbox docs when you have them (webhook signature scheme, QR format, refund API) to finalise the adapter.
4. Is **refund to store credit** wanted in G2.5 (adds a store-credit tender)? Default: no.
5. Raast QR expiry default (proposal: 3 minutes) and whether a store may disable Raast itself.
6. Confirm the order G2.1 ∥ G2.2 first. Smallest safe first deliverable: G2.1 backend + mock (no app change, no data risk).

## 5. Risks (overall)
| Risk | Mitigation |
|---|---|
| Real provider semantics differ from the mock | Contract tests, sandbox run, adapter isolated |
| Webhook forgery/replay | Signature before parse, replay window, dedupe by `providerEventId`, amount taken from our intent |
| Payment confirmed but sale not created | Intent consumed in the sale transaction; orphan recovery + shift-close warning |
| PII (CNIC/IBAN) exposure | Field encryption, masking, audited reads, private documents, no secrets in repo |
| Regulatory (aggregator licence, Raast rules, tax invoice format) | Marked unverified; nothing assumed; owner/legal confirms before go-live |
| Nav rebuild regressions | Controllers untouched, build flag, full test suites each step |
| Deploy pipeline still broken | Fix first; staging verified via `/health/version` |
