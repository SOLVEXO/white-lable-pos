import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/components/owner_unlock_button.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/roles_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.2 roles & permissions: grouped by area, each action with who may do it (Cashier / Manager; the Owner always, locked) and its approval rules
/// (on / off, who approves, above which limit). "Changed" marks a difference from the default; pinned actions are locked with the reason. The owner edits;
/// Save shows the server's preview first. Managers see it read only.
class RolesView extends StatefulWidget {
  const RolesView({super.key, this.controller});
  final RolesController? controller;
  @override
  State<RolesView> createState() => _RolesViewState();
}

class _RolesViewState extends State<RolesView> {
  late final String _tag = 'roles_${identityHashCode(this)}';
  late final RolesController c = widget.controller ?? Get.put(RolesController(), tag: _tag);

  @override
  void dispose() {
    if (widget.controller == null) Get.delete<RolesController>(tag: _tag);
    super.dispose();
  }

  Future<void> _review() async {
    final diff = await c.previewSave();
    if (diff == null || !mounted) return;
    final ok = await PermPreviewSheet.open(title: 'Review changes', diff: diff, labelOf: c.labelOf, confirmLabel: 'Save changes');
    if (ok == true) await c.save();
  }

  /// G5.6: pick a preset → the server's preview of what changes → confirm.
  Future<void> _preset() async {
    final presets = c.matrix.value?.presets ?? const <RolePreset>[];
    if (presets.isEmpty) return;
    final picked = await showModalBottomSheet<RolePreset>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          key: const Key('presetList'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
          children: [
            Text('Role presets', style: ctx.type.subtitle),
            const SizedBox(height: Space.s1),
            Text('A preset replaces your custom permissions. You will see exactly what changes before anything is saved.', style: ctx.type.bodySmall.copyWith(color: ctx.palette.textSecondary)),
            const SizedBox(height: Space.s2),
            for (final p in presets)
              ListTile(
                key: Key('preset_${p.key}'),
                contentPadding: EdgeInsets.zero,
                title: Row(children: [Flexible(child: Text(p.label)), if (p.proposed) ...[const SizedBox(width: Space.s2), const StatusBadge('Proposed', tone: StatusTone.warning)]]),
                subtitle: Text(p.summary),
                onTap: () => Navigator.of(ctx).pop(p),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final diff = await c.previewPreset(picked.key);
    if (diff == null || !mounted) return;
    final ok = await PermPreviewSheet.open(title: 'Apply "${picked.label}"', diff: diff, labelOf: c.labelOf, confirmLabel: 'Apply preset');
    if (ok == true) await c.applyPreset(picked);
  }

  Future<void> _reset() async {
    final diff = await c.previewReset();
    if (diff == null || !mounted) return;
    final ok = await PermPreviewSheet.open(title: 'Reset to defaults', diff: diff, labelOf: c.labelOf, confirmLabel: 'Reset to defaults', danger: true);
    if (ok == true) await c.reset();
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Roles & permissions',
      maxWidth: 900,
      actions: [
        Obx(() => c.canEdit && (c.matrix.value?.presets.isNotEmpty ?? false) ? TextButton(key: const Key('permPresets'), onPressed: c.busy.value ? null : _preset, child: const Text('Presets')) : const SizedBox.shrink()),
        Obx(() => c.canEdit ? TextButton(key: const Key('permReset'), onPressed: c.busy.value ? null : _reset, child: const Text('Reset to defaults')) : const SizedBox.shrink()),
      ],
      body: Obx(() {
        final m = c.matrix.value;
        if (!reportsOnlineRx().value && m == null) return const ReportsNeedsInternet(subject: 'Roles & permissions');
        if (m == null && c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('permLoading')));
        if (m == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        final p = context.palette;
        final groups = c.byArea;
        return Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('permList'),
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
                children: [
                  if (!m.canEdit) ...[
                    const ReportInfo(key: Key('permReadOnly'), 'Only the owner can change roles and permissions. You can see them here.', icon: Icons.lock_outline_rounded),
                    OwnerUnlockButton(onUnlocked: c.load),
                  ]
                  else if (!reportsOnlineRx().value)
                    const ReportInfo('Changing permissions needs an internet connection.', warn: true),
                  if (c.notice.value != null) ReportInfo(key: const Key('permNotice'), c.notice.value!, icon: Icons.check_circle_outline_rounded),
                  if (c.saveError.value != null)
                    Container(
                      key: const Key('permError'),
                      margin: const EdgeInsets.only(bottom: Space.s2),
                      padding: const EdgeInsets.all(Space.s3),
                      decoration: BoxDecoration(color: p.dangerSoft, borderRadius: Radii.rMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.saveError.value!, style: context.type.bodySmall.copyWith(color: p.dangerFg)),
                          if (c.conflict.value) ...[
                            const SizedBox(height: Space.s2),
                            AppButton(key: const Key('permReload'), label: 'Reload', icon: Icons.refresh_rounded, variant: AppButtonVariant.secondary, onPressed: c.load),
                          ],
                        ],
                      ),
                    ),
                  Text('The owner can always do everything. Approval means a manager\'s PIN (or the owner) is needed above the limit.', style: context.type.bodySmall.copyWith(color: p.textSecondary)),
                  for (final e in groups.entries) ...[InvSectionTitle(permAreaLabel(e.key)), for (final a in e.value) _ActionCard(c: c, a: a)],
                ],
              ),
            ),
            if (c.dirty)
              SafeArea(
                top: false,
                child: Container(
                  key: const Key('permBar'),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2),
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${c.edits.length} action${c.edits.length == 1 ? '' : 's'} changed', style: context.type.body.copyWith(color: p.textPrimary)),
                      ),
                      TextButton(key: const Key('permDiscard'), onPressed: c.busy.value ? null : c.discard, child: const Text('Discard')),
                      const SizedBox(width: Space.s2),
                      Flexible(
                        child: AppButton(key: const Key('permReview'), label: 'Review & save', expand: false, loading: c.busy.value, onPressed: c.busy.value ? null : _review),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.c, required this.a});
  final RolesController c;
  final PermAction a;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = context.palette;
      final t = context.type;
      final cur = c.current(a);
      final edited = c.edits.containsKey(a.action);
      final editable = c.canEdit && !a.pinned;
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.s2),
        child: AppCard(
          key: Key('perm_${a.action}'),
          radius: Radii.rMd,
          padding: const EdgeInsets.all(Space.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(a.label, style: t.subtitle.copyWith(color: p.textPrimary)),
                  ),
                  if (a.pinned) const StatusBadge('Locked', icon: Icons.lock_outline_rounded, tone: StatusTone.neutral),
                  if (!a.pinned && (a.changed || edited))
                    StatusBadge(edited ? 'Edited' : 'Changed', key: Key('permChanged_${a.action}'), icon: Icons.edit_outlined, tone: edited ? StatusTone.warning : StatusTone.accent),
                ],
              ),
              if (a.pinned)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s1),
                  child: Text('This protects who may see and change permissions, so it can never change.', style: t.caption.copyWith(color: p.textMuted)),
                ),
              const SizedBox(height: Space.s2),
              Wrap(
                spacing: Space.s2,
                runSpacing: Space.s1,
                children: [
                  for (final r in PermRole.all)
                    FilterChip(
                      key: Key('permRole_${a.action}_$r'),
                      label: Text(PermRole.label(r)),
                      avatar: r == PermRole.owner ? const Icon(Icons.lock_outline_rounded, size: 16) : null,
                      selected: r == PermRole.owner || cur.roles.contains(r),
                      onSelected: r == PermRole.owner || !editable ? null : (_) => c.toggleRole(a, r),
                    ),
                ],
              ),
              for (var i = 0; i < cur.approval.length; i++) _ApprovalRow(c: c, a: a, i: i, rule: cur.approval[i], editable: editable),
            ],
          ),
        ),
      );
    });
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({required this.c, required this.a, required this.i, required this.rule, required this.editable});
  final RolesController c;
  final PermAction a;
  final int i;
  final PermApproval rule;
  final bool editable;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Container(
      margin: const EdgeInsets.only(top: Space.s2),
      padding: const EdgeInsets.all(Space.s2),
      decoration: BoxDecoration(color: p.fill, borderRadius: Radii.rSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Needs approval',
                      style: t.bodySmall.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    Text(rule.when, style: t.caption.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
              Switch.adaptive(
                key: Key('permApproval_${a.action}_$i'),
                value: rule.enabled,
                onChanged: editable ? (v) => c.setApproval(a, i, enabled: v) : null,
              ),
            ],
          ),
          if (rule.enabled)
            Wrap(
              spacing: Space.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Approved by', style: t.caption.copyWith(color: p.textSecondary)),
                for (final who in const [PermRole.manager, PermRole.owner])
                  ChoiceChip(
                    key: Key('permApprover_${a.action}_${i}_$who'),
                    label: Text(PermRole.label(who)),
                    selected: rule.approver == who,
                    onSelected: editable ? (_) => c.setApproval(a, i, approver: who) : null,
                  ),
              ],
            )
          else
            Text('Off: no approval is asked for.', style: t.caption.copyWith(color: p.warningFg)),
        ],
      ),
    );
  }
}

