import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_scan_camera_view.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Look up a product by barcode and add it straight to the cart.
/// Also exposes a "Scan with camera" entry point (see [PosScanCameraSheet]).
class PosBarcodeSheet extends StatefulWidget {
  final PosHomeController c;
  const PosBarcodeSheet({super.key, required this.c});

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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: AppColors.lightGrey2, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const CustomText(
            text: 'Scan or enter barcode',
            fontSize: AppFontSize.small2,
            fontWeight: FontWeight.bold,
            color: AppColors.black2,
          ),
          const SizedBox(height: 4),
          const CustomText(
            text: 'Point the camera at a barcode, or type it in manually.',
            fontSize: AppFontSize.tiny,
            color: AppColors.iosGrey,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              Get.back();
              final code = await Get.to<String>(() => const PosScanCameraView());
              if (code != null && code.isNotEmpty) {
                await widget.c.addProductByBarcode(code);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryColor.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryColor, size: 20),
                  SizedBox(width: 8),
                  CustomText(
                    text: 'Scan with camera',
                    fontSize: AppFontSize.verySmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: CustomTextField(
                controller: _controller,
                hintText: 'Barcode number',
                keyboardType: TextInputType.number,
                fillColor: AppColors.background,
                onFieldSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _submit,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.arrow_forward_rounded, color: AppColors.white),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
