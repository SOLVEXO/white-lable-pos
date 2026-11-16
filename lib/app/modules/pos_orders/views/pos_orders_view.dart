import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_stats_row.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transaction_card.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transactions_empty.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transactions_shimmer.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_app_bar.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosOrdersView extends StatelessWidget {
  PosOrdersView({super.key});

  final PosOrdersController controller = Get.put(PosOrdersController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: Center(
        // tablet: a centred column, not a stretched phone (G6.3)
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(
        children: [
          const PosAppBar(title: 'Transactions'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s1),
            child: TextField(
              key: const Key('ordersSearch'),
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.characters,
              style: context.type.body.copyWith(color: p.textPrimary),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, color: p.textMuted),
                hintText: 'Find by receipt no. (OFF-…, INV-…, CN-…)',
                isDense: true,
              ),
              onSubmitted: controller.searchByReceipt,
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const PosTransactionsShimmer();
              }
              final txns = controller.filteredSales;

              return RefreshIndicator(
                onRefresh: controller.refreshData,
                color: p.accent,
                child: txns.isEmpty
                    ? LayoutBuilder(
                        builder: (_, box) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: box.maxHeight),
                            child: const PosTransactionsEmpty(),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        controller: controller.scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FilterHeader(controller: controller),
                            PosStatsRow(controller: controller),
                            Divider(height: 1, color: p.border),
                            ListView.separated(
                              padding: const EdgeInsets.all(Space.s4),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: txns.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: Space.s3),
                              itemBuilder: (_, i) => PosTransactionCard(
                                sale: txns[i],
                                controller: controller,
                              ),
                            ),
                            if (controller.isLoadingMore.value)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: Space.s4),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: p.accent,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              );
            }),
          ),
        ],
      )),
      ),
    );
  }
}

class _FilterHeader extends StatelessWidget {
  final PosOrdersController controller;
  const _FilterHeader({required this.controller});

