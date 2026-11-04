import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// Search field with clear button and an optional scan (barcode) action.
/// Named `AppSearchBar` to avoid colliding with Material's `SearchBar`.
class AppSearchBar extends StatefulWidget {
  const AppSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onScan,
    this.autofocus = false,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Shows a scan button when set.
  final VoidCallback? onScan;
  final bool autofocus;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  TextEditingController? _own;
  TextEditingController get _c =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _c,
      builder: (context, value, _) => TextField(
        controller: _c,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        style: context.type.body.copyWith(color: p.textPrimary),
        cursorColor: p.accent,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: Icon(Icons.search_rounded, color: p.textMuted),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  constraints: const BoxConstraints(
                    minWidth: Space.minTouch,
                    minHeight: Space.minTouch,
                  ),
                  icon: Icon(Icons.close_rounded, color: p.textMuted),
                  onPressed: () {
                    _c.clear();
                    widget.onChanged?.call('');
                  },
                ),
              if (widget.onScan != null)
                IconButton(
                  tooltip: 'Scan barcode',
                  constraints: const BoxConstraints(
                    minWidth: Space.minTouch,
                    minHeight: Space.minTouch,
                  ),
                  icon: Icon(Icons.qr_code_scanner_rounded, color: p.accentFg),
                  onPressed: widget.onScan,
                ),
            ],
          ),
          border: OutlineInputBorder(
            borderRadius: Radii.rFull,
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: Radii.rFull,
            borderSide: BorderSide(color: p.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: Radii.rFull,
            borderSide: BorderSide(color: p.accent, width: 2),
          ),
        ),
      ),
    );
  }
}
