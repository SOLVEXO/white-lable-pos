import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
                MobileScanner(controller: _controller, onDetect: _onDetect),
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
