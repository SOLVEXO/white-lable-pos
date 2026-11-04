import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Forces the dark palette for a subtree, whatever the app theme is. Used by
/// the splash and the auto-lock overlay, which are always dark ink.
///
/// [lightStatusBar] also makes the system status-bar icons light, so the clock
/// and battery stay readable on the dark ink (pass it for full-screen uses; a
/// half-screen panel must not claim the status bar).
class InkScope extends StatelessWidget {
  const InkScope({super.key, required this.child, this.lightStatusBar = false});
  final Widget child;
  final bool lightStatusBar;

  @override
  Widget build(BuildContext context) {
    final themed = Theme(data: AppTheme.dark, child: child);
    if (!lightStatusBar) return themed;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness:
            Brightness.dark, // iOS (describes the content behind the bar)
      ),
      child: themed,
    );
  }
}
