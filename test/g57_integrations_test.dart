// G5.7: Owner → Integrations — switches (e-mail / SMS receipts, fiscal) with provider status, the accounting export shared as a CSV, and store API keys
// (created with the full key shown once, listed without it, revoked with a confirmation). Owner-only routes go with the owner's session.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/controllers/pos_integrations_controller.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/views/pos_integrations_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _Repo extends Mock implements PosRepository {}

ConnectorsStatus _status({bool fiscal = false, bool email = false}) => ConnectorsStatus.fromJson({
      'flags': {'emailReceipts': email, 'smsReceipts': false, 'fiscal': fiscal},
      'cardGateway': {'provider': null},
      'fiscal': {'provider': 'mock', 'testMode': true, 'configured': true},
      'raast': {'kybStatus': 'verified', 'enabled': true},
    });
StoreApiKeys _keys([List<Map<String, dynamic>> ks = const []]) => StoreApiKeys.fromJson({'keys': ks, 'scopes': ['sales:read', 'inventory:read', 'accounting:read'], 'maxActive': 10, 'ratePerMinute': 60});
const _k1 = {'id': 'k1', 'name': 'Books', 'prefix': 'ABCDEFGHIJKL', 'scopes': ['accounting:read'], 'status': 'active', 'expiresAt': '2027-02-10T00:00:00.000Z'};

void main() {
  late _Repo repo;
  final shared = <ShareParams>[];
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, bool>{});
  });
  setUp(() {
    Get.reset();
    repo = _Repo();
    shared.clear();
  });

  Future<PosIntegrationsController> pump(WidgetTester t) async {
    final c = PosIntegrationsController(repo: repo, storeId: 'st1', share: (p) async => shared.add(p), clock: () => DateTime(2026, 11, 12));
    final loaded = c.load();
    t.view.physicalSize = const Size(430, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: PosIntegrationsView(key: UniqueKey(), controller: c))));
    await t.runAsync(() => loaded);
    await t.pump(const Duration(milliseconds: 200));
    return c;
  }

  testWidgets('switches show provider status; turning fiscal on writes the store switch', (t) async {
    when(() => repo.getConnectors('st1')).thenAnswer((_) async => _status());
    when(() => repo.getApiKeys('st1')).thenAnswer((_) async => _keys());
    when(() => repo.setConnectors('st1', any())).thenAnswer((_) async => (success: true, code: null, message: null));
    await pump(t);
    expect(find.text('Test mode'), findsOneWidget);
    await t.tap(find.byKey(const Key('intSwitch_fiscal')));
    await t.pump(const Duration(milliseconds: 200));
    verify(() => repo.setConnectors('st1', {'fiscal': true})).called(1);
  });

  testWidgets('accounting export: the period goes to the server and the CSV goes to the share sheet', (t) async {
    when(() => repo.getConnectors('st1')).thenAnswer((_) async => _status());
    when(() => repo.getApiKeys('st1')).thenAnswer((_) async => _keys());
    when(() => repo.accountingExport('st1', from: '2026-11-01', to: '2026-11-12')).thenAnswer((_) async => (bytes: 'date_local\n'.codeUnits, code: null, message: null));
    final c = await pump(t);
    await t.runAsync(c.exportAccounting);
    expect(shared.single.subject, 'Accounting export 2026-11-01 to 2026-11-12');
    expect(shared.single.files!.single.mimeType, 'text/csv');
    expect(c.notice.value, contains('2026-11-01'));
    when(() => repo.accountingExport('st1', from: '2026-11-01', to: '2026-11-12')).thenAnswer((_) async => (bytes: null, code: 'POS_ACTION_FORBIDDEN', message: 'no'));
    await t.runAsync(c.exportAccounting);
    expect(c.error.value, contains('Only the store owner'));
  });

  testWidgets('API key: create → the full key shown once with Copy; listed without the secret; revoke asks first', (t) async {
    when(() => repo.getConnectors('st1')).thenAnswer((_) async => _status());
    var listed = _keys();
    when(() => repo.getApiKeys('st1')).thenAnswer((_) async => listed);
    when(() => repo.createApiKey('st1', name: 'Books', scopes: ['sales:read', 'accounting:read'], expiresInDays: 365)).thenAnswer((_) async {
      listed = _keys([_k1]);
      return (success: true, code: null, message: null, key: 'sxk_ABCDEFGHIJKL_${'s' * 43}', apiKey: StoreApiKey.fromJson(_k1));
    });
    when(() => repo.revokeApiKey('st1', 'k1')).thenAnswer((_) async => (success: true, code: null, message: null));
    await pump(t);
    await t.tap(find.byKey(const Key('apiKeyNew')));
    await t.pumpAndSettle();
    await t.enterText(find.descendant(of: find.byKey(const Key('apiKeyName')), matching: find.byType(TextField)), 'Books');
    await t.tap(find.byKey(const Key('apiKeyScope_accounting:read')));
    await t.tap(find.text('1 year'));
    await t.pump();
    await t.tap(find.byKey(const Key('apiKeyCreate')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('apiKeyValue')), findsOneWidget);
    expect(find.text('sxk_ABCDEFGHIJKL_${'s' * 43}'), findsOneWidget);
    await t.tap(find.byKey(const Key('apiKeyDone')));
    await t.pumpAndSettle();
    expect(find.textContaining('sxk_ABCDEFGHIJKL_…'), findsOneWidget); // the list shows the prefix only
    expect(find.textContaining('s' * 43), findsNothing);
    await t.tap(find.byKey(const Key('apiKeyRevoke_k1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('apiKeyRevokeConfirm')));
    await t.pumpAndSettle();
    verify(() => repo.revokeApiKey('st1', 'k1')).called(1);
  });

  test('error words and owner routes', () {
    expect(PosIntegrationsController.integrationsErrorMessage('TOO_MANY_KEYS', null), contains('Revoke one first'));
    expect(OwnerRoutes.requiresOwner('POST', '/api/pos/api-keys/st1'), isTrue);
    expect(OwnerRoutes.requiresOwner('GET', '/api/pos/reports/accounting-export/st1?from=x'), isTrue);
    expect(OwnerRoutes.requiresOwner('GET', '/api/pos/connectors/st1'), isFalse);
  });
}
