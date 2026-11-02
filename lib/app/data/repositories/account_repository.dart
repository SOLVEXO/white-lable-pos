import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';

enum DeletionOutcome { requested, wrongPassword, openSessions, needsWeb, failed }

/// Owner account deletion. Owner-only on the backend: on a registered device the Dio layer attaches the owner's in-memory
/// session (see OwnerRoutes), never the device token.
class AccountRepository {
  AccountRepository({BaseClient? client}) : _client = client ?? BaseClient();
  final BaseClient _client;

  /// Schedules deletion (30-day grace). Returns the scheduled date on success.
  Future<({DeletionOutcome outcome, DateTime? scheduledFor, String? message})> requestDeletion(String password) async {
    try {
      final res = await _client.post(ApiConstants.sellerAccountDeletion, data: {'password': password}, requiresAuth: true);
      final ok = res.data is Map && (res.data as Map)['success'] == true;
      final when = ok ? DateTime.tryParse(((res.data as Map)['data'] as Map?)?['scheduledFor']?.toString() ?? '') : null;
      return (outcome: ok ? DeletionOutcome.requested : DeletionOutcome.failed, scheduledFor: when, message: null);
    } on DioException catch (e) {
      final body = e.response?.data;
      final code = body is Map ? body['code'] as String? : null;
      final msg = body is Map ? body['message']?.toString() : null;
      final outcome = switch (code) {
        'INVALID_PASSWORD' => DeletionOutcome.wrongPassword,
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
