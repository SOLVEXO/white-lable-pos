import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Money text in the response's own currency, or null when the amount or the currency was not stated (nothing is rendered then).
String? cashMoney(int? minor, InvCur? cur) => supplyMoney(minor, cur);

/// "Needs internet": expenses lists, the daybook and every decision need the server (a drawer cash in / out and a drawer expense do not).
class CashNeedsInternet extends StatelessWidget {
  const CashNeedsInternet({super.key, this.subject = 'This screen'});
  final String subject;
  @override
  Widget build(BuildContext context) => EmptyState(
    key: const Key('cashNeedsInternet'),
    icon: Icons.wifi_off_rounded,
    title: 'Needs internet',
    message: '$subject needs an internet connection. Connect the till and it will load by itself.',
    tone: context.palette.warningFg,
  );
}

/// "3 waiting to sync": cash entries made offline that have not reached the server yet.
class WaitingToSyncBadge extends StatelessWidget {
  const WaitingToSyncBadge({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => StatusBadge('Waiting to sync · $count', tone: StatusTone.warning, icon: Icons.sync_rounded);
}

StatusTone expenseTone(String s) => switch (s) {
  ExpenseStatus.approved => StatusTone.success,
  ExpenseStatus.rejected => StatusTone.danger,
  _ => StatusTone.neutral,
};

class ExpenseStatusBadge extends StatelessWidget {
  const ExpenseStatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => StatusBadge(ExpenseStatus.label(status), tone: expenseTone(status));
}

/// One expense row: category, payee / note, when, method and the amount (money only when stated), and its status.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, required this.cur, required this.onTap});
  final Expense expense;
  final InvCur? cur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final money = cashMoney(expense.amountMinor, expense.cur ?? cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('expense_${expense.id}'),
        radius: Radii.rMd,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(cashCategoryLabel(expense.category), style: t.subtitle.copyWith(color: p.textPrimary)),
                      ExpenseStatusBadge(expense.status),
                    ],
                  ),
                  if (expense.payee != null)
                    Text(
                      expense.payee!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: p.textSecondary),
                    ),
                  if (money != null)
                    Text(
                      money,
                      key: Key('expenseAmount_${expense.id}'),
                      style: t.amountMd.copyWith(color: p.textPrimary),
                    ),
                  Text(
                    [
                      expense.number,
                      invDateTime(expense.occurredAt),
                      expenseMethodLabel(expense.method),
                      if (expense.employeeName != null) 'by ${expense.employeeName}',
                      if (expense.hasReceipt) 'Receipt',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    style: t.caption.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
