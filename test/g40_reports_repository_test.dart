// G4.0 / G4.1 repository: report paths and STORE-day queries, compare / filters / product sort, the pulse, the time zone (GET / owner PATCH) and the
// daybook by store day; refusals come back as null / a code.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

import 'support/g40_fixtures.dart';

class _MockClient extends Mock implements BaseClient {}

Response _res(dynamic data, {int? statusCode}) => Response(
  data: data,
  statusCode: statusCode ?? 200,
  requestOptions: RequestOptions(path: ''),
);
DioException _fail(int status, Map<String, dynamic> body) => DioException(
  requestOptions: RequestOptions(path: ''),
  type: DioExceptionType.badResponse,
  response: _res(body, statusCode: status),
);

void main() {
  late _MockClient client;
  late PosRepository repo;
  final sent = <({String url, Map<String, dynamic> headers, dynamic data, Map<String, dynamic>? query, String verb})>[];
  final base = '${ApiConstants.apiPrefix}/pos';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    await AppPreferences.setPosEmployeeToken('tok-emp');
    client = _MockClient();
    repo = PosRepository(client: client, intents: IdempotencyIntentStore());
    sent.clear();
  });

  void scriptGet(Object outcome) =>
      when(
        () => client.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
          data: any(named: 'data'),
          requiresAuth: any(named: 'requiresAuth'),
          responseType: any(named: 'responseType'),
          validateStatus: any(named: 'validateStatus'),
          retryable: any(named: 'retryable'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((i) async {
        sent.add((
          url: i.positionalArguments[0] as String,
          headers: (i.namedArguments[#headers] as Map).cast<String, dynamic>(),
          data: null,
          query: (i.namedArguments[#queryParameters] as Map?)?.cast<String, dynamic>(),
          verb: 'GET',
        ));
        if (outcome is DioException) throw outcome;
        return outcome as Response;
      });

  void scriptWrite(String verb, List<Object> outcomes) {
    var n = 0;
    Future<Response> answer(Invocation i) async {
      sent.add((url: i.positionalArguments[0] as String, headers: (i.namedArguments[#headers] as Map).cast<String, dynamic>(), data: i.namedArguments[#data], query: null, verb: verb));
      final o = outcomes[n++];
      if (o is DioException) throw o;
      return o as Response;
    }

    if (verb == 'POST') {
      when(
        () => client.post(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(answer);
    } else {
      when(
        () => client.patch(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(answer);
    }
  }

  test('each report: path, store days, compare and filters; parsed by kind', () async {
    for (final k in ReportKind.values) {
      sent.clear();
      scriptGet(_res({'success': true, 'data': reportJson(k)}));
      final r = await repo.getBizReport('st1', k, const ReportQuery(from: '2026-11-02', to: '2026-11-08', compare: true, registerId: 'r1', employeeId: 'e1'));
      expect(sent.single.url, '$base/reports/${k.path}/st1', reason: k.name);
      expect(sent.single.query, {'from': '2026-11-02', 'to': '2026-11-08', 'compare': 'previous', 'registerId': 'r1', 'employeeId': 'e1'}, reason: k.name);
      expect(sent.single.headers['x-pos-employee-token'], 'tok-emp');
      expect(r!.kind, k);
    }
  });

  test('products: sort and limit', () async {
    scriptGet(_res({'success': true, 'data': productsJson()}));
    final r = await repo.getBizReport(
      'st1',
      ReportKind.products,
      const ReportQuery(from: '2026-11-02', to: '2026-11-02'),
      sort: 'margin',
      limit: 100,
    );
    expect(sent.single.query, {'from': '2026-11-02', 'to': '2026-11-02', 'sort': 'margin', 'limit': 100});
    expect((r as ProductsReport).products.first.sku, 'TEA-1');
  });

  test('pulse: today by default, a store day when asked', () async {
    scriptGet(_res({'success': true, 'data': pulseJson()}));
    final p = await repo.getBusinessPulse('st1');
    await repo.getBusinessPulse('st1', date: '2026-11-09');
    expect(
      [sent[0].url, sent[0].query, sent[1].query],
      [
        '$base/reports/pulse/st1',
        <String, dynamic>{},
        {'date': '2026-11-09'},
      ],
    );
    expect(p!.topProducts.single.name, 'Green tea');
  });

  test('a refusal is null with the code kept (a cashier asking for the pulse; a junk range)', () async {
    scriptGet(_fail(403, {'code': 'POS_ACTION_FORBIDDEN', 'message': 'no'}));
    expect(await repo.getBusinessPulse('st1'), isNull);
    expect(repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
    scriptGet(_fail(400, {'code': 'RANGE_TOO_LONG', 'message': 'no'}));
    expect(await repo.getBizReport('st1', ReportKind.sales, const ReportQuery(from: '2025-01-01', to: '2026-11-01')), isNull);
    expect(repo.lastErrorCode, 'RANGE_TOO_LONG');
  });

  test('time zone: read; the owner\'s PATCH; INVALID_TIME_ZONE / forbidden come back as codes', () async {
    scriptGet(_res({'success': true, 'data': zoneJson()}));
    final z = await repo.getStoreTimeZone('st1');
    expect([sent.single.url, z!.timeZone, z.today], ['$base/store/time-zone/st1', 'Asia/Karachi', '2026-11-10']);
    sent.clear();
    scriptWrite('PATCH', [
      _res({'success': true, 'data': zoneJson(tz: 'Europe/London', explicit: true)}),
      _fail(400, {'code': 'INVALID_TIME_ZONE', 'message': 'bad'}),
      _fail(403, {'code': 'POS_ACTION_FORBIDDEN', 'message': 'no'}),
    ]);
    final ok = await repo.setStoreTimeZone('st1', 'Europe/London');
    expect(
      [sent.single.verb, sent.single.url, sent.single.data],
      [
        'PATCH',
        '$base/store/time-zone/st1',
        {'timeZone': 'Europe/London'},
      ],
    );
    expect([ok.success, ok.zone!.timeZone, ok.zone!.explicit], [true, 'Europe/London', true]);
    final bad = await repo.setStoreTimeZone('st1', 'Mars/Olympus');
    expect([bad.success, bad.code], [false, 'INVALID_TIME_ZONE']);
    final no = await repo.setStoreTimeZone('st1', 'UTC');
    expect([no.success, no.code], [false, 'POS_ACTION_FORBIDDEN']);
  });

  test('the daybook of one STORE day (date=YYYY-MM-DD)', () async {
    scriptGet(
      _res({
        'success': true,
        'data': {'currency': 'PKR', 'currencyExponent': 2, 'shifts': [], 'lines': []},
      }),
    );
    await repo.getDaybookDay('st1', date: '2026-11-05', registerId: 'r1');
    expect(
      [sent.single.url, sent.single.query],
      [
        '$base/cash/daybook/st1',
        {'date': '2026-11-05', 'registerId': 'r1'},
      ],
    );
  });
}
