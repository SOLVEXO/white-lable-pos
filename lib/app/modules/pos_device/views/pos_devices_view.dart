import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_device_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_device_repository.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Revoke "${d.name}"?'),
        content: Text(isThis
            ? 'This is the device you are holding. It will be signed out immediately. Unsynced sales stay on it until it is set up again for this store.'
            : 'It stops working immediately and has to be set up again by the owner. Sales it has not synced yet stay on it and upload after it is set up again for this store.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Revoke', style: TextStyle(color: AppColors.red))),
        ],
      ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _devices == null
              ? Center(child: TextButton(onPressed: _load, child: const Text("Couldn't load devices — tap to retry")))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _devices!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final d = _devices![i];
                      return Container(
                        key: Key('device-${d.id}'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.black.withOpacity(0.06))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${d.name}${d.id == _thisDeviceId ? '  (this device)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                d.revoked ? 'Revoked${d.revokedAt != null ? ' ${fmt.format(d.revokedAt!.toLocal())}' : ''}' : 'Last seen ${d.lastSeenAt != null ? fmt.format(d.lastSeenAt!.toLocal()) : '—'}${d.platform != null ? ' · ${d.platform}' : ''}',
                                style: TextStyle(fontSize: 12, color: d.revoked ? AppColors.red : AppColors.iosGrey),
                              ),
                            ]),
                          ),
                          if (!d.revoked) TextButton(key: Key('revoke-${d.id}'), onPressed: () => _revoke(d), child: const Text('Revoke', style: TextStyle(color: AppColors.red))),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
