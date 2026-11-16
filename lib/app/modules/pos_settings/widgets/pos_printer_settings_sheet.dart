import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Per-device receipt printing options. Changing them is for managers/the owner (the Settings tile checks the role);
/// they apply to THIS device only.
class PosPrinterSettingsSheet extends StatelessWidget {
  const PosPrinterSettingsSheet({super.key, required this.service, this.canEdit = true});
  final ThermalPrinterService service;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    // stack the two test buttons when large text would squeeze them side by side
    final stack = MediaQuery.textScalerOf(context).scale(16) > 19;
    final testPrint = AppButton(
      key: const Key('testPrint'),
      label: 'Print test page',
      variant: AppButtonVariant.secondary,
      icon: Icons.print_rounded,
      expand: true,
      onPressed: () async {
        final err = await service.printTest();
        if (err != null) {
          CustomAppSnackbar.error(err);
        } else {
          CustomAppSnackbar.success('Test page sent to the printer.');
        }
      },
    );
    final testDrawer = AppButton(
      key: const Key('testDrawer'),
      label: 'Open drawer',
      variant: AppButtonVariant.secondary,
      icon: Icons.point_of_sale_rounded,
      expand: true,
      onPressed: () async {
        final err = await service.openDrawer();
        if (err != null) CustomAppSnackbar.error(err);
      },
    );
    return AppSheetFrame(
      title: 'Printer settings',
      child: Obx(() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!canEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s3),
                child: Text('Only a manager can change these.', style: t.bodySmall.copyWith(color: p.textSecondary)),
              ),
            Text('Paper width', style: t.label.copyWith(color: p.textPrimary)),
            const SizedBox(height: Space.s2),
            SegmentedButton<int>(
              key: const Key('paperWidth'),
              segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
              selected: {service.paperMm.value},
              onSelectionChanged: canEdit ? (s) => service.setPaperMm(s.first) : null,
            ),
            const SizedBox(height: Space.s2),
            SwitchListTile(
              key: const Key('autoPrint'),
              contentPadding: EdgeInsets.zero,
              title: Text('Print receipt after each sale', style: t.body.copyWith(color: p.textPrimary)),
              value: service.autoPrint.value,
              onChanged: canEdit ? service.setAutoPrint : null,
            ),
            SwitchListTile(
              key: const Key('kickDrawer'),
              contentPadding: EdgeInsets.zero,
              title: Text('Open cash drawer on cash sales', style: t.body.copyWith(color: p.textPrimary)),
              subtitle: Text('Needs a drawer connected to the printer', style: t.bodySmall.copyWith(color: p.textSecondary)),
              value: service.kickDrawer.value,
              onChanged: canEdit ? service.setKickDrawer : null,
            ),
            Row(children: [
              Expanded(child: Text('Copies', style: t.body.copyWith(color: p.textPrimary))),
              IconButton(
                key: const Key('copiesMinus'),
                tooltip: 'Fewer copies',
                onPressed: canEdit && service.copies.value > 1 ? () => service.setCopies(service.copies.value - 1) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${service.copies.value}', style: t.amountMd.copyWith(color: p.textPrimary)),
              IconButton(
                key: const Key('copiesPlus'),
                tooltip: 'More copies',
                onPressed: canEdit && service.copies.value < 5 ? () => service.setCopies(service.copies.value + 1) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            const SizedBox(height: Space.s3),
            if (stack) ...[
              testPrint,
              const SizedBox(height: Space.s2),
              testDrawer,
            ] else
              Row(children: [
                Expanded(child: testPrint),
                const SizedBox(width: Space.s3),
                Expanded(child: testDrawer),
              ]),
          ])),
    );
  }
}
