import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'skeleton.dart';

/// Cached network image for the design system.
///
/// - **Decode size follows layout.** The decode cap is taken from the laid-out
///   box (× device pixel ratio), so a grid of full-size product photos is
///   decoded at tile size, not photo size. With `BoxFit.cover` and an unknown
///   image aspect, the cap is set on the *larger* box side (as `memCacheWidth`,
///   which preserves aspect) so both dimensions still cover the box.
///   [cacheWidth] is only the fallback when the box is unbounded.
/// - **Loading:** a skeleton block (shimmer unless reduced motion).
/// - **Error / no URL:** a neutral tinted block with an icon — no red, no text.
///
/// (The legacy `CommonImageView` hard-codes legacy colours and decodes at full
/// size; it stays for un-migrated screens.)
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth = 400,
    this.fallbackIcon = Icons.image_outlined,
  });
  final String? url;
  final BoxFit fit;
  final int cacheWidth;
  final IconData fallbackIcon;

  /// The decode width for a box, exposed for tests.
  @visibleForTesting
  static int decodeWidthFor(
    BoxConstraints box,
    double devicePixelRatio,
    int fallback,
  ) {
    final w = box.hasBoundedWidth ? box.maxWidth : 0.0;
    final h = box.hasBoundedHeight ? box.maxHeight : 0.0;
    final longest = w > h ? w : h;
    if (longest <= 0 || !longest.isFinite) return fallback;
    return (longest * devicePixelRatio).ceil().clamp(32, 2048);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget fallback() => ColoredBox(
      color: p.fill,
      child: Center(child: Icon(fallbackIcon, color: p.textMuted, size: 28)),
    );
    final u = url;
    if (u == null || u.isEmpty) return fallback();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) => CachedNetworkImage(
        imageUrl: u,
        fit: fit,
        memCacheWidth: decodeWidthFor(box, dpr, cacheWidth),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => const SkeletonShimmer(
          child: SizedBox.expand(
            child: SkeletonBox(height: double.infinity, radius: 0),
          ),
        ),
        errorWidget: (_, _, _) => fallback(),
      ),
    );
  }
}
