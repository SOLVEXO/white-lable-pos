import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Production-level reusable image picker.
///
/// iOS  → image_picker triggers the native system dialog; no manual
///         permission code is needed or used.
/// Android → full permission lifecycle: check → rationale → request →
///           permanently-denied settings redirect.
///
/// Usage anywhere in the app:
/// ```dart
/// AppImagePicker.show(
///   onPicked: (file) => c.logoFile.value = file,
///   canRemove: c.hasLogo.value,
///   onRemove:  () => c.clearLogo(),
/// );
/// ```
class AppImagePicker {
  AppImagePicker._();

  static final _picker = ImagePicker();

  // ── Public entry point ──────────────────────────────────────────────────────

  static void show({
    required ValueChanged<File> onPicked,
    bool canRemove = false,
    VoidCallback? onRemove,
    String title = 'Choose Photo',
  }) {
    AppBottomSheet.showGet<void>(
      _PickerSheet(
        canRemove: canRemove,
        onCamera: () async {
          Get.back();
          final file = await _fromCamera();
          if (file != null) onPicked(file);
        },
        onGallery: () async {
          Get.back();
          final file = await _fromGallery();
          if (file != null) onPicked(file);
        },
        onRemove: (canRemove && onRemove != null)
            ? () {
                Get.back();
                onRemove();
              }
            : null,
      ),
      title: title,
    );
  }

  // ── Pick methods ────────────────────────────────────────────────────────────

  static Future<File?> _fromGallery() async {
    // The system photo picker needs no permission on either platform (the app never browses the library itself).
    return _pickImage(ImageSource.gallery);
  }

  static Future<File?> _fromCamera() async {
    // iOS: image_picker handles its own system permission prompt
    if (!Platform.isAndroid || await _checkAndroid(Permission.camera)) {
      return _pickImage(ImageSource.camera);
    }
    return null;
  }

  static Future<File?> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      return xfile != null ? File(xfile.path) : null;
    } catch (e) {
      debugPrint('AppImagePicker error: $e');
      return null;
    }
  }

  // ── Android permission helpers ──────────────────────────────────────────────

  /// Full Android permission lifecycle.
  /// Returns true if permission is granted and we can proceed.
  static Future<bool> _checkAndroid(Permission permission) async {
    PermissionStatus status = await permission.status;

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied) {
      _showSettingsDialog(_permissionLabel(permission));
      return false;
    }

    // Show rationale before requesting (Android best practice)
    if (await permission.shouldShowRequestRationale) {
      final proceed = await _showRationaleDialog(_permissionLabel(permission));
      if (!proceed) return false;
    }

    status = await permission.request();

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied) {
      _showSettingsDialog(_permissionLabel(permission));
    }
    return false;
  }

  static String _permissionLabel(Permission p) =>
      p == Permission.camera ? 'Camera' : 'Permission';

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  /// Rationale dialog — explains WHY before Android's system dialog appears.
  static Future<bool> _showRationaleDialog(String permissionName) async {
    final result = await Get.dialog<bool>(
      _DialogFrame(
        child: AppDialogCard(
          title: '$permissionName Access',
          message: 'This app needs access to your $permissionName to let you upload photos.',
          actions: [
            AppButton(
              label: 'Not Now',
              variant: AppButtonVariant.secondary,
              onPressed: () => Get.back(result: false),
            ),
            AppButton(
              label: 'Allow',
              onPressed: () => Get.back(result: true),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  /// Settings redirect dialog — shown when permission is permanently denied.
  static void _showSettingsDialog(String permissionName) {
    Get.dialog(
      _DialogFrame(
        child: AppDialogCard(
          title: '$permissionName Blocked',
          message: '$permissionName access was denied. Please enable it in your device settings to upload photos.',
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Get.back(),
            ),
            AppButton(
              label: 'Open Settings',
              onPressed: () {
                Get.back();
                openAppSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Centres an [AppDialogCard] inside a `Get.dialog` route (which has no layout of its own) with the standard gutter.
class _DialogFrame extends StatelessWidget {
  final Widget child;

  const _DialogFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.s6),
          child: child,
        ),
      ),
    );
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _PickerSheet extends StatelessWidget {
  final bool canRemove;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback? onRemove;

  const _PickerSheet({
    required this.canRemove,
    required this.onCamera,
    required this.onGallery,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListRow(
          icon: Icons.camera_alt_rounded,
          title: 'Take Photo',
          onTap: onCamera,
          chevron: false,
        ),
        const SizedBox(height: Space.s2),
        AppListRow(
          icon: Icons.photo_library_rounded,
          title: 'Choose from Gallery',
          onTap: onGallery,
          chevron: false,
        ),
        if (onRemove != null) ...[
          const SizedBox(height: Space.s2),
          AppListRow(
            icon: Icons.delete_outline_rounded,
            title: 'Remove Photo',
            onTap: onRemove,
            tone: StatusTone.danger,
            chevron: false,
          ),
        ],
      ],
    );
  }
}
