import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Step3SellerTypeGrid extends StatelessWidget {
  final SellerOnboardingController controller;

  const Step3SellerTypeGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        children: [
          const SizedBox(height: Space.s2),
          Text(
            'What kind of seller are you?',
            style: t.headline.copyWith(color: p.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s2),
          Text(
            "We'll personalise your dashboard and tools based on your answer.",
            style: t.bodySmall.copyWith(color: p.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s5),
          Column(
            children: [
              for (int i = 0; i < kSellerTypes.length; i += 2)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i + 2 < kSellerTypes.length ? Space.s3 : 0,
                  ),
                  child: _TypeCardRow(
                    first: kSellerTypes[i],
                    second: i + 1 < kSellerTypes.length
                        ? kSellerTypes[i + 1]
                        : null,
                    controller: controller,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.s4),
        ],
      ),
    );
  }
}

// Pairs two cards per row. Deliberately NOT `IntrinsicHeight` +
// `CrossAxisAlignment.stretch` — that combo mismeasures here: IntrinsicHeight
// computes each card's height from `Text.maxLines`-wrapped descriptions at a
// width that doesn't match the Expanded's actual constrained width, so it
// under-allocates by about one text line and every card overflows at the
// bottom by a fixed ~20px regardless of content. Letting each card size to
// its own natural height (`.start`, no IntrinsicHeight) avoids that
// class of bug entirely — the tradeoff is a row's two cards may differ in
// height when their descriptions wrap differently, which reads fine here.
class _TypeCardRow extends StatelessWidget {
  final SellerTypeData first;
  final SellerTypeData? second;
  final SellerOnboardingController controller;

  const _TypeCardRow({
    required this.first,
    required this.second,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // The `.value` reads below must happen inside this Obx's own builder
    // call to be tracked — reading them one widget down (inside _TypeCard's
    // build) is outside the scope Obx watches and throws "improper use of
    // GetX" the moment nothing else in this subtree is read directly here.
    return Obx(
      () => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _TypeCard(
              data: first,
              isSelected: controller.sellerType.value == first.type,
              onTap: () => controller.selectSellerType(first.type),
            ),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _TypeCard(
                    data: second!,
                    isSelected: controller.sellerType.value == second!.type,
                    onTap: () => controller.selectSellerType(second!.type),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final SellerTypeData data;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.data,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(
            color: isSelected ? p.accentSoft : p.surface,
            borderRadius: Radii.rMd,
            border: Border.all(
              color: isSelected ? p.accent : p.border,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: context.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(data.emoji, style: t.headline),
                  _RadioDot(isSelected: isSelected),
                ],
              ),
              const SizedBox(height: Space.s2),
              Text(
                data.name,
                style: t.body.copyWith(
                  color: isSelected ? p.accentFg : p.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.s1),
              Text(
                data.description,
                style: t.bodySmall.copyWith(color: p.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool isSelected;
  const _RadioDot({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? p.accentFill : p.surface,
        border: Border.all(
          color: isSelected ? p.accentFill : p.border,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: isSelected
          ? Icon(Icons.check_rounded, size: 11, color: p.onAccentFill)
          : null,
    );
  }
}
