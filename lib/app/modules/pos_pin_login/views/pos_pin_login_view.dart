import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/controllers/pos_pin_login_controller.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/widgets/pos_pin_login_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosPinLoginView extends StatelessWidget {
  PosPinLoginView({super.key});

  final PosPinLoginController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPinBg,
      body: SafeArea(
        child: Obx(() {
          if (c.isLoadingStore.value) {
            return const PosPinLoginShimmer();
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                _Header(),
                const SizedBox(height: 28),
                _RegisterSelector(c: c),
                const SizedBox(height: 20),
                _EmailField(c: c),
                const SizedBox(height: 32),
                _PinDots(c: c),
                const SizedBox(height: 32),
                _PinKeypad(c: c),
                const SizedBox(height: 16),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ── Theme constants ────────────────────────────────────────────────────────────
const kPinBg = Color(0xFF1A1A1A);
const kPinSurface = Color(0xFF252525);
const kPinBorder = Color(0xFF333333);
const kPinText = Color(0xFFE8E8E8);
const kPinSub = Color(0xFF888888);
const kPinOrange = Color(0xFFd97757);

// ── Header ─────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kPinOrange.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: SvgIcon(
            assetName: AppIcons.posIcon,
            color: kPinOrange,
            size: 32,
          ),
        ),
        const SizedBox(height: 14),
        const CustomText(
          text: 'Employee Login',
          fontFamily: AppTextStyles.headingFontFamily,
          fontSize: AppFontSize.large,
          fontWeight: FontWeight.bold,
          color: kPinText,
        ),
        const SizedBox(height: 6),
        const CustomText(
          text: 'Enter your email and 4-digit PIN',
          fontSize: AppFontSize.verySmall,
          color: kPinSub,
        ),
      ],
    );
  }
}

// ── Register selector ──────────────────────────────────────────────────────────
class _RegisterSelector extends StatelessWidget {
  final PosPinLoginController c;
  const _RegisterSelector({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.registers.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kPinSurface,
            borderRadius: BorderRadius.circular(AppDimen.borderRadius),
            border: Border.all(color: kPinBorder),
          ),
          child: const Row(
            children: [
              SvgIcon(assetName: AppIcons.posIcon, color: kPinSub, size: 18),
              SizedBox(width: 10),
              CustomText(
                text: 'No registers configured',
                fontSize: AppFontSize.verySmall,
                color: kPinSub,
              ),
            ],
          ),
        );
      }
      return GestureDetector(
        onTap: () => _showRegisterSheet(context, c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: kPinSurface,
            borderRadius: BorderRadius.circular(AppDimen.borderRadius),
            border: Border.all(color: kPinBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.point_of_sale_outlined,
                color: kPinOrange,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomText(
                  text: c.selectedRegister.value?['name'] ?? 'Select Register',
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.w600,
                  color: kPinText,
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: kPinSub,
                size: 20,
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showRegisterSheet(BuildContext context, PosPinLoginController c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kPinSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
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
                  color: kPinBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const CustomText(
              text: 'Select Register',
              fontSize: AppFontSize.small,
              fontWeight: FontWeight.bold,
              color: kPinText,
            ),
            const SizedBox(height: 12),
            ...c.registers.map(
              (reg) => GestureDetector(
                onTap: () {
                  c.selectRegister(reg);
                  Get.back();
                },
                child: Obx(
                  () => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: c.selectedRegister.value?['id'] == reg['id']
                          ? kPinOrange.withOpacity(0.15)
                          : kPinBg,
                      borderRadius: BorderRadius.circular(
                        AppDimen.borderRadius,
                      ),
                      border: Border.all(
                        color: c.selectedRegister.value?['id'] == reg['id']
                            ? kPinOrange
                            : kPinBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.point_of_sale_outlined,
                          color: c.selectedRegister.value?['id'] == reg['id']
                              ? kPinOrange
                              : kPinSub,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        CustomText(
                          text: reg['name'] ?? '',
                          fontSize: AppFontSize.verySmall,
                          fontWeight: FontWeight.w600,
                          color: kPinText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Email field ────────────────────────────────────────────────────────────────
class _EmailField extends StatelessWidget {
  final PosPinLoginController c;
  const _EmailField({required this.c});

  @override
  Widget build(BuildContext context) {
    return CustomTextField(
      controller: c.emailController,
      hintText: 'Employee Email',
      textColor: AppColors.white,
      keyboardType: TextInputType.emailAddress,
      borderRadius: BorderRadius.circular(AppDimen.borderRadius),
      fillColor: kPinSurface,
      onChanged: (v) => c.email.value = v,
      prefixIcon: SvgIcon(
        assetName: AppIcons.emailIcon,
        color: kPinSub,
        size: 20,
      ),
    );
  }
}

// ── PIN dots ───────────────────────────────────────────────────────────────────
class _PinDots extends StatelessWidget {
  final PosPinLoginController c;
  const _PinDots({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final len = c.pin.value.length;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = i < len;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? kPinOrange : Colors.transparent,
              border: Border.all(
                color: filled ? kPinOrange : kPinBorder,
                width: 2,
              ),
            ),
          );
        }),
      );
    });
  }
}

// ── Keypad ─────────────────────────────────────────────────────────────────────
class _PinKeypad extends StatelessWidget {
  final PosPinLoginController c;
  const _PinKeypad({required this.c});

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Column(
        children: _keys
            .map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((key) {
                    if (key.isEmpty)
                      return const SizedBox(width: 80, height: 72);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: _KeyButton(
                        label: key,
                        isLoading: key == '⌫' && c.isLoading.value,
                        onTap: () {
                          if (key == '⌫') {
                            c.backspace();
                          } else {
                            c.appendDigit(key);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  bool get isBackspace => label == '⌫';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 80,
        height: 72,
        decoration: BoxDecoration(
          color: isBackspace ? kPinOrange.withOpacity(0.12) : kPinSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPinBorder),
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kPinOrange,
                ),
              )
            : isBackspace
            ? const Icon(Icons.backspace_outlined, color: kPinOrange, size: 22)
            : CustomText(
                text: label,
                fontSize: AppFontSize.veryLarge,
                fontWeight: FontWeight.w600,
                color: kPinText,
              ),
      ),
    );
  }
}
