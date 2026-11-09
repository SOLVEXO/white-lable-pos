import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_permissions/controllers/pos_permissions_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Pre-flight explainer for what the phone may be asked for, with a "why" and a "without it" per item. Skippable; re-openable from More.
class PosPermissionsView extends StatelessWidget {
  PosPermissionsView({super.key, PosPermissionsController? controller}) : c = controller ?? Get.put(PosPermissionsController());
  final PosPermissionsController c;

  static IconData _icon(AppPermission p) => switch (p) {
        AppPermission.camera => Icons.photo_camera_outlined,
        AppPermission.bluetooth => Icons.bluetooth_rounded,
        AppPermission.localNetwork => Icons.wifi_rounded,
        AppPermission.notifications => Icons.notifications_none_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Permissions'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0, automaticallyImplyLeading: !c.afterSetup),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s4),
                    children: [
                      Text('Allow only what you need. Everything keeps working without these; you can change them any time in More → Permissions.', key: const Key('permissionsIntro'), style: t.body.copyWith(color: p.textSecondary)),
                      const SizedBox(height: Space.s4),
                      for (final r in c.rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.s3),
                          child: Obx(() {
                            final s = c.stateOf(r.permission);
                            final label = c.actionLabel(r.permission);
                            return AppCard(
                              key: Key('perm_${r.permission.name}'),
                              radius: Radii.rMd,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(_icon(r.permission), color: p.textPrimary),
                                    const SizedBox(width: Space.s3),
                                    Expanded(child: Text(r.title, style: t.subtitle.copyWith(color: p.textPrimary))),
                                    _badge(s, r.permission, key: Key('permState_${r.permission.name}')),
                                  ]),
                                  const SizedBox(height: Space.s2),
                                  Text(r.why, style: t.body.copyWith(color: p.textSecondary)),
                                  const SizedBox(height: Space.s1),
                                  Text('Without it: ${r.without}', key: Key('permWithout_${r.permission.name}'), style: t.caption.copyWith(color: p.textMuted)),
                                  if (s == PermState.permanentlyDenied)
                                    Padding(
                                      padding: const EdgeInsets.only(top: Space.s2),
                                      child: Text('This was turned off. Open Settings to turn it back on.', key: Key('permBlocked_${r.permission.name}'), style: t.caption.copyWith(color: p.warningFg)),
                                    ),
                                  if (label != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: Space.s3),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: AppButton(key: Key('permAct_${r.permission.name}'), label: label, variant: AppButtonVariant.secondary, onPressed: c.busy.value ? null : () => c.act(r.permission)),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
                  child: AppButton(
                    key: const Key('permContinue'),
                    label: c.afterSetup ? 'Continue' : 'Done',
                    onPressed: () => c.afterSetup ? Get.offAllNamed(Routes.posPinLogin) : Get.back<void>(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(PermState s, AppPermission perm, {Key? key}) {
    final (text, tone) = switch (s) {
      PermState.granted => ('Allowed', StatusTone.success),
      PermState.denied => ('Not allowed', StatusTone.warning),
      PermState.permanentlyDenied => ('Turned off', StatusTone.danger),
      PermState.unknown => (perm == AppPermission.localNetwork ? 'Asked when used' : 'Not asked yet', StatusTone.neutral),
      PermState.notRequired => ('Not used', StatusTone.neutral),
    };
    return StatusBadge(text, tone: tone, key: key);
  }
}
