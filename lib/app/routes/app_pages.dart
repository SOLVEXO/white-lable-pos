import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/pulse_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/reports_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/time_zone_view.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/config/debug_launch_params.dart';
import 'package:solvexo_pos/core/design/gallery/design_gallery_view.dart';
import 'package:solvexo_pos/app/middleware/auth_middleware.dart';
import 'package:solvexo_pos/app/middleware/owner_access_middleware.dart';
import '../modules/pos_device/views/device_setup_view.dart';
import '../modules/pos_device/views/delete_account_view.dart';
import '../modules/pos_plan/views/pos_plan_inactive_view.dart';
import '../modules/pos_plan/views/pos_plan_status_view.dart';
import '../modules/pos_device/views/owner_gate_view.dart';
import '../modules/pos_device/views/pos_devices_view.dart';
import '../modules/splash_screen/bindings/splash_screen_binding.dart';
import '../modules/splash_screen/views/splash_screen_view.dart';
import '../modules/onboarding/bindings/onboarding_binding.dart';
import '../modules/onboarding/views/onboarding_view.dart';
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
import '../modules/pos_inventory/bindings/pos_inventory_binding.dart';
import '../modules/pos_inventory/bindings/pos_stock_binding.dart';
import '../modules/pos_inventory/views/inv_count_view.dart';
import '../modules/pos_inventory/views/inv_detail_view.dart';
import '../modules/pos_inventory/views/inv_limits_view.dart';
import '../modules/pos_inventory/views/inv_movements_view.dart';
import '../modules/pos_inventory/views/inv_overview_view.dart';
import '../modules/pos_inventory/views/inv_stock_list_view.dart';
import '../modules/pos_inventory/views/pos_inventory_view.dart';
import '../modules/pos_needs_attention/bindings/pos_needs_attention_binding.dart';
import '../modules/pos_documents/views/tax_invoice_view.dart';
import '../modules/pos_returns/views/pos_return_view.dart';
import '../modules/pos_catalog/views/pos_catalog_view.dart';
import '../modules/pos_tax_profile/pos_tax_profile.dart';
import '../modules/pos_kyb/bindings/pos_kyb_binding.dart';
import '../modules/pos_kyb/views/pos_kyb_view.dart';
import '../modules/pos_offline/bindings/pos_offline_binding.dart';
import '../modules/pos_offline/views/pos_offline_view.dart';
import '../modules/pos_permissions/bindings/pos_permissions_binding.dart';
import '../modules/pos_permissions/views/pos_permissions_view.dart';
import '../modules/pos_needs_attention/views/pos_needs_attention_view.dart';
import '../modules/pos_stock_activity/bindings/pos_stock_activity_binding.dart';
import '../modules/pos_stock_activity/views/pos_stock_activity_view.dart';
import '../modules/pos_customers/bindings/pos_customers_binding.dart';
import '../modules/pos_customers/views/customer_list_view.dart';
import '../modules/pos_customers/views/customer_profile_view.dart';
import '../modules/pos_customers/views/pos_customers_view.dart';
import '../data/models/pos/pos_team_models.dart';
import '../modules/pos_team/views/attendance_view.dart';
import '../modules/pos_team/views/clock_view.dart';
import '../modules/pos_team/views/record_view.dart';
import '../modules/pos_team/views/roster_view.dart';
import '../modules/pos_team/views/team_report_view.dart';
import '../modules/pos_cash/views/cash_home_view.dart';
import '../modules/pos_cash/views/daybook_view.dart';
import '../modules/pos_cash/views/expense_detail_view.dart';
import '../modules/pos_cash/views/expense_list_view.dart';
import '../modules/pos_supply/views/payables_view.dart';
import '../modules/pos_supply/views/po_detail_view.dart';
import '../modules/pos_supply/views/po_form_view.dart';
import '../modules/pos_supply/views/po_list_view.dart';
import '../modules/pos_supply/views/receive_view.dart';
import '../modules/pos_supply/views/supplier_ledger_view.dart';
import '../modules/pos_supply/views/supplier_list_view.dart';
import '../modules/pos_supply/views/supplier_profile_view.dart';
import '../modules/pos_supply/views/supply_home_view.dart';
part 'app_routes.dart';

class AppPages {
  /// Debug builds may start elsewhere: `--dart-define=INITIAL_ROUTE=/design-gallery` or an `INITIAL_ROUTE=` line in
  /// the DebugLaunchParams file. Release builds always start at the splash.
  static final String initialRoute = kDebugMode ? _debugInitialRoute() : Routes.splashScreen;

