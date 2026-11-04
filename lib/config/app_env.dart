// The API URL lives in `ApiConstants.baseUrl` (lib/app/network/api_constaints.dart). `--dart-define=API_BASE_URL=...`
// can override it (e.g. a local backend). A release build refuses to start unless the URL is https and non-local.
import 'package:solvexo_pos/app/network/api_constaints.dart';

class AppEnv {
  const AppEnv._();

  static const String name = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static const String apiBaseUrl = ApiConstants.baseUrl;

  static bool get isProd => name == 'prod';

  /// Null when the configuration is acceptable; otherwise a developer-facing reason the app must not start.
  static String? validate({
    required bool release,
    String env = name,
    String baseUrl = apiBaseUrl,
  }) {
    if (baseUrl.isEmpty) return 'API_BASE_URL is empty';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority) {
      return 'API_BASE_URL is not a valid URL: $baseUrl';
    }
    if (!release) return null;
    if (uri.scheme != 'https') {
      return 'Release builds require an https API_BASE_URL (got ${uri.scheme}://)';
    }
    final host = uri.host.toLowerCase();
    final local =
        host == 'localhost' ||
        host.startsWith('127.') ||
        host == '10.0.2.2' ||
        host.endsWith('.local') ||
        RegExp(r'^(10|192\.168)\.').hasMatch(host);
    if (local) {
      return 'Release builds must not point at a local/dev host ($host)';
    }
    return null;
  }
}
