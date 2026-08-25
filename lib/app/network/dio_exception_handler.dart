import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class DioExceptionHandler {
  static void handleDioException(
    DioException dioException, {
    bool showToast = true,
  }) {
    String errorMessage = "An error occurred";

    debugPrint("Status code --> ${dioException.response?.statusCode}");
    debugPrint("Error type --> ${dioException.type}");
    debugPrint("Error data --> ${dioException.response?.data}");

    switch (dioException.type) {
      case DioExceptionType.cancel:
        errorMessage = "Request was cancelled";
        break;
      case DioExceptionType.connectionTimeout:
        errorMessage =
            "Connection timeout. Please check your internet connection";
        break;
      case DioExceptionType.receiveTimeout:
        errorMessage = "Server is taking too long to respond";
        break;
      case DioExceptionType.sendTimeout:
        errorMessage = "Failed to send request";
        break;
      case DioExceptionType.badResponse:
        errorMessage = _handleResponseError(dioException.response!);
        break;
      case DioExceptionType.badCertificate:
        errorMessage = "Security certificate error";
        break;
      case DioExceptionType.connectionError:
        errorMessage = "No internet connection. Please check your network";
        break;
      case DioExceptionType.unknown:
        errorMessage = "An unexpected error occurred. Please try again";
        break;
    }

    if (showToast) {
      ToastUtil.showToast(errorMessage);
    }

    debugPrint("Error --> $errorMessage");
  }

  static String _handleResponseError(Response<dynamic> response) {
    String errorMessage;

    try {
      // Our backend sends errors in this format:
      // { "success": false, "message": "Error message here" }
      if (response.data is Map && response.data["message"] != null) {
        errorMessage = response.data["message"];
      } else if (response.data is String &&
          !(response.data as String).trimLeft().startsWith('<')) {
        // Only use the raw string if it is not an HTML error page (e.g. nginx 413)
        errorMessage = response.data;
      } else {
        errorMessage = _getDefaultErrorMessage(response.statusCode);
      }
    } catch (e) {
      errorMessage = _getDefaultErrorMessage(response.statusCode);
    }

    return errorMessage;
  }

  static String _getDefaultErrorMessage(int? statusCode) {
    switch (statusCode) {
      case 400:
        return "Bad request. Please check your input";
      case 401:
        return "Unauthorized. Please login again";
      case 403:
        return "Access denied";
      case 404:
        return "Resource not found";
      case 409:
        return "Conflict. Resource already exists";
      case 413:
        return "File is too large. Please upload a smaller file";
      case 422:
        return "Validation error. Please check your input";
      case 500:
        return "Server error. Please try again later";
      case 502:
        return "Bad gateway. Please try again";
      case 503:
        return "Service unavailable. Please try again later";
      default:
        return "Something went wrong. Please try again";
    }
  }

  /// Extract validation errors from response
  static Map<String, String>? getValidationErrors(Response<dynamic>? response) {
    if (response?.data is Map && response?.data["errors"] != null) {
      Map<String, String> errors = {};
      var errorsData = response?.data["errors"];

      if (errorsData is Map) {
        errorsData.forEach((key, value) {
          errors[key] = value.toString();
        });
      }

      return errors.isNotEmpty ? errors : null;
    }
    return null;
  }
}
