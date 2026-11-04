import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/controllers/pos_pin_login_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

// Still imported from here by the legacy Open Register screen (until it is migrated).
export 'package:solvexo_pos/app/modules/pos_pin_login/widgets/pin_legacy_theme.dart'
    show kPinBg, kPinSurface, kPinBorder, kPinText, kPinSub;

/// Cashier sign-in on a shared till: employee email + register + 4-digit PIN.
/// Phone: one column. Tablet landscape: who-you-are on the left, PIN pad on the right.
class PosPinLoginView extends StatelessWidget {
  PosPinLoginView({super.key});

  final PosPinLoginController c = Get.find();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Obx(() {
          if (c.isLoadingStore.value) return const _LoadingSkeleton();
          return LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 840;
              final identity = _Identity(c: c);
              final pin = _PinSection(c: c);
              final owner = TextButton.icon(
                key: const Key('ownerAccessButton'),
                onPressed: () => Get.toNamed(Routes.sellerHome),
                style: TextButton.styleFrom(
                  minimumSize: const Size(Space.minTouch, Space.minTouch),
                  foregroundColor: p.textSecondary,
                ),
                icon: Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 18,
                  color: p.textSecondary,
                ),
                label: Text(
                  'Owner access',
                  style: context.type.label.copyWith(
                    color: p.textSecondary,
                    fontSize: context.type.body.fontSize,
                  ),
                ),
              );
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s6,
                  vertical: Space.s6,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: box.maxHeight - Space.s12,
                  ),
                  child: Center(
                    child: wide
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 960),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: Space.s8,
                                        ),
                                        child: identity,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 420,
                                      color: p.border,
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: Space.s8,
                                        ),
                                        child: Center(child: pin),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: Space.s4),
                                owner,
                              ],
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                identity,
                                const SizedBox(height: Space.s8),
                                pin,
                                const SizedBox(height: Space.s4),
                                owner,
                              ],
                            ),
                          ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.c});
  final PosPinLoginController c;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GateHeader(
            icon: Icons.point_of_sale_rounded,
            title: 'Employee login',
            subtitle: 'Enter your email and 4-digit PIN',
          ),
          const SizedBox(height: Space.s8),
          _RegisterSelector(c: c),
          const SizedBox(height: Space.s4),
          AppTextField(
            label: 'Employee email',
            controller: c.emailController,
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            onChanged: (v) => c.email.value = v,
          ),
        ],
      ),
    );
  }
}

class _RegisterSelector extends StatelessWidget {
  const _RegisterSelector({required this.c});
  final PosPinLoginController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (c.registers.isEmpty) {
        return AppCard(
          color: p.fill,
          radius: Radii.rMd,
          child: Row(
            children: [
              Icon(Icons.point_of_sale_outlined, color: p.textMuted, size: 20),
              const SizedBox(width: Space.s3),
              Text(
                'No registers configured',
                style: context.type.body.copyWith(color: p.textMuted),
              ),
            ],
          ),
        );
      }
      final name = c.selectedRegister.value?['name'] ?? 'Select register';
      return AppCard(
        onTap: () => _pick(context),
        color: p.fill,
        radius: Radii.rMd,
        semanticLabel: 'Register: $name. Tap to change',
        child: Row(
          children: [
            Icon(Icons.point_of_sale_outlined, color: p.accentFg, size: 20),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.subtitle.copyWith(color: p.textPrimary),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: p.textMuted),
          ],
        ),
      );
    });
  }

  void _pick(BuildContext context) {
    AppBottomSheet.show<void>(
      context,
      title: 'Select register',
      builder: (ctx) {
        final p = ctx.palette;
        return Column(
          children: [
            for (final reg in c.registers)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s2),
                child: Obx(() {
                  final selected = c.selectedRegister.value?['id'] == reg['id'];
                  return AppCard(
                    onTap: () {
                      c.selectRegister(reg);
                      Navigator.of(ctx).pop();
                    },
                    color: selected ? p.accentSoft : p.fill,
                    radius: Radii.rMd,
                    semanticLabel:
                        '${reg['name'] ?? ''}${selected ? ', selected' : ''}',
                    child: Row(
                      children: [
                        Icon(
                          Icons.point_of_sale_outlined,
                          color: selected ? p.accentFg : p.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: Space.s3),
                        Expanded(
                          child: Text(
                            reg['name'] ?? '',
                            style: ctx.type.subtitle.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_rounded, color: p.accentFg),
                      ],
                    ),
                  );
                }),
              ),
          ],
        );
      },
    );
  }
}

/// PIN dots + keypad. Watches the PIN: when a full PIN is cleared by the controller (a failed attempt), the dots
/// shake and buzz. No PIN logic lives here.
class _PinSection extends StatefulWidget {
  const _PinSection({required this.c});
  final PosPinLoginController c;

  @override
  State<_PinSection> createState() => _PinSectionState();
}

class _PinSectionState extends State<_PinSection> {
  late final Worker _worker;
  int _prevLen = 0;
  int _errorTick = 0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _worker = ever<String>(widget.c.pin, (v) {
      if (_prevLen >= 4 && v.isEmpty) {
        setState(() {
          _errorTick++;
          _hasError = true;
        });
      } else if (v.isNotEmpty && _hasError) {
        setState(() => _hasError = false);
      }
      _prevLen = v.length;
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(
          () => PinDots(
            length: 4,
            filled: c.pin.value.length,
            errorTick: _errorTick,
            hasError: _hasError,
          ),
        ),
        const SizedBox(height: Space.s2),
        SizedBox(
          height: 22,
          child: Obx(
            () => c.isLoading.value
                ? Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.palette.accent,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: Space.s4),
        Obx(
          () => PinPad(
            enabled: !c.isLoading.value,
            onDigit: c.appendDigit,
            onBackspace: c.backspace,
            onClear: c.clearPin,
          ),
        ),
      ],
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: const Padding(
          padding: EdgeInsets.all(Space.s6),
          child: SkeletonShimmer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBox(width: 64, height: 64, radius: 32),
                SizedBox(height: Space.s4),
                SkeletonBox(width: 180, height: 22),
                SizedBox(height: Space.s2),
                SkeletonBox(width: 220, height: 14),
                SizedBox(height: Space.s8),
                SkeletonBox(height: 56, radius: Radii.md),
                SizedBox(height: Space.s4),
                SkeletonBox(height: 56, radius: Radii.md),
                SizedBox(height: Space.s8),
                SkeletonBox(width: 160, height: 18, radius: 9),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
