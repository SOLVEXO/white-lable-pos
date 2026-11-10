import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_movement_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/expense_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Expenses of a period: total per category, status chips and every expense (a cashier sees only their own: the server filters). Adding one works
/// offline for a drawer expense; the list itself needs internet.
class ExpenseListView extends StatelessWidget {
  ExpenseListView({super.key, ExpenseListController? controller}) : c = controller ?? Get.put(ExpenseListController());
  final ExpenseListController c;

  Future<void> _add() async {
    final o = await ExpenseFormSheet.open();
    if (o == null) return;
    CustomAppSnackbar.success(o == CashOutcome.queued ? 'Saved on this device. It will sync when the till is online.' : 'Expense saved.');
    await c.load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Expenses',
      actions: [IconButton(key: const Key('expenseAdd'), tooltip: 'Add expense', icon: const Icon(Icons.add_rounded), onPressed: _add)],
      body: Obx(() {
        if (!cashOnlineRx().value) return const CashNeedsInternet(subject: 'The expense list');
        if (c.loading.value && c.items.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('cashLoading')));
        if (c.error.value != null && c.items.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.load);
        final total = cashMoney(c.totalMinor, c.cur.value);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  key: const Key('expensePeriods'),
                  spacing: Space.s2,
                  runSpacing: Space.s1,
                  children: [
                    for (final per in ExpensePeriod.values)
                      ChoiceChip(key: Key('expensePeriod_${per.name}'), label: Text(per.label), selected: c.period.value == per, onSelected: (_) => c.setPeriod(per)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  key: const Key('expenseStatuses'),
                  spacing: Space.s2,
                  runSpacing: Space.s1,
                  children: [
                    for (final (id, label) in ExpenseStatus.filters) ChoiceChip(key: Key('expenseStatus_$id'), label: Text(label), selected: c.status.value == id, onSelected: (_) => c.setStatus(id)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: ListView(
                  key: const Key('expenseList'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                  children: [
                    if (c.totals.isNotEmpty && total != null)
                      AppCard(
                        key: const Key('expenseTotals'),
                        radius: Radii.rMd,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total (not counting rejected)', style: t.caption.copyWith(color: p.textSecondary)),
                            AmountText(total, key: const Key('expenseTotal'), style: t.amountLg, animate: false),
                            const SizedBox(height: Space.s2),
                            for (final e in (c.totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                              if (cashMoney(e.value, c.cur.value) != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: Space.s1),
                                  child: Row(
                                    key: Key('expenseCat_${e.key}'),
                                    children: [
                                      Expanded(
                                        child: Text(cashCategoryLabel(e.key), style: t.body.copyWith(color: p.textSecondary)),
                                      ),
                                      Text(cashMoney(e.value, c.cur.value)!, style: t.amountMd.copyWith(color: p.textPrimary)),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Space.s3),
                    if (c.items.isEmpty)
                      const EmptyState(icon: Icons.receipt_long_outlined, title: 'No expenses', message: 'Expenses in this period and status will show here.')
                    else
                      for (final e in c.items)
                        ExpenseTile(
                          expense: e,
                          cur: c.cur.value,
                          onTap: () => Get.toNamed(Routes.posCashExpense, arguments: {'expenseId': e.id})?.then((_) => c.load()),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
