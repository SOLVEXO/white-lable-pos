import 'dart:async';

import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/modules/home/widgets/icon_badge.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/core/theme/base_animations.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shared search field for the Home search bar and the dedicated Search
/// screen. Owns the Daraz-style rotating hint (e.g. `Search "Electronics"`)
/// shown only while the field is empty and unfocused, so both call sites get
/// identical behaviour instead of each hand-rolling a Stack + Timer.
///
/// Delegates the actual editable field to [CustomTextField] — this widget
/// only adds the pill chrome, the optional [trailing] icon slot (e.g. the
/// filter trigger on Home, rendered inline inside the pill on the right,
/// same as the search/clear icons — not as a separate button beside it),
/// and the animated-hint overlay, since a plain `TextField.hintText` can't
/// itself animate.
///
/// Stays a `StatelessWidget`, GetX-style: focus tracking + the rotation
/// timer live on [_SearchHintController], scoped to this field's lifetime
/// via `GetX`'s own `init`/`autoRemove` (tagged by the passed
/// [TextEditingController]'s identity so Home's and Search's instances never
/// collide) — the same "controller owns state" convention used everywhere
/// else in this app, just scoped to a widget instead of a screen.
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? suffixIcon;
  final Widget? trailing;

  /// Real category names to cycle through. Empty while categories haven't
  /// loaded yet — [staticHint] is shown instead and the rotation timer
  /// doesn't start until this becomes non-empty.
  final List<String> rotatingHints;
  final String staticHint;
  final EdgeInsetsGeometry margin;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.staticHint,
    this.onChanged,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.trailing,
    this.rotatingHints = const [],
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final field = GetX<_SearchHintController>(
      tag: identityHashCode(controller).toString(),
      init: _SearchHintController(
        textController: controller,
        hints: rotatingHints,
        staticHint: staticHint,
      ),
      builder: (hintController) {
        hintController.syncHints(rotatingHints);
        return Container(
          height: 50,
          padding: EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppDimen.borderRadius),
            border: Border.all(color: AppColors.primaryColor, width: 0.2),
          ),
          child: Row(
            children: [
              IconBadge(icon: AppIcons.searchIcon),
              SizedBox(width: BaseSpacing.xs),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    CustomTextField(
                      controller: controller,
                      focusNode: hintController.focusNode,
                      onChanged: onChanged,
                      onFieldSubmitted: onFieldSubmitted,
                      hintText: '',
                      isDecoration: false,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (hintController.showOverlay.value)
                      Positioned(
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: AnimatedSwitcher(
                            duration: BaseMotion.normal,
                            switchInCurve: BaseMotion.standard,
                            switchOutCurve: BaseMotion.standard,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.3),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: CustomText(
                              key: ValueKey(hintController.currentHint),
                              text: hintController.currentHint,
                              color: AppColors.iosGrey,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (suffixIcon != null) ...[
                SizedBox(width: BaseSpacing.xs),
                suffixIcon!,
              ],
              if (trailing != null) ...[
                SizedBox(width: BaseSpacing.xs),
                trailing!,
              ],
            ],
          ),
        );
      },
    );

    return Padding(padding: margin, child: field);
  }
}

/// Focus tracking + the rotation timer for one [AppSearchField] instance.
/// Created and disposed automatically by the `GetX` widget wrapping it
/// (`autoRemove` defaults to true) — no manual dispose plumbing needed even
/// though this is a plain `StatelessWidget`.
class _SearchHintController extends GetxController {
  _SearchHintController({
    required this.textController,
    required List<String> hints,
    required this.staticHint,
  }) : _hints = hints;

  final TextEditingController textController;
  final String staticHint;
  List<String> _hints;

  final FocusNode focusNode = FocusNode();
  final RxBool showOverlay = true.obs;
  final RxInt hintIndex = 0.obs;
  Timer? _timer;

  String get currentHint =>
      _hints.isEmpty ? staticHint : _hints[hintIndex.value % _hints.length];

  @override
  void onInit() {
    super.onInit();
    showOverlay.value = textController.text.isEmpty;
    focusNode.addListener(_updateOverlay);
    textController.addListener(_updateOverlay);
    _restartTimer();
  }

  /// Called from the widget's `builder` on every rebuild so category names
  /// that finish loading after this controller was first created start
  /// rotating without needing to recreate the controller.
  void syncHints(List<String> hints) {
    if (hints.length == _hints.length) return;
    _hints = hints;
    hintIndex.value = 0;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_hints.isEmpty) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      hintIndex.value = (hintIndex.value + 1) % _hints.length;
    });
  }

  void _updateOverlay() {
    showOverlay.value = textController.text.isEmpty && !focusNode.hasFocus;
  }

  @override
  void onClose() {
    _timer?.cancel();
    focusNode.removeListener(_updateOverlay);
    textController.removeListener(_updateOverlay);
    focusNode.dispose();
    super.onClose();
  }
}
