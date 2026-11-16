// Tests never reach a real network (production, staging, a LAN printer or any other host). Installed for EVERY test file by
// test/flutter_test_config.dart.
//
// Flutter's widget-test binding already swaps HttpClient for a mock that answers every request with an empty 400 and sends nothing — but it
// does that SILENTLY: a test whose code calls an unmocked repository gets a 400, the repository swallows it, and the test passes while looking
// as if it had called the API (G6.4: test/nav_five_tabs_test.dart did exactly that). This guard makes such a call FAIL the test instead:
//  * any HttpClient request (Dio, package:http, HttpClient) throws at once and is recorded;
//  * a raw socket to a non-loopback host (e.g. a network receipt printer, a LAN scan) throws and is recorded;
//  * the test that made the attempt fails in tearDown, naming the URL — even if the app code caught the exception.
// A test that genuinely needs HTTP passes its own fake client (HttpOverrides.runZoned / an injected Dio adapter / a mocked repository);
// loopback sockets (127.0.0.1, ::1, localhost) stay allowed for tests that run a local fake server.
import 'dart:async';
import 'dart:io';

/// Attempts made by the current test (cleared after each test).
final List<String> blockedNetworkAttempts = [];

bool _isLoopback(dynamic host) {
  if (host is InternetAddress) return host.isLoopback;
  final h = '$host'.toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h.startsWith('127.');
}

Never _block(String what) {
  blockedNetworkAttempts.add(what);
  throw StateError('Tests must not reach the network: $what — inject a fake (mocked repository / fake HttpClient) instead.');
}

/// Every HttpClient a test creates refuses every request.
class NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockingHttpClient();
}

class _BlockingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _block('$method $url');
  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) async => _block('$method $host:$port$path');
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) => open('GET', host, port, path);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) => open('POST', host, port, path);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) => open('HEAD', host, port, path);
  @override
  void close({bool force = false}) {}
  // Settings the app's HTTP stack may assign: accept and ignore them (no request is ever made).
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Raw sockets: loopback only.
class NoNetworkIOOverrides extends IOOverrides {
  @override
  Future<Socket> socketConnect(dynamic host, int port, {dynamic sourceAddress, int sourcePort = 0, Duration? timeout}) {
    if (!_isLoopback(host)) return Future<Socket>(() => _block('socket $host:$port')); // fails like a real connect: through the future
    return super.socketConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort, timeout: timeout);
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(dynamic host, int port, {dynamic sourceAddress, int sourcePort = 0}) {
    if (!_isLoopback(host)) return Future<ConnectionTask<Socket>>(() => _block('socket $host:$port'));
    return super.socketStartConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort);
  }
}

/// For a test whose screen legitimately shows a network image (the image widget is what is under test): asserts every blocked attempt was
/// that image URL — nothing else — and clears them, so the guard does not fail the test. Any OTHER attempt still fails it.
void expectOnlyBlockedImageFetch(String urlPrefix) {
  final others = blockedNetworkAttempts.where((a) => !a.contains(urlPrefix)).toList();
  if (others.isNotEmpty) throw StateError('unexpected network attempts: $others');
  blockedNetworkAttempts.clear();
}

/// Installs both overrides (call after the test binding is initialised, which installs its own HttpClient mock first).
void installNoNetworkGuard() {
  HttpOverrides.global = NoNetworkHttpOverrides();
  IOOverrides.global = NoNetworkIOOverrides();
}
