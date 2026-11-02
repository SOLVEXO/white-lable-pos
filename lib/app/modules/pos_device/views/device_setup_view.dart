import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// One-time (and after a revocation) setup: the signed-in OWNER picks which register this terminal is, and the app swaps the
/// owner's session for the device's own long-lived token. From then on the owner's password is only asked for owner-only areas.
class DeviceSetupView extends StatefulWidget {
  const DeviceSetupView({super.key, SellerRepository? sellerRepository, PosDeviceService? deviceService})
      : _seller = sellerRepository,
        _device = deviceService;
  final SellerRepository? _seller;
  final PosDeviceService? _device;

  @override
  State<DeviceSetupView> createState() => _DeviceSetupViewState();
}

class _DeviceSetupViewState extends State<DeviceSetupView> {
  late final SellerRepository _seller = widget._seller ?? SellerRepository();
  late final PosDeviceService _device = widget._device ?? Get.find<PosDeviceService>();
  final _name = TextEditingController(text: Platform.isIOS ? 'iPad / iPhone till' : 'Android till');
  List<({String id, String name})> _registers = const [];
  String? _registerId;
  String _storeId = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _storeId = await AppPreferences.getStoreId() ?? '';
    final store = _storeId.isEmpty ? null : await _seller.getStoreById(_storeId);
    if (!mounted) return;
    setState(() {
      _registers = (store?.registers ?? const []).map((r) => (id: r.id, name: r.name)).toList();
      _registerId = _registers.isNotEmpty ? _registers.first.id : null;
      _loading = false;
      if (_registers.isEmpty) _error = 'This store has no registers yet. Create one in management first.';
    });
  }

  Future<void> _go() async {
    if (_busy || _registerId == null || _name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _device.register(storeId: _storeId, registerId: _registerId!, name: _name.text.trim(), platform: Platform.isIOS ? 'ios' : 'android');
    if (!mounted) return;
    switch (r) {
      case DeviceSetupResult.ok:
        Get.offAllNamed(Routes.posPinLogin);
        return;
      case DeviceSetupResult.otherStoreWithUnsyncedSales:
        setState(() => _error = 'This device still holds unsynced sales from a different store. Set it up for that store first so they can upload.');
      case DeviceSetupResult.failed:
        setState(() => _error = "Couldn't register this device. Check your connection and try again.");
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up this device')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Obx(() => _device.revokedNotice.value == null
                      ? const SizedBox.shrink()
                      : Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_device.revokedNotice.value!, style: const TextStyle(color: Colors.orange)))),
                  const Text('Which register is this device?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('After this, staff sign in with their PIN and your owner password is not kept on the device.'),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    key: const Key('setupRegister'),
                    value: _registerId,
                    items: [for (final r in _registers) DropdownMenuItem(value: r.id, child: Text(r.name))],
                    onChanged: (v) => setState(() => _registerId = v),
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Register'),
                  ),
                  const SizedBox(height: 12),
                  TextField(key: const Key('setupName'), controller: _name, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Device name')),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(key: const Key('setupConfirm'), onPressed: _busy || _registerId == null ? null : _go, child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Register this device')),
                  ),
                ]),
              ),
      ),
    );
  }
}
