import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/core/design/design.dart';

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
  // Visual only: bumps on every failed attempt so the dots shake.
  int _errorTick = 0;
  String? _storeName;

  @override
  void initState() {
    super.initState();
    AppPreferences.getStoreName().then((n) {
      if (mounted && n != null && n.isNotEmpty) setState(() => _storeName = n);
    });
  }

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
      if (_error != null) _errorTick++; // visual only: shakes the dots
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

  // The on-screen pad edits the same controller the (hidden) field uses, then runs the same
  // "4 digits -> unlock" step the field's onChanged does.
  void _append(String d) {
    if (_busy || _pin.text.length >= 4) return;
    setState(() => _error = null);
    _pin.text += d;
    if (_pin.text.length == 4) _unlock();
  }

  void _backspace() {
    if (_busy || _pin.text.isEmpty) return;
    _pin.text = _pin.text.substring(0, _pin.text.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.service.employeeName.value;
    // Always dark ink, whatever the app theme — and no blur: just an opaque overlay.
    return InkScope(
      lightStatusBar: true,
      child: Builder(
        builder: (context) {
          final p = context.palette;
          final header = GateHeader(
            icon: Icons.lock_outline_rounded,
            title: 'Locked',
            subtitle: name == null || name.isEmpty
                ? 'Enter your PIN to continue'
                : '$name — enter your PIN to continue',
            footnote: 'Your cart and unsynced sales are kept.',
          );
          final pad = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _pin,
                builder: (context, v, _) => PinDots(
                  length: 4,
                  filled: v.text.length,
                  errorTick: _errorTick,
                  hasError: _error != null,
                ),
              ),
              SizedBox(
                height: 44,
                child: Center(
                  child: _busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.accent,
                          ),
                        )
                      : (_error == null
                            ? null
                            : Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: context.type.bodySmall.copyWith(
                                    color: p.dangerFg,
                                  ),
                                ),
                              )),
                ),
              ),
              // Hidden input: keeps the field (and its controller) that the unlock flow has always used, so
              // a hardware keyboard / test can still type straight into it. No soft keyboard (the pad is the input).
              Opacity(
                opacity: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: ExcludeSemantics(
                    child: TextField(
                      key: const Key('lockPin'),
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.none,
                      maxLength: 4,
                      onChanged: (v) {
                        if (v.length == 4) _unlock();
                      },
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
              PinPad(
                autofocus: true,
                enabled: !_busy,
                onDigit: _append,
                onBackspace: _backspace,
                onClear: () => _pin.clear(),
              ),
              const SizedBox(height: Space.s2),
              AppButton(
                key: const Key('lockSwitchUser'),
                label: 'Switch user',
                variant: AppButtonVariant.ghost,
                expand: false,
                icon: Icons.swap_horiz_rounded,
                onPressed: _busy ? null : _switchUser,
              ),
            ],
          );
          return Material(
            color: p.background,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 840;
                  final clock = _LockClock(storeName: _storeName);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(Space.s6),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: box.maxHeight - Space.s12,
                      ),
                      child: Center(
                        child: wide
                            ? ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 920,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          clock,
                                          const SizedBox(height: Space.s8),
                                          header,
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: Space.s8),
                                    Expanded(child: pad),
                                  ],
                                ),
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 380,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    clock,
                                    const SizedBox(height: Space.s6),
                                    header,
                                    const SizedBox(height: Space.s5),
                                    pad,
                                  ],
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Large clock + date + store name. Ticks once a second but only rebuilds when the minute changes.
class _LockClock extends StatefulWidget {
  const _LockClock({this.storeName});
  final String? storeName;

  @override
  State<_LockClock> createState() => _LockClockState();
}

class _LockClockState extends State<_LockClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute || n.hour != _now.hour) {
        setState(() => _now = n);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final time = DateFormat(
      MediaQuery.alwaysUse24HourFormatOf(context) ? 'HH:mm' : 'h:mm a',
    ).format(_now);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.storeName != null) ...[
          Text(
            widget.storeName!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.label.copyWith(color: p.textMuted, letterSpacing: 2),
          ),
          const SizedBox(height: Space.s2),
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            time,
            style: t.amountXl.copyWith(
              fontSize: 64,
              height: 1.1,
              color: p.textPrimary,
            ),
          ),
        ),
        Text(
          DateFormat.MMMMEEEEd().format(_now),
          style: t.body.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}
