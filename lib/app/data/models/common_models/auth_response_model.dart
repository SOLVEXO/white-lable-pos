import 'package:solvexo_pos/app/data/models/common_models/token_pair.dart';
import 'package:solvexo_pos/app/data/models/common_models/user_model.dart';
import 'package:flutter/material.dart';

class AuthResponseModel {
  final bool success;
  final String message;
  final UserModel user;
  final TokenPair token;

  AuthResponseModel({
    required this.success,
    required this.message,
    required this.user,
    required this.token,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    try {
      debugPrint("🔍 Parsing AuthResponseModel");

      final data = json['data'] ?? {};

      return AuthResponseModel(
        // ✅ Safe parsing (avoid crash if null)
        success: json['success'] ?? false,
        message: json['message'] ?? '',

        // ✅ Nested parsing with safety
        user: UserModel.fromJson((data['user'] ?? {}) as Map<String, dynamic>),

        token: TokenPair.fromJson(
          (data['token'] ?? {}) as Map<String, dynamic>,
        ),
      );
    } catch (e) {
      debugPrint("❌ AuthResponseModel parsing error: $e");
      debugPrint("JSON: $json");
      rethrow;
    }
  }
}
