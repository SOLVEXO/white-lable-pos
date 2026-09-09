import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Bottom sheet listing the device's paired Bluetooth printers, so a
/// cashier can pick one once and have it remembered — see
/// ThermalPrinterService's doc comment.
class PosPrinterPickerSheet extends StatefulWidget {
  final ThermalPrinterService service;

  const PosPrinterPickerSheet({super.key, required this.service});

  @override
  State<PosPrinterPickerSheet> createState() => _PosPrinterPickerSheetState();
}

class _PosPrinterPickerSheetState extends State<PosPrinterPickerSheet> {
  bool _loading = true;
  bool _bluetoothOff = false;
  List<PosPrinterOption> _options = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.service.isBluetoothEnabled;
    if (!enabled) {
      setState(() {
        _bluetoothOff = true;
        _loading = false;
      });
      return;
    }
    final options = await widget.service.listPairedPrinters();
    setState(() {
      _options = options;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightGrey2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const CustomText(
            text: 'Select receipt printer',
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: 4),
          const CustomText(
            text: 'Pair the printer in your device\'s Bluetooth settings first, then pick it here.',
            fontSize: AppFontSize.tiny,
            color: AppColors.grey,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bluetoothOff)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CustomText(text: 'Bluetooth is off. Turn it on and try again.'),
            )
          else if (_options.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CustomText(text: 'No paired Bluetooth devices found.'),
            )
          else
            ..._options.map(
              (o) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: CustomText(text: o.name.isEmpty ? o.address : o.name),
                subtitle: CustomText(text: o.address, fontSize: AppFontSize.tiny, color: AppColors.grey),
                trailing: widget.service.savedPrinterAddress.value == o.address
                    ? const Icon(Icons.check_circle, color: AppColors.green)
                    : null,
                onTap: () async {
                  await widget.service.selectPrinter(o);
                  if (context.mounted) Get.back();
                },
              ),
            ),
          if (widget.service.hasSavedPrinter) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await widget.service.forgetPrinter();
                if (context.mounted) Get.back();
              },
              child: const CustomText(text: 'Forget saved printer', color: AppColors.red),
            ),
          ],
        ],
      ),
    );
  }
}
