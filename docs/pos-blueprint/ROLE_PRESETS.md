# Role presets: PROPOSED, pending sign-off by Sir Atiq (G5.6)

**Status:** proposed. The three presets below are built and can be applied, but they are labelled **"Proposed"** in the app until they are signed off.
- Nothing is applied automatically.
- A store keeps the documented defaults unless its **owner** applies a preset.
- Applying a preset shows the exact before/after diff first.
- Each apply is audited (`permissions_preset_applied`, with the full diff) and version-guarded (two owner devices cannot overwrite each other).

**How a preset works:**
- It is a complete set of overrides over the default matrix ([G3_PERMISSIONS_AND_LIMITS.md](G3_PERMISSIONS_AND_LIMITS.md)).
- Applying it **replaces** the store's custom permissions, so the result is the same whatever was there before.
- The owner can never be removed from anything, and the pinned actions (who may see or edit permissions) are never touched; a test enforces both.
- Approval limits are not changed by any preset.

**Where:**
- Backend: `src/pos/pos-role-presets.ts`.
- Route: `POST /api/pos/permissions/:storeId/preset { preset, preview?, expectedVersion? }` (tier **owner**).
- The list is in `GET /api/pos/permissions/:storeId` → `presets`.
- App: Roles & permissions → **Presets**.

## The presets

### 1. Standard
The documented defaults: cashiers sell, managers run the shop, and the owner controls money settings. It is the same as "Reset to defaults".

### 2. Small shop
For a shop where the owner is usually at the till. Cashiers may also:

| Action | Default | Small shop |
|---|---|---|
| Edit customers (`customers.edit`) | manager, owner | **cashier**, manager, owner |
| Start a stock count (`inventory.count.start`) | manager, owner | **cashier**, manager, owner |
| Finish a stock count (`inventory.count.finish`) | manager, owner | **cashier**, manager, owner |
| Receive goods without a PO (`supply.receive.direct`) | manager, owner | **cashier**, manager, owner |

### 3. Strict (owner away)
For a shop run by staff.

| Action | Default | Strict |
|---|---|---|
| Adjust stock (`inventory.adjust`) | cashier, manager, owner | manager, owner |
| Record an expense (`expenses.record`) | cashier, manager, owner | manager, owner |
| Refund to store credit (`storeCredit.refundIssue`) | cashier, manager, owner | manager, owner |
| Clock in for someone else (`team.attendance.onBehalf`) | cashier, manager, owner | manager, owner |
| Import the catalog (`catalog.import`) | manager, owner | **owner** |
| Pay a supplier (`supply.payment`) | manager, owner | **owner** |
| Adjust store credit (`storeCredit.adjust`) | manager, owner | **owner** |

## What Sir Atiq needs to decide
1. Are these the right three presets, and are the names right?
2. For each changed action: keep, drop or change.
3. Should any preset also change **approval limits** (e.g. lower cash-out limits in Strict)? Today none does.
4. Once signed off: remove the "proposed" status in `GET /api/pos/permissions/:storeId` (`status: 'proposed'` → `'approved'`). The app then drops the badge.
