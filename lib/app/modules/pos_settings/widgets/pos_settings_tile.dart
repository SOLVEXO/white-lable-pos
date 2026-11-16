import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

/// One Settings row: an [AppListRow] with the current value on the right.
class PosSettingsTileWidget extends StatelessWidget {
  final PosSettingsTile tile;

  const PosSettingsTileWidget({super.key, required this.tile});

  /// The rows' trailing values that are money (shown with the tabular amount style).
  static const _moneyTitles = {"Today's Sales", 'Opening Float'};

  /// A line icon per row (the tile model carries a legacy SVG asset; the design system uses Material line icons).
  static const _icons = <String, IconData>{
    'Register Name': Icons.point_of_sale_rounded,
    'Tax Rate': Icons.percent_rounded,
    'Business Name': Icons.storefront_rounded,
    'Business Tax ID': Icons.badge_outlined,
    'Receipt Header': Icons.vertical_align_top_rounded,
    'Receipt Footer': Icons.vertical_align_bottom_rounded,
    'Receipt Printer': Icons.print_rounded,
    'Printer settings': Icons.tune_rounded,
    'Inventory': Icons.inventory_2_outlined,
    'Stock Activity': Icons.swap_vert_rounded,
    'Customers': Icons.people_outline_rounded,
    "Today's Sales": Icons.trending_up_rounded,
    'Opening Float': Icons.payments_outlined,
    'Shift History': Icons.history_rounded,
    'Cash Management': Icons.account_balance_wallet_outlined,
    'Sync & needs attention': Icons.sync_problem_rounded,
    'Close Shift': Icons.logout_rounded,
    'Plan status': Icons.workspace_premium_outlined,
    'Store time zone': Icons.schedule_rounded,
    'Sound Effects': Icons.volume_up_outlined,
    'Auto-Lock': Icons.lock_clock_outlined,
    'Devices': Icons.devices_other_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final value = tile.trailing;
    final valueColor = tile.isDanger ? p.dangerFg : p.textSecondary;
    Widget? trailing;
    if (value != null && value.isNotEmpty) {
      trailing = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.38),
        child: _moneyTitles.contains(tile.title)
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AmountText(value, style: context.type.amountSm, color: valueColor, animate: false),
              )
            : Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.type.bodySmall.copyWith(color: valueColor),
              ),
      );
    }
    return AppListRow(
      icon: _icons[tile.title] ?? Icons.settings_outlined,
      title: tile.title,
      tone: tile.isDanger ? StatusTone.danger : StatusTone.accent,
      trailing: trailing,
      onTap: tile.onTap,
      chevron: true,
    );
  }
}
