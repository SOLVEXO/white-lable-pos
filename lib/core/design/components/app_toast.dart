import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

enum ToastType { success, error, warning, info }

enum ToastPosition { top, bottom }

/// Single, consistent in-app toast. One toast at a time: a new one replaces the
/// current one rather than stacking. Announced to screen readers (live region).
///
/// Works without a BuildContext (uses GetX's overlay context) so the legacy
/// `CustomAppSnackbar` / `ToastUtil` adapters can delegate here.
abstract final class AppToast {
  static _ToastHandle? _entry;

  static void success(String message, {String? title, BuildContext? context}) =>
      show(message, type: ToastType.success, title: title, context: context);
  static void error(String message, {String? title, BuildContext? context}) =>
      show(message, type: ToastType.error, title: title, context: context);
  static void warning(String message, {String? title, BuildContext? context}) =>
      show(message, type: ToastType.warning, title: title, context: context);
  static void info(String message, {String? title, BuildContext? context}) =>
      show(message, type: ToastType.info, title: title, context: context);

  static void show(
    String message, {
    ToastType type = ToastType.info,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
    ToastPosition position = ToastPosition.top,
    BuildContext? context,
  }) {
    final ctx = context ?? Get.overlayContext;
    if (ctx == null) return;
    final overlay = Overlay.maybeOf(ctx, rootOverlay: true);
    if (overlay == null) return;

    dismiss();
    late final _ToastHandle handle;
    // Carry the caller's theme (light/dark) into the root overlay.
    final themes = InheritedTheme.capture(from: ctx, to: overlay.context);
    final entry = OverlayEntry(
      builder: (_) => themes.wrap(
        _ToastView(
          message: message,
          duration: duration,
          title: title,
          type: type,
          position: position,
          actionLabel: actionLabel,
          onAction: onAction,
          onDismissed: () {
            if (_entry == handle) _entry = null;
            handle.remove();
          },
        ),
      ),
    );
    handle = _ToastHandle(entry);
    _entry = handle;
    overlay.insert(entry);
  }

  /// Removes the current toast immediately.
  static void dismiss() {
    final h = _entry;
    _entry = null;
    h?.remove();
  }
}

/// An overlay entry that can be removed any number of times, from any path (the toast's own timer, a swipe, `dismiss()`),
/// but is only ever removed and disposed once. (`OverlayEntry.mounted` stays true until the next frame after `remove()`,
/// so it cannot be used for this.)
class _ToastHandle {
  _ToastHandle(this.entry);
  final OverlayEntry entry;
  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    entry.remove();
    entry.dispose();
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.duration,
    required this.type,
    required this.position,
    required this.onDismissed,
    this.title,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final Duration duration;
  final String? title;
  final ToastType type;
  final ToastPosition position;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissed;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.slow,
    reverseDuration: Motion.base,
  )..forward();
  bool _hiding = false;
  // Owned by the State so it dies with the widget tree (no orphan timers).
  late final Timer _timer = Timer(widget.duration, hide);

  Future<void> hide() async {
    if (_hiding || !mounted) return;
    _hiding = true;
    await _c.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void initState() {
    super.initState();
    _timer; // start the auto-dismiss countdown
  }

  @override
  void dispose() {
    _timer.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = widget.position == ToastPosition.top;
    final (icon, tone, soft) = switch (widget.type) {
      ToastType.success => (
        Icons.check_circle_rounded,
        p.successFg,
        p.successSoft,
      ),
      ToastType.error => (Icons.error_rounded, p.dangerFg, p.dangerSoft),
      ToastType.warning => (
        Icons.warning_amber_rounded,
        p.warningFg,
        p.warningSoft,
      ),
      ToastType.info => (Icons.info_rounded, p.infoFg, p.infoSoft),
    };
    final reduced = Motion.reduced(context);
    final curved = CurvedAnimation(
      parent: _c,
      curve: Motion.emphasized,
      reverseCurve: Curves.easeIn,
    );
    final mq = MediaQuery.of(context);

    return Positioned(
      top: top ? mq.padding.top + Space.s3 : null,
      bottom: top ? null : mq.padding.bottom + 80,
      left: Space.s4,
      right: Space.s4,
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: reduced ? Offset.zero : Offset(0, top ? -0.4 : 0.4),
                end: Offset.zero,
              ).animate(curved),
              child: Dismissible(
                key: const ValueKey('app_toast'),
                direction: top ? DismissDirection.up : DismissDirection.down,
                onDismissed: (_) => widget.onDismissed(),
                child: Semantics(
                  liveRegion: true,
                  label: '${widget.title ?? ''} ${widget.message}'.trim(),
                  excludeSemantics: true,
                  child: Material(
                    color: p.surfaceRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: Radii.rMd,
                      side: BorderSide(color: p.border),
                    ),
                    elevation: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: Radii.rMd,
                        boxShadow: context.overlayShadow,
                      ),
                      child: InkWell(
                        borderRadius: Radii.rMd,
                        onTap: hide,
                        child: Padding(
                          padding: const EdgeInsets.all(Space.s3),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: soft,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(icon, size: 20, color: tone),
                              ),
                              const SizedBox(width: Space.s3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.title != null)
                                      Text(
                                        widget.title!,
                                        style: context.type.label.copyWith(
                                          color: tone,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    Text(
                                      widget.message,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.type.bodySmall.copyWith(
                                        color: p.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.actionLabel != null)
                                TextButton(
                                  onPressed: () {
                                    widget.onAction?.call();
                                    hide();
                                  },
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      Space.minTouch,
                                      Space.minTouch,
                                    ),
                                    foregroundColor: p.accentFg,
                                  ),
                                  child: Text(
                                    widget.actionLabel!,
                                    style: context.type.label.copyWith(
                                      color: p.accentFg,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
