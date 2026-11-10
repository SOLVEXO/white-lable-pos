import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_movement_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_movement_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Cash & expenses. Everyone: cash in / out on the open shift (works offline), expenses (their own for a cashier) and the daybook (their own shifts for a
/// cashier). What each screen shows is the server's decision. A small badge counts cash entries waiting to sync.
class CashHomeView extends StatelessWidget {
  const CashHomeView({super.key});

  Future<void> _move(String type) async {
    final o = await CashMovementSheet.open(type: type);
    if (o == null) return;
    CustomAppSnackbar.success(o == CashOutcome.queued ? 'Saved on this device. It will sync when the till is online.' : (type == 'cash_in' ? 'Cash in recorded.' : 'Cash out recorded.'));
  }

  Widget _gap(Widget w) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s2),
    child: w,
  );

  @override
  Widget build(BuildContext context) {
    final queue = cashQueue();
    return InvScaffold(
      title: 'Cash & expenses',
      body: ListView(
        key: const Key('cashHome'),
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        children: [
          if (queue != null)
            Obx(
              () => queue.unresolvedCount.value == 0
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: Space.s3),
                      child: Wrap(
                        spacing: Space.s2,
                        runSpacing: Space.s1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          WaitingToSyncBadge(count: queue.pendingCount.value),
                          if (queue.failedCount.value > 0)
                            TextButton(key: const Key('cashNeedsAttention'), onPressed: () => Get.toNamed(Routes.posNeedsAttention), child: Text('${queue.failedCount.value} need attention')),
                        ],
                      ),
                    ),
            ),
          _gap(HubRow(key: const Key('cashIn'), icon: Icons.south_west_rounded, title: 'Cash in', subtitle: 'Float top-up, owner injection, other', onTap: () => _move('cash_in'))),
          _gap(HubRow(key: const Key('cashOut'), icon: Icons.north_east_rounded, title: 'Cash out', subtitle: 'Bank deposit, safe drop, petty cash, owner draw', onTap: () => _move('cash_out'))),
          _gap(
            HubRow(
              key: const Key('cashExpenses'),
              icon: Icons.receipt_long_outlined,
              title: 'Expenses',
              subtitle: 'Record and review expenses, with receipts',
              onTap: () => Get.toNamed(Routes.posCashExpenses),
            ),
          ),
          _gap(
            HubRow(
              key: const Key('cashDaybook'),
              icon: Icons.menu_book_outlined,
              title: 'Daybook',
              subtitle: 'Every cash movement of a day, shift by shift',
              onTap: () => Get.toNamed(Routes.posCashDaybook),
            ),
          ),
        ],
      ),
    );
  }
}
