import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
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
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Set up this device')),
      body: SafeArea(
        child: _loading
            ? Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: p.accent,
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(Space.s6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: box.maxHeight - Space.s12,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Obx(
                              () => _device.revokedNotice.value == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: Space.s4,
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: p.warningSoft,
                                          borderRadius: Radii.rMd,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(
                                            Space.s3,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.info_outline_rounded,
                                                size: 20,
                                                color: p.warningFg,
                                              ),
                                              const SizedBox(width: Space.s3),
                                              Expanded(
                                                child: Text(
                                                  _device.revokedNotice.value!,
                                                  style: context.type.bodySmall
                                                      .copyWith(
                                                        color: p.warningFg,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                            const GateHeader(
                              icon: Icons.tablet_mac_rounded,
                              title: 'Which register is this device?',
                              subtitle:
                                  'After this, staff sign in with their PIN and your owner password is not kept on the device.',
                            ),
                            const SizedBox(height: Space.s6),
                            DropdownButtonFormField<String>(
                              key: const Key('setupRegister'),
                              value: _registerId,
                              items: [
                                for (final r in _registers)
                                  DropdownMenuItem(
                                    value: r.id,
                                    child: Text(r.name),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _registerId = v),
                              style: context.type.body.copyWith(
                                color: p.textPrimary,
                              ),
                              dropdownColor: p.surfaceRaised,
                              borderRadius: Radii.rMd,
                              decoration: const InputDecoration(
                                labelText: 'Register',
                                prefixIcon: Icon(Icons.point_of_sale_outlined),
                              ),
                            ),
                            const SizedBox(height: Space.s4),
                            AppTextField(
                              key: const Key('setupName'),
                              label: 'Device name',
                              controller: _name,
                              prefixIcon: Icons.badge_outlined,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _go(),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: Space.s3),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _error!,
                                    style: context.type.bodySmall.copyWith(
                                      color: p.dangerFg,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: Space.s6),
                            AppButton(
                              key: const Key('setupConfirm'),
                              label: 'Register this device',
                              size: AppButtonSize.lg,
                              loading: _busy,
                              onPressed: _registerId == null ? null : _go,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
