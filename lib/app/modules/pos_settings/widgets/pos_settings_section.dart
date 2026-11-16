import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_settings_tile.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

/// One titled group of Settings rows (REGISTER, RECEIPT, SHIFT, …).
class PosSettingsSectionWidget extends StatelessWidget {
  final PosSettingsSection section;

  const PosSettingsSectionWidget({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return AppSection(
      section.header,
      [for (final t in section.tiles) PosSettingsTileWidget(tile: t)],
    );
  }
}
