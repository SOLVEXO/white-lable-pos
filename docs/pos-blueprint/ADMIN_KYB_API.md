# Admin KYB API — for the admin UI

Everything the admin UI needs to review store **business verifications (KYB)** for digital payments. It is written so the UI can be built without reading the backend code. The backend is `solvexo-api` (branch `feature/jamibranch`); **no admin UI exists yet** — another agent builds it.

Base path: `/api/admin/kyb`. All routes are JSON except the document download.

## 0. Concepts in one minute
* Solvexo is a payment **aggregator**. A store may take **digital payments (Raast QR)** only when **both** are true: its KYB status is `verified` **and** an admin has entered the provider's **sub-merchant reference** for it. Settlement goes straight to the store's own bank account; Solvexo never holds customer funds.
* The store owner fills the KYB in the owner portal (owner API at the end of this file). Admins review it here.
* This is **separate from the marketplace "Leads" verification** (`/api/admin/marketplace/leads`). Approving a KYB does not publish a store and does not touch the lead status.
* Sensitive values (CNIC, NTN, IBAN, account title) are **encrypted at rest**. Lists never show them; the detail endpoint returns them decrypted **and writes an audit row first**. Documents are private files: every view/download is audited.

## 1. Status flow
```
                    owner submits                     admin approves
   ┌────────┐  ─────────────────▶  ┌───────────┐  ───────────────────▶  ┌──────────┐
   │ draft  │                      │ submitted │                        │ verified │
   └────────┘  ◀─────────────────  └───────────┘                        └──────────┘
        ▲        (never: locked)         │ admin rejects (reason)             │ admin rejects / revokes (reason)
        │                                ▼                                    ▼
        │       owner edits         ┌──────────┐ ◀───────────────────────────┘
        └────────────────────────── │ rejected │
                                    └──────────┘
```
| Status | Meaning | Who can change it |
|---|---|---|
| `draft` | Owner is filling it in (also the state of a rejected application once the owner edits it again) | owner |
| `submitted` | Waiting for review. **Locked**: the owner cannot edit | admin: approve / reject |
| `verified` | Business verified. Digital payments need the sub-merchant reference as well | admin: set sub-merchant, or reject (= revoke, effective **immediately**) |
| `rejected` | Reason shown to the owner. Owner edits → back to `draft` → submits again | owner |

`digitalPaymentsEnabled` (returned on list/detail) = `status === 'verified'` **and** a sub-merchant reference is set for the active provider.

## 2. Auth, roles, permissions
Every endpoint: `Authorization: Bearer <admin JWT>`, role `admin`. The owner / Super Admin passes everything. A **team admin** needs a permission in their role:

| Permission | Endpoints |
|---|---|
| `kyb.review` | everything under `submissions…` |
| `kyb.settings` | `retention…` |

**The permission list lives in the web admin too** (`solvexo-web` `api/services/adminTeam.ts` — keep in sync with `src/admin-team/admin-permissions.ts`): add `kyb.review` and `kyb.settings` there so they can be granted to roles. Add them to a role's permission picker with these labels: "KYB: review submissions, view documents, approve / reject, set sub-merchant" and "KYB: document retention settings".

Not an admin (seller, buyer, staff, no token) → **403**. A team admin without the permission → **403** `{"statusCode":403,"message":"Your admin role doesn't have permission to do this (requires: kyb.review)","error":"Forbidden"}`. A read-only team admin cannot call any non-GET route (403).

## 3. Response and error shapes
Success: `{ "success": true, "data": … }` (the download endpoint returns the file).

Errors come in two shapes — handle both:
```jsonc
// business errors: HTTP status + a stable machine "code" (show `message`, switch on `code`)
{ "code": "KYB_NOT_SUBMITTED", "message": "Only a submitted application can be approved (it is draft)" }
// validation / guard errors (Nest default)
{ "statusCode": 400, "message": ["page must not be less than 1"], "error": "Bad Request" }
```
Error codes used by this API:

