import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

/// The More tab: everything that is not selling, orders or stock, grouped, with the rows each role may open. Every row opens an
/// EXISTING screen behind its existing guard (owner gate / manager PIN / plan) — this tab only decides what is shown.
class PosMoreHubView extends StatelessWidget {
  const PosMoreHubView({super.key, this.access, this.unresolvedOverride});

  final PosAccess? access;
  final int? unresolvedOverride;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PosAccess>(
      future: access != null ? Future.value(access) : PosAccess.current(),
      builder: (context, snap) {
        final a = snap.data ?? PosAccess.cashier;
        // Obx only when there is something to observe (an Obx with no observable throws).
        if (unresolvedOverride == null && Get.isRegistered<PendingSaleSyncService>()) {
          final svc = Get.find<PendingSaleSyncService>();
          return Obx(() => _content(a, svc.unresolvedCount.value));
        }
        return _content(a, unresolvedOverride ?? 0);
      },
    );
  }

  Widget _content(PosAccess a, int unresolved) {
    return HubScaffold(
      title: 'More',
      listKey: const Key('moreHub'),
      children: [
        HubSection('This shift', [
          HubRow(icon: Icons.schedule_rounded, title: 'Shift summary', subtitle: 'Sales, cash and card for the open shift', onTap: () => Get.toNamed(Routes.posSessionReport)),
          HubRow(icon: Icons.pause_circle_outline_rounded, title: 'Held sales', subtitle: 'Resume or discard parked sales', onTap: () => Get.toNamed(Routes.posHeldSales)),
          HubRow(icon: Icons.sync_problem_rounded, title: 'Sync & needs attention', subtitle: 'Offline sales that are not on the server yet', badge: unresolved, onTap: () => Get.toNamed(Routes.posNeedsAttention)),
          HubRow(icon: Icons.cloud_off_rounded, title: 'Offline mode', subtitle: 'What works without internet and what is waiting to sync', onTap: () => Get.toNamed(Routes.posOfflineMode)),
        ]),
        HubSection('People', [
          HubRow(icon: Icons.groups_2_outlined, title: 'Customers', subtitle: 'Search, add, store credit and points', onTap: () => Get.toNamed(Routes.posCustomerDirectory)),
        ]),
        if (!a.canManage)
          HubSection('Stock', [
            HubRow(icon: Icons.inventory_rounded, title: 'Stock', subtitle: 'Look up quantities and low stock', onTap: () => Get.toNamed(Routes.posStockOverview)),
          ]),
        if (a.canManage)
          HubSection('Business', [
            HubRow(icon: Icons.inventory_rounded, title: 'Inventory', subtitle: 'Stock levels, history, counts and limits', onTap: () => Get.toNamed(Routes.posStockOverview)),
            HubRow(icon: Icons.local_shipping_outlined, title: 'Suppliers & purchase orders', subtitle: 'Orders, receiving, supplier returns and payables', onTap: () => Get.toNamed(Routes.posSupply)),
            HubRow(icon: Icons.history_rounded, title: 'Past buyers', subtitle: 'Who has ordered from the store, and what they spent', onTap: () => Get.toNamed(Routes.posCustomers), locked: true),
            HubRow(icon: Icons.bar_chart_rounded, title: 'Daily report', subtitle: 'Sales, tenders and top products', onTap: () => Get.toNamed(Routes.posDailyReport), locked: true),
            HubRow(icon: Icons.date_range_rounded, title: 'Date-range report', subtitle: 'Any period', onTap: () => Get.toNamed(Routes.posRangeReport), locked: true),
            HubRow(icon: Icons.inventory_2_outlined, title: 'Catalog', subtitle: 'Price, barcode, HS code, category, stock', onTap: () => Get.toNamed(Routes.posCatalog), locked: true),
            HubRow(icon: Icons.history_toggle_off_rounded, title: 'Shift history', subtitle: 'Past shifts and cash differences', onTap: () => Get.toNamed(Routes.posSessionHistory), locked: true),
          ]),
        if (a.canManage)
          const HubSection('Coming soon', [
            HubRow(icon: Icons.payments_outlined, title: 'Expenses & daybook', soon: true),
            HubRow(icon: Icons.badge_outlined, title: 'Attendance', soon: true),
          ]),
        if (a.canManage)
          HubSection('Team & security', [
            HubRow(icon: Icons.manage_accounts_outlined, title: 'Team & registers', subtitle: 'Employees, PINs and registers', onTap: () => Get.toNamed(Routes.sellerPosManagement), locked: true),
            HubRow(icon: Icons.devices_other_rounded, title: 'Devices', subtitle: 'Registered tills', onTap: () => Get.toNamed(Routes.posDevices), locked: true),
            HubRow(icon: Icons.shield_outlined, title: 'Audit log', subtitle: 'Who did what, and when', onTap: () => Get.toNamed(Routes.posAuditLog), locked: true),
            HubRow(icon: Icons.badge_outlined, title: 'Store tax profile', subtitle: 'NTN, STRN, returns policy', onTap: () => Get.toNamed(Routes.posTaxProfile), locked: true),
            HubRow(icon: Icons.verified_user_outlined, title: 'Business verification', subtitle: 'Needed for Raast QR payments', onTap: () => Get.toNamed(Routes.posKyb), locked: true),
            HubRow(icon: Icons.workspace_premium_outlined, title: 'Plan status', subtitle: 'Your POS plan', onTap: () => Get.toNamed(Routes.posPlanStatus), locked: true),
          ]),
        HubSection('App', [
          HubRow(icon: Icons.privacy_tip_outlined, title: 'Permissions', subtitle: 'Camera, Bluetooth printer, local network', onTap: () => Get.toNamed(Routes.posPermissions)),
          HubRow(icon: Icons.settings_outlined, title: 'Settings', subtitle: a.canManage ? 'Receipt, printer, tax, auto-lock, shift close' : 'Printer, sound, auto-lock', onTap: () => Get.toNamed(Routes.posSettings)),
        ]),
      ],
    );
  }
}
