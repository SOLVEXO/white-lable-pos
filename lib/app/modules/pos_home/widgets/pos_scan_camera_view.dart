import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
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
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: CustomAppBarTwo(
        title: 'Scan barcode',
        backgroundColor: AppColors.black,
        color: AppColors.white,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) => Icon(
                state.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: AppColors.white,
              ),
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
            width: 240,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primaryColor, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const Positioned(
            bottom: 40,
            child: CustomText(
              text: 'Align the barcode within the frame',
              color: Colors.white70,
              fontSize: AppFontSize.verySmall,
            ),
          ),
        ],
      ),
    );
  }
}
