// G6.2: "older backend" is decided ONLY by the explicit probe GET /api/pos/capabilities — never by an ordinary 404 — re-checked on every start
// (and after login / store switch), cached for offline starts; a network error or 5xx never changes the decision.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/server_capabilities.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

class _Client extends Mock implements BaseClient {}

const _features = ['productPage', 'receiptDelivery', 'connectors', 'receiptLogo', 'rolePresets', 'integrations', 'apiKeys', 'fiscalContract', 'fiscalIssues', 'connectorUi'];
Map<String, dynamic> _caps([List<String> f = _features]) => {'success': true, 'data': {'contract': 1, 'release': 2, 'features': f}};
const _nestRouteMissing = {'message': 'Cannot GET /api/pos/capabilities', 'error': 'Not Found', 'statusCode': 404};

Response<dynamic> _res(int status, dynamic data, String path) => Response(requestOptions: RequestOptions(path: path), statusCode: status, data: data);
DioException _dio404(String path, Map<String, dynamic> body) =>
    DioException(requestOptions: RequestOptions(path: path), response: _res(404, body, path), type: DioExceptionType.badResponse);

void main() {
  late _Client client;
  late PosRepository repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    ServerCapabilities.resetForTest();
    client = _Client();
    repo = PosRepository(client: client);
    ServerCapabilities.probe = repo.probeCapabilities;
  });

  void probeAnswers(int? status, dynamic body) {
    final call = when(() => client.get('${ApiConstants.apiPrefix}/pos/capabilities', requiresAuth: false, validateStatus: any(named: 'validateStatus'), retryable: false));
    if (status == null) {
      call.thenThrow(DioException(requestOptions: RequestOptions(path: '${ApiConstants.apiPrefix}/pos/capabilities'), type: DioExceptionType.connectionError));
    } else {
      call.thenAnswer((_) async => _res(status, body, '${ApiConstants.apiPrefix}/pos/capabilities'));
    }
  }

  group('classifying the one probe', () {
    test('200 with features → found; 200 without the field → older; the framework\'s own route-missing 404 → older', () {
      expect(CapabilityProbe.classify(200, _caps()).kind, CapabilityProbeKind.found);
      expect(CapabilityProbe.classify(200, _caps()).features, containsAll(['productPage', 'integrations']));
      expect(CapabilityProbe.classify(200, {'success': true, 'data': {'contract': 1}}).kind, CapabilityProbeKind.older);
      expect(CapabilityProbe.classify(404, _nestRouteMissing).kind, CapabilityProbeKind.older);
    });

    test('anything else is inconclusive: a 404 carrying our own code, 5xx, 401 / 403, a proxy page, no response', () {
      expect(CapabilityProbe.classify(404, {'statusCode': 404, 'code': 'NOT_FOUND', 'message': 'Product not found'}).kind, CapabilityProbeKind.inconclusive);
      expect(CapabilityProbe.classify(404, '<html>Not Found</html>').kind, CapabilityProbeKind.inconclusive);
      for (final s in [500, 502, 503, 401, 403, 429]) {
        expect(CapabilityProbe.classify(s, {'message': 'x'}).kind, CapabilityProbeKind.inconclusive, reason: '$s');
      }
      expect(CapabilityProbe.classify(null, null).kind, CapabilityProbeKind.inconclusive);
    });
  });

  group('decisions', () {
    test('an ordinary resource 404 does NOT hide features (a missing product, sale, customer, document — or connectors)', () async {
      probeAnswers(200, _caps());
      await ServerCapabilities.refresh();
      expect(ServerCapabilities.has('productPage'), isTrue);
      for (final p in ['${ApiConstants.apiPrefix}/pos/catalog-admin/products/st1/missing', '${ApiConstants.apiPrefix}/pos/sales/missing', '${ApiConstants.apiPrefix}/pos/connectors/st1']) {
        when(() => client.get(p, queryParameters: any(named: 'queryParameters'), requiresAuth: true, headers: any(named: 'headers'))).thenThrow(_dio404(p, {'statusCode': 404, 'code': 'NOT_FOUND', 'message': 'Not found'}));
      }
      expect(await repo.getProductPage('st1', 'missing'), isNull);
      expect(await repo.getConnectors('st1'), isNull);
      // even a route-missing-shaped 404 on ANOTHER route changes nothing: only the probe decides
      when(() => client.get('${ApiConstants.apiPrefix}/pos/sales/missing', queryParameters: any(named: 'queryParameters'), requiresAuth: true, headers: any(named: 'headers'))).thenThrow(_dio404('${ApiConstants.apiPrefix}/pos/sales/missing', _nestRouteMissing));
      expect(ServerCapabilities.olderServer, isFalse);
      expect(['productPage', 'integrations', 'connectors', 'receiptLogo'].every(ServerCapabilities.has), isTrue);
    });

    test('an older backend (the probe route is missing) hides the release-#2 features', () async {
      probeAnswers(404, _nestRouteMissing);
      await ServerCapabilities.refresh();
      expect(ServerCapabilities.olderServer, isTrue);
      expect(['productPage', 'integrations', 'connectors', 'receiptLogo'].any(ServerCapabilities.has), isFalse);
    });

    test('a newer backend names its features: one it does not list stays hidden', () async {
      probeAnswers(200, _caps(['productPage']));
      await ServerCapabilities.refresh();
      expect([ServerCapabilities.has('productPage'), ServerCapabilities.has('integrations')], [true, false]);
    });

    test('upgrading the backend between two app starts shows the features (no reinstall, no clearing data)', () async {
      // start 1: production still on G5.1
      probeAnswers(404, _nestRouteMissing);
      await ServerCapabilities.loadCached();
      await ServerCapabilities.refresh();
      expect(ServerCapabilities.olderServer, isTrue);
      // release #2 goes live; start 2 = a fresh process: the cache says "older" until the probe answers
      ServerCapabilities.releaseTwo.value = null;
      ServerCapabilities.features.clear();
      await ServerCapabilities.loadCached();
      expect(ServerCapabilities.olderServer, isTrue);
      probeAnswers(200, _caps());
      await ServerCapabilities.refresh();
      expect(ServerCapabilities.olderServer, isFalse);
      expect(ServerCapabilities.has('integrations'), isTrue);
      final saved = jsonDecode((await SharedPreferences.getInstance()).getString(ServerCapabilities.prefsKey)!) as Map;
      expect(saved['older'], isFalse);
    });

    test('offline (and 5xx) keep the last known result — after a restart too', () async {
      probeAnswers(200, _caps());
      await ServerCapabilities.refresh();
      // restart while offline
      ServerCapabilities.releaseTwo.value = null;
      ServerCapabilities.features.clear();
      await ServerCapabilities.loadCached();
      probeAnswers(null, null); // no network
      expect((await ServerCapabilities.refresh()).kind, CapabilityProbeKind.inconclusive);
      expect([ServerCapabilities.olderServer, ServerCapabilities.has('integrations')], [false, true]);
      probeAnswers(503, {'message': 'maintenance'});
      await ServerCapabilities.refresh();
      expect(ServerCapabilities.has('integrations'), isTrue);
      // and the other way round: a known-older result is not undone by an outage
      probeAnswers(404, _nestRouteMissing);
      await ServerCapabilities.refresh();
      probeAnswers(null, null);
      await ServerCapabilities.refresh();
      expect(ServerCapabilities.olderServer, isTrue);
    });

    test('nothing known yet (fresh install, offline) → features shown as before', () async {
      probeAnswers(null, null);
      await ServerCapabilities.loadCached();
      await ServerCapabilities.refresh();
      expect(ServerCapabilities.releaseTwo.value, isNull);
      expect(ServerCapabilities.has('integrations'), isTrue);
    });

    test('the cache belongs to one API: a build pointed at another backend ignores it', () async {
      probeAnswers(404, _nestRouteMissing);
      await ServerCapabilities.refresh();
      ServerCapabilities.releaseTwo.value = null;
      ServerCapabilities.apiBase = () => 'https://other.example';
      await ServerCapabilities.loadCached();
      expect(ServerCapabilities.releaseTwo.value, isNull);
    });

    test('a store switch re-checks; concurrent re-checks share one request', () async {
      probeAnswers(200, _caps());
      AppPreferences.onStoreChanged = () => ServerCapabilities.refresh();
      await AppPreferences.saveStoreId('st2');
      await Future.wait([ServerCapabilities.refresh(), ServerCapabilities.refresh()]);
      verify(() => client.get('${ApiConstants.apiPrefix}/pos/capabilities', requiresAuth: false, validateStatus: any(named: 'validateStatus'), retryable: false)).called(lessThanOrEqualTo(2));
      expect(ServerCapabilities.releaseTwo.value, isTrue);
      AppPreferences.onStoreChanged = null;
    });
  });
}
