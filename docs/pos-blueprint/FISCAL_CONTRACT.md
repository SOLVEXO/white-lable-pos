# Fiscal contract v1: what the POS app reads, shows and prints (G6.1)

**For:** whoever builds FBR, or any tax authority, on the backend.

**The rule:** the app renders and prints **exactly** what the server sends. It never chooses:
- a tax-authority name or label;
- NTN, STRN or POS-ID wording;
- the QR format;
- which documents are fiscalised.

When FBR (or a change of route) arrives, nothing in the app changes. The backend fills this block.

The backend side as built on `feature/jamibranch`:
- `src/pos/pos-fiscal.service.ts` (`PosFiscalService.view` produces the block);
- `src/pos/connectors/fiscal.ts` (the provider interface);
- `src/pos/pos-fiscal.controller.ts`;
- tests in `src/pos/pos.g61.integration.spec.ts`.

The app side:
- `PosFiscalInfo` (`pos_credit_note_model.dart`);
- `FiscalPrint` (`lib/utils/fiscal_print.dart`);
- `FiscalStatusCard`;
- tests in `test/g61_fiscal_contract_test.dart` and `test/older_backend_test.dart`.

## 1. The block

Every document that can be fiscalised carries a `fiscal` object:

```jsonc
{
  "status": "confirmed",                 // see §2
  "externalInvoiceNumber": "7000007DI1747119701593", // the authority's number, or null
  "qrPayload": "7000007DI1747119701593",  // any string; the app renders it as a QR code as given, or null
  "displayLines": [                        // printed and shown in this order, exactly as given (max 12 lines; label ≤ 80, value ≤ 200)
    { "label": "FBR Invoice No", "value": "7000007DI1747119701593" },
    { "label": "Dated", "value": "2026-11-13 10:42" }
  ],
  "message": null,                         // failed / rejected: why, in words for the cashier and the owner
  "willRetry": false,                      // true = the server will send it again on its own
  "logoUrl": null,                         // optional authority logo printed next to the QR (any image URL; cached for thermal)
  "testMode": false,                       // true = test / sandbox provider: the app shows a "Test mode" badge
  "contractVersion": 1,
  "attempts": 1, "lastError": null         // kept from G5.5, informational
}
```

Every field is optional for the app, which defaults safely. An older server (G5.5) that sends only `status`, `externalInvoiceNumber` and `qrPayload` still works: the number is printed alone, without a label.

## 2. Statuses and transitions

| `status` | Meaning | When the server sets it | App: print | App: screen |
|---|---|---|---|---|
| `not_enabled` / `not_required` | The store does not fiscalise this document | The store's `connectors.fiscal` switch is off and nothing was sent. **`not_enabled` is the live value and is kept for compatibility**; `not_required` means the same | Nothing | Nothing |
| `pending` | Not fiscalised yet; **safe to send again** | The switch is on and no attempt yet; or the provider was down or not reached; or the provider is not configured | `displayLines` if any, else **"Fiscal pending"** | "Fiscal: pending", plus "will be sent automatically" when `willRetry` |
| `confirmed` | Accepted by the authority | The provider returned its number | `displayLines` (label line + bold value), the logo, the QR. With no lines: the number alone | "Fiscal: confirmed" + the lines (+ "Test mode") |
| `failed` | Not fiscalised and **not** retried automatically | The provider says resending is unsafe (outcome unknown, auth error, production locked, …), or `pending` reached 20 attempts (the server then reports `failed`) | `displayLines` if any, else "Fiscal pending" | Warning + `message` + "The owner can send it again from Integrations → Fiscal" |
| `rejected` | Refused by the authority (validation) | The provider says so | `displayLines` if any, else nothing | Error + `message` |
| anything else | A status from a newer server | — | Nothing | Nothing (treated as not required) |

**Transitions:**
- `pending → confirmed | failed | rejected`
- `failed → confirmed | failed | rejected`, only through the owner's manual retry
- `confirmed` and `rejected` are final.

Our own invoice and credit-note numbers never change. Every attempt is an append-only `posfiscalrecords` row, written with an audit row in the same transaction.

**Never blocking:** the sale, refund or void is complete before fiscalisation runs. A failure only changes this block.

## 3. Which endpoints carry it

