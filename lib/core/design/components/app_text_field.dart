import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// Floating-label text field (a `TextFormField` underneath, so it also works inside a `Form`). Shakes (and optionally buzzes) when [errorText]
/// appears or changes. Pass your own [controller]/[focusNode] to keep their
/// lifecycle; if omitted, the field creates and disposes its own.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.errorText,
    this.helperText,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.showObscureToggle = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.mono = false,
    this.haptic = true,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? errorText;
  final String? helperText;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;

  /// Adds an eye toggle (password fields).
  final bool showObscureToggle;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int maxLines;

  /// The tabular amount style (Manrope `tnum`) — amounts, SKUs, codes.
  final bool mono;
  final bool haptic;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: Motion.slower,
  );
  TextEditingController? _ownController;
  late bool _obscured = widget.obscureText;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void didUpdateWidget(covariant AppTextField old) {
    super.didUpdateWidget(old);
    final err = widget.errorText;
    if (err != null && err != old.errorText && !Motion.reduced(context)) {
      _shake.forward(from: 0);
      if (widget.haptic) HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final style = (widget.mono ? t.amountMd : t.body).copyWith(
      color: p.textPrimary,
    );

    Widget? suffix = widget.suffix;
    if (widget.showObscureToggle) {
      suffix = IconButton(
        tooltip: _obscured ? 'Show' : 'Hide',
        constraints: const BoxConstraints(
          minWidth: Space.minTouch,
          minHeight: Space.minTouch,
        ),
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: p.textMuted,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }

    final field = TextFormField(
      controller: _controller,
      focusNode: widget.focusNode,
      obscureText: widget.showObscureToggle ? _obscured : widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      maxLines: widget.obscureText || widget.showObscureToggle
          ? 1
          : widget.maxLines,
      style: style,
      cursorColor: p.accent,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helperText,
        errorText: widget.errorText,
        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(widget.prefixIcon, color: p.textMuted),
        suffixIcon: suffix,
      ),
    );

    return AnimatedBuilder(
      animation: _shake,
      child: field,
      builder: (context, child) {
        final dx =
            math.sin(_shake.value * math.pi * 5) * (1 - _shake.value) * 8;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}
