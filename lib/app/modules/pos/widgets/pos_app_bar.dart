import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solvexo_pos/config/app_brand.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// The header of the till's Products / Transactions / Settings screens: drawn on the page background (palette tokens
/// only, so it follows light and dark), a caption-sized subtitle over a headline title, and the cashier's initial.
class PosAppBar extends StatelessWidget {
  final String title;

  /// Defaults to "{tenant app name} POS" via BrandingService when unset.
  final String? subtitle;

  const PosAppBar({super.key, this.title = 'Quick Sale', this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final effectiveSubtitle = subtitle ?? '${AppBrand.appName} POS';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        color: p.background,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + Space.s3,
          left: Space.s5,
          right: Space.s5,
          bottom: Space.s2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(effectiveSubtitle, style: t.caption.copyWith(color: p.textSecondary)),
                  const SizedBox(height: 2),
                  Semantics(
                    header: true,
                    child: Text(title, style: t.headline.copyWith(color: p.textPrimary)),
                  ),
                ],
              ),
            ),
            FutureBuilder<String?>(
              future: AppPreferences.getPosEmployeeName(),
              builder: (context, snapshot) {
                final name = snapshot.data ?? '';
                final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';
                return Container(
                  width: Space.s10,
                  height: Space.s10,
                  decoration: BoxDecoration(color: p.accentFill, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(initial, style: t.subtitle.copyWith(color: p.onAccentFill, fontWeight: FontWeight.w700)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
