import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// PIN progress dots. Fill is animated; bump [errorTick] to shake (with a heavy
/// haptic) — the dots themselves hold no PIN state, the screen does.
class PinDots extends StatefulWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.errorTick = 0,
    this.hasError = false,
  });
  final int length;
  final int filled;
  final int errorTick;
  final bool hasError;

  @override
  State<PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<PinDots> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: Motion.slower,
  );

  @override
  void didUpdateWidget(covariant PinDots old) {
    super.didUpdateWidget(old);
    if (widget.errorTick != old.errorTick) {
      HapticFeedback.heavyImpact();
      if (!Motion.reduced(context)) _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final on = widget.hasError ? p.danger : p.accent;
    return Semantics(
      label: 'PIN',
      value: '${widget.filled} of ${widget.length} digits entered',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            math.sin(_shake.value * math.pi * 6) * (1 - _shake.value) * 12,
            0,
          ),
          child: child,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.base),
                  curve: Motion.spring,
                  width: 16,
                  height: 16,
                  transform: Matrix4.diagonal3Values(
                    i < widget.filled ? 1.0 : 0.78,
                    i < widget.filled ? 1.0 : 0.78,
                    1,
                  ),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < widget.filled ? on : Colors.transparent,
                    border: Border.all(
                      color: i < widget.filled ? on : p.border,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 3×4 numeric keypad. Pure input: it reports digits/backspace and keeps no PIN
/// state. Keys give a light haptic. [extraKey] fills the bottom-left slot.
///
/// Also accepts a physical keyboard (tablets): digits 0-9 (incl. numpad),
/// Backspace/Delete → [onBackspace], Escape → [onClear]. Key events are handled
/// only while the pad owns focus, so a text field elsewhere on the screen still
/// receives its own typing; tapping a pad key gives the pad focus.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onClear,
    this.enabled = true,
    this.extraKey,
    this.autofocus = false,
  });
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Long-press on backspace, and Escape on a keyboard.
  final VoidCallback? onClear;
  final bool enabled;
  final Widget? extraKey;

  /// Take keyboard focus as soon as the pad appears (lock screen, gates).
  final bool autofocus;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  final FocusNode _focus = FocusNode(debugLabel: 'PinPad');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!widget.enabled || e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      widget.onBackspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && widget.onClear != null) {
      widget.onClear!();
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (e is KeyDownEvent &&
        ch != null &&
        ch.length == 1 &&
        '0123456789'.contains(ch)) {
      widget.onDigit(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _digit(String d) {
    _focus.requestFocus();
    widget.onDigit(d);
  }

  @override
  Widget build(BuildContext context) {
    final keyH = context.isPhone ? 64.0 : 72.0;
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              _row([
                for (final d in row)
                  _PadKey(
                    label: d,
                    height: keyH,
                    enabled: widget.enabled,
                    onTap: () => _digit(d),
                  ),
              ]),
            _row([
              widget.extraKey ?? const SizedBox.shrink(),
              _PadKey(
                label: '0',
                height: keyH,
                enabled: widget.enabled,
                onTap: () => _digit('0'),
              ),
              _PadKey(
                icon: Icons.backspace_outlined,
                semantic: 'Delete',
                height: keyH,
                enabled: widget.enabled,
                onTap: () {
                  _focus.requestFocus();
                  widget.onBackspace();
                },
                onLongPress: widget.onClear,
                quiet: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        for (final c in children)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: c,
            ),
          ),
      ],
    ),
  );
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    this.label,
    this.icon,
    this.semantic,
    required this.height,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
    this.quiet = false,
  });
  final String? label;
  final IconData? icon;
  final String? semantic;
  final double height;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic ?? label,
      excludeSemantics: true,
      child: Material(
        color: quiet ? Colors.transparent : p.fill,
        borderRadius: Radii.rLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          onLongPress: enabled ? onLongPress : null,
          child: SizedBox(
            height: height,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 24, color: p.textSecondary)
                  : Text(
                      label!,
                      style: context.type.amountLg.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
