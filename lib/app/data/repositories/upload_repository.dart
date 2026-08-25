import 'dart:io';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class UploadRepository {
  final BaseClient _client = BaseClient();
  final ImagePicker _picker = ImagePicker();

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<File?> pickImage({
    required ImageSource source,
    double maxWidth = 1024,
    double maxHeight = 1024,
    int quality = 85,
  }) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: quality,
      );
      if (picked == null) return null;
      debugPrint('📷 Image selected: ${picked.path}');
      return File(picked.path);
    } catch (e) {
      debugPrint('❌ pickImage error: $e');
      return null;
    }
  }

  // ── POST /api/upload/file ─────────────────────────────────────────────────
  //
  // Uploads any file and returns its Cloudinary URL, or null on failure.

  Future<String?> uploadFile(File file) async {
    final bytes = await file.length();
    if (bytes > 5 * 1024 * 1024) {
      ToastUtil.showToast('Image is too large. Please use an image under 5 MB');
      return null;
    }
    try {
      debugPrint('🔄 Uploading file: ${file.path}');

      final filename = file.path.split('/').last;
      final mime = _mimeFromExtension(filename);

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: filename,
          contentType: DioMediaType.parse(mime),
        ),
      });

      final response = await _client.post(
        ApiConstants.uploadFile,
        data: formData,
        requiresAuth: true,
      );

      if (response.data['success'] == true) {
        final url = response.data['data']['url'] as String?;
        debugPrint('✅ Uploaded → $url');
        return url;
      }

      debugPrint('❌ Upload failed: ${response.data}');
      return null;
    } on DioException catch (e) {
      debugPrint('❌ uploadFile DioException: ${e.response?.statusCode}');
      debugPrint('   Response: ${e.response?.data}');
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ uploadFile error: $e');
      return null;
    }
  }

  // Backwards-compatible alias used by existing callers (profile, store logo…)
  Future<String?> uploadImage(File file) => uploadFile(file);

  // ── POST /api/upload/private-file ─────────────────────────────────────────
  //
  // Uploads a digital product file privately (no public URL).
  // Returns the full data map: { publicId, fileName, fileSize, mimeType, … }

  Future<Map<String, dynamic>?> uploadPrivateFile(File file, {String? purpose}) async {
    final bytes = await file.length();
    if (bytes > 20 * 1024 * 1024) {
      ToastUtil.showToast('File is too large. Please upload a file under 20 MB');
      return null;
    }
    try {
      debugPrint('🔄 Uploading private file: ${file.path}');

      final filename = file.path.split('/').last;
      final mime = _mimeFromExtension(filename);

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: filename,
          contentType: DioMediaType.parse(mime),
        ),
        if (purpose != null) 'purpose': purpose,
      });

      final response = await _client.post(
        ApiConstants.uploadPrivateFile,
        data: formData,
        requiresAuth: true,
      );

      if (response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        debugPrint('✅ Private file uploaded: ${data['publicId']}');
        return data;
      }

      debugPrint('❌ Private upload failed: ${response.data}');
      return null;
    } on DioException catch (e) {
      debugPrint('❌ uploadPrivateFile DioException: ${e.response?.statusCode}');
      debugPrint('   Response: ${e.response?.data}');
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ uploadPrivateFile error: $e');
      return null;
    }
  }

  static String _mimeFromExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  // ── Pick then upload ───────────────────────────────────────────────────────

  Future<String?> pickAndUpload({required ImageSource source}) async {
    final file = await pickImage(source: source);
    if (file == null) return null;
    return uploadFile(file);
  }

  // ── Profile image helpers ─────────────────────────────────────────────────

  Future<bool> updateProfileImage(String imageUrl) async {
    try {
      final response = await _client.put(
        ApiConstants.updateUserProfile,
        data: {'profileImage': imageUrl},
      );
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      debugPrint('❌ updateProfileImage error: $e');
      return false;
    }
  }

  Future<String?> pickUploadAndUpdateProfile({
    required ImageSource source,
  }) async {
    final url = await pickAndUpload(source: source);
    if (url == null) return null;
    await updateProfileImage(url);
    return url;
  }
}
