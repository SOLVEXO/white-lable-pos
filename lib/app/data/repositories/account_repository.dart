import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:solvexo_pos/app/data/models/common_models/social_login_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';

enum DeletionOutcome { requested, wrongPassword, wrongIdentity, openSessions, needsWeb, failed }

/// How this owner can prove it is them: a password, a social provider, or both. Unknown (offline/older server) is treated
/// as "password" so the screen still works.
class DeletionAuthMethods {
  const DeletionAuthMethods({this.hasPassword = true, this.authProvider});
  final bool hasPassword;
  final String? authProvider; // 'google' | 'apple' | null

  bool get canUseGoogle => authProvider == 'google';
  bool get canUseApple => authProvider == 'apple';
  bool get hasProvider => canUseGoogle || canUseApple;
}

/// Owner account deletion. Owner-only on the backend: on a registered device the Dio layer attaches the owner's in-memory
/// session (see OwnerRoutes), never the device token.
class AccountRepository {
  AccountRepository({BaseClient? client}) : _client = client ?? BaseClient();
  final BaseClient _client;

  /// `GET /seller/account-deletion` — which re-authentication this owner has. Never throws.
  Future<DeletionAuthMethods> authMethods() async {
    try {
      final res = await _client.get(ApiConstants.sellerAccountDeletion, requiresAuth: true);
      final data = res.data is Map ? (res.data as Map)['data'] : null;
      if (data is! Map) return const DeletionAuthMethods();
      return DeletionAuthMethods(hasPassword: data['hasPassword'] != false, authProvider: data['authProvider'] as String?);
    } catch (e) {
      debugPrint('authMethods: ${e.runtimeType}');
      return const DeletionAuthMethods();
    }
  }

  /// Schedules deletion (30-day grace). Re-authenticates with EITHER the [password] or a fresh [reauth] provider identity
  /// (Google/Apple sign-in just performed). Returns the scheduled date on success.
  Future<({DeletionOutcome outcome, DateTime? scheduledFor, String? message})> requestDeletion({String? password, SocialLoginModel? reauth}) async {
    try {
      final body = reauth != null ? {'authProvider': reauth.authProvider, 'socialId': reauth.socialId, 'token': reauth.token} : {'password': password};
      final res = await _client.post(ApiConstants.sellerAccountDeletion, data: body, requiresAuth: true);
      final ok = res.data is Map && (res.data as Map)['success'] == true;
      final when = ok ? DateTime.tryParse(((res.data as Map)['data'] as Map?)?['scheduledFor']?.toString() ?? '') : null;
      return (outcome: ok ? DeletionOutcome.requested : DeletionOutcome.failed, scheduledFor: when, message: null);
    } on DioException catch (e) {
      final body = e.response?.data;
      final code = body is Map ? body['code'] as String? : null;
      final msg = body is Map ? body['message']?.toString() : null;
      final outcome = switch (code) {
        'INVALID_PASSWORD' => DeletionOutcome.wrongPassword,
        'INVALID_REAUTH' => DeletionOutcome.wrongIdentity,
        'ACCOUNT_HAS_OPEN_SESSIONS' => DeletionOutcome.openSessions,
        'PASSWORD_REQUIRED_FOR_DELETION' => DeletionOutcome.needsWeb,
        _ => DeletionOutcome.failed,
      };
      return (outcome: outcome, scheduledFor: null, message: msg);
    } catch (e) {
      debugPrint('requestDeletion: ${e.runtimeType}');
      return (outcome: DeletionOutcome.failed, scheduledFor: null, message: null);
    }
  }
}
