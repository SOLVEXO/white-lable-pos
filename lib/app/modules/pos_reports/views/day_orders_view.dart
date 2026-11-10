import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/day_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

String _saleMoney(PosSaleModel s) => Money.format(s.total, currency: s.currency, exponent: s.currencyExponent);
String _hm(DateTime d) => '${d.toLocal().hour.toString().padLeft(2, '0')}:${d.toLocal().minute.toString().padLeft(2, '0')}';

/// The sales of one store day, newest first; a sale opens its detail.
class DayOrdersView extends StatefulWidget {
  const DayOrdersView({super.key, required this.date, this.controller});
  final String date;
  final DayOrdersController? controller;
  @override
  State<DayOrdersView> createState() => _DayOrdersViewState();
}

class _DayOrdersViewState extends State<DayOrdersView> {
  late final String _tag = 'dayOrders_${identityHashCode(this)}';
  late final DayOrdersController c = widget.controller ?? Get.put(DayOrdersController(date: widget.date), tag: _tag);

  @override
  void dispose() {
    if (widget.controller == null) Get.delete<DayOrdersController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Sales on ${storeDayLabel(widget.date)}',
      body: Obx(() {
        if (!reportsOnlineRx().value && c.sales.isEmpty) return const ReportsNeedsInternet(subject: 'The list of sales');
        if (c.loading.value && c.sales.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('dayOrdersLoading')));
        if (c.error.value != null && c.sales.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.load);
        if (c.sales.isEmpty) return const EmptyState(key: Key('dayOrdersEmpty'), icon: Icons.receipt_long_outlined, title: 'No sales', message: 'Nothing was sold on this day.');
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) c.loadMore();
            return false;
          },
          child: ListView(
            key: const Key('dayOrdersList'),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              Text('${c.total.value} sale${c.total.value == 1 ? '' : 's'} on this store day', style: t.caption.copyWith(color: p.textSecondary)),
              const SizedBox(height: Space.s2),
              for (final s in c.sales)
                ReportRow(
                  key: Key('daySale_${s.id}'),
                  title: s.saleNumber.isEmpty ? 'Sale' : s.saleNumber,
                  subtitle: [_hm(s.createdAt), if ((s.employeeName ?? '').isNotEmpty) s.employeeName!, s.paymentMethod].join(' · '),
                  value: _saleMoney(s),
                  detail: s.status == 'completed' ? null : s.status.replaceAll('_', ' '),
                  onTap: () => Get.toNamed(Routes.posSaleDetail, arguments: s.id),
                ),
              if (c.loadingMore.value)
                const Center(
                  child: Padding(padding: EdgeInsets.all(Space.s3), child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
        );
      }),
    );
  }
}
