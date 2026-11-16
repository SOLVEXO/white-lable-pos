import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_device_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_device_repository.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Owner-only list of this store's terminals with a Revoke action. Reached through [OwnerAccessMiddleware], so the owner has
/// re-authenticated; the backend list/revoke endpoints independently require the owner's own session.
class PosDevicesView extends StatefulWidget {
  const PosDevicesView({super.key, PosDeviceRepository? repository}) : _repo = repository;
  final PosDeviceRepository? _repo;

  @override
  State<PosDevicesView> createState() => _PosDevicesViewState();
}

class _PosDevicesViewState extends State<PosDevicesView> {
  late final PosDeviceRepository _repo = widget._repo ?? PosDeviceRepository();
  List<PosDeviceModel>? _devices;
  String _storeId = '';
  String? _thisDeviceId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _storeId = await AppPreferences.getStoreId() ?? '';
    _thisDeviceId = (await AppPreferences.getDeviceRegistration()).deviceId;
    final list = _storeId.isEmpty ? null : await _repo.list(_storeId);
    if (!mounted) return;
    setState(() {
      _devices = list;
      _loading = false;
    });
  }

  Future<void> _revoke(PosDeviceModel d) async {
    final isThis = d.id == _thisDeviceId;
    final ok = await AppDialog.confirm(
      context,
      title: 'Revoke "${d.name}"?',
      message: isThis
          ? 'This is the device you are holding. It will be signed out immediately. Unsynced sales stay on it until it is set up again for this store.'
          : 'It stops working immediately and has to be set up again by the owner. Sales it has not synced yet stay on it and upload after it is set up again for this store.',
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (ok != true) return;
    if (await _repo.revoke(_storeId, d.id)) {
      await _load(); // the list itself shows it as revoked
    } else {
      CustomAppSnackbar.error('Could not revoke the device.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');
    final p = context.palette;
    return AppPage(
      title: 'Devices',
      body: _loading
          ? Center(child: CircularProgressIndicator(color: p.accent))
          : _devices == null
              ? AppErrorState(message: "Couldn't load devices — tap to retry", onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(Space.s4),
                    itemCount: _devices!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Space.s2),
                    itemBuilder: (_, i) {
                      final d = _devices![i];
                      return AppCard(
                        key: Key('device-${d.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s3),
                        child: Row(children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: d.revoked ? p.fill : p.accentSoft, borderRadius: Radii.rMd),
                            child: Icon(Icons.point_of_sale_rounded, size: IconSizes.md, color: d.revoked ? p.textMuted : p.accentFg),
                          ),
                          const SizedBox(width: Space.s3),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${d.name}${d.id == _thisDeviceId ? '  (this device)' : ''}', style: context.type.subtitle.copyWith(color: p.textPrimary)),
                              const SizedBox(height: 2),
                              Text(
                                d.revoked ? 'Revoked${d.revokedAt != null ? ' ${fmt.format(d.revokedAt!.toLocal())}' : ''}' : 'Last seen ${d.lastSeenAt != null ? fmt.format(d.lastSeenAt!.toLocal()) : '—'}${d.platform != null ? ' · ${d.platform}' : ''}',
                                style: context.type.bodySmall.copyWith(color: d.revoked ? p.dangerFg : p.textSecondary),
                              ),
                            ]),
                          ),
                          if (!d.revoked) ...[
                            const SizedBox(width: Space.s2),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: AppButton(key: Key('revoke-${d.id}'), label: 'Revoke', variant: AppButtonVariant.secondary, onPressed: () => _revoke(d)),
                            ),
                          ],
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
