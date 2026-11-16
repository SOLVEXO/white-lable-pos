import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/models/pos/store_locations_overview_model.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

class LocationCard extends StatelessWidget {
  final StoreLocationModel location;
  final LocationOverviewStat? stat;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const LocationCard({
    super.key,
    required this.location,
    this.stat,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final isActive = location.isActive;
    final hasPhone = location.phone != null && location.phone!.trim().isNotEmpty;
    return AppCard(
      onTap: onEdit,
      semanticLabel: '${location.name}, ${isActive ? 'Active' : 'Archived'}',
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: isActive ? p.accentSoft : p.fill, borderRadius: Radii.rMd),
                child: Icon(
                  Icons.store_mall_directory_outlined,
                  color: isActive ? p.accentFg : p.textSecondary,
                  size: IconSizes.md,
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Text(
                  location.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.subtitle.copyWith(color: p.textPrimary),
                ),
              ),
              const SizedBox(width: Space.s2),
              StatusBadge(
                isActive ? 'Active' : 'Archived',
                tone: isActive ? StatusTone.success : StatusTone.neutral,
              ),
              if (isActive)
                IconButton(
                  tooltip: 'Archive',
                  icon: Icon(Icons.archive_outlined, size: IconSizes.sm, color: p.textSecondary),
                  onPressed: onArchive,
                )
              else
                const SizedBox(width: Space.s2),
            ],
          ),
          if (location.addressLabel.isNotEmpty) ...[
            const SizedBox(height: Space.s2),
            _InfoLine(icon: Icons.location_on_outlined, text: location.addressLabel),
          ],
          if (hasPhone) ...[
            const SizedBox(height: Space.s1),
            _InfoLine(icon: Icons.phone_outlined, text: location.phone!),
          ],
          if (stat != null) ...[
            const SizedBox(height: Space.s2),
            Wrap(
              spacing: Space.s4,
              runSpacing: Space.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.payments_outlined, size: IconSizes.xxs, color: p.successFg),
                    const SizedBox(width: Space.s1),
                    AmountText(
                      Money.format(stat!.totalSales),
                      style: t.amountSm,
                      color: p.textPrimary,
                      animate: false,
                    ),
                    const SizedBox(width: Space.s1),
                    Text('sales', style: t.caption.copyWith(color: p.textSecondary)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: IconSizes.xxs, color: p.textSecondary),
                    const SizedBox(width: Space.s1),
                    Text(
                      '${stat!.transactionCount} transactions',
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Icon(icon, size: IconSizes.xxs, color: p.textSecondary),
        const SizedBox(width: Space.s1),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: context.type.bodySmall.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}