| HTTP | `code` | When |
|---|---|---|
| 400 | `INVALID_FILTER` | unknown `status` / `businessType` in the list filter |
| 400 | `REASON_REQUIRED` | reject with a reason shorter than 10 characters |
| 400 | `INVALID_PROVIDER` | `providerKey` not 2–40 chars of `a-z 0-9 _ -` |
| 400 | `INVALID_SUB_MERCHANT_REF` | `ref` not 3–100 chars of letters, digits, `. _ : -` |
| 400 | `INVALID_RETENTION` | `afterClosureDays` not a whole number 30–3650 (or `null`) |
| 400 | `RETENTION_PERIOD_REQUIRED` | enabling deletion with no period set |
| 404 | `KYB_NOT_FOUND` | the store has no KYB record |
| 404 | `KYB_DOCUMENT_NOT_FOUND` | unknown document id |
| 409 | `KYB_NOT_SUBMITTED` | approve a KYB that is not `submitted` |
| 409 | `KYB_NOT_REVIEWABLE` | reject a KYB that is not `submitted`/`verified` |
| 409 | `KYB_NOT_VERIFIED` | set a sub-merchant on a store that is not `verified` |
| 409 | `SUB_MERCHANT_IN_USE` | that reference already belongs to another store |
| 409 | `KYB_PURGED` | documents/sensitive data were deleted by the retention job |
| 503 | `KYB_ENCRYPTION_UNAVAILABLE` | the server has no usable encryption key (fail closed): show "temporarily unavailable", retry later; nothing was read or stored |

A 409 `KYB_NOT_SUBMITTED` / `KYB_NOT_REVIEWABLE` also happens if someone else reviewed it a second earlier: reload the submission.

## 4. Endpoints

### 4.1 `GET /api/admin/kyb/submissions` — list / filter
Role: admin + `kyb.review`. Masked data only; **works even without the encryption key**; no audit row per list.

Query: `status` (`draft|submitted|verified|rejected|all`; **default `submitted`** = the review queue) · `businessType` (`sole_proprietor|partnership|company`) · `q` (substring of the legal business name, or an exact store id, or an exact sub-merchant reference) · `from`, `to` (ISO dates, filter on `submittedAt`) · `sort` (`-submittedAt` default, `submittedAt`, `updatedAt`, `-updatedAt`) · `page` (≥1, default 1) · `limit` (1–100, default 25).
```json
{ "success": true, "data": {
  "items": [ {
    "storeId": "6aec1f0d6e343b5a7beb5539", "storeName": "Dev Coffee", "storeSlug": "dev-coffee",
    "status": "submitted", "businessType": "company", "legalBusinessName": "Bright Traders (Pvt) Ltd",
    "submittedAt": "2026-11-05T06:51:36.692Z", "reviewedAt": null, "documentCount": 4,
    "subMerchantRef": null, "digitalPaymentsEnabled": false, "updatedAt": "2026-11-05T06:51:36.692Z" } ],
  "page": 1, "limit": 25, "total": 1, "pages": 1 } }
```

