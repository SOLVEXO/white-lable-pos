import 'package:get/get.dart';
import 'package:solvexo_pos/app/middleware/auth_middleware.dart';
import '../modules/pos_login/bindings/pos_login_binding.dart';
import '../modules/pos_login/views/pos_login_view.dart';
import '../modules/seller_onboarding/bindings/seller_onboarding_binding.dart';
import '../modules/seller_onboarding/views/seller_onboarding_view.dart';
import '../modules/seller_stores/bindings/seller_stores_binding.dart';
import '../modules/seller_stores/views/seller_stores_view.dart';
import '../modules/pos/bindings/pos_binding.dart';
import '../modules/pos/views/pos_main_view.dart';
import '../modules/pos_orders/bindings/pos_orders_binding.dart';
import '../modules/pos_orders/views/pos_orders_view.dart';
import '../modules/pos_products/bindings/pos_products_binding.dart';
import '../modules/pos_products/views/pos_products_view.dart';
import '../modules/pos_settings/bindings/pos_settings_binding.dart';
import '../modules/pos_settings/views/pos_settings_view.dart';
import '../modules/pos_pin_login/bindings/pos_pin_login_binding.dart';
import '../modules/pos_pin_login/views/pos_pin_login_view.dart';
import '../modules/pos_open_register/bindings/pos_open_register_binding.dart';
import '../modules/pos_open_register/views/pos_open_register_view.dart';
import '../modules/pos_held_sales/bindings/pos_held_sales_binding.dart';
import '../modules/pos_held_sales/views/pos_held_sales_view.dart';
import '../modules/pos_daily_report/bindings/pos_daily_report_binding.dart';
import '../modules/pos_daily_report/views/pos_daily_report_view.dart';
import '../modules/seller_pos_management/bindings/seller_pos_management_binding.dart';
import '../modules/seller_pos_management/views/seller_pos_management_view.dart';
import '../modules/seller_pos_locations/bindings/seller_pos_locations_binding.dart';
import '../modules/seller_pos_locations/views/seller_pos_locations_view.dart';
import '../modules/pos_sale_detail/bindings/pos_sale_detail_binding.dart';
import '../modules/pos_sale_detail/views/pos_sale_detail_view.dart';
import '../modules/pos_session_report/bindings/pos_session_report_binding.dart';
import '../modules/pos_session_report/views/pos_session_report_view.dart';
import '../modules/pos_session_history/bindings/pos_session_history_binding.dart';
import '../modules/pos_session_history/views/pos_session_history_view.dart';
import '../modules/pos_audit_log/bindings/pos_audit_log_binding.dart';
import '../modules/pos_audit_log/views/pos_audit_log_view.dart';
import '../modules/pos_range_report/bindings/pos_range_report_binding.dart';
import '../modules/pos_range_report/views/pos_range_report_view.dart';
part 'app_routes.dart';

class AppPages {
  static const initialRoute = Routes.posLogin;

  static final routes = [
    GetPage(
      name: Routes.posLogin,
      page: () => const PosLoginView(),
      binding: PosLoginBinding(),
    ),
    GetPage(
      name: Routes.sellerOnboarding,
      page: () => SellerOnboardingView(),
      binding: SellerOnboardingBinding(),
    ),
    GetPage(
      name: Routes.sellerStores,
      page: () => SellerStoresView(),
      binding: SellerStoresBinding(),
    ),
    // Seller-management dashboard removed (Phase 2) — this app carries no
    // seller dashboard shell, only POS configuration (staff/registers/
    // locations), same as the buyer app before the Phase 3 extraction.
    GetPage(
      name: Routes.sellerHome,
      page: () => SellerPosManagementView(),
      binding: SellerPosManagementBinding(),
    ),
    GetPage(
      name: Routes.posHome,
      page: () => PosMainView(),
      binding: PosBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.sellerPosManagement,
      page: () => SellerPosManagementView(),
      binding: SellerPosManagementBinding(),
    ),
    GetPage(
      name: Routes.sellerPosLocations,
      page: () => SellerPosLocationsView(),
      binding: SellerPosLocationsBinding(),
    ),
    GetPage(
      name: Routes.posOrders,
      page: () => PosOrdersView(),
      binding: PosOrdersBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posPinLogin,
      page: () => PosPinLoginView(),
      binding: PosPinLoginBinding(),
      middlewares: [PosAccessMiddleware()],
    ),
    GetPage(
      name: Routes.posOpenRegister,
      page: () => PosOpenRegisterView(),
      binding: PosOpenRegisterBinding(),
      middlewares: [PosAccessMiddleware()],
    ),
    GetPage(
      name: Routes.posHeldSales,
      page: () => PosHeldSalesView(),
      binding: PosHeldSalesBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posDailyReport,
      page: () => PosDailyReportView(),
      binding: PosDailyReportBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posProducts,
      page: () => PosProductsView(),
      binding: PosProductsBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posSettings,
      page: () => PosSettingsView(),
      binding: PosSettingsBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posSaleDetail,
      page: () => PosSaleDetailView(),
      binding: PosSaleDetailBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posSessionReport,
      page: () => PosSessionReportView(),
      binding: PosSessionReportBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posSessionHistory,
      page: () => PosSessionHistoryView(),
      binding: PosSessionHistoryBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    GetPage(
      name: Routes.posAuditLog,
      page: () => PosAuditLogView(),
      binding: PosAuditLogBinding(),
      middlewares: [PosAccessMiddleware()],
    ),
    GetPage(
      name: Routes.posRangeReport,
      page: () => PosRangeReportView(),
      binding: PosRangeReportBinding(),
      middlewares: [PosAccessMiddleware()],
    ),
  ];
}