  static String _debugInitialRoute() {
    const defined = String.fromEnvironment('INITIAL_ROUTE');
    if (defined.isNotEmpty) return defined;
    final fromFile = DebugLaunchParams.get('INITIAL_ROUTE');
    return (fromFile != null && fromFile.isNotEmpty) ? fromFile : Routes.splashScreen;
  }

  static final routes = [
    if (kDebugMode) GetPage(name: Routes.designGallery, page: () => const DesignGalleryView()),
    GetPage(
      name: Routes.splashScreen,
      page: () => const SplashScreenView(),
      binding: SplashScreenBinding(),
    ),
    GetPage(
      name: Routes.onboarding,
      page: () => const OnboardingView(),
      binding: OnboardingBinding(),
    ),
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
      middlewares: [OwnerAccessMiddleware()],
    ),
    GetPage(
      name: Routes.posHome,
      page: () => PosMainView(),
      binding: PosBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)],
    ),
    GetPage(
      name: Routes.sellerPosManagement,
      page: () => SellerPosManagementView(),
      binding: SellerPosManagementBinding(),
      middlewares: [OwnerAccessMiddleware()],
    ),
    GetPage(
      name: Routes.sellerPosLocations,
      page: () => SellerPosLocationsView(),
      binding: SellerPosLocationsBinding(),
      middlewares: [OwnerAccessMiddleware()],
    ),
    // 5D — shared-device security
    GetPage(name: Routes.posDeviceSetup, page: () => const DeviceSetupView()),
    GetPage(name: Routes.posOwnerGate, page: () => const OwnerGateView()),
    GetPage(name: Routes.posDeleteAccount, page: () => const DeleteAccountView(), middlewares: [OwnerAccessMiddleware()]),
    GetPage(name: Routes.posDevices, page: () => const PosDevicesView(), middlewares: [OwnerAccessMiddleware()]),
    GetPage(
      name: Routes.posOrders,
      page: () => PosOrdersView(),
      binding: PosOrdersBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)],
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
      middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)],
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
      middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)],
    ),
    GetPage(
      name: Routes.posSaleDetail,
      page: () => PosSaleDetailView(),
      binding: PosSaleDetailBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)],
    ),
    // G2.5: the tax invoice (+ credit notes) and the return flow; reachable in restricted mode too (returns must work after a plan lapses)
    GetPage(name: Routes.posTaxInvoice, page: () => TaxInvoiceView(), middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)]),
    // G2.6: POS catalog edits (a manager's PIN per change) and the owner's store tax profile
    GetPage(name: Routes.posCatalog, page: () => PosCatalogView(), middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)]),
    GetPage(name: Routes.posTaxProfile, page: () => PosTaxProfileView(), middlewares: [OwnerAccessMiddleware()]),
    GetPage(name: Routes.posReturn, page: () => PosReturnView(), middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)]),
    GetPage(
      name: Routes.posSessionReport,
      page: () => PosSessionReportView(),
      binding: PosSessionReportBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)],
    ),
    GetPage(
      name: Routes.posSessionHistory,
      page: () => PosSessionHistoryView(),
      binding: PosSessionHistoryBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true, allowWhenRestricted: true)],
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
    // G3.1 inventory: overview, stock list / low stock, item detail, movement history, stock count, approval limits (the server enforces who may do what)
    GetPage(name: Routes.posStockOverview, page: () => InvOverviewView(), binding: PosStockOverviewBinding(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posStockList, page: () => InvStockListView(lowOnly: (Get.arguments is Map && Get.arguments['lowOnly'] == true), initialFilter: (Get.arguments is Map ? Get.arguments['filter'] as String? : null) ?? 'all'), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posStockDetail, page: () => InvDetailView(variantId: '${(Get.arguments as Map)['variantId']}', role: (Get.arguments as Map)['role'] as String?), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posStockMovements, page: () => InvMovementsView(), binding: PosStockMovementsBinding(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posStockCount, page: () => InvCountView(), binding: PosStockCountBinding(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posStockLimits, page: () => InvLimitsView(), binding: PosStockLimitsBinding(), middlewares: [PosAccessMiddleware()]),
    GetPage(
      name: Routes.posInventory,
      page: () => PosInventoryView(),
      binding: PosInventoryBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true)],
    ),
    // Reachable in restricted mode too: unsynced sales must be resolvable whatever the plan says.
    GetPage(
      name: Routes.posNeedsAttention,
      page: () => PosNeedsAttentionView(),
      binding: PosNeedsAttentionBinding(),
      middlewares: [PosAccessMiddleware()],
    ),
    // Owner-only business verification (G2.2 owner endpoints): behind the owner gate, screenshots blocked, wiped on background/lock
    GetPage(
      name: Routes.posKyb,
      page: () => PosKybView(),
      binding: PosKybBinding(),
      middlewares: [OwnerAccessMiddleware()],
    ),
    // What works offline, what doesn't, the sync queue — reachable in restricted mode too (it only reads and syncs)
    GetPage(
      name: Routes.posOfflineMode,
      page: () => PosOfflineView(),
      binding: PosOfflineBinding(),
      middlewares: [PosAccessMiddleware()],
    ),
    // Camera / Bluetooth / local network explainer: reachable right after device setup (before the PIN login, so no access middleware) and from More
    GetPage(
      name: Routes.posPermissions,
      page: () => PosPermissionsView(),
      binding: PosPermissionsBinding(),
    ),
    GetPage(
      name: Routes.posStockActivity,
      page: () => PosStockActivityView(),
      binding: PosStockActivityBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true), OwnerAccessMiddleware()],
    ),
    GetPage(
      name: Routes.posCustomers,
      page: () => PosCustomersView(),
      binding: PosCustomersBinding(),
      middlewares: [PosAccessMiddleware(requireActiveSession: true), OwnerAccessMiddleware()],
    ),
    // G3.3 customers: the directory and a profile (every role; the server decides what a role sees / may change). The legacy past-buyers list above stays on /pos/customers.
    GetPage(name: Routes.posCustomerDirectory, page: () => CustomerListView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posCustomerProfile, page: () => CustomerProfileView(customerId: '${(Get.arguments as Map)['customerId']}'), middlewares: [PosAccessMiddleware()]),
    // G3.4 supply: the server decides who may do what (a cashier only receives against approved orders and never sees a cost)
    GetPage(name: Routes.posSupply, page: () => const SupplyHomeView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplyOrders, page: () => PoListView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplyOrder, page: () => PoDetailView(orderId: '${(Get.arguments as Map)['orderId']}'), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplyOrderForm, page: () => PoFormView(orderId: Get.arguments is Map ? (Get.arguments as Map)['orderId'] as String? : null, supplierId: Get.arguments is Map ? (Get.arguments as Map)['supplierId'] as String? : null), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplyReceive, page: () => ReceiveView(orderId: Get.arguments is Map ? (Get.arguments as Map)['orderId'] as String? : null, supplierId: Get.arguments is Map ? (Get.arguments as Map)['supplierId'] as String? : null), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplySuppliers, page: () => SupplierListView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplySupplier, page: () => SupplierProfileView(supplierId: '${(Get.arguments as Map)['supplierId']}'), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplyPayables, page: () => PayablesView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posSupplyLedger, page: () => SupplierLedgerView(supplierId: '${(Get.arguments as Map)['supplierId']}'), middlewares: [PosAccessMiddleware()]),
    // G3.5 cash & expenses: cash in / out (works offline), expenses with a private receipt photo, the daybook. The server decides who may do what.
    GetPage(name: Routes.posCash, page: () => const CashHomeView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posCashExpenses, page: () => ExpenseListView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posCashExpense, page: () => ExpenseDetailView(expenseId: '${(Get.arguments as Map)['expenseId']}'), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posCashDaybook, page: () => DaybookView(), middlewares: [PosAccessMiddleware()]),
    // G3.6 team: the clock (works offline), attendance history, one record, the roster, the attendance report. The server decides who may do what.
    GetPage(name: Routes.posTeamClock, page: () => const TeamClockView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posTeamAttendance, page: () => AttendanceView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posTeamRecord, page: () => AttendanceRecordView(record: (Get.arguments as Map)['record'] as AttendanceRecord), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posTeamRoster, page: () => RosterView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posTeamReport, page: () => TeamReportView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posPulse, page: () => const PulseView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posReports, page: () => const ReportsHubView(), middlewares: [PosAccessMiddleware()]),
    GetPage(
      name: Routes.posReport,
      page: () => ReportView(
        kind: ReportKind.byPath(Get.arguments is Map ? (Get.arguments as Map)['kind'] as String? : null) ?? ReportKind.cashiers,
        employeeId: Get.arguments is Map ? (Get.arguments as Map)['employeeId'] as String? : null,
      ),
      middlewares: [PosAccessMiddleware()],
    ),
    GetPage(name: Routes.posStoreTimeZone, page: () => const TimeZoneView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posPlanInactive, page: () => const PosPlanInactiveView(), middlewares: [PosAccessMiddleware()]),
    GetPage(name: Routes.posPlanStatus, page: () => const PosPlanStatusView(), middlewares: [PosAccessMiddleware(), OwnerAccessMiddleware()]),
  ];
}
