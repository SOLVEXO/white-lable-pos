# G4 — Intelligence & control: plan (PLAN ONLY — no code written)

Written after G3.6. Sources: `GAP_AUDIT.md` §G4, `G3_PLAN.md`, `FBR_PLAN.md`, `G3_CLOSEOUT.md`, and what G3 actually built (the numbers below are about *data that now exists*, not about screens).

## 0. What G3 gives G4 for free (so it is cheap)
| Need | Already there |
|---|---|
| Profit | every sale line stores the **weighted-average cost snapshot** (`unitCostMinor`, G3.1) and lot costs; supplier bills / credits are in the payables ledger; returns come back at the sale's snapshot cost |
| Tax | invoice / credit-note documents carry per-line net / tax / total in minor units (G2.5); credit notes for returns and voids; backfill series `CN-B` for old ones |
| Payment mix | per-line tenders (cash / card / other / Raast / store credit), refunds per tender, cross-till attribution (G3.0) |
| Cashier / register / hour | every sale / refund / void / movement carries employee, register, shift, device, device time |
| Cash | the daybook (G3.5) reconciles to shift close; expenses, supplier payments, cash in/out are categorised minor-only rows |
| Stock | the stock ledger (`StockMovement`) — opening + Σ = stock; lots, expiry, adjustments with reasons |
| Roles | the permission matrix is **data** (`pos-permissions.config.ts`: action → roles → approval rule, limits per store in `PosSettings.approvalLimits`); every use is audited |
| Audit | `PosAuditLog` (append-only in code) + per-domain append-only ledgers |
| Attendance | G3.6 hours, lateness, anomalies — feeds a "labour" line in the business pulse |

What G4 must still **build**: aggregation endpoints (reports read the same tables; nothing new is *recorded*), a chart toolkit (no chart package approved yet — see decision 4), the per-store editable matrix, the settings hub, and tamper-evidence for the audit log.

## 1. Sub-phases (shippable, in order)
| Sub-phase | What ships | Depends on | Size | Risk |
|---|---|---|---|---|
| **G4.0 Report engine + business pulse** | one server-side aggregation layer (`api/pos/reports/*`): period + register/cashier/location filters, minor-only, currency stated; **Business pulse** (today vs same weekday last week: sales, transactions, avg basket, margin, cash vs card, refunds, expenses, top 5, low stock, attendance) | G3 data | M | slow queries on big stores → pre-aggregated daily rollups (an append-only `daily_facts` table written at shift close and rebuilt on demand); decide before building |
| **G4.1 The eight reports** | Sales, **Profit** (uses WAC snapshots; "cost unknown" lines listed, never guessed), Product, Category, Tax (by rate / HS code; ties to invoices and credit notes — a test asserts report = Σ documents), Payment mix, Cashier, Hourly; date strip, compare-to-previous, CSV + shareable PDF; every number drills into its documents | G4.0 | L | profit when cost is missing for old sales (show coverage %); timezone of "a day" (store time zone setting — see decision 6) |
| **G4.2 Roles & granular permissions (owner only)** | make the G3 matrix **editable per store**: an override document per store (role → action allowed / not, approval rule, limits), safe defaults = today's table, presets (Owner-operated / Small team / Strict), a **diff preview** before saving, every change audited with before/after, a "reset to defaults" button; manager-PIN approvals stay separate; the till reads the effective matrix (cached with a version, like the settings version) | G3.0 matrix | M–L | an owner locking themselves or the till out → invariants: owner can always do everything and always edit permissions; cashier can always sell and open/close their own shift; some actions are "pinned" (not editable) |
| **G4.3 Settings hub** | the full hub as screens over existing + new endpoints: store profile, registers & devices (exists), payments setup (Raast / KYB status, exists), tax rules (exists partly), receipt designer (logo, footer, what to print, 58/80 mm preview), notifications (which alerts, who gets them), hardware (printer, drawer, scanner test pages), integrations (accounting export, API keys — optional), security (PIN rules, auto-lock, session length), backup & sync status (queue depth, last sync, Needs attention), help, about | G4.2 (security / roles screens), G3 | L | breadth, not depth — each screen is small; hardware pages need real devices |
| **G4.4 Audit log screens + tamper evidence** | audit viewer (filters: who / what / when / document, drill to the document), export; **hash chain** over the audit rows (each row stores the hash of the previous: tamper-evident, verified by a job + a "verify" button) | none | M | chain gaps under concurrent writes → one chain per store written inside the same transaction as the event, or a nightly sealing job (decision 5) |
| **G4.5 Catalog completion (carried from G2/G3)** | create product, images, variants editor, categories CRUD, price books, modifiers, bulk import (all deferred in `G2_CLOSEOUT` / `G3_CLOSEOUT`) — optional here, could move to G5 or after | G3.1 | L | the biggest unknown is modifiers (no backend yet) |

