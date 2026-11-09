import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Full-screen camera barcode scanner. Pops with the decoded barcode string
/// once a code is detected, or null if the user backs out.
class PosScanCameraView extends StatefulWidget {
  const PosScanCameraView({super.key});

  @override
  State<PosScanCameraView> createState() => _PosScanCameraViewState();
}

class _PosScanCameraViewState extends State<PosScanCameraView> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    Get.back(result: code);
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
              title: Text('Scan barcode', style: context.type.title.copyWith(color: Colors.white)),
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
                  child: Text('Align the barcode within the frame', style: context.type.body.copyWith(color: Colors.white70)),
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
