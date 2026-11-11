import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Full-screen camera barcode scanner. Pops with the decoded barcode string
/// once a code is detected, or null if the user backs out.
///
/// G5.1 CONTINUOUS mode ([onCode] given): the camera stays open and every new code goes to [onCode], which answers a short line to show
/// ("Added Rice 5kg", "Not found: 123…"). The same code is ignored for 1.5 s (no double add while it is still in view); Done closes it.
class PosScanCameraView extends StatefulWidget {
  const PosScanCameraView({super.key, this.onCode, this.title});
  final Future<String?> Function(String code)? onCode;
  final String? title;

  @override
  State<PosScanCameraView> createState() => _PosScanCameraViewState();
}

class _PosScanCameraViewState extends State<PosScanCameraView> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastLine;
  int _count = 0;
  bool _working = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    final onCode = widget.onCode;
    if (onCode == null) {
      _handled = true;
      Get.back(result: code);
      return;
    }
    final now = DateTime.now();
    if (_working || (code == _lastCode && now.difference(_lastAt) < const Duration(milliseconds: 1500))) return;
    _lastCode = code;
    _lastAt = now;
    _working = true;
    onCode(code).then((line) {
      if (!mounted) return;
      setState(() {
        _count++;
        _lastLine = line ?? code;
        _working = false;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always dark: a camera viewfinder reads best on ink, whatever the app theme.
    return InkScope(
      lightStatusBar: true,
      child: Builder(
        builder: (context) {
          final p = context.palette;
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(widget.title ?? (widget.onCode != null ? 'Keep scanning' : 'Scan barcode'), style: context.type.title.copyWith(color: Colors.white)),
              actions: [
                IconButton(
                  tooltip: 'Torch',
                  constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
                  icon: ValueListenableBuilder(
                    valueListenable: _controller,
                    builder: (context, state, child) => Icon(state.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white),
                  ),
                  onPressed: () => _controller.toggleTorch(),
                ),
              ],
            ),
            body: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect, errorBuilder: (context, error) => ScanCameraProblem(error: error)),
                Container(
                  width: 260,
                  height: 170,
                  decoration: BoxDecoration(border: Border.all(color: p.accent, width: 3), borderRadius: Radii.rLg),
                ),
                Positioned(
                  bottom: Space.s10,
                  left: Space.s4,
                  right: Space.s4,
                  child: widget.onCode == null
                      ? Text('Align the barcode within the frame', textAlign: TextAlign.center, style: context.type.body.copyWith(color: Colors.white70))
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_lastLine ?? 'Scan one item after another', key: const Key('scanLastLine'), textAlign: TextAlign.center, style: context.type.body.copyWith(color: Colors.white)),
                            if (_count > 0) Text('$_count scanned', key: const Key('scanCount'), style: context.type.caption.copyWith(color: Colors.white70)),
                            const SizedBox(height: Space.s3),
                            AppButton(key: const Key('scanDone'), label: 'Done', onPressed: () => Get.back<String>()),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The camera could not start (permission denied / turned off in Settings / no camera): say so plainly and offer the way out — the barcode can
/// always be typed or searched by name, so nothing is blocked.
class ScanCameraProblem extends StatelessWidget {
  const ScanCameraProblem({super.key, required this.error, this.onOpenSettings});
  final MobileScannerException error;
  final Future<void> Function()? onOpenSettings;

  bool get denied => error.errorCode == MobileScannerErrorCode.permissionDenied;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: Space.s3),
            Text(
              denied ? 'Camera access is off' : 'The camera could not start',
              key: const Key('scanProblemTitle'),
              style: context.type.title.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.s2),
            Text(
              denied ? 'Allow the camera in Settings to scan barcodes. Until then, type the barcode or search by name — selling is not affected.' : 'You can type the barcode or search by name instead.',
              key: const Key('scanProblemBody'),
              style: context.type.body.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.s4),
            if (denied)
              AppButton(key: const Key('scanOpenSettings'), label: 'Open Settings', onPressed: () => (onOpenSettings ?? () async { await openAppSettings(); })()),
            const SizedBox(height: Space.s2),
            AppButton(key: const Key('scanTypeInstead'), label: 'Type it instead', variant: AppButtonVariant.secondary, onPressed: () => Get.back<String>()),
          ],
        ),
      ),
    );
  }
}
