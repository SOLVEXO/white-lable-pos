import 'dart:io';

import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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
    Get.bottomSheet(
      _PickerSheet(
        title: title,
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
    );
  }

  // ── Pick methods ────────────────────────────────────────────────────────────

  static Future<File?> _fromGallery() async {
    // iOS: image_picker handles its own system permission prompt
    if (!Platform.isAndroid || await _checkAndroid(_galleryPermission())) {
      return _pickImage(ImageSource.gallery);
    }
    return null;
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

  /// Returns the correct Android gallery permission based on OS version.
  /// Android 13+ (API 33+): READ_MEDIA_IMAGES
  /// Android < 13          : READ_EXTERNAL_STORAGE
  static Permission _galleryPermission() {
    // permission_handler maps Permission.photos to READ_MEDIA_IMAGES on
    // Android 13+ and READ_EXTERNAL_STORAGE on older versions automatically.
    return Permission.photos;
  }

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
      p == Permission.camera ? 'Camera' : 'Photo Library';

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  /// Rationale dialog — explains WHY before Android's system dialog appears.
  static Future<bool> _showRationaleDialog(String permissionName) async {
    final result = await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: CustomText(
          text: '$permissionName Access',
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
        ),
        content: CustomText(
          text: 'This app needs access to your $permissionName to let you upload photos.',
          fontSize: 14,
          color: AppColors.grey,
          height: 1.5,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const CustomText(text: 'Not Now', color: AppColors.grey),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: CustomText(
              text: 'Allow',
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Settings redirect dialog — shown when permission is permanently denied.
  static void _showSettingsDialog(String permissionName) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: CustomText(
          text: '$permissionName Blocked',
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
        ),
        content: CustomText(
          text: '$permissionName access was denied. Please enable it in your device settings to upload photos.',
          fontSize: 14,
          color: AppColors.grey,
          height: 1.5,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const CustomText(text: 'Cancel', color: AppColors.grey),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              openAppSettings();
            },
            child: CustomText(
              text: 'Open Settings',
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _PickerSheet extends StatelessWidget {
  final String title;
  final bool canRemove;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback? onRemove;

  const _PickerSheet({
    required this.title,
    required this.canRemove,
    required this.onCamera,
    required this.onGallery,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(0, 12, 0, bottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.lightGrey2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CustomText(
                text: title,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.black,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.lightGrey2),
          _Option(
            icon: Icons.camera_alt_rounded,
            label: 'Take Photo',
            onTap: onCamera,
          ),
          const Divider(height: 1, indent: 72, color: AppColors.lightGrey2),
          _Option(
            icon: Icons.photo_library_rounded,
            label: 'Choose from Gallery',
            onTap: onGallery,
          ),
          if (onRemove != null) ...[
            const Divider(height: 1, indent: 72, color: AppColors.lightGrey2),
            _Option(
              icon: Icons.delete_outline_rounded,
              label: 'Remove Photo',
              onTap: onRemove!,
              danger: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _Option({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : AppColors.primaryColor;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            CustomText(
              text: label,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: danger ? AppColors.red : AppColors.black,
            ),
          ],
        ),
      ),
    );
  }
}
