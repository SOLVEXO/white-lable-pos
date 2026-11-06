import 'package:flutter/material.dart';

/// Covers [child] with an opaque panel whenever the app is not in the foreground (inactive / paused / hidden). iOS takes the app-switcher
/// snapshot as the app goes inactive, so what is on screen then is what shows in the switcher: this makes that a plain panel.
class PrivacyCurtain extends StatefulWidget {
  const PrivacyCurtain({super.key, required this.child, this.message = 'Hidden for your privacy'});
  final Widget child;
  final String message;

  @override
  State<PrivacyCurtain> createState() => _PrivacyCurtainState();
}

class _PrivacyCurtainState extends State<PrivacyCurtain> with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cover = state != AppLifecycleState.resumed;
    if (cover != _covered) setState(() => _covered = cover);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: ColoredBox(
              key: const Key('privacyCurtain'),
              color: Theme.of(context).colorScheme.surface,
              child: Center(child: Icon(Icons.lock_outline_rounded, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
      ],
    );
  }
}
