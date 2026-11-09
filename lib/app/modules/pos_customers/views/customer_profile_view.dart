import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_profile_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/credit_adjust_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One customer: balances, points and tier, orders and last visit, recent sales. Managers and owners also see lifetime spend, the identity
/// details and the store-credit history, and may edit the customer or adjust the credit. A cashier sees none of those.
class CustomerProfileView extends StatelessWidget {
  CustomerProfileView({super.key, required String customerId, CustomerProfileController? controller}) : c = controller ?? Get.put(CustomerProfileController(customerId: customerId), tag: customerId);
  final CustomerProfileController c;

  Future<void> _edit(CustomerProfile p) async {
    final saved = await CustomerFormSheet.open(existing: p.customer);
    if (saved != null) c.applyEdit(saved);
  }

  Future<void> _adjust(CustomerProfile p) async {
    final cur = p.cur;
    if (cur == null) return;
    final ok = await CreditAdjustSheet.open(customerId: p.customer.id, exponent: cur.exponent, currencyCode: cur.code);
    if (ok == true) await c.load();
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Customer',
      maxWidth: 760,
      body: Obx(() {
        final p = c.profile.value;
        if (c.loading.value && p == null) return const Center(child: CircularProgressIndicator(key: Key('customersLoading')));
        if (p == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        return RefreshIndicator(onRefresh: c.load, child: _content(context, p));
      }),
    );
  }

