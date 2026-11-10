import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/pay_supplier_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Pay a supplier: amount, method (cash / bank / other) and a reference. Cash needs the open shift (it comes out of the drawer); with no
/// open shift cash is disabled and the sheet says so. The server decides about limits and the balance.
class PaySupplierSheet extends StatefulWidget {
  const PaySupplierSheet({super.key, required this.controller, required this.currencyCode});
  final PaySupplierController controller;
  final String currencyCode;

  static Future<bool?> open({required String supplierId, required int exponent, required String currencyCode, int? balanceMinor, PaySupplierController? controller}) => AppBottomSheet.showGet<bool>(
    PaySupplierSheet(
      controller: controller ?? PaySupplierController(supplierId: supplierId, exponent: exponent, balanceMinor: balanceMinor),
      currencyCode: currencyCode,
    ),
    title: 'Pay supplier',
  );

  @override
  State<PaySupplierSheet> createState() => _PaySupplierSheetState();
}

class _PaySupplierSheetState extends State<PaySupplierSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  PaySupplierController get c => widget.controller;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (await c.submit() && mounted) Get.back<bool>(result: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          key: const Key('paAmount'),
          label: 'Amount (${widget.currencyCode})',
          controller: _amount,
          mono: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (s) => c.amountText.value = s,
        ),
        if (c.fullBalanceText != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('paFull'),
              onPressed: () {
                _amount.text = c.fullBalanceText!;
                c.amountText.value = c.fullBalanceText!;
              },
              child: const Text('Pay the full balance'),
            ),
          ),
        const SizedBox(height: Space.s3),
        Text('Paid by', style: t.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s1),
        Obx(
          () => Wrap(
            spacing: Space.s2,
            children: [
              ChoiceChip(key: const Key('paCash'), label: const Text('Cash'), selected: c.method.value == 'cash', onSelected: c.canPayCash ? (_) => c.pickMethod('cash') : null),
              ChoiceChip(key: const Key('paBank'), label: const Text('Bank'), selected: c.method.value == 'bank', onSelected: (_) => c.pickMethod('bank')),
              ChoiceChip(key: const Key('paOther'), label: const Text('Other'), selected: c.method.value == 'other', onSelected: (_) => c.pickMethod('other')),
            ],
          ),
        ),
        Obx(
          () => c.canPayCash
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s2),
                  child: Text(
                    'Open a shift to pay cash',
                    key: const Key('paNoShift'),
                    style: t.caption.copyWith(color: p.warningFg),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('paReference'), label: 'Reference (optional)', controller: _reference, onChanged: (s) => c.reference.value = s),
        Obx(() => SupplyErrorText(c.error.value, errorKey: const Key('paError'))),
        Obx(
          () => supplyOnlineRx().value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Needs internet. A payment can only be recorded while the till is online.',
                    key: const Key('paOffline'),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppButton(key: const Key('paConfirm'), label: 'Record payment', loading: c.busy.value, onPressed: (c.canSubmit && supplyOnlineRx().value) ? _pay : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
