import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/theme_preference.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Settings → Appearance (G6.4): System / Light / Dark for THIS device. Every role sees it (a device preference, not a store setting);
/// the choice applies at once and is kept across restarts and sign-out.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, this.preference});
  final ThemePreference? preference;

  ThemePreference? get _pref => preference ?? (Get.isRegistered<ThemePreference>() ? Get.find<ThemePreference>() : null);

  @override
  Widget build(BuildContext context) {
    final pref = _pref;
    if (pref == null) return const SizedBox.shrink();
    return Obx(() {
      final c = pref.choice.value;
      return AppSection('Appearance', [
        AppListRow(
          key: const Key('settingsAppearance'),
          icon: switch (c) { AppearanceChoice.system => Icons.brightness_auto_rounded, AppearanceChoice.light => Icons.light_mode_outlined, AppearanceChoice.dark => Icons.dark_mode_outlined },
          title: 'Appearance',
          subtitle: 'This device only',
          trailing: Text(c.label, style: context.type.bodySmall.copyWith(color: context.palette.textSecondary)),
          onTap: () => showAppearanceSheet(context, pref),
        ),
      ]);
    });
  }
}

/// The three choices as rows with a check on the current one; picking one applies it immediately and closes the sheet.
Future<void> showAppearanceSheet(BuildContext context, ThemePreference pref) => AppBottomSheet.show<void>(
      context,
      title: 'Appearance',
      builder: (ctx) => Obx(() {
        final current = pref.choice.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in AppearanceChoice.values) ...[
              AppListRow(
                key: Key('appearance_${c.name}'),
                icon: switch (c) { AppearanceChoice.system => Icons.brightness_auto_rounded, AppearanceChoice.light => Icons.light_mode_outlined, AppearanceChoice.dark => Icons.dark_mode_outlined },
                title: c.label,
                subtitle: c.description,
                tone: c == current ? StatusTone.accent : StatusTone.neutral,
                chevron: false,
                trailing: c == current ? Icon(Icons.check_rounded, color: ctx.palette.accentFg) : null,
                onTap: () async {
                  await pref.set(c);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
              const SizedBox(height: Space.s2),
            ],
          ],
        );
      }),
    );
