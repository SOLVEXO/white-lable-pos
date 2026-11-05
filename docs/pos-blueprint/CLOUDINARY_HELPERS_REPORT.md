# Cloudinary helpers — every caller, risk ranking, proposed fixes (REPORT ONLY — no caller or helper was changed)

Two defects in `UploadService`, verified against the real account:
* **`generateSignedUrl`** builds a `type:'private'` delivery URL. Its `expires_at` option is ignored, so **every link works forever** (200 long after "expiry"). Separately, passing a `fileName` that contains a dot (`receipt.pdf`) makes Cloudinary answer **400 "Invalid flag in transformation: pdf"** (the helper writes `flags: attachment:<name>`) — so every caller that passes a file name returns a link that does not work today.
* **`deleteFile`** calls `destroy` without `type:'private'`: for a private asset the answer is `not found` and **nothing is deleted**.

## 1. Every caller of `generateSignedUrl`
| # | Where | Feature / data | Private? | Who receives the link | Risk |
|---|---|---|---|---|---|
| 1 | `store.service.ts:315` `signedDocumentUrl` (600 s intended) | Marketplace seller verification: **CNIC / passport, address proof, business registration, tax certificate** (`getVerification`, and the admin lead detail) | yes (`private/kyc-documents`) | the owning seller; platform admins | **HIGH** — identity documents behind a permanent link; **and it passes `d.fileName`, so the link returns 400 for any file with an extension (likely broken today)** |
| 2 | `renewal-invoices.service.ts:190` `signedProof` (`PROOF_URL_SECONDS`) | Membership renewal **payment proofs** (bank-transfer receipts: names, account numbers, amounts) | yes (`private/renewal-proofs/<store>`) | the buyer (own receipt) and the store's seller/admin | **MEDIUM-HIGH** — financial documents; same file-name 400 bug |
| 3 | `courses.service.ts:159-160` `mediaUrl` (`MEDIA_URL_SECONDS`) | **Paid course** video lessons and downloadable files | yes | the enrolled customer | **MEDIUM (revenue)** — a forwarded link is a permanent free copy of paid content; file lessons pass a file name (400 bug) |
| 4 | `orders.service.ts:2288` and `:3520` | Digital-product **download** after purchase (bought file) | yes (`private/digital-products`) | **nobody** — fetched server-side (`fetch(url)`) and streamed to the buyer; the link never leaves the server | LOW |
| 5 | `digital-delivery.service.ts:185` | Same digital-product download (new delivery service) | yes | nobody — server-side fetch | LOW |
| 6 | `upload.service.ts:174` `downloadPrivateFileBuffer` (and `downloadPrivatePdfBuffer`) | internal helper; only KYB (G2.2) calls it | yes | nobody — server-side | LOW |

## 2. Every caller of `deleteFile`
| Where | What it deletes | Correct today? |
|---|---|---|
| `media-library.service.ts:178` `deleteAsset` | store media-library images/files uploaded through the normal (public) upload | yes while those assets are public; **would silently do nothing for a private asset** |
| `store-app-requests.service.ts:355` | a just-uploaded public app-icon image that fails the size check | yes |
| `store-banner.service.ts:296` (direct `cloudinary.uploader.destroy`) | store banner / video | yes (public) |

**Nobody deletes private files at all.** Consequences (orphans that stay in the account forever): a replaced/removed verification document; a replaced renewal proof (each re-submission uploads a new file); a deleted course lesson's media; a digital-product file that is replaced or whose product is deleted; preview sources (`private/digital-preview-sources`); abandoned uploads (`POST upload/private-file` that never became a product).

## 3. Ranking and proposed fixes
1. **Verification documents (store.service)** — switch to `generateExpiringPrivateUrl(publicId, resourceType, 300, { inline: true })`; the file-name flag bug disappears with it; audit-log views the same way KYB does (who viewed which document).
2. **Renewal proofs** — same switch (inline view, ≤ 300 s).
3. **Course media** — files: same switch (attachment with name). **Videos need care:** the signed download API serves the file as a download, and players may need HTTP range requests; confirm playback on a real device first. If it does not stream, move lesson videos to Cloudinary `authenticated` delivery with token auth (needs the account's token key) — a separate migration.
4. **Server-side fetchers (orders ×2, digital-delivery, downloadPrivateFileBuffer)** — switch for consistency (no link is exposed, so no urgency).
5. **Preferred shape of the fix:** change the **helper itself** so the bug cannot return: make `generateSignedUrl` build the expiring download-API URL (enforced expiry, ceiling 300 s, no filename flag bug) and keep the old behaviour only under an explicit `allowPermanent` name that nobody uses; make `deleteFile` take the delivery `type` (`'upload' | 'private'`, default `'upload'`) and have private callers pass `'private'`. Then the KYB-only helpers (`generateExpiringPrivateUrl`, `deletePrivateFile`) become thin aliases. Tests: the existing real-storage script/spec already prove 200 → 401 and delete.
6. **Orphans — cleanup plan:** (a) a read-only inventory script lists every private asset in the account under `private/` (Admin API `resources_by_type('private')`, paged) and every `publicId` referenced from MongoDB (`products.digital.files[].url` and previews, course lessons, renewal proofs, `store.verification.documents`, `store_kybs.documents`); the difference is the orphan list (counts, bytes, age) — nothing deleted; (b) review the list; (c) only assets older than 30 days and unreferenced are eligible; delete in batches with the fixed private delete, dry-run first, audit-logged; (d) make every feature that replaces/removes a private file delete the old one in the same code path (verification replace, renewal-proof resubmit, lesson removal, product-file replace/delete) so no new orphans appear.
7. **Order of work I suggest:** 1 → 2 (small, high value) → helper fix + 4 → 3 (after a playback check) → inventory script → cleanup.
