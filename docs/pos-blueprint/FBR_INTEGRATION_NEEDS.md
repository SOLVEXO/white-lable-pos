# FBR / fiscal integration: what is built, and what it needs (G5.5)

**Status:** scaffolding only. The fiscal switch is OFF for every store. Only a **mock** provider exists; the real routes are typed TODOs that throw "not configured". **No PRAL, FBR or integrator field, endpoint or certification step has been guessed.** The legal background and the open questions are in [FBR_PLAN.md](FBR_PLAN.md); this note says what must arrive and where each piece plugs in.

## 1. What is built (solvexo-api)

| Piece | Where | What it does |
|---|---|---|
| Provider interface | `src/pos/connectors/fiscal.ts` | `FiscalProvider.fiscalise(FiscalDocumentInput) → { status: confirmed / rejected / pending, fiscalInvoiceNumber, qrPayload }`. The input is our own data: document type, our number, the original invoice for a credit note, minor units with currency and exponent, the seller NTN/STRN, and lines with HS code, net and tax. |
| Mock | `MockFiscalProvider` | Dev and tests only, and never in production. It confirms `MOCK-FBR-I-<INV no>` / `MOCK-FBR-C-<CN no>`. `MOCK_FISCAL_DOWN=true` simulates an outage. |
| Real routes | `NotConfiguredFiscalProvider('pral' / 'integrator' / …)` | Throws `FiscalNotConfiguredError` and points at this file. The attempt is recorded as `pending` with that reason. |
| Provider choice | `fiscalProviderFor()`, env `FISCAL_PROVIDER` | Outside production the default is `mock`. In production the default is none, and any key (even `mock`) means not configured. |
| Store switch | `PosSettings.connectorPrefs.fiscal` (default `false`) | Changed through `PATCH /api/pos/store/settings/:storeId` `{ connectors: { fiscal: true } }`: owner only, audited (`store_settings_changed`). |
| Records | `posfiscalrecords` (append-only) | One row per attempt (`attempt` 1, 2, …; unique per document and attempt). Each row is written in the same transaction as an audit row (`fiscal_confirmed`, `fiscal_pending` or `fiscal_rejected`). Our invoice and credit-note numbers are never changed. |
| When | `PosFiscalService` (`src/pos/pos-fiscal.service.ts`) | Runs after create sale, complete sale, refund (credit note) and void (credit note) when the switch is on. It never fails the sale. A **sweep** every 2 minutes (`POS_FISCAL_SWEEP_CRON`) retries pending documents and picks up the last 7 days' invoices and credit notes that have no record yet, i.e. offline sales that synced, or a crash. It stops after 20 attempts. |
| What responses show | documents, sale read, sale response, public receipt | The latest attempt is laid over the existing `invoice.fiscal` / `creditNote.fiscal` field, with the same shape as before: `status`, `externalInvoiceNumber`, `qrPayload`, `attempts`, `lastError`, plus `testMode`. With the switch on and no attempt yet it reads `pending`. |
| Status for the app | `GET /api/pos/connectors/:storeId` → `fiscal { provider, testMode, configured }` | Read-only. |

**App (pos):**
- The thermal receipt, tax invoice, credit note and PDFs print the **FBR invoice number + QR** once confirmed, and **"Fiscal pending"** until then.
- An offline sale's receipt always prints "Fiscal pending" when the store fiscalises.
- A reprint after confirmation shows the confirmed block.

This applies the brief's choice for FBR_PLAN §10 decision (c): print "Fiscal pending" and rely on the reprint and the digital receipt for the number.

## 2. What must arrive before a real adapter can be written

| # | Needed | From whom | Why |
|---|---|---|---|
| 1 | **Route decision:** PRAL (free licensed integrator) or a licensed integrator, or Solvexo's own licence | Owner (Sir Atiq), with the tax advisor | Decides which adapter is written (`pral` or `integrator`) and who registers the terminals. FBR_PLAN §1, §10 (a, e). |
| 2 | **Current retail-POS integration specification:** endpoint, auth, payload, response and error codes, for both sandbox and production | FBR/PRAL (helpline@fbr.gov.pk) or the chosen integrator | The adapter maps `FiscalDocumentInput` to their payload. The Digital Invoicing v1.2 spec in FBR_PLAN §3 may not be the retail one. |
| 3 | **Credit-note rule:** the field that references the original invoice, and whether a void is a credit note | Same | `fiscaliseCreditNote` already sends `againstInvoiceNumber`, but the field name is unknown. |
| 4 | **Code lists:** UoM, HS, SRO and sale type, as files | Same | Products already carry HS codes (G2.6); UoM and sale type are not captured yet. |
| 5 | **QR rule** (content or verification URL, size) and the **FBR logo** file | Same | The app prints whatever `qrPayload` string the server returns; the logo slot is reserved. |
| 6 | **Sandbox credentials:** POS IDs and token per test store and terminal, and whitelisting of the server's **static egress IP** | FBR portal (store owner) and the hosting provider | Railway needs a static egress IP or a proxy (FBR_PLAN §2). |
| 7 | **Per-store credentials storage decision** | Owner | Planned: encrypted with the existing versioned AES-256-GCM key facility (KYB_KEY_ROTATION.md). |
| 8 | **Provincial specs** (PRA, SRB, BRA), only if restaurants and services are in scope | Provincial authorities | KPRA's spec is in hand. |

## 3. When the documents arrive

1. Add an adapter class next to `NotConfiguredFiscalProvider` in `src/pos/connectors/fiscal.ts`, e.g. `PralFiscalProvider implements FiscalProvider`. Map `FiscalDocumentInput` to their payload, converting minor units to their decimals at the edge (PKR, exponent 2), and map their response to `FiscalResult`.
   - Return `confirmed` only with their number.
   - Return `pending` for network errors and 5xx, so the sweep retries.
   - Return `rejected` for a validation error, so it is not retried and stays visible.
2. Read credentials per store from encrypted settings, not from env. Add an owner-only route to set them, declare its tier in `pos-route-tiers.ts`, and audit it.
3. **Multi-instance safety before production:** the sweep runs on every API instance.
   - Today, a race on the same attempt number is absorbed by the unique index, but the provider could be called twice.
   - Before go-live, wrap the sweep in the existing Mongo `JobLeaseService`.
   - Make the adapter idempotent: send our document number as their idempotency or reference key if they support one.
4. Switch `fiscalProviderFor()` to return the new adapter for its key (`FISCAL_PROVIDER=pral`).
5. Run it in sandbox with one test store: turn the switch on, then sell online, sell offline and sync, refund, and void. Check the confirmed block on the reprints and the public receipt page.
6. Update the 24-hour offline rule alert (FBR_PLAN §5): pending documents older than about 20 hours should appear in *Needs attention* (not built yet).

## 4. Not built (deliberately)
- No PRAL or integrator payload, endpoint, token or certification step.
- No per-terminal FBR POS ID mapping (it needs the spec).
- No signboard or registration-number print (it needs the software registration number).
- No 24-hour alert.
