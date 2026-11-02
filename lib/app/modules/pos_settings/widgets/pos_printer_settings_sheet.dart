import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';

/// Per-device receipt printing options. Changing them is for managers/the owner (the Settings tile checks the role);
/// they apply to THIS device only.
class PosPrinterSettingsSheet extends StatelessWidget {
  const PosPrinterSettingsSheet({super.key, required this.service, this.canEdit = true});
  final ThermalPrinterService service;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Obx(() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Printer settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (!canEdit) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Only a manager can change these.', style: TextStyle(color: AppColors.iosGrey))),
            const SizedBox(height: 14),
            const Text('Paper width'),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              key: const Key('paperWidth'),
              segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
              selected: {service.paperMm.value},
              onSelectionChanged: canEdit ? (s) => service.setPaperMm(s.first) : null,
            ),
            SwitchListTile(
              key: const Key('autoPrint'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Print receipt after each sale'),
              value: service.autoPrint.value,
              onChanged: canEdit ? service.setAutoPrint : null,
            ),
            SwitchListTile(
              key: const Key('kickDrawer'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Open cash drawer on cash sales'),
              subtitle: const Text('Needs a drawer connected to the printer'),
              value: service.kickDrawer.value,
              onChanged: canEdit ? service.setKickDrawer : null,
            ),
            Row(children: [
              const Expanded(child: Text('Copies')),
              IconButton(key: const Key('copiesMinus'), onPressed: canEdit && service.copies.value > 1 ? () => service.setCopies(service.copies.value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('${service.copies.value}', style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(key: const Key('copiesPlus'), onPressed: canEdit && service.copies.value < 5 ? () => service.setCopies(service.copies.value + 1) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('testPrint'),
                  onPressed: () async {
                    final err = await service.printTest();
                    if (err != null) {
                      CustomAppSnackbar.error(err);
                    } else {
                      CustomAppSnackbar.success('Test page sent to the printer.');
                    }
                  },
                  child: const Text('Print test page'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('testDrawer'),
                  onPressed: () async {
                    final err = await service.openDrawer();
                    if (err != null) CustomAppSnackbar.error(err);
                  },
                  child: const Text('Open drawer'),
                ),
              ),
            ]),
          ])),
    );
  }
}