/// The server's preview of a change, in words, with Confirm / Cancel. Returns true when confirmed.
class PermPreviewSheet extends StatelessWidget {
  const PermPreviewSheet({super.key, required this.diff, required this.labelOf, required this.confirmLabel, this.danger = false});
  final List<PermDiff> diff;
  final String Function(String) labelOf;
  final String confirmLabel;
  final bool danger;

  static Future<bool?> open({required String title, required List<PermDiff> diff, required String Function(String) labelOf, required String confirmLabel, bool danger = false}) =>
      AppBottomSheet.showGet<bool>(
        PermPreviewSheet(diff: diff, labelOf: labelOf, confirmLabel: confirmLabel, danger: danger),
        title: title,
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      key: const Key('permPreviewSheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (diff.isEmpty)
          Text(
            'Nothing would change.',
            key: const Key('permPreviewEmpty'),
            style: t.body.copyWith(color: p.textSecondary),
          )
        else ...[
          Text('${diff.length} change${diff.length == 1 ? '' : 's'}. Every till follows them at once.', style: t.bodySmall.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s2),
          for (final d in diff)
            Padding(
              key: Key('permDiff_${d.action}_${d.field}'),
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(labelOf(d.action), style: t.subtitle.copyWith(color: p.textPrimary)),
                  Text('${d.fieldLabel}: ${d.beforeText}  →  ${d.afterText}', style: t.bodySmall.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
        ],
        const SizedBox(height: Space.s3),
        AppButton(
          key: const Key('permConfirm'),
          label: confirmLabel,
          variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary,
          onPressed: diff.isEmpty ? null : () => Get.back(result: true),
        ),
        const SizedBox(height: Space.s2),
        AppButton(key: const Key('permCancel'), label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: () => Get.back(result: false)),
      ],
    );
  }
}
