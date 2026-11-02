/// Build-time environment, injected with `--dart-define-from-file=config/env/<env>.json` (or individual `--dart-define`s):
///   APP_ENV       dev | staging | prod
///   API_BASE_URL  absolute base URL of the API
/// There is NO default URL in code. A release build refuses to start unless it points at an https, non-local backend.
class AppEnv {
  const AppEnv._();

  static const String name = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isProd => name == 'prod';

  /// Null when the configuration is acceptable; otherwise a developer-facing reason the app must not start.
  static String? validate({required bool release, String env = name, String baseUrl = apiBaseUrl}) {
    if (baseUrl.isEmpty) return 'API_BASE_URL is not set. Build with --dart-define-from-file=config/env/<env>.json';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority) return 'API_BASE_URL is not a valid URL: $baseUrl';
    if (!release) return null;
    if (uri.scheme != 'https') return 'Release builds require an https API_BASE_URL (got ${uri.scheme}://)';
    final host = uri.host.toLowerCase();
    final local = host == 'localhost' || host.startsWith('127.') || host == '10.0.2.2' || host.endsWith('.local') || RegExp(r'^(10|192\.168)\.').hasMatch(host);
    if (local) return 'Release builds must not point at a local/dev host ($host)';
    if (env != 'staging' && env != 'prod') return 'Release builds need APP_ENV=staging or prod (got "$env")';
    return null;
  }
}