  static const _filters = ['All', 'cash', 'card', 'other'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.s2,
            children: [
              Text(
                'Transactions',
                style: context.type.title.copyWith(color: p.textPrimary),
              ),
              _buildFilterRow(context),
            ],
          ),
          _DateFilterChip(controller: controller),
          // G5.1: managers filter by cashier / register (store-wide)
          Obx(() => controller.isManager.value ? Padding(padding: const EdgeInsets.only(top: Space.s1), child: OrdersPeopleFilters(controller: controller)) : const SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
          Obx(
            () => AppPill(
              onTap: () => _showFilterSheet(context),
              selected: true,
              label: controller.paymentFilter.value == 'All'
                  ? 'All'
                  : controller.paymentFilter.value.capitalizeFirst ??
                        '',
              trailingIcon: Icons.keyboard_arrow_down_rounded,
            ),
          ),
          const SizedBox(width: Space.s2),
          Obx(
            () => AppPill(
              onTap: () => _showStatusFilterSheet(context),
              label: controller.statusFilter.value == 'All'
                  ? 'Status'
                  : controller.statusFilter.value.capitalizeFirst ?? '',
              trailingIcon: Icons.keyboard_arrow_down_rounded,
            ),
          ),
      ],
    );
  }

  Widget _option(BuildContext context, {required String label, required bool selected, required VoidCallback onTap}) {
    final p = context.palette;
    return ListTile(
      onTap: onTap,
      minTileHeight: Space.minTouch,
      shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
      title: Text(label, style: context.type.body.copyWith(color: p.textPrimary)),
      trailing: selected ? Icon(Icons.check_rounded, color: p.accentFg) : null,
    );
  }

  void _showStatusFilterSheet(BuildContext context) {
    AppBottomSheet.show<void>(
      context,
      title: 'Filter by Status',
      useRootNavigator: false,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...PosOrdersController.statusFilters.map(
            (s) => Obx(
              () => _option(
                context,
                onTap: () {
                  controller.setStatusFilter(s);
                  Navigator.pop(context);
                },
                label: s == 'All'
                    ? 'All Statuses'
                    : (s.capitalizeFirst ?? s).replaceAll('_', ' '),
                selected: controller.statusFilter.value == s,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    AppBottomSheet.show<void>(
      context,
      title: 'Filter by Payment',
      useRootNavigator: false,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._filters.map(
            (f) => Obx(
              () => _option(
                context,
                onTap: () {
                  controller.setPaymentFilter(f);
                  Navigator.pop(context);
                },
                label: f == 'All' ? 'All Methods' : (f.capitalizeFirst ?? f),
                selected: controller.paymentFilter.value == f,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateFilterChip extends StatelessWidget {
  final PosOrdersController controller;
  const _DateFilterChip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final active = controller.fromDate.value != null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPill(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now,
                initialDateRange: controller.fromDate.value != null && controller.toDate.value != null
                    ? DateTimeRange(start: controller.fromDate.value!, end: controller.toDate.value!)
                    : null,
              );
              if (picked != null) {
                controller.setDateRange(picked.start, picked.end);
              }
            },
            selected: active,
            icon: Icons.calendar_today_outlined,
            label: controller.dateFilter.value,
          ),
          if (active)
            IconButton(
              tooltip: 'Clear dates',
              constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
              onPressed: () => controller.setDateRange(null, null),
              icon: Icon(Icons.close_rounded, size: IconSizes.sm, color: p.accentFg),
            ),
        ],
      );
    });
  }
}

/// G5.1 — the managers' cashier / register filters on Orders (token-styled; store-wide while set).
class OrdersPeopleFilters extends StatelessWidget {
  const OrdersPeopleFilters({super.key, required this.controller});
  final PosOrdersController controller;

  Future<void> _pick(BuildContext context, String title, Future<List<({String id, String name})>> Function() load, ({String id, String name})? current, void Function(({String id, String name})?) set) async {
    final options = await load();
    if (!context.mounted) return;
    final picked = await AppBottomSheet.showGet<({String id, String name})?>(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(key: const Key('ordersPickAll'), title: const Text('Everyone / all'), trailing: current == null ? const Icon(Icons.check_rounded) : null, onTap: () => Get.back(result: (id: '', name: ''))),
          for (final o in options)
            ListTile(key: Key('ordersPick_${o.id}'), title: Text(o.name), trailing: current?.id == o.id ? const Icon(Icons.check_rounded) : null, onTap: () => Get.back(result: o)),
          if (options.isEmpty) const Padding(padding: EdgeInsets.all(Space.s4), child: Text('Nothing to choose from.')),
        ],
      ),
      title: title,
    );
    if (picked == null) return; // dismissed
    set(picked.id.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final c = controller.cashierFilter.value;
      final r = controller.registerFilter.value;
      return Wrap(
        spacing: Space.s2,
        runSpacing: Space.s1,
        children: [
          InputChip(
            key: const Key('ordersCashierFilter'),
            avatar: Icon(Icons.person_outline_rounded, size: 16, color: p.textSecondary),
            label: Text(c == null ? 'Cashier: all' : 'Cashier: ${c.name}'),
            selected: c != null,
            onPressed: () => _pick(context, 'Cashier', controller.cashierOptions, c, controller.setCashierFilter),
            onDeleted: c == null ? null : () => controller.setCashierFilter(null),
          ),
          InputChip(
            key: const Key('ordersRegisterFilter'),
            avatar: Icon(Icons.point_of_sale_rounded, size: 16, color: p.textSecondary),
            label: Text(r == null ? 'Register: all' : 'Register: ${r.name}'),
            selected: r != null,
            onPressed: () => _pick(context, 'Register', controller.registerOptions, r, controller.setRegisterFilter),
            onDeleted: r == null ? null : () => controller.setRegisterFilter(null),
          ),
          if (c != null || r != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Whole store, not only this shift', key: const Key('ordersStoreWide'), style: context.type.caption.copyWith(color: p.textMuted))),
        ],
      );
    });
  }
}
