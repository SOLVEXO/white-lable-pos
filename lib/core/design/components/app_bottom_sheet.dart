import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../tokens/palette.dart';
import '../tokens/tokens.dart';

/// Modal bottom sheet: drag handle, optional title, keyboard-aware, and capped
/// to 560 px wide on tablets so it doesn't stretch edge to edge.
abstract final class AppBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useRootNavigator = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useRootNavigator: useRootNavigator,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => AppSheetFrame(title: title, child: builder(ctx)),
    );
  }

  /// Same look as [show], but presented with `Get.bottomSheet`, so GetX's `Get.isBottomSheetOpen` is true while it is
  /// up. The POS keyboard-wedge barcode scanner checks that flag to stay quiet while a sheet is open; a plain
  /// `showModalBottomSheet` would not set it. [child] provides its own content (wrapped in [AppSheetSurface]).
  ///
  /// Set [scrollable] to false when [child] contains its own scrolling list (it then gets the remaining height).
  static Future<T?> showGet<T>(
    Widget child, {
    String? title,
    bool isDismissible = true,
    bool enableDrag = true,
    bool scrollable = true,
    double maxWidth = 560,
  }) {
    return Get.bottomSheet<T>(
      AppSheetSurface(title: title, scrollable: scrollable, maxWidth: maxWidth, child: child),
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      barrierColor: (Get.theme.extension<AppPalette>() ?? AppPalette.light).scrim,
    );
  }
}

/// The surface of a sheet presented with `Get.bottomSheet` (whose route background is transparent): rounded top, the
/// palette's surface colour, centred and width-capped, with the standard [AppSheetFrame] chrome inside.
class AppSheetSurface extends StatelessWidget {
  const AppSheetSurface({super.key, required this.child, this.title, this.scrollable = true, this.maxWidth = 560, this.padding});
  final Widget child;
  final String? title;
  final bool scrollable;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(context).height * 0.94),
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
            side: BorderSide(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: AppSheetFrame(title: title, scrollable: scrollable, padding: padding ?? const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5), child: child),
        ),
      ),
    );
  }
}

/// The chrome inside an [AppBottomSheet]; also usable directly for custom sheets.
class AppSheetFrame extends StatelessWidget {
  const AppSheetFrame({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5),
    this.scrollable = true,
  });
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry padding;

  /// False when [child] manages its own scrolling (a list); it is then laid out in the remaining space.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedPadding(
      duration: Motion.of(context, Motion.base),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: Space.s3),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: p.border, borderRadius: Radii.rFull),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s3),
                child: Semantics(header: true, child: Text(title!, style: context.type.title.copyWith(color: p.textPrimary))),
              ),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(padding: padding, child: child)
                  : Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}
