import 'dart:io';
import 'package:solvexo_pos/app/network/dio_service.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';

/// Network-level failures only (timeouts, no connection) — never a real
/// response from the server (`badResponse`), since retrying a genuine 4xx/5xx
/// business error just repeats it. Pure function, no Dio instance needed —
/// see base_client_retry_test.dart.
bool isRetryableDioErrorType(DioExceptionType type) {
  switch (type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return true;
    default:
      return false;
  }
}

/// Backoff delay before retry attempt [attemptNumber] (1-indexed: the delay
/// awaited before the *second* try is `retryBackoffDelay(1)`, etc).
Duration retryBackoffDelay(int attemptNumber) =>
    Duration(milliseconds: 500 * (1 << (attemptNumber - 1))); // 500ms, 1s, 2s...

class BaseClient {
  /// Retries [attempt] on network-level failures only (see
  /// [isRetryableDioErrorType]) — a real error response from the server is
  /// never retried, since GET/PATCH-with-absolute-value calls are the only
  /// callers of this, and those already can't turn a business error into a
  /// success by repeating it.
  Future<Response> _withRetry(Future<Response> Function() attempt, {int maxAttempts = 3}) async {
    var attemptNumber = 0;
    while (true) {
      attemptNumber++;
      try {
        return await attempt();
      } on DioException catch (e) {
        if (!isRetryableDioErrorType(e.type) || attemptNumber >= maxAttempts) rethrow;
        await Future.delayed(retryBackoffDelay(attemptNumber));
      }
    }
  }

  Future<Response> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    bool requiresAuth = false,
    ResponseType? responseType,
    // Lets a caller mark specific non-2xx statuses as "not an error" (e.g.
    // an optional endpoint that's a known 404 until the backend implements
    // it) — Dio then returns a normal Response instead of throwing, so it
    // never reaches DioService's onError interceptor/logging at all.
    bool Function(int? status)? validateStatus,
    // Reads are naturally idempotent, so GET retries on network failure by
    // default — pass false to opt out for a specific call.
    bool retryable = true,
  }) async {
    final dio = await DioService.getDio();
    debugPrint("GET → $url");

    Future<Response> attempt() => dio.get(
          url,
          queryParameters: queryParameters,
          data: data,
          options: Options(
            extra: {'requiresAuth': requiresAuth},
            responseType: responseType,
            validateStatus: validateStatus,
          ),
        );

    return retryable ? _withRetry(attempt) : attempt();
  }

  Future<Response> post(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
    Map<String, dynamic>? headers,
  }) async {
    final dio = await DioService.getDio();
    debugPrint("POST → $url");

    return dio.post(
      url,
      data: data,
      queryParameters: queryParameters,
      options: Options(
        // FormData: leave null so Dio auto-sets multipart/form-data + boundary.
        // Everything else: explicitly application/json.
        contentType: data is FormData ? null : 'application/json',
        headers: headers,
        extra: {'requiresAuth': requiresAuth},
      ),
    );
  }

  Future<Response> put(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
  }) async {
    final dio = await DioService.getDio();
    debugPrint("PUT → $url");

    return dio.put(
      url,
      data: data,
      queryParameters: queryParameters,
      options: Options(extra: {'requiresAuth': requiresAuth}),
    );
  }

  Future<Response> patch(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
    Map<String, dynamic>? headers,
    // Unlike GET, a PATCH is only safe to retry if the caller has confirmed
    // it's an absolute-value update (not a delta) — defaults to false, opt
    // in per call site (e.g. InventoryRepository.updateVariantStock).
    bool retryable = false,
  }) async {
    final dio = await DioService.getDio();
    debugPrint("PATCH → $url");

    Future<Response> attempt() => dio.patch(
          url,
          data: data,
          queryParameters: queryParameters,
          options: Options(
            contentType: data is FormData ? null : 'application/json',
            headers: headers,
            extra: {'requiresAuth': requiresAuth},
          ),
        );

    return retryable ? _withRetry(attempt) : attempt();
  }

  Future<Response> delete(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
  }) async {
    final dio = await DioService.getDio();
    debugPrint("DELETE → $url");

    return dio.delete(
      url,
      data: data,
      queryParameters: queryParameters,
      options: Options(extra: {'requiresAuth': requiresAuth}),
    );
  }

  /// Multipart upload helper — builds FormData from files + optional fields.
  Future<Response> postMultipart(
    String url, {
    required List<File> files,
    String fieldName = 'file',
    Map<String, dynamic>? additionalData,
    bool requiresAuth = true,
  }) async {
    final dio = await DioService.getDio();
    final map = <String, dynamic>{};

    for (final file in files) {
      final name = file.path.split('/').last;
      final ext = name.split('.').last.toLowerCase();

      map[fieldName] = await MultipartFile.fromFile(
        file.path,
        filename: name,
        contentType: MediaType('image', ext),
      );
    }

    if (additionalData != null) map.addAll(additionalData);

    return dio.post(
      url,
      data: FormData.fromMap(map),
      options: Options(
        extra: {'requiresAuth': requiresAuth},
        // ✅ No contentType override — Dio sets multipart/form-data automatically
      ),
    );
  }

  /// Streaming POST — for SSE endpoints.
  Future<ResponseBody> postStream(
    String url, {
    required Map<String, dynamic> data,
    Map<String, dynamic>? headers,
  }) async {
    final dio = await DioService.getDio(headers: headers);
    dio.options.responseType = ResponseType.stream;

    final response = await dio.post(url, data: data);
    return response.data as ResponseBody;
  }
}