| Endpoint | Where |
|---|---|
| `POST /api/pos/sales` (sale response) | `data.invoice.fiscal`, fiscalised inline when the store's switch is on; otherwise the stored placeholder |
| `POST /api/pos/sales/:id/complete` (held → completed) | `data.invoice.fiscal` |
| `POST /api/pos/sales/:id/refund`, `…/void` | `data.creditNote.fiscal` (G6.1; only when the switch is on) |
| `GET /api/pos/sales/:id` (sale detail, reprint) | `data.invoice.fiscal` (latest attempt) |
| `GET /api/pos/sales/:id/documents` (tax invoice, credit notes, documents screen) | `data.invoice.fiscal`, `data.creditNotes[].fiscal` |
| Public receipt page `/r/:token`, `/r/s/:store/:key` (HTML) | `displayLines`, printed only once `confirmed` |
| `GET /api/pos/fiscal/:storeId/issues` (manager) | `{ items: [{ documentType, documentId, saleId, documentNumber, status, message, attempts, lastAttemptAt, retryable }] }`: documents that are `failed`, `rejected` or out of retries, last 30 days |
| `POST /api/pos/fiscal/:storeId/retry` (owner) | Body `{ documentType: "invoice"\|"credit_note", documentId }`. One new attempt, audited with who asked. Returns the block. `FISCAL_NOT_RETRYABLE` for anything but `failed` |
| `GET /api/pos/connectors/:storeId` | `flags.fiscal` (the store's switch), `fiscal` (provider, `testMode`, `configured`), `ui.fiscal.title` (the switch's name, e.g. "Fiscal invoices (FBR)") |

Seller tax identifiers on the tax-invoice header follow the same rule. The server may send `invoice.seller.taxIds` (and `creditNote.seller.taxIds`) as `[{label, value}]`, which the app prints as given. Without them, the app falls back to the G2.6 `ntn` and `strn` fields, labelled "NTN" and "STRN", so today's production server keeps printing what it prints.

## 4. Offline and retries

- **Offline sale (no server):** the till prints **"Fiscal pending"** on the receipt when the store's switch was on at the last connectors read. It never invents a number.
- **When it syncs:** the sale is created, then fiscalised inline (or by the sweep). A **reprint** shows the confirmed block from `GET /sales/:id`.
- **Retries:** the sweep (`POS_FISCAL_SWEEP_CRON`, default every 2 min) re-sends `pending` documents from the last 7 days, up to 50 per run and 20 attempts each.
  - It never re-sends `failed` or `rejected`.
  - One provider call per document runs at a time across all API instances, through MongoDB lease `pos:fiscal:<type>:<id>`, which also covers the sale-time path. Lease `pos:fiscal-sweep` covers the sweep.
- **The 24-hour rule:** FBR expects offline invoices to be reported within 24 hours (FBR_PLAN §5). An alert for pending documents older than about 20 hours is **not built**. Add it to `issues` if required.

## 5. What a real adapter must return

Implement `FiscalProvider.fiscalise(doc) → FiscalResult`:
```ts
{ status: 'confirmed' | 'pending' | 'failed' | 'rejected', fiscalInvoiceNumber, qrPayload, message?, displayLines?, logoUrl? }
```

Map main's FBR Digital Invoicing client (`src/fbr-di`, `FbrResult`) like this:

| `FbrResult` | Contract |
|---|---|
| `ok` + `invoiceNumber` | `confirmed`. `fiscalInvoiceNumber = invoiceNumber`, `qrPayload = qrText(invoiceNumber)` (the number itself, per main's `fbr-di.util`), `displayLines` as the route requires, e.g. `[{label:'FBR Invoice No', value}, {label:'Dated', value: dated}]` |
| `retryable` / `notSent` | `pending` (nothing reached FBR; safe to resend) |
| `unknownOutcome` | `failed` with a message: FBR has no duplicate check, so **never resend automatically**. The owner checks, then retries |
| `authError` | `failed` ("the store's FBR token is wrong or expired") |
| `locked` | `failed` (production filing locked) |
| `errors[]` with validation codes | `rejected`, with `message` built from `errors[].message` (and `itemSNo`) |
| FBR logo | `logoUrl` (an image the server serves) |

A PRAL-direct or licensed-integrator route fits the same shape:
- the authority's number;
- a QR string (number or verification URL);
- any labelled lines (POS ID, NTN, date, USIN …);
- a logo.

Nothing in the app depends on which route is chosen.

## 6. Checklist: the app shows and prints it correctly when…

- [ ] Every response in §3 carries `fiscal` for each fiscalisable document, and the stored placeholder `not_enabled` stays for stores that don't fiscalise.
- [ ] `confirmed` always has `externalInvoiceNumber` **and** the `displayLines` the authority requires on paper, in print order, with your labels.
- [ ] `qrPayload` is exactly the string to encode (QR size is the printer's; 1×1 inch at 80 mm).
- [ ] `logoUrl` (if the authority requires a logo) is a small monochrome-friendly image (PNG/JPEG, ≤ 1024 px), reachable by the till.
- [ ] `failed` and `rejected` carry a `message` a cashier can read. Avoid internal codes or stack traces.
- [ ] `willRetry` is true only for `pending`.
- [ ] `testMode` is true for sandbox and mock providers.
- [ ] `connectors.ui.fiscal.title` names the authority on the owner's switch.
- [ ] `issues` lists every `failed` / `rejected` document, and `retry` is only allowed for `failed`.
- [ ] The sweep is leased (built) and the provider is idempotent per document where the authority allows it.
- [ ] Tested with the mock: `MOCK_FISCAL_MODE=down|fail|reject` (and none = confirmed).
