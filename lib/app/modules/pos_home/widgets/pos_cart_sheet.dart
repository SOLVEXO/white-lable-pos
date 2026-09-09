import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_cart_item_tile.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosCartSheet extends StatelessWidget {
  final PosHomeController c;
  const PosCartSheet({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.lightGrey2,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // ── Header ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.shopping_bag_rounded,
                  color: AppColors.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const CustomText(
              text: 'Cart',
              fontSize: AppFontSize.regular,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            const SizedBox(width: 8),
            Obx(() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: CustomText(
                text: '${c.itemCount}',
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            )),
            const Spacer(),
            GestureDetector(
              onTap: () { c.clearSale(); Get.back(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const CustomText(
                  text: 'Clear',
                  fontSize: AppFontSize.tiny,
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
        const Divider(height: 1, color: AppColors.lightGrey2),

        // ── Cart items ────────────────────────────────────────────
        Expanded(
          child: Obx(() {
            if (c.cartItems.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.shopping_bag_outlined,
                        size: 36, color: AppColors.primaryColor),
                  ),
                  const SizedBox(height: 14),
                  const CustomText(
                    text: 'Your cart is empty',
                    fontSize: AppFontSize.small2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.black2,
                  ),
                ]),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: c.cartItems.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1, color: AppColors.lightGrey2, indent: 16, endIndent: 16,
              ),
              itemBuilder: (_, i) =>
                  PosCartItemTile(c: c, item: c.cartItems[i]),
            );
          }),
        ),

        _CartFooter(c: c),
      ]),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────────────────
class _CartFooter extends StatelessWidget {
  final PosHomeController c;
  const _CartFooter({required this.c});

  static const Map<String, String> _payIcons = {
    'cash':  AppIcons.cashIcon,
    'card':  AppIcons.cardIcon,
    'other': AppIcons.bankIcon,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.lightGrey2)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, 14 + MediaQuery.of(context).padding.bottom),
      child: Obx(() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Customer name ────────────────────────────────────────
          CustomTextField(
            controller: c.customerController,
            hintText: 'Customer name (optional)',
            fillColor: AppColors.background,
            onChanged: c.onCustomerTextChanged,
            prefixIcon: const Icon(Icons.person_outline_rounded,
                color: AppColors.iosGrey, size: 18),
            suffixIcon: GestureDetector(
              onTap: c.openCustomerPicker,
              child: const Icon(Icons.person_search_outlined,
                  color: AppColors.iosGrey, size: 20),
            ),
          ),
          const SizedBox(height: 8),

          // ── Discount & Tax ───────────────────────────────────────
          // Discount entry is manager-only, matching the backend's real,
          // token-verified check (see PosHomeController.isDiscountBlocked).
          Row(children: [
            Expanded(
              child: Opacity(
                opacity: c.isManager.value ? 1.0 : 0.5,
                child: IgnorePointer(
                  ignoring: !c.isManager.value,
                  child: CustomTextField(
                    controller: c.discountController,
                    hintText: c.isManager.value
                        ? (c.isPercentDiscount.value ? 'Discount (%)' : 'Discount (${c.currencySymbol.value})')
                        : 'Discount (managers only)',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    fillColor: AppColors.background,
                    onChanged: (_) => c.cartItems.refresh(),
                    prefixIcon: GestureDetector(
                      onTap: c.toggleDiscountType,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: CustomText(
                          text: c.isPercentDiscount.value ? '%' : c.currencySymbol.value,
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomTextField(
                controller: c.taxController,
                hintText: 'Tax (%)',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                fillColor: AppColors.background,
                onChanged: (_) => c.cartItems.refresh(),
                prefixIcon: const Icon(Icons.percent_rounded,
                    color: AppColors.iosGrey, size: 18),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // ── Order summary ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              _TotalRow(label: 'Subtotal',
                  value: '${c.currencySymbol.value}${c.subtotal.toStringAsFixed(2)}'),
              if (c.discountValue > 0) ...[
                const SizedBox(height: 5),
                _TotalRow(label: 'Discount',
                    value: '-${c.currencySymbol.value}${c.discountValue.toStringAsFixed(2)}',
                    valueColor: AppColors.green2),
              ],
              if (c.taxValue > 0) ...[
                const SizedBox(height: 5),
                _TotalRow(label: 'Tax', value: '+${c.currencySymbol.value}${c.taxValue.toStringAsFixed(2)}'),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: AppColors.lightGrey2),
              ),
              Row(children: [
                const CustomText(
                  text: 'Total',
                  fontSize: AppFontSize.small2,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black2,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CustomText(
                    text: '${c.currencySymbol.value}${c.total.toStringAsFixed(2)}',
                    fontSize: AppFontSize.medium,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryColor,
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 10),

          // ── Payment selector ─────────────────────────────────────
          Row(
            children: PosPaymentMethod.all.map((method) {
              final isSelected = c.selectedPayment.value == method;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => c.selectPayment(method),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryColor
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryColor
                              : AppColors.lightGrey2,
                        ),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SvgIcon(
                          assetName: _payIcons[method] ?? AppIcons.duePayment,
                          size: 18,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.iosGrey,
                        ),
                        const SizedBox(height: 3),
                        CustomText(
                          text: PosPaymentMethod.label(method),
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.iosGrey,
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // ── Cash tendered / change due ────────────────────────────
          if (c.selectedPayment.value == PosPaymentMethod.cash) ...[
            const SizedBox(height: 10),
            CustomTextField(
              controller: c.tenderedController,
              hintText: 'Cash tendered (${c.currencySymbol.value})',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              fillColor: AppColors.background,
              onChanged: (_) => c.cartItems.refresh(),
              prefixIcon: const Icon(Icons.payments_outlined, color: AppColors.iosGrey, size: 18),
            ),
            if (c.tenderedController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                CustomText(
                  text: c.isCashUnderTendered ? 'Amount short' : 'Change due',
                  fontSize: AppFontSize.tiny,
                  color: c.isCashUnderTendered ? AppColors.red : AppColors.iosGrey,
                ),
                const Spacer(),
                CustomText(
                  text: c.isCashUnderTendered
                      ? '${c.currencySymbol.value}${(c.total - c.tenderedAmount).toStringAsFixed(2)}'
                      : '${c.currencySymbol.value}${c.changeDue.toStringAsFixed(2)}',
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.bold,
                  color: c.isCashUnderTendered ? AppColors.red : AppColors.green2,
                ),
              ]),
            ],
          ],

          // ── Bank / Other reference ────────────────────────────────
          if (c.selectedPayment.value == PosPaymentMethod.other) ...[
            const SizedBox(height: 10),
            CustomTextField(
              controller: c.paymentReferenceController,
              hintText: 'Reference / transaction # (optional)',
              fillColor: AppColors.background,
              prefixIcon: const Icon(Icons.notes_outlined, color: AppColors.iosGrey, size: 18),
            ),
          ],
          const SizedBox(height: 10),

          // ── Hold + Charge buttons ─────────────────────────────────
          Row(children: [
            // Hold
            Expanded(
              child: GestureDetector(
                onTap: c.isChargingOrHolding.value ? null : c.holdSale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lightGrey2),
                  ),
                  alignment: Alignment.center,
                  child: const CustomText(
                    text: 'Hold',
                    fontSize: AppFontSize.verySmall,
                    fontWeight: FontWeight.bold,
                    color: AppColors.black2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Charge
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: (c.canCharge && !c.isChargingOrHolding.value)
                    ? c.completeSale
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: c.canCharge
                        ? LinearGradient(
                            colors: [AppColors.primaryColor, AppColors.primaryColorLight2],
                          )
                        : null,
                    color: c.canCharge ? null : AppColors.buttonDisableColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: c.canCharge
                        ? [BoxShadow(
                            color: AppColors.primaryColor.withOpacity(0.35),
                            blurRadius: 10, offset: const Offset(0, 4),
                          )]
                        : [],
                  ),
                  alignment: Alignment.center,
                  child: c.isChargingOrHolding.value
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                        )
                      : CustomText(
                          text: !c.hasItems
                              ? 'Add items'
                              : c.isCashUnderTendered
                                  ? 'Enter full amount'
                                  : 'Charge ${c.currencySymbol.value}${c.total.toStringAsFixed(2)}',
                          color: AppColors.white,
                          fontSize: AppFontSize.verySmall,
                          fontWeight: FontWeight.bold,
                        ),
                ),
              ),
            ),
          ]),
        ],
      )),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _TotalRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CustomText(
        text: label,
        fontSize: AppFontSize.verySmall,
        color: AppColors.iosGrey,
      ),
      const Spacer(),
      CustomText(
        text: value,
        fontSize: AppFontSize.verySmall,
        fontWeight: FontWeight.w500,
        color: valueColor ?? AppColors.black2,
      ),
    ]);
  }
}