Suggested order: **G4.0 → G4.1 → G4.2 → G4.4 → G4.3**, then G4.5 if you want it. Reports first because they are what owners open every day and the data already exists; roles second because it changes how every later screen is gated.

## 2. Where the FBR integration fits
**Recommendation: after G4.1 (reports) and in parallel with G4.2–G4.3 — not before G4, not blocked by it.**
* FBR needs **documents** (invoices with per-line tax, credit notes) — those are done (G2.5/G2.6). It needs **a registration route and credentials** — that is a business/legal step, not code (`FBR_PLAN.md` §10: route A (PRAL) vs B (licence), the PRAL spec for retail, sandbox access).
* It depends on: (1) the open questions in `FBR_PLAN.md` §10 answered (documents + the tax advisor's questions, incl. loyalty-discount vs store-credit treatment); (2) the **Tax report** (G4.1) being right, because the FBR figures and the Tax report must agree; (3) the **settings hub** (G4.3) for the registration screen and the offline-invoice policy; (4) the **audit hash chain** (G4.4) is not required but strengthens the story.
* It does **not** depend on G4.2 / G4.5. So: start the FBR work as soon as the documents/credentials arrive; in the meantime G4.0–G4.2 proceed. If the credentials arrive earlier, FBR can jump ahead of G4.2.
* Rough size (from `FBR_PLAN.md` §9): 4–6 weeks including sandbox certification; the unknown is the approval timeline at FBR/PRAL, not the build.

## 3. Risks (cross-cutting)
1. **"A day" is ambiguous** without a store time zone — daybook uses the client's local day today; reports must use one server rule (decision 6).
2. **Performance:** report queries scan sales/lines; fine for a single shop, not for a chain with years of data → rollups (decision 1) and indexes; add a performance budget (a report ≤ 2 s on 1 M lines).
3. **Profit correctness:** only as good as cost data. Show **cost coverage**; never impute zero.
4. **Permissions editor foot-guns** (lock-out, privilege escalation by a manager) → invariants above, owner-only, diff + confirm, full audit, and tests that run the same 150-row matrix test against random overrides.
5. **Charts without a package** (CustomPainter): doable for bars / lines / donut, accessibility (labels, patterns, not colour alone) must be designed in.
6. **Data leaving the app:** CSV/PDF export of reports and the audit log — owner/manager only, audited.

## 4. Decisions I need from you
1. **Reports backend:** (a) compute live from the ledgers (simplest; fine up to ~ a few hundred thousand lines), or (b) add daily rollups now (faster, more code, rebuildable). *Recommendation: (a) for G4.0–G4.1 with indexes and a performance test, add rollups only if the test fails.*
2. **Profit definition:** gross margin = net sales (ex tax, after discounts) − WAC cost of units sold, **returns reversing at the sale's cost**; does "profit" also subtract expenses (an operating-profit line)? *Recommendation: show both gross margin and an "after expenses" line, clearly labelled.*
3. **Who sees what:** profit/cost reports manager + owner only (as today for costs); the cashier report for a cashier = only themselves. OK?
4. **Charts:** may I add **one** chart dependency (e.g. `fl_chart`) or must it be hand-drawn with CustomPainter? (Packages need your approval.) *Recommendation: hand-drawn bars/lines/donut — three simple chart types, no dependency.*
5. **Audit tamper evidence:** (a) hash chain written in the same transaction as the event (strong, a bit slower, serialises per store) or (b) append-only DB role + a nightly sealing job that signs a daily digest (cheaper, weaker). *Recommendation: (b) first, (a) if a customer/auditor asks.*
6. **Store time zone:** add a store-level IANA time zone (default from the country) and use it for "today", "hourly" and the daybook day. *Recommendation: yes, in G4.0.*
7. **Roles editor scope:** per-store matrix editing for the 3 fixed roles only (recommended), or custom roles (e.g. "Supervisor", "Stock clerk")? Custom roles are a bigger change (employee → role mapping, UI to create roles).
8. **Presets:** which preset should be the default for **new** stores — today's table (recommended) or a stricter one?
9. **FBR route (A PRAL / B licence)** and whether to start before G4.2 — only you can decide with the tax advisor.
10. **Catalog (G4.5):** keep in G4, or move to its own phase after FBR?

## 5. Smallest safe first deliverable
**G4.0 + the Sales and Payment-mix reports**, read-only, owner/manager only, no new tables, with the performance test — it proves the aggregation layer, the chart toolkit and the date strip on data that is already correct. Nothing in it can lose or change money.
