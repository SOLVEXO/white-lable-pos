import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:solvexo_pos/app/data/models/pos/kyb_models.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_service.dart';

typedef KybResult = ({KybView? view, String? message});

/// The owner endpoints of the business-verification API (`/api/kyb/:storeId…`, the owner's own session — the app swaps in the owner
/// token for these routes). Pure transport: nothing is cached, nothing is written to disk; the server owns every rule.
class KybRepository {
  KybRepository({BaseClient? client}) : _client = client ?? BaseClient();
  final BaseClient _client;

  KybResult _view(Response res) {
    final data = res.data is Map ? (res.data as Map)['data'] : null;
    if (data is Map) return (view: KybView.fromJson(data.cast<String, dynamic>()), message: null);
    return (view: null, message: null);
  }

  KybResult _fail(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      String? msg;
      if (d is Map) {
        final m = d['message'];
        msg = m is String ? m : (m is Map ? m['message'] as String? : null);
      }
      return (view: null, message: msg ?? (e.response == null ? 'No connection — try again when you are online.' : 'The request was refused.'));
    }
    debugPrint('kyb: $e');
    return (view: null, message: 'Something went wrong. Try again.');
  }

  Future<KybResult> get(String storeId) async {
    try {
      return _view(await _client.get(ApiConstants.kyb(storeId), requiresAuth: true));
    } catch (e) {
      return _fail(e);
    }
  }

  /// [fields] holds only what the owner typed (blank sensitive fields are simply not sent, so a masked value is never overwritten).
  Future<KybResult> saveDraft(String storeId, Map<String, dynamic> fields) async {
    try {
      return _view(await _client.put(ApiConstants.kybDraft(storeId), data: fields, requiresAuth: true));
    } catch (e) {
      return _fail(e);
    }
  }

  /// Uploads straight from the picked file's bytes on disk; the caller deletes that temporary file afterwards.
  Future<KybResult> uploadDocument(String storeId, {required String type, required File file}) async {
    try {
      final name = file.path.split('/').last;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
      final mime = ext == 'pdf' ? MediaType('application', 'pdf') : MediaType('image', ext == 'png' ? 'png' : 'jpeg');
      final dio = await DioService.getDio();
      final res = await dio.post(
        ApiConstants.kybDocuments(storeId),
        data: FormData.fromMap({'type': type, 'file': await MultipartFile.fromFile(file.path, filename: name, contentType: mime)}),
        options: Options(extra: {'requiresAuth': true}),
      );
      return _view(res);
    } catch (e) {
      return _fail(e);
    }
  }

  Future<KybResult> removeDocument(String storeId, String docId) async {
    try {
      return _view(await _client.delete(ApiConstants.kybDocument(storeId, docId), requiresAuth: true));
    } catch (e) {
      return _fail(e);
    }
  }

  Future<KybResult> submit(String storeId) async {
    try {
      return _view(await _client.post(ApiConstants.kybSubmit(storeId), data: const <String, dynamic>{}, requiresAuth: true));
    } catch (e) {
      return _fail(e);
    }
  }
}
