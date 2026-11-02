import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';

/// Wraps the whole app: reports every touch to [IdleLockService] and, while the till is locked, covers everything with a
/// PIN screen. It is an OVERLAY — the screens underneath (and the cart on them) are untouched.
class PosLockOverlay extends StatelessWidget {
  const PosLockOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<IdleLockService>()) return child;
    final lock = Get.find<IdleLockService>();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => lock.onActivity(),
      onPointerMove: (_) => lock.onActivity(),
      child: Stack(children: [
        child,
        Obx(() => lock.locked.value ? PosLockScreen(service: lock) : const SizedBox.shrink()),
      ]),
    );
  }
}

class PosLockScreen extends StatefulWidget {
  const PosLockScreen({super.key, required this.service});
  final IdleLockService service;

  @override
  State<PosLockScreen> createState() => _PosLockScreenState();
}

class _PosLockScreenState extends State<PosLockScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy || _pin.text.length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.service.unlock(_pin.text);
    if (!mounted) return;
    _pin.clear();
    setState(() {
      _busy = false;
      _error = switch (r) {
        UnlockResult.ok => null,
        UnlockResult.wrongPin => 'Wrong PIN.',
        UnlockResult.differentEmployee => "That PIN belongs to someone else. Use 'Switch user'.",
        UnlockResult.failed => "Couldn't check the PIN. Try again.",
      };
    });
  }

  /// Someone else takes over: a proper PIN logout (their token dies server-side) and the PIN screen. The cart snapshot and the
  /// offline queue are untouched; each queued sale keeps the cashier who rang it.
  Future<void> _switchUser() async {
    final storeId = await AppPreferences.getStoreId() ?? '';
    if (storeId.isNotEmpty) await PosRepository().pinLogout(storeId);
    await AppPreferences.clearPosEmployee();
    widget.service.releaseWithoutPin();
    Get.offAllNamed(Routes.posPinLogin);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.service.employeeName.value;
    return Material(
      color: AppColors.posThemeBg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline_rounded, size: 44, color: AppColors.posThemeText),
                const SizedBox(height: 12),
                const Text('Locked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.posThemeText)),
                const SizedBox(height: 4),
                Text(name == null || name.isEmpty ? 'Enter your PIN to continue' : '$name — enter your PIN to continue', style: const TextStyle(color: AppColors.posThemeSubText)),
                const SizedBox(height: 4),
                const Text('Your cart and unsynced sales are kept.', style: TextStyle(color: AppColors.posThemeSubText, fontSize: 12)),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('lockPin'),
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  onChanged: (v) {
                    if (v.length == 4) _unlock();
                  },
                  style: const TextStyle(color: AppColors.posThemeText, fontSize: 22, letterSpacing: 8),
                  decoration: InputDecoration(counterText: '', border: const OutlineInputBorder(), errorText: _error),
                ),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _unlock, child: const Text('Unlock'))),
                TextButton(
                  key: const Key('lockSwitchUser'),
                  onPressed: _busy ? null : _switchUser,
                  child: const Text('Switch user'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
