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

  /// The production API's host. Only config/env/prod.json may point at it (test/env_configs_test.dart).
  static const String productionApiHost = 'api.solvexo.store';

  /// Null when the configuration is acceptable; otherwise a developer-facing reason the app must not start.
  static String? validate({
    required bool release,
    String env = name,
    String baseUrl = apiBaseUrl,
  }) {
    // Staging has no API of its own yet (config/env/staging.json leaves API_BASE_URL empty): any staging build or run stops here instead of
    // quietly talking to production. Once ops provide a staging URL, put it in staging.json (never the production address).
    if (env == 'staging' && (baseUrl.isEmpty || Uri.tryParse(baseUrl)?.host.toLowerCase() == productionApiHost)) {
      return 'No staging API configured: config/env/staging.json has no staging API_BASE_URL yet (it must never be the production API, '
          '$productionApiHost). Ask the web team / ops for the staging URL.';
    }
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
