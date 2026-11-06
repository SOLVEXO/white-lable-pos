import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/modules/pos_offline/controllers/pos_offline_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// "Offline mode": what keeps working without a connection, what needs one, how many sales are waiting and when the till last synced.
class PosOfflineView extends StatelessWidget {
  PosOfflineView({super.key, PosOfflineController? controller}) : c = controller ?? Get.put(PosOfflineController());
  final PosOfflineController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Offline mode'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Obx(() {
              c.watch();
              final online = c.isOnline;
              final last = c.lastSync;
              return ListView(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                children: [
                  AppCard(
                    color: online ? p.successSoft : p.warningSoft,
                    radius: Radii.rMd,
                    child: Row(
                      children: [
                        Icon(online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: online ? p.successFg : p.warningFg),
                        const SizedBox(width: Space.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(online ? 'Connected' : 'No connection', key: const Key('offlineStatus'), style: t.subtitle.copyWith(color: online ? p.successFg : p.warningFg)),
                              Text(
                                online ? 'Everything works, and sales go straight to the server.' : 'You can keep selling. Cash and recorded card sales are saved here and sync later.',
                                style: t.caption.copyWith(color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  Row(
                    children: [
                      Expanded(child: _Stat(label: 'Waiting to sync', value: '${c.pending}', keyName: 'pendingCount')),
                      const SizedBox(width: Space.s3),
                      Expanded(child: _Stat(label: 'Rejected', value: '${c.failed}', keyName: 'failedCount', warn: c.failed > 0)),
                    ],
                  ),
                  const SizedBox(height: Space.s3),
                  Text(
                    last == null ? 'Last sync: not yet on this device' : 'Last sync: ${DateFormat('d MMM, HH:mm').format(last.toLocal())}',
                    key: const Key('lastSync'),
                    style: t.body.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: Space.s3),
                  AppButton(
                    key: const Key('syncNow'),
                    label: 'Sync now',
                    icon: Icons.sync_rounded,
                    loading: c.isSyncing,
                    onPressed: (!online || c.isSyncing) ? null : c.syncNow,
                  ),
                  if (c.pending + c.failed > 0) ...[
                    const SizedBox(height: Space.s2),
                    TextButton(key: const Key('openNeedsAttention'), onPressed: () => Get.toNamed(Routes.posNeedsAttention), child: const Text('Review sales that need attention')),
                  ],
                  const SizedBox(height: Space.s5),
                  _Group(title: 'Works offline', icon: Icons.check_circle_rounded, tone: p.successFg, items: PosOfflineController.worksOffline, keyName: 'worksOffline'),
                  const SizedBox(height: Space.s4),
                  _Group(title: 'Needs a connection', icon: Icons.wifi_off_rounded, tone: p.warningFg, items: PosOfflineController.needsConnection, keyName: 'needsConnection'),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.keyName, this.warn = false});
  final String label;
  final String value;
  final String keyName;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      radius: Radii.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.caption.copyWith(color: p.textMuted)),
          const SizedBox(height: Space.s1),
          Text(value, key: Key(keyName), style: context.type.amountLg.copyWith(color: warn ? p.dangerFg : p.textPrimary)),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.icon, required this.tone, required this.items, required this.keyName});
  final String title;
  final IconData icon;
  final Color tone;
  final List<String> items;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      key: Key(keyName),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s2),
        for (final line in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: tone),
                const SizedBox(width: Space.s2),
                Expanded(child: Text(line, style: t.body.copyWith(color: p.textSecondary))),
              ],
            ),
          ),
      ],
    );
  }
}
