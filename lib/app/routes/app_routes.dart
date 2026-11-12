part of 'app_pages.dart';
// DO NOT EDIT. This is code generated via package:get_cli/get_cli.dart

abstract class Routes {
  // First-launch entry — splash, then a one-time onboarding carousel before
  // the POS-specific login (this app has no buyer auth flow).
  static const splashScreen = '/splash';
  static const onboarding = '/onboarding';
  static const posLogin = '/pos/login';

  // Seller setup — store-picker + first-store creation flow.
  static const sellerOnboarding = '/seller/onboarding';
  static const sellerStores = '/seller/stores';

  // Role-based home — seller-management dashboard was removed upstream
  // (Phase 2); this repoints at the POS management screen, same as the
  // buyer app did before the Phase 3 extraction.
  static const sellerHome = '/seller/home';
  static const posHome = '/pos/home';

  // Seller POS management
  static const sellerPosManagement = '/seller/pos-management';
  static const sellerPosLocations = '/seller/pos-locations';

  // POS sub-screens
  static const posOrders = '/pos/orders';
  static const posProducts = '/pos/products';
  static const posSettings = '/pos/settings';

  // POS entry flow
  static const posPinLogin = '/pos/pin-login';
  static const posOpenRegister = '/pos/open-register';

  // POS plan: read-only status (owner) and the neutral "plan isn't active" screen — the app never sells a plan
  static const posPlanInactive = '/pos/plan-inactive';
  static const posPlanStatus = '/pos/plan-status';

  // POS operational screens
  static const posHeldSales = '/pos/held-sales';
  static const posSaleDetail = '/pos/sale-detail';
  static const posSessionReport = '/pos/session-report';
  static const posDailyReport = '/pos/daily-report';
  static const posSessionHistory = '/pos/session-history';
  static const posAuditLog = '/pos/audit-log';
  static const posRangeReport = '/pos/range-report';

  // Phase 2 — supporting modules
  static const posInventory = '/pos/inventory';
  static const posStockActivity = '/pos/stock-activity';
  // G3.1 inventory (the legacy /pos/inventory screen stays reachable)
  static const posStockOverview = '/pos/stock';
  static const posStockList = '/pos/stock/list';
  static const posStockDetail = '/pos/stock/item';
  static const posStockMovements = '/pos/stock/movements';
  static const posStockCount = '/pos/stock/count';
  static const posStockLimits = '/pos/stock/limits';
  static const posNeedsAttention = '/pos/needs-attention';
  static const posOfflineMode = '/pos/offline-mode';
  static const posPermissions = '/pos/permissions';
  static const posKyb = '/pos/business-verification';
  static const posPaymentsSetup = '/pos/payments-setup'; // G5.4
  static const posTaxInvoice = '/pos/tax-invoice';
  static const posReturn = '/pos/return';
  static const posCatalog = '/pos/catalog';
  static const posTaxProfile = '/pos/tax-profile';
  static const posCustomers = '/pos/customers';
  // G3.3 customers: the directory (everyone) and one customer's profile
  static const posCustomerDirectory = '/pos/customers/directory';
  static const posCustomerProfile = '/pos/customers/profile';

  // G3.4 supply: home (managers), purchase orders, one order, order form, receiving, suppliers, a supplier, payables, a ledger
  static const posSupply = '/pos/supply';
  static const posSupplyOrders = '/pos/supply/orders';
  static const posSupplyOrder = '/pos/supply/order';
  static const posSupplyOrderForm = '/pos/supply/order-form';
  static const posSupplyReceive = '/pos/supply/receive';
  static const posSupplySuppliers = '/pos/supply/suppliers';
  static const posSupplySupplier = '/pos/supply/supplier';
  static const posSupplyPayables = '/pos/supply/payables';
  static const posSupplyLedger = '/pos/supply/ledger';

  // G3.5 cash & expenses: home (cash in / out, expenses, daybook), the expense list, one expense, the daybook
  static const posCash = '/pos/cash';
  static const posCashExpenses = '/pos/cash/expenses';
  static const posCashExpense = '/pos/cash/expense';
  static const posCashDaybook = '/pos/cash/daybook';

  // G3.6 team: the clock, attendance history, one record, the roster, the attendance report
  static const posTeamClock = '/pos/team/clock';
  static const posTeamAttendance = '/pos/team/attendance';
  static const posTeamRecord = '/pos/team/record';
  static const posTeamRoster = '/pos/team/roster';
  static const posTeamReport = '/pos/team/report';

  // G4.0 / G4.1 business pulse, reports, store time zone
  static const posPulse = '/pos/pulse';
  static const posReports = '/pos/reports';
  static const posReport = '/pos/reports/view';
  static const posStoreTimeZone = '/pos/store/time-zone';
  static const posDayOrders = '/pos/reports/day-orders';

  // G4.2 – G4.4 roles & permissions, store settings hub and its screens
  static const posRoles = '/pos/roles';
  static const posSettingsHub = '/pos/settings-hub';
  static const posReceiptDesigner = '/pos/settings/receipt';
  static const posAlertSettings = '/pos/settings/notifications';
  static const posSecuritySettings = '/pos/settings/security';
  static const posBackupSync = '/pos/settings/backup-sync';

  // G4.6 stock transfers and expiring lots
  static const posTransfers = '/pos/inventory/transfers';
  static const posExpiry = '/pos/inventory/expiry';

  // G4.5 products & pricing admin
  static const posCatalogAdmin = '/pos/catalog-admin';
  static const posModifierGroups = '/pos/catalog-admin/modifiers';
  static const posPriceBooks = '/pos/catalog-admin/price-books';
  static const posCatalogNewProduct = '/pos/catalog-admin/new-product';
  static const posCatalogCategories = '/pos/catalog-admin/categories';
  static const posCatalogImport = '/pos/catalog-admin/import';

  // 5D — shared-device security
  static const posDeviceSetup = '/pos/device-setup';
  static const posOwnerGate = '/pos/owner-gate';
  static const posDevices = '/pos/devices';
  static const posDeleteAccount = '/pos/delete-account';

  // Debug builds only (see app_pages.dart) — design-system component catalogue.
  static const designGallery = '/design-gallery';
}
