# POS permission matrix and approval limits (G3.0 — decisions D1 and D6)

Single source: `solvexo-api/src/pos/pos-permissions.config.ts` (data, not scattered checks). Routes name an **action**; `PosAuthorizer` evaluates action × role × limits. The tables below are generated from that file (`npx ts-node -r tsconfig-paths/register src/scripts/pos-permissions-doc.ts`) and the spec `pos-permissions.spec.ts` asserts every action × role (allowed / denied / needs approval, below and above each limit) — 127 cases.

**Roles (fixed for G3):** `cashier`, `manager` (employee PIN sessions) and `owner` (the owner's own login — a non-device JWT). **Approval:** a manager's PIN in header `x-pos-approver-token` (same store, role ≥ manager, verified server-side); an *owner* approval can only come from the owner's own login (a manager gets `POS_OWNER_REQUIRED`). A role that already ranks as high as the approver acts as its own approver. Denials and approvals are audit-logged (`pos_action_denied`, `pos_approval_missing`, `pos_approval_given`) with who asked and who approved. The limit is **inclusive** (exactly at the limit is allowed).

**Limits (D6)** are per store (`PosSettings.approvalLimits`, owner-editable through `PATCH pos/inventory/limits/:storeId`, audited with before/after). A limit not set uses the default below — **money defaults are in major units of the store currency and scale with its exponent** (USD ×100, JPY ×1, KWD ×1000); quantities are plain units/points. A stored override is in **minor units** (money) or plain numbers (counts).

Making the matrix editable per store later (G4) means changing where the table is read from, not touching a route.

## Matrix and limits
| Action | What | Cashier | Manager | Owner | Needs approval |
|---|---|---|---|---|---|
| `inventory.view` | See stock, lots and low stock | ✔ | ✔ | ✔ |  |
| `inventory.history.view` | See stock movement history | — | ✔ | ✔ |  |
| `inventory.adjust` | Adjust stock (a cashier only a little, a manager PIN above the limits) | ✔ | ✔ | ✔ | stockAdjustQty > limit → manager; stockAdjustValueMinor > limit → manager |
| `inventory.writeoff` | Write off damaged / expired stock | — | ✔ | ✔ |  |
| `inventory.count.start` | Start a stock count | — | ✔ | ✔ |  |
| `inventory.count.enter` | Enter counted quantities | ✔ | ✔ | ✔ |  |
| `inventory.count.finish` | Finish a count and post its variances | — | ✔ | ✔ |  |
| `inventory.transfer.create` | Create / ship a stock transfer | — | ✔ | ✔ |  |
| `inventory.transfer.receive` | Receive a stock transfer | — | ✔ | ✔ |  |
| `inventory.lot.sellExpired` | Sell stock from an expired lot (override) | ✔ | ✔ | ✔ | always → manager |
| `catalog.edit` | Edit price, barcode, category, HS code | — | ✔ | ✔ |  |
| `customers.view` | Find customers and see their balance | ✔ | ✔ | ✔ |  |
| `customers.create` | Add a customer | ✔ | ✔ | ✔ |  |
| `customers.edit` | Edit customer details and tax ID | — | ✔ | ✔ |  |
| `storeCredit.spend` | Pay with store credit | ✔ | ✔ | ✔ |  |
| `storeCredit.refundIssue` | Refund to store credit | ✔ | ✔ | ✔ | storeCreditRefundMinor > limit → manager |
| `storeCredit.adjust` | Adjust a customer's store credit by hand | — | ✔ | ✔ | storeCreditAdjustMinor > limit → owner |
| `loyalty.redeem` | Redeem loyalty points at checkout | ✔ | ✔ | ✔ |  |
| `loyalty.configure` | Set the loyalty earn / redeem rates for the till | — | — | ✔ |  |
| `loyalty.adjust` | Adjust loyalty points by hand | — | ✔ | ✔ | loyaltyAdjustPoints > limit → owner |
| `supply.view` | See suppliers and purchase orders | — | ✔ | ✔ |  |
| `supply.po.write` | Create / edit a purchase order | — | ✔ | ✔ |  |
| `supply.po.approve` | Approve a purchase order (above the limit the owner approves) | — | ✔ | ✔ | purchaseOrderMinor > limit → owner |
| `supply.po.receive` | Receive stock against an approved purchase order | ✔ | ✔ | ✔ |  |
| `supply.receive.direct` | Receive stock without a purchase order | — | ✔ | ✔ |  |
| `supply.return` | Return stock to a supplier | — | ✔ | ✔ |  |
| `supply.costs.view` | See costs, payables and payments | — | ✔ | ✔ |  |
| `supply.payment` | Pay a supplier | — | ✔ | ✔ | supplierPaymentManagerMinor > limit → owner |
| `cash.in` | Cash in (float top-up) | ✔ | ✔ | ✔ |  |
| `cash.out` | Cash out / safe drop | ✔ | ✔ | ✔ | cashOutMinor > limit → manager |
| `expenses.record` | Record an expense | ✔ | ✔ | ✔ | expenseMinor > limit → manager |
| `expenses.approve` | Approve / reject an expense | — | ✔ | ✔ |  |
| `daybook.view` | See the daybook (a cashier only the shifts they worked) | ✔ | ✔ | ✔ |  |
| `team.attendance.own` | Clock in / out | ✔ | ✔ | ✔ |  |
| `team.attendance.view` | See everyone's attendance, anomalies and reports | — | ✔ | ✔ |  |
| `team.roster.view` | See the shift roster | ✔ | ✔ | ✔ |  |
| `team.attendance.edit` | Edit someone's attendance | — | ✔ | ✔ |  |
| `team.roster.edit` | Edit the shift roster | — | ✔ | ✔ |  |
| `settings.approvalLimits.view` | See the approval limits | — | ✔ | ✔ |  |
| `settings.approvalLimits.edit` | Change the approval limits | — | — | ✔ |  |

| Limit | What it limits | Default |
|---|---|---|
| `stockAdjustQty` | Stock adjustment a cashier may make alone — units | 5 units |
| `stockAdjustValueMinor` | Stock adjustment a cashier may make alone — value at cost | 20.00 (major units of the store currency) |
| `cashOutMinor` | Cash out / safe drop | 100.00 (major units of the store currency) |
| `expenseMinor` | Expense | 100.00 (major units of the store currency) |
| `purchaseOrderMinor` | Purchase order a manager may approve alone | 1000.00 (major units of the store currency) |
| `supplierPaymentManagerMinor` | Supplier payment a manager may make alone | 500.00 (major units of the store currency) |
| `supplierPaymentOwnerMinor` | Supplier payment that needs the owner | 2000.00 (major units of the store currency) |
| `storeCreditRefundMinor` | Refund to store credit | 50.00 (major units of the store currency) |
| `storeCreditAdjustMinor` | Manual store-credit adjustment | 100.00 (major units of the store currency) |
| `loyaltyAdjustPoints` | Manual loyalty points adjustment | 500 points |