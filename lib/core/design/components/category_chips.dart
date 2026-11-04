import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// Horizontally scrolling chips with a pill that slides to the selection.
/// Chip widths are measured after layout, so labels can be any length.
class CategoryChips extends StatefulWidget {
  const CategoryChips({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<CategoryChips> {
  final _rowKey = GlobalKey();
  final _scroll = ScrollController();
  List<GlobalKey> _keys = const [];
  Rect? _pill;

  @override
  void initState() {
    super.initState();
    _syncKeys();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _measure(animateScroll: false),
    );
  }

  @override
  void didUpdateWidget(covariant CategoryChips old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) _syncKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncKeys() =>
      _keys = List.generate(widget.labels.length, (_) => GlobalKey());

  void _measure({bool animateScroll = true}) {
    if (!mounted ||
        widget.selectedIndex < 0 ||
        widget.selectedIndex >= _keys.length) {
      return;
    }
    final rowBox = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    final chipBox =
        _keys[widget.selectedIndex].currentContext?.findRenderObject()
            as RenderBox?;
    if (rowBox == null ||
        chipBox == null ||
        !rowBox.attached ||
        !chipBox.attached) {
      return;
    }
    final topLeft = chipBox.localToGlobal(Offset.zero, ancestor: rowBox);
    final r = topLeft & chipBox.size;
    if (r != _pill) setState(() => _pill = r);
    if (_scroll.hasClients) {
      final target = (r.center.dx - _scroll.position.viewportDimension / 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      if (animateScroll && !Motion.reduced(context)) {
        _scroll.animateTo(
          target,
          duration: Motion.slow,
          curve: Motion.emphasized,
        );
      } else {
        _scroll.jumpTo(target);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dur = Motion.of(context, Motion.slow);
    return SizedBox(
      height: Space.minTouch,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        child: Stack(
          key: _rowKey,
          children: [
            if (_pill != null)
              AnimatedPositioned(
                duration: dur,
                curve: Motion.emphasized,
                left: _pill!.left,
                top: _pill!.top,
                width: _pill!.width,
                height: _pill!.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.accent,
                    borderRadius: Radii.rFull,
                  ),
                ),
              ),
            Row(
              children: [
                for (var i = 0; i < widget.labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s2),
                  _Chip(
                    key: _keys[i],
                    label: widget.labels[i],
                    selected: i == widget.selectedIndex,
                    onTap: () => widget.onSelected(i),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: Radii.rFull,
            border: Border.all(color: selected ? Colors.transparent : p.border),
          ),
          child: AnimatedDefaultTextStyle(
            duration: Motion.of(context, Motion.base),
            style: context.type.label.copyWith(
              color: selected ? p.onAccent : p.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
