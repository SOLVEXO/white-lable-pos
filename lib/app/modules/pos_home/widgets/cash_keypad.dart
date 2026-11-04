import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Numeric keypad for "cash received". It reads the field's CURRENT text from [controller] at the moment of each key
/// press (never a copy from the last build, so two quick presses in one frame can't act on stale text) and hands back
/// the NEW text ([onChanged]); the caller writes it into `tenderedController` and refreshes the cart exactly as the old
/// text field did. Limits decimals to
/// [decimals] (the currency's own). Also accepts a physical keyboard while it has focus.
class CashKeypad extends StatefulWidget {
  const CashKeypad({super.key, required this.controller, required this.decimals, required this.onChanged, this.enabled = true});
  final TextEditingController controller;
  final int decimals;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// The text after pressing [key] ('0'-'9', '.', or 'back') on [current]. Exposed for tests.
  static String apply(String current, String key, int decimals) {
    if (key == 'back') return current.isEmpty ? current : current.substring(0, current.length - 1);
    if (key == '.') {
      if (decimals <= 0 || current.contains('.')) return current;
      return current.isEmpty ? '0.' : '$current.';
    }
    if (current == '0') return key; // no leading zeros
    final dot = current.indexOf('.');
    if (dot >= 0 && current.length - dot - 1 >= decimals) return current; // currency has no more decimals
    if (current.length >= 12) return current;
    return '$current$key';
  }

  @override
  State<CashKeypad> createState() => _CashKeypadState();
}

class _CashKeypadState extends State<CashKeypad> {
  final FocusNode _focus = FocusNode(debugLabel: 'CashKeypad');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _press(String key) {
    if (!widget.enabled) return;
    _focus.requestFocus();
    HapticFeedback.selectionClick();
    widget.onChanged(CashKeypad.apply(widget.controller.text, key, widget.decimals));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!widget.enabled || e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
      widget.onChanged(CashKeypad.apply(widget.controller.text, 'back', widget.decimals));
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (e is KeyDownEvent && ch != null && ch.length == 1 && ('0123456789'.contains(ch) || ch == '.')) {
      widget.onChanged(CashKeypad.apply(widget.controller.text, ch, widget.decimals));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // shorter keys on short screens (small phones, landscape phones) so the whole pad fits above the Charge button
    // (G1a: the blueprint fonts have taller line boxes than the ones this sheet was laid out with. The decision uses the height the
    // app really has — screen minus status bar and home indicator — so a phone as tall as an iPhone 17 Pro, whose usable height is
    // ~780 px, also gets the 44 px keys (still the minimum tap target) and the pad stays clear of the Charge button.)
    final m = MediaQuery.of(context);
    final keyH = m.size.height < 900 ? 44.0 : 56.0;
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in rows) _row([for (final d in r) _Key(label: d, height: keyH, onTap: () => _press(d))]),
          _row([
            widget.decimals > 0 ? _Key(label: '.', height: keyH, onTap: () => _press('.')) : const SizedBox.shrink(),
            _Key(label: '0', height: keyH, onTap: () => _press('0')),
            _Key(icon: Icons.backspace_outlined, semantic: 'Delete', height: keyH, onTap: () => _press('back'), onLongPress: () => widget.onChanged('')),
          ]),
        ],
      ),
    );
  }

  Widget _row(List<Widget> kids) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [for (final k in kids) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: k))]),
  );
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.semantic, required this.height, required this.onTap, this.onLongPress});
  final String? label;
  final IconData? icon;
  final String? semantic;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: semantic ?? label,
      excludeSemantics: true,
      child: Material(
        color: icon != null ? Colors.transparent : p.fill,
        borderRadius: Radii.rMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            height: height,
            child: Center(child: icon != null ? Icon(icon, size: 22, color: p.textSecondary) : Text(label!, style: context.type.amountLg.copyWith(color: p.textPrimary))),
          ),
        ),
      ),
    );
  }
}
