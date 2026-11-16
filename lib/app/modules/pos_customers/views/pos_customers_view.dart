import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/pos_customers_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Browse-only view of the store's real past buyers. To attach a customer
/// to the current sale, use the picker sheet from the checkout cart footer
/// instead (PosCustomerPickerSheet) — this screen is for looking someone up
/// / reviewing order history, not for driving into an active sale.
class PosCustomersView extends StatelessWidget {
  PosCustomersView({super.key});

  final PosCustomersController c = Get.put(PosCustomersController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: 'Customers',
      body: Obx(() {
        if (c.isLoading.value) {
          return const SkeletonList(padding: EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6));
        }
        if (c.customers.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_2_outlined,
            title: 'No customers yet',
            message: 'They show up here after their first order.',
          );
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: p.accentFg,
          child: ListView.builder(
            controller: c.scrollController,
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
            itemCount: c.customers.length + (c.isLoadingMore.value ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= c.customers.length) {
                return Padding(
                  padding: const EdgeInsets.all(Space.s4),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: p.accentFg),
                    ),
                  ),
                );
              }
              return _CustomerTile(
                customer: c.customers[i],
                currencySymbol: c.currencySymbol.value,
              );
            },
          ),
        );
      }),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerModel customer;
  final String currencySymbol;
  const _CustomerTile({required this.customer, required this.currencySymbol});

  static const _segmentTones = {
    'vip': StatusTone.warning,
    'returning': StatusTone.accent,
    'at_risk': StatusTone.danger,
    'new': StatusTone.success,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final contact = customer.phone ?? customer.email ?? '';
    final name = customer.name.trim();
    final stack = MediaQuery.textScalerOf(context).scale(16) > 19;
    final spent = customer.orderCount == null
        ? null
        : Column(
            crossAxisAlignment: stack ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              AmountText(
                Money.format((customer.totalSpent ?? 0)),
                style: t.amountMd,
                color: p.textPrimary,
                animate: false,
              ),
              Text(
                '${customer.orderCount} order${customer.orderCount == 1 ? '' : 's'}',
                style: t.caption.copyWith(color: p.textMuted),
              ),
            ],
          );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          customer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.subtitle.copyWith(color: p.textPrimary),
        ),
        if (contact.isNotEmpty)
          Text(
            contact,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption.copyWith(color: p.textMuted),
          ),
        if (customer.segment != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: StatusBadge(
              customer.segment!,
              tone: _segmentTones[customer.segment] ?? StatusTone.neutral,
            ),
          ),
        if (stack && spent != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: spent,
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        radius: Radii.rMd,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: p.accentSoft,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: t.subtitle.copyWith(color: p.accentFg),
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(child: details),
            if (!stack && spent != null) ...[
              const SizedBox(width: Space.s3),
              spent,
            ],
          ],
        ),
      ),
    );
  }
}
