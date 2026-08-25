part of 'app_pages.dart';
// DO NOT EDIT. This is code generated via package:get_cli/get_cli.dart

abstract class Routes {
  // Entry — POS-specific login (this app has no buyer auth flow).
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

  // POS operational screens
  static const posHeldSales = '/pos/held-sales';
  static const posSaleDetail = '/pos/sale-detail';
  static const posSessionReport = '/pos/session-report';
  static const posDailyReport = '/pos/daily-report';
  static const posSessionHistory = '/pos/session-history';
  static const posAuditLog = '/pos/audit-log';
  static const posRangeReport = '/pos/range-report';
}
