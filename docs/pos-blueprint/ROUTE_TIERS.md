# POS route tiers (generated)

Written by `solvexo-api/src/pos/pos-route-tiers.spec.ts` from Nest's route metadata and `src/pos/pos-route-tiers.ts`. Do not edit by hand — change the registry and run the spec.

**Tiers:** `owner` = the owner's own session only · `manager-with-limit` = a manager or the owner (some actions have per-store approval limits) · `cashier` = any PIN-signed employee (approval limits may ask for a manager) · `public` = no PIN session (device, PIN login, public receipt).

**Declared:** 148 routes — owner 26, manager-with-limit 68, cashier 47, public 7. Other GET routes (no cost / settings data): 43.

| Method | Route | Tier | Handler | Guards |
|---|---|---|---|---|
| GET | `/api/pos/audit-logs/:storeId` | manager-with-limit | PosController.getAuditLogs | FeatureFlagGuard + PosAuthGuard + RolesGuard + manager PIN |
| GET | `/api/pos/audit/verify/:storeId` | manager-with-limit | PosAuditController.verify | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/cash/daybook/:storeId` | cashier | PosCashController.daybook | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/cash/expenses/:storeId` | cashier | PosCashController.expense | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/cash/expenses/:storeId/:id/decision` | manager-with-limit | PosCashController.decide | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/cash/expenses/:storeId/:id/receipt` | cashier | PosCashController.receipt | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/cash/movements/:storeId` | cashier | PosCashController.move | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/cash/movements/:storeId/:requestId/receipt` | cashier | PosCashController.movementReceipt | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/catalog-admin/categories/:storeId` | cashier | PosCatalogAdminController.categories | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/catalog-admin/categories/:storeId` | manager-with-limit | PosCatalogAdminController.categoryCreate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| PATCH | `/api/pos/catalog-admin/categories/:storeId/:id` | manager-with-limit | PosCatalogAdminController.categoryUpdate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/catalog-admin/categories/:storeId/:id/delete` | manager-with-limit | PosCatalogAdminController.categoryDelete | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/catalog-admin/import/:storeId` | manager-with-limit | PosCatalogAdminController.importCsv | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/catalog-admin/modifiers/:storeId` | cashier | PosCatalogAdminController.modifiers | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/catalog-admin/modifiers/:storeId` | manager-with-limit | PosCatalogAdminController.modifierCreate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| PATCH | `/api/pos/catalog-admin/modifiers/:storeId/:id` | manager-with-limit | PosCatalogAdminController.modifierUpdate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/catalog-admin/price-books/:storeId` | cashier | PosCatalogAdminController.priceBooks | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/catalog-admin/price-books/:storeId` | manager-with-limit | PosCatalogAdminController.priceBookCreate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| PATCH | `/api/pos/catalog-admin/price-books/:storeId/:id` | manager-with-limit | PosCatalogAdminController.priceBookUpdate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/catalog-admin/price-books/:storeId/customers/:customerId` | manager-with-limit | PosCatalogAdminController.assignBook | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/catalog-admin/products/:storeId` | manager-with-limit | PosCatalogAdminController.createProduct | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/catalog-admin/products/:storeId/:productId/variants` | manager-with-limit | PosCatalogAdminController.addVariant | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/catalog-admin/products/:storeId/:productId/variants/:variantId/archive` | manager-with-limit | PosCatalogAdminController.archiveVariant | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| PATCH | `/api/pos/catalog/:storeId/variants/:variantId` | manager-with-limit | PosController.updateCatalogVariant | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/catalog/:storeId/variants/:variantId/stock` | manager-with-limit | PosController.adjustCatalogStock | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/customers/:storeId` | cashier | PosCustomersController.create | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| PATCH | `/api/pos/customers/:storeId/:id` | manager-with-limit | PosCustomersController.update | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/customers/credit/:storeId/:id/adjust` | manager-with-limit | PosCustomersController.creditAdjust | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| PATCH | `/api/pos/customers/loyalty/:storeId` | owner | PosCustomersController.setLoyalty | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/dashboard/:storeId` | cashier | PosController.dashboard | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/devices` | owner | PosController.registerDevice | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| POST | `/api/pos/devices/:storeId/:deviceId/revoke` | owner | PosController.revokeDevice | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| POST | `/api/pos/devices/me/sign-out` | public | PosController.deviceSignOut | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/employees` | owner | PosController.addEmployee | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| DELETE | `/api/pos/employees/:employeeId` | owner | PosController.removeEmployee | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| PATCH | `/api/pos/employees/:employeeId` | owner | PosController.updateEmployee | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| DELETE | `/api/pos/employees/:storeId/:employeeId` | owner | PosController.removeEmployeeV2 | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| PATCH | `/api/pos/employees/:storeId/:employeeId` | owner | PosController.updateEmployeeV2 | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| POST | `/api/pos/employees/:storeId/:employeeId/reset-pin` | owner | PosController.resetPin | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/:storeId` | cashier | PosController.posInventory | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/:storeId/low-stock` | cashier | PosController.posLowStock | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/inventory/adjust/:storeId/:variantId` | cashier | PosInventoryController.adjust | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/inventory/counts/:storeId` | cashier | PosInventoryController.countList | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/inventory/counts/:storeId` | manager-with-limit | PosInventoryController.countStart | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/inventory/counts/:storeId/:id` | cashier | PosInventoryController.countGet | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/inventory/counts/:storeId/:id/cancel` | manager-with-limit | PosInventoryController.countCancel | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/inventory/counts/:storeId/:id/find` | cashier | PosInventoryController.countFind | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/inventory/counts/:storeId/:id/finish` | manager-with-limit | PosInventoryController.countFinish | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/inventory/counts/:storeId/:id/items/:itemId` | cashier | PosInventoryController.countEnter | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/inventory/expiry/:storeId` | cashier | PosInventoryController.expiry | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/limits/:storeId` | manager-with-limit | PosInventoryController.limits | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PATCH | `/api/pos/inventory/limits/:storeId` | owner | PosInventoryController.setLimits | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/inventory/locations/:storeId` | cashier | PosInventoryController.locations | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/lookup/:storeId` | cashier | PosInventoryController.lookup | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/inventory/lots/:storeId/:lotId/write-off` | manager-with-limit | PosInventoryController.writeOff | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/inventory/lots/:storeId/:variantId` | cashier | PosInventoryController.lots | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/low-stock/:storeId` | cashier | PosInventoryController.lowStock | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/movements/:storeId` | cashier | PosInventoryController.movements | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/overview/:storeId` | cashier | PosInventoryController.overview | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/stock/:storeId` | cashier | PosInventoryController.stock | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/inventory/transfers/:storeId` | cashier | PosInventoryController.transfers | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/inventory/transfers/:storeId` | manager-with-limit | PosInventoryController.transferShip | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/inventory/transfers/:storeId/:id/cancel` | manager-with-limit | PosInventoryController.transferCancel | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/inventory/transfers/:storeId/:id/receive` | manager-with-limit | PosInventoryController.transferReceive | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/inventory/variant/:storeId/:variantId` | cashier | PosInventoryController.detail | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/locations/:storeId` | owner | PosController.createLocation | FeatureFlagGuard + JwtAuthGuard + RolesGuard + PermissionsGuard |
| DELETE | `/api/pos/locations/:storeId/:locationId` | owner | PosController.archiveLocation | FeatureFlagGuard + JwtAuthGuard + RolesGuard + PermissionsGuard |
| PATCH | `/api/pos/locations/:storeId/:locationId` | owner | PosController.updateLocation | FeatureFlagGuard + JwtAuthGuard + RolesGuard + PermissionsGuard |
| POST | `/api/pos/locations/:storeId/import` | owner | PosController.importLocations | FeatureFlagGuard + JwtAuthGuard + RolesGuard + PermissionsGuard |
| POST | `/api/pos/offline-discards` | manager-with-limit | PosController.recordOfflineDiscard | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/permissions/:storeId` | manager-with-limit | PosPermissionsStoreController.get | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PUT | `/api/pos/permissions/:storeId` | owner | PosPermissionsStoreController.update | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/permissions/:storeId/reset` | owner | PosPermissionsStoreController.reset | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/pin-login` | public | PosController.pinLogin | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/pin-logout` | public | PosController.pinLogout | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/products/:storeId` | cashier | PosController.getPosProducts | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/products/barcode/:storeId/:barcode` | cashier | PosController.getProductByBarcode | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/products/search` | cashier | PosController.searchProducts | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/registers/:storeId` | owner | PosController.addRegister | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| DELETE | `/api/pos/registers/:storeId/:registerId` | owner | PosController.removeRegister | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| PATCH | `/api/pos/registers/:storeId/:registerId` | owner | PosController.updateRegister | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| GET | `/api/pos/reports/cashiers/:storeId` | cashier | PosReportsController.cashiers | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/categories/:storeId` | manager-with-limit | PosReportsController.categories | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/daily` | manager-with-limit | PosController.getDailyReport | FeatureFlagGuard + PosAuthGuard + RolesGuard + manager PIN |
| GET | `/api/pos/reports/daily/export` | manager-with-limit | PosController.exportDailyReport | FeatureFlagGuard + PosAuthGuard + RolesGuard + manager PIN |
| GET | `/api/pos/reports/employee/:employeeId` | manager-with-limit | PosController.getEmployeeReport | FeatureFlagGuard + PosAuthGuard + RolesGuard + manager PIN |
| GET | `/api/pos/reports/hourly/:storeId` | manager-with-limit | PosReportsController.hourly | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/payments/:storeId` | cashier | PosReportsController.payments | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/products/:storeId` | manager-with-limit | PosReportsController.products | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/profit/:storeId` | manager-with-limit | PosReportsController.profit | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/pulse/:storeId` | manager-with-limit | PosReportsController.pulse | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/range` | manager-with-limit | PosController.getDateRangeReport | FeatureFlagGuard + PosAuthGuard + RolesGuard + manager PIN |
| GET | `/api/pos/reports/register/:registerId` | manager-with-limit | PosController.getRegisterReport | FeatureFlagGuard + PosAuthGuard + RolesGuard + manager PIN |
| GET | `/api/pos/reports/sales/:storeId` | manager-with-limit | PosReportsController.sales | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/reports/tax/:storeId` | manager-with-limit | PosReportsController.tax | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/reprints/:storeId` | cashier | PosReprintController.reprint | PosAuthGuard + RolesGuard |
| POST | `/api/pos/sales` | cashier | PosController.createSale | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/sales/:saleId/complete` | cashier | PosController.completeSale | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| DELETE | `/api/pos/sales/:saleId/discard` | cashier | PosController.discardHeldSale | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PATCH | `/api/pos/sales/:saleId/items` | cashier | PosController.editHeldSaleItems | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/sales/:saleId/receipt-link/revoke` | manager-with-limit | PosController.revokeReceiptLink | FeatureFlagGuard + PosAuthGuard + RolesGuard + manager PIN |
| POST | `/api/pos/sales/:saleId/refund` | cashier | PosController.refundSale | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/sales/:saleId/resolve-review` | manager-with-limit | PosController.resolveSaleReview | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/sales/:saleId/void` | manager-with-limit | PosController.voidSale | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/sales/quote` | cashier | PosController.quoteSale | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/sessions/:sessionId/cash-adjustment` | manager-with-limit | PosController.cashInOut | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/sessions/:sessionId/force-close` | owner | PosController.forceCloseSession | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| POST | `/api/pos/sessions/close` | cashier | PosController.closeSession | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/sessions/open` | cashier | PosController.openSession | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/settings/:storeId` | cashier | PosController.getPosSettings | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PATCH | `/api/pos/settings/:storeId` | owner | PosController.updatePosSettings | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| POST | `/api/pos/shifts/:storeId` | owner | PosController.addShift | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| DELETE | `/api/pos/shifts/:storeId/:shiftId` | owner | PosController.deleteShift | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| PATCH | `/api/pos/shifts/:storeId/:shiftId` | owner | PosController.updateShift | FeatureFlagGuard + JwtAuthGuard + RolesGuard |
| GET | `/api/pos/store/settings/:storeId` | manager-with-limit | PosStoreController.getSettings | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PATCH | `/api/pos/store/settings/:storeId` | owner | PosStoreController.setSettings | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/store/time-zone/:storeId` | cashier | PosStoreController.timeZone | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PATCH | `/api/pos/store/time-zone/:storeId` | owner | PosStoreController.setTimeZone | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/supply/orders/:storeId` | cashier | PosSupplyController.orders | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/supply/orders/:storeId` | manager-with-limit | PosSupplyController.createOrder | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/supply/orders/:storeId/:id` | cashier | PosSupplyController.order | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PATCH | `/api/pos/supply/orders/:storeId/:id` | manager-with-limit | PosSupplyController.updateOrder | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/supply/orders/:storeId/:id/approve` | manager-with-limit | PosSupplyController.approveOrder | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/supply/orders/:storeId/:id/cancel` | manager-with-limit | PosSupplyController.cancelOrder | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/supply/orders/:storeId/:id/close-short` | manager-with-limit | PosSupplyController.closeShort | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/supply/orders/:storeId/:id/send` | manager-with-limit | PosSupplyController.sendOrder | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/supply/orders/:storeId/from-low-stock` | manager-with-limit | PosSupplyController.draftFromLowStock | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/supply/payables/:storeId` | manager-with-limit | PosSupplyController.payables | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| GET | `/api/pos/supply/payables/:storeId/:id` | manager-with-limit | PosSupplyController.ledger | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/supply/payments/:storeId/:id` | manager-with-limit | PosSupplyController.pay | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/supply/receipts/:storeId` | manager-with-limit | PosSupplyController.receipts | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/supply/receipts/:storeId` | cashier | PosSupplyController.receive | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/supply/returns/:storeId` | manager-with-limit | PosSupplyController.returnsList | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/supply/returns/:storeId` | manager-with-limit | PosSupplyController.createReturn | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/supply/suppliers/:storeId` | manager-with-limit | PosSupplyController.suppliers | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| POST | `/api/pos/supply/suppliers/:storeId` | manager-with-limit | PosSupplyController.createSupplier | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/api/pos/supply/suppliers/:storeId/:id` | manager-with-limit | PosSupplyController.supplier | FeatureFlagGuard + PosAuthGuard + RolesGuard |
| PATCH | `/api/pos/supply/suppliers/:storeId/:id` | manager-with-limit | PosSupplyController.updateSupplier | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/team/anomalies/:storeId/ack` | manager-with-limit | PosTeamController.ack | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/team/clock/:storeId` | cashier | PosTeamController.clock | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/team/corrections/:storeId` | manager-with-limit | PosTeamController.correct | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/team/roster/:storeId` | manager-with-limit | PosTeamController.rosterCreate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| PATCH | `/api/pos/team/roster/:storeId/:id` | manager-with-limit | PosTeamController.rosterUpdate | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| POST | `/api/pos/team/roster/:storeId/:id/cancel` | manager-with-limit | PosTeamController.rosterCancel | FeatureFlagGuard + PosAuthGuard + RolesGuard + PosEntitlementGuard |
| GET | `/r/:token` | public | PublicReceiptController.page | — |
| GET | `/r/:token/credit-note/:number` | public | PublicReceiptController.creditNote | — |
| GET | `/r/:token/invoice` | public | PublicReceiptController.invoice | — |
| GET | `/r/s/:store/:key` | public | PublicReceiptController.byClientKey | — |