### 4.2 `GET /api/admin/kyb/submissions/:storeId` — one submission, decrypted
Role: admin + `kyb.review`. **Writes `kyb_viewed` to the audit trail before decrypting** (if that write fails the request fails and nothing is returned). 503 `KYB_ENCRYPTION_UNAVAILABLE` if no key.
```json
{ "success": true, "data": {
  "storeId": "6aec…5539",
  "store": { "name": "Dev Coffee", "slug": "dev-coffee", "baseCurrency": "PKR", "country": "PK" },
  "status": "submitted", "businessType": "company",
  "legalBusinessName": "Bright Traders (Pvt) Ltd", "businessAddress": "Shop 4, Main Boulevard, Lahore",
  "contact": { "name": "Ayesha Khan", "designation": null, "email": "ayesha@bright.pk", "phone": "+923001234567" },
  "bankName": "Standard Chartered",
  "cnic": "3520212345671", "ntn": "7654321", "iban": "PK36SCBL0000001123456702", "accountTitle": "Bright Traders Collection A/C",
  "documents": [ { "id": "6aec…2133", "type": "owner_cnic", "fileName": "owner_cnic.pdf", "mimeType": "application/pdf", "fileSize": 120331, "uploadedAt": "2026-11-05T06:51:36.617Z" } ],
  "requirements": { "businessType": "company",
    "requiredFields": ["businessType","legalBusinessName","businessAddress","contact.name","contact.email","contact.phone","cnic","bankName","accountTitle","iban","ntn"],
    "requiredDocuments": ["owner_cnic","bank_proof","business_registration","tax_registration"], "optionalDocuments": ["address_proof"], "missingDocuments": [] },
  "submittedAt": "2026-11-05T06:51:36.692Z", "reviewedAt": null, "reviewedBy": null, "rejectionReason": null,
  "subMerchant": { "ref": null, "providerKey": null, "setAt": null, "setBy": null },
  "digitalPaymentsEnabled": false,
  "history": [ { "action": "submitted", "note": null, "actorId": "6aec…", "actorRole": "owner", "at": "2026-11-05T06:51:36.692Z" } ] } }
```
Document types: `owner_cnic` (owner's CNIC), `bank_proof` (cheque / bank statement showing the IBAN), `business_registration`, `tax_registration` (NTN certificate), `address_proof`. **Storage ids never appear in any response.** Show the CNIC/NTN/IBAN to the reviewer to compare with the documents; do not log or store them in the browser.

`history[].action`: `draft_saved`, `document_uploaded`, `document_removed`, `submitted`, `approved`, `rejected`, `reopened`, `sub_merchant_set`, `purged`.

### 4.3 `GET /api/admin/kyb/submissions/:storeId/documents/:docId/url` — view a document
Role: admin + `kyb.review`. **Audit row `kyb_document_viewed` is written first; no audit row → no URL.** Returns a signed link valid for 5 minutes. Open it in a new tab / embedded viewer; do not cache it.
```json
{ "success": true, "data": { "url": "https://res.cloudinary.com/…signed…", "expiresInSeconds": 300, "fileName": "owner_cnic.pdf", "mimeType": "application/pdf" } }
```

### 4.4 `GET /api/admin/kyb/submissions/:storeId/documents/:docId/download` — download
Role: admin + `kyb.review`. **Audit `kyb_document_downloaded` first.** Response is the file (`Content-Disposition: attachment`, `Cache-Control: no-store`), not JSON. Errors are the JSON shapes above.

### 4.5 `POST /api/admin/kyb/submissions/:storeId/approve`
Role: admin + `kyb.review`. Body (optional): `{ "note": "documents match" }` (≤300 chars). Only from `submitted`.
```json
{ "success": true, "data": { "storeId": "6aec…5539", "status": "verified", "digitalPaymentsEnabled": false, "needsSubMerchant": true } }
```
After approving, the UI should prompt for the sub-merchant reference (4.7): payments stay off until it is set.

### 4.6 `POST /api/admin/kyb/submissions/:storeId/reject`
Role: admin + `kyb.review`. Body: `{ "reason": "The CNIC photo is unreadable" }` — required, **10–500 characters**; the **owner sees this text**. From `submitted` (reject) or `verified` (**revoke**: digital payments stop immediately, in-flight QR payments already confirmed are unaffected).
```json
{ "success": true, "data": { "storeId": "6aec…5539", "status": "rejected", "digitalPaymentsEnabled": false } }
```

### 4.7 `PUT /api/admin/kyb/submissions/:storeId/sub-merchant`
Role: admin + `kyb.review`. Only when `verified`. Body: `{ "providerKey": "mock", "ref": "SM-100" }` — `providerKey` is the payment provider the reference belongs to (`mock` today; later e.g. `payfast`, `1link`), `ref` the sub-merchant id the provider gave for this store. Setting a new value replaces the old one (both are in the audit row). The reference only works for the **currently active provider** (`PAYMENTS_PROVIDER_POS`).
```json
{ "success": true, "data": { "storeId": "6aec…5539", "subMerchant": { "ref": "SM-100", "providerKey": "mock" }, "digitalPaymentsEnabled": true } }
```

### 4.8 `GET /api/admin/kyb/submissions/:storeId/audit` — audit trail of one store
Role: admin + `kyb.review`. Query: `page`, `limit` (≤100, default 25), `action` (exact). Newest first. Append-only; nothing in it can be edited.
```json
{ "success": true, "data": { "items": [ {
  "_id": "6aec…", "storeId": "6aec…5539", "actorType": "admin", "actorId": "adm-1", "action": "kyb_document_viewed",
  "targetType": "document", "targetId": "6aec…2133", "meta": { "type": "owner_cnic", "fileName": "owner_cnic.pdf" },
  "ip": "10.0.0.1", "userAgent": "Mozilla/5.0 …", "at": "2026-11-05T07:02:11.000Z" } ],
  "page": 1, "limit": 25, "total": 9, "pages": 1 } }
```
`action` values: `kyb_draft_saved`, `kyb_reopened`, `kyb_document_uploaded`, `kyb_document_removed`, `kyb_submitted`, **`kyb_viewed`** (an admin read the decrypted fields), **`kyb_document_viewed`**, **`kyb_document_downloaded`**, `kyb_approved`, `kyb_rejected`, `kyb_sub_merchant_set`, `kyb_purged`. `actorType` is `owner`, `admin` or `system`. `meta` never contains CNIC/NTN/IBAN/account-title values.

### 4.9 Retention (`kyb.settings`)
Documents are kept while the store is active. After the store is **closed** they are kept for a period you configure, then deleted — **but there is no default period and deletion is off** until the owner provides the legal period.

`GET /api/admin/kyb/retention`
```json
{ "success": true, "data": { "afterClosureDays": null, "purgeEnabled": false, "updatedAt": null, "updatedBy": null, "policy": "Documents are kept while the store is active. …" } }
```
`PUT /api/admin/kyb/retention` — body `{ "afterClosureDays": 730, "purgeEnabled": true }` (either field optional). `afterClosureDays`: whole number 30–3650 or `null`. `purgeEnabled: true` is refused (400 `RETENTION_PERIOD_REQUIRED`) while the period is `null`. Every change is audited (platform-level, store id `platform`).

`POST /api/admin/kyb/retention/run` — body `{ "dryRun": true }` (**default and recommended: dry run**, changes nothing). With `dryRun:false` it deletes the documents and the encrypted fields of applications whose store was closed longer than the period ago (the submission row, history and audit stay; the submission is marked purged).
```json
{ "success": true, "data": { "skipped": false, "dryRun": true, "cutoff": "2024-11-05T00:00:00.000Z", "eligible": 1, "purged": 0, "failed": 0, "stores": [ { "storeId": "6aec…", "documents": 4 } ] } }
```
`{"skipped": true, "reason": "no_retention_period_set" | "purge_disabled"}` when it refuses. A scheduled run exists but is **off** (needs `KYB_RETENTION_JOB_ENABLED=true` on the server and `purgeEnabled`).

## 5. What is encrypted / masked
| Field | At rest | Admin list | Admin detail | Owner view |
|---|---|---|---|---|
| CNIC, NTN, IBAN, account title | AES-256-GCM ciphertext (`kyb:v<key version>:…`) | not returned | **decrypted, audited** | masked (`•••••••••5671`, `PK••••••••••••••••••6702`); account title: "set" flag only |
| Legal business name, address, contact, bank name | plain text | name only | yes | yes |
| Documents (files) | private storage, never a public URL | count only | file name/type/size; view/download audited | file name/type/size |

## 6. Audit behaviour (what the compliance reviewer can rely on)
* Every submission change, every decrypted read, every document view/download, every sub-merchant change, every retention setting change and every purge is one append-only row (who, what, when, IP, user agent).
* **Reads are audited before they happen, and fail closed**: if the audit row cannot be written the request fails and nothing is shown.
* The trail never contains the sensitive values themselves.

## 7. UI suggestions
* Queue page = list (default `submitted`), badge counts per status via `status=all` + client grouping or one list call per status.
* Detail page: show the decrypted fields in a "Sensitive — viewing is logged" panel; documents as a list with "View" (4.3) and "Download" (4.4) buttons; checklist from `requirements`; actions Approve / Reject (reason textarea ≥10 chars) / Set sub-merchant; the history and the audit trail as a timeline.
* Never cache the detail response or the signed URLs; clear them when the reviewer leaves the page.

## 8. Owner-facing API (for the owner portal; not for the admin UI)
Seller JWT, role `seller`, base `/api/kyb/:storeId`. Owner responses are always masked.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/kyb/:storeId` | status, masked values, documents, requirement checklist, `digitalPaymentsEnabled`, `rejectionReason` |
| PUT | `/api/kyb/:storeId/draft` | partial save: `businessType`, `legalBusinessName`, `businessAddress`, `contact{name,designation,email,phone}`, `bankName`, `cnic`, `ntn`, `iban`, `accountTitle`. Sending `""`/`null` clears a field. 400 `KYB_INVALID_FIELD` with `field`; 409 `KYB_LOCKED` once submitted; editing a `rejected` application reopens it as `draft`; 503 `KYB_ENCRYPTION_UNAVAILABLE` |
| POST | `/api/kyb/:storeId/documents` | multipart: `type`, `file` (PDF/JPEG/PNG ≤ 10 MB); one document per type (a new upload replaces the old) |
| DELETE | `/api/kyb/:storeId/documents/:docId` | draft/rejected only |
| POST | `/api/kyb/:storeId/submit` | 400 `KYB_INCOMPLETE` with `missingFields[]` and `missingDocuments[]`; 409 `KYB_LOCKED` if already submitted |

The POS app reads one extra field, additive: `GET /api/pos/subscription/:storeId` → `data.digitalPaymentsEnabled` (boolean) so the till can hide the QR option for an unverified store.
