import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/store_locations_overview_model.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Combined "all branches" stats card from the locations overview endpoint
/// (defaults to the last 30 days on the backend).
class LocationsOverviewHeader extends StatelessWidget {
  final StoreLocationsOverviewModel overview;
  const LocationsOverviewHeader({super.key, required this.overview});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final large = MediaQuery.textScalerOf(context).scale(16) > 19;
    final sales = _OverviewStat(
      label: 'Total Sales',
      value: AmountText(
        Money.format(overview.combinedTotalSales),
        style: t.amountLg,
        color: p.textPrimary,
        animate: false,
      ),
    );
    final txns = _OverviewStat(
      label: 'Transactions',
      value: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text('${overview.combinedTransactionCount}', style: t.amountLg.copyWith(color: p.textPrimary)),
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, size: IconSizes.xs, color: p.accentFg),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Text('All Branches', style: t.subtitle.copyWith(color: p.textPrimary)),
              ),
              Text('Last 30 days', style: t.caption.copyWith(color: p.textSecondary)),
            ],
          ),
          const SizedBox(height: Space.s3),
          if (large)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [sales, const SizedBox(height: Space.s2), txns],
            )
          else
            Row(
              children: [
                Expanded(child: sales),
                const SizedBox(width: Space.s2),
                Expanded(child: txns),
              ],
            ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final String label;
  final Widget value;
  const _OverviewStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(color: p.fill, borderRadius: Radii.rMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          value,
          const SizedBox(height: Space.s1),
          Text(label, style: context.type.caption.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}