  Widget _content(BuildContext context, CustomerProfile p) {
    final pal = context.palette;
    final t = context.type;
    final cur = p.cur;
    final manage = c.canManage;
    final online = customersOnlineRx().value;
    final customer = p.customer;
    Widget stat(Key key, String label, String value) => AppCard(
      key: key,
      radius: Radii.rMd,
      semanticLabel: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.caption.copyWith(color: pal.textSecondary)),
          const SizedBox(height: Space.s1),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: t.amountLg.copyWith(color: pal.textPrimary))),
        ],
      ),
    );
    return ListView(
      key: const Key('customerProfileList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        if (p.asOf != null) Padding(padding: const EdgeInsets.only(bottom: Space.s3), child: CustomerAsOfBanner(asOf: p.asOf!, subject: 'this customer')),
        Row(
          children: [
            CustomerAvatar(customer, radius: 28),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.name, key: const Key('profileName'), style: t.headline.copyWith(color: pal.textPrimary)),
                  if (customer.subtitle.isNotEmpty) Text(customer.subtitle, style: t.bodySmall.copyWith(color: pal.textMuted)),
                  if (customer.group != null) Text(customer.group!, style: t.caption.copyWith(color: pal.textMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        LayoutBuilder(
          builder: (context, box) {
            const gap = Space.s3;
            final cols = box.maxWidth >= 560 ? 3 : 2;
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            Widget sized(Widget child) => SizedBox(width: w, child: child);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                if (p.creditBalanceMinor != null && cur != null) sized(stat(const Key('profileCredit'), 'Store credit', invMoney(p.creditBalanceMinor!, cur))),
                sized(stat(const Key('profilePoints'), p.loyaltyTier == null ? 'Points' : 'Points · ${loyaltyTierLabel(p.loyaltyTier)}', '${p.loyaltyPoints}')),
                sized(stat(const Key('profileOrders'), 'Orders', '${p.orderCount}')),
                if (p.lastVisitAt != null) sized(stat(const Key('profileLastVisit'), 'Last visit', invDate(p.lastVisitAt))),
                if (manage && p.lifetimeSpendMinor != null && cur != null) sized(stat(const Key('profileLifetime'), 'Lifetime spend', invMoney(p.lifetimeSpendMinor!, cur))),
              ],
            );
          },
        ),
        if (manage) ...[
          const SizedBox(height: Space.s4),
          Row(
            children: [
              Expanded(
                child: AppButton(key: const Key('profileEdit'), label: 'Edit', icon: Icons.edit_outlined, variant: AppButtonVariant.secondary, onPressed: online ? () => _edit(p) : null),
              ),
              if (p.creditBalanceMinor != null && cur != null) ...[
                const SizedBox(width: Space.s3),
                Expanded(
                  child: AppButton(key: const Key('profileAdjust'), label: 'Adjust credit', icon: Icons.account_balance_wallet_outlined, onPressed: online ? () => _adjust(p) : null),
                ),
              ],
            ],
          ),
          if (!online) const Padding(padding: EdgeInsets.only(top: Space.s2), child: CustomerNote(noteKey: Key('profileOffline'), icon: Icons.cloud_off_rounded, text: 'Needs internet to change a customer or their credit.')),
          _details(context, customer),
        ],
        if (p.recentSales.isNotEmpty) ...[
          const InvSectionTitle('Recent sales'),
          for (final s in p.recentSales)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('profileSale_${s.id}'),
                radius: Radii.rMd,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.number, style: t.subtitle.copyWith(color: pal.textPrimary)),
                          Text([invDateTime(s.at), s.status.replaceAll('_', ' ')].where((e) => e.isNotEmpty).join(' · '), style: t.caption.copyWith(color: pal.textMuted)),
                        ],
                      ),
                    ),
                    if (cur != null) Text(invMoney(s.totalMinor, cur), style: t.amountMd.copyWith(color: pal.textPrimary)),
                  ],
                ),
              ),
            ),
        ],
        if (manage && p.creditBalanceMinor != null) _ledger(context, cur),
      ],
    );
  }

  Widget _details(BuildContext context, PosCustomer customer) {
    final pal = context.palette;
    final t = context.type;
    final rows = <(String, String)>[
      if (customer.address != null) ('Address', customer.address!),
      if (customer.ntn != null) ('NTN', customer.ntn!),
      if (customer.cnic != null) ('CNIC', customer.cnic!),
      if (customer.registrationType != null) ('Registration', loyaltyTierLabel(customer.registrationType)),
      if (customer.notes != null) ('Notes', customer.notes!),
      ('Marketing', customer.marketingConsent ? 'OK to send offers' : 'No offers'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InvSectionTitle('Details'),
        AppCard(
          key: const Key('profileDetails'),
          child: Column(
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 110, child: Text(k, style: t.body.copyWith(color: pal.textSecondary))),
                      Expanded(child: Text(v, style: t.body.copyWith(color: pal.textPrimary))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ledger(BuildContext context, InvCur? cur) {
    final pal = context.palette;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InvSectionTitle('Store credit history'),
        Obx(() {
          if (c.ledgerLoading.value && c.ledger.isEmpty) return const Center(child: CircularProgressIndicator());
          if (c.ledgerError.value != null && c.ledger.isEmpty) return Text(c.ledgerError.value!, key: const Key('ledgerError'), style: t.body.copyWith(color: pal.dangerFg));
          if (c.ledger.isEmpty) return Text('No credit movements yet', key: const Key('ledgerEmpty'), style: t.body.copyWith(color: pal.textSecondary));
          return Column(
            children: [
              for (final e in c.ledger)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: AppCard(
                    key: Key('ledger_${e.id}'),
                    radius: Radii.rMd,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(creditTypeLabel(e.type), style: t.subtitle.copyWith(color: pal.textPrimary)),
                              Text(invDateTime(e.at), style: t.caption.copyWith(color: pal.textMuted)),
                              if (e.note != null) Text(e.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall.copyWith(color: pal.textSecondary)),
                              if (e.creditNoteNumber != null) Text('Credit note ${e.creditNoteNumber}', style: t.caption.copyWith(color: pal.textMuted)),
                            ],
                          ),
                        ),
                        if (cur != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${e.amountMinor < 0 ? '−' : '+'}${invMoney(e.amountMinor.abs(), cur)}', style: t.amountMd.copyWith(color: e.amountMinor < 0 ? pal.dangerFg : pal.successFg)),
                              Text('Balance ${invMoney(e.balanceAfterMinor, cur)}', style: t.caption.copyWith(color: pal.textMuted)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}
