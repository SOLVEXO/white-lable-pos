import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_scan_camera_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Look up a product by barcode and add it straight to the cart.
/// Also exposes a "Scan with camera" entry point (see [PosScanCameraView]).
/// Opened with `Get.bottomSheet` (transparent route background), so it draws its own surface.
class PosBarcodeSheet extends StatefulWidget {
  final PosHomeController c;

  /// The camera screen opened by "Scan with camera" — production uses [PosScanCameraView]; a test can substitute a
  /// stand-in that pops with a code (the real one needs the camera plugin).
  final Widget Function()? scanScreenBuilder;

  const PosBarcodeSheet({super.key, required this.c, this.scanScreenBuilder});

  @override
  State<PosBarcodeSheet> createState() => _PosBarcodeSheetState();
}

class _PosBarcodeSheetState extends State<PosBarcodeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    Get.back();
    await widget.c.addProductByBarcode(code);
  }

  Future<void> _scan() async {
    Get.back();
    final code = await Get.to<String>(() => (widget.scanScreenBuilder ?? () => const PosScanCameraView())());
    if (code != null && code.isNotEmpty) {
      await widget.c.addProductByBarcode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppSheetSurface(
      title: 'Scan or enter barcode',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Point the camera at a barcode, or type it in manually.', style: context.type.body.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s4),
          AppButton(key: const Key('scanWithCamera'), label: 'Scan with camera', icon: Icons.qr_code_scanner_rounded, variant: AppButtonVariant.secondary, onPressed: _scan),
          const SizedBox(height: Space.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  key: const Key('barcodeField'),
                  label: 'Barcode number',
                  controller: _controller,
                  mono: true,
                  prefixIcon: Icons.qr_code_2_rounded,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: Space.s3),
              SizedBox(
                width: 56,
                child: AppButton(key: const Key('barcodeSubmit'), label: '', semanticLabel: 'Add product', icon: Icons.arrow_forward_rounded, size: AppButtonSize.lg, expand: true, onPressed: _submit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
