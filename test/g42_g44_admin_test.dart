// G4.2 roles & permissions, G4.3 activity log + integrity, G4.4 settings hub (receipt designer, notifications, security, backup & sync) and the
// G4.1 follow-up (a sales-report day opens that store day's sales). Controllers and screens over a mocked repository; phone, tablet and dark.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/daybook_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/roles_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/roles_view.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/settings_hub_views.dart';
import 'package:solvexo_pos/app/modules/pos_audit_log/controllers/pos_audit_log_controller.dart';
import 'package:solvexo_pos/app/modules/pos_audit_log/views/pos_audit_log_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/day_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/day_orders_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _Repo extends Mock implements PosRepository {}

const _phone = Size(390, 1600);
const _tablet = Size(1024, 1366);

enum _Env { phone, tablet, dark }

typedef _PermRes = ({bool success, String? code, String? message, PermissionMatrix? matrix, List<PermDiff> diff});
typedef _SetRes = ({bool success, String? code, String? message, StoreSettings? settings});

Map<String, dynamic> _matrixJson({bool canEdit = true, int version = 3, List<String> refundRoles = const ['manager', 'owner']}) => {
  'version': version,
  'canEdit': canEdit,
  'actions': [
    {
      'action': 'customers.refund',
      'label': 'Refund a sale',
      'roles': refundRoles,
      'defaultRoles': ['manager', 'owner'],
      'approval': [
        {'limit': 'refund', 'limitLabel': 'Refund limit', 'defaultApprover': 'manager', 'approver': 'manager', 'enabled': true},
      ],
    },
    {
      'action': 'settings.permissions.edit',
      'label': 'Change permissions',
      'pinned': true,
      'roles': ['owner'],
      'defaultRoles': ['owner'],
    },
    {
      'action': 'inventory.adjust',
      'label': 'Adjust stock',
      'changed': true,
      'roles': ['cashier', 'manager', 'owner'],
      'defaultRoles': ['manager', 'owner'],
    },
  ],
};

PermissionMatrix _matrix({bool canEdit = true, int version = 3}) => PermissionMatrix.fromJson(_matrixJson(canEdit: canEdit, version: version));

StoreSettings _settings({bool canEdit = true, Map<String, dynamic>? receipt, Map<String, dynamic>? security, Map<String, dynamic>? alerts}) => StoreSettings.fromJson({
  'receipt': receipt ?? {'showLogo': true, 'defaultPaperWidth': 80, 'footer': 'No returns after 7 days'},
  'alerts': alerts ?? {'lowStock': true, 'largeRefund': false},
  'security': security ?? {'autoLockMinutes': 5, 'lockOnBackground': false},
  'profile': {'businessName': 'Dev Store', 'businessAddress': 'Mall Road, Lahore', 'businessTaxId': '7654321-0'},
  'timeZone': 'Asia/Karachi',
  'canEdit': canEdit,
});

PosAuditLogModel _log(String id, String action, {String? employeeId = 'e1', String type = 'sale'}) =>
    PosAuditLogModel.fromJson({'_id': id, 'storeId': 'st1', 'employeeId': employeeId, 'action': action, 'targetType': type, 'targetId': 't$id', 'createdAt': '2026-11-10T09:30:00.000Z'});

PosSaleModel _sale(String id, String number) => PosSaleModel.fromJson({
  '_id': id,
  'saleNumber': number,
  'storeId': 'st1',
  'sessionId': 'se',
  'registerId': 'r',
  'employeeId': 'e',
  'items': [],
  'discount': 0,
  'tax': 0,
  'subtotal': 4.0,
  'total': 4.0,
  'paymentMethod': 'cash',
  'customerName': 'Walk-in',
  'notes': '',
  'status': 'completed',
  'createdAt': '2026-11-09T10:00:00.000Z',
  'currency': 'PKR',
  'currencyExponent': 2,
});

void main() {
  late _Repo repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    StoreDay.forget();
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => StoreTimeZone.fromJson({'timeZone': 'Asia/Karachi', 'today': '2026-11-10', 'canEdit': true}));
    when(() => repo.getEmployees('st1')).thenAnswer(
      (_) async => [PosEmployeeModel.fromJson({'_id': 'e1', 'storeId': 'st1', 'sellerId': 's', 'name': 'Ayesha', 'email': 'a@x', 'role': 'cashier', 'shiftIds': [], 'status': 'active'})],
    );
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pump(WidgetTester t, Widget w, [_Env env = _Env.phone]) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(
          key: UniqueKey(),
          theme: env == _Env.dark ? AppTheme.dark : AppTheme.light,
          getPages: [
            GetPage(name: Routes.posDayOrders, page: () => Scaffold(body: Text('DAY:${(Get.arguments as Map)['date']}'))),
            GetPage(name: Routes.posSaleDetail, page: () => Scaffold(body: Text('SALE:${Get.arguments}'))),
            GetPage(name: Routes.posRoles, page: () => const Scaffold(body: Text('ROLES'))),
            GetPage(name: Routes.posAuditLog, page: () => const Scaffold(body: Text('AUDIT'))),
          ],
          home: w,
        ),
      ),
    );
    await settle(t);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.pump(); // lay out at the new scroll offset before tapping
    await t.tap(f);
    await settle(t);
  }

  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);

  // ── G4.2 roles & permissions ─────────────────────────────────────────────────────────────
  group('G4.2 roles & permissions', () {
    void stubPerms({PermissionMatrix? m}) => when(() => repo.getPermissionMatrix('st1')).thenAnswer((_) async => m ?? _matrix());

    RolesController ctl() => Get.put(RolesController(repository: repo, storeId: 'st1'), tag: 'r${DateTime.now().microsecondsSinceEpoch}');

    for (final env in _Env.values) {
      testWidgets('${env.name}: grouped by area; the owner is locked on; pinned actions are locked; "Changed" marks a non-default', (t) async {
        stubPerms();
        await pump(t, RolesView(controller: ctl()), env);
        expect(find.byKey(const Key('permList')), findsOneWidget);
        expect(find.text('Customers, credit & loyalty'), findsOneWidget);
        expect(find.byKey(const Key('permChanged_inventory.adjust')), findsOneWidget);
        expect(find.text('Locked'), findsOneWidget);
        final owner = t.widget<FilterChip>(find.byKey(const Key('permRole_customers.refund_owner')));
        expect([owner.selected, owner.onSelected], [true, null]);
        final pinned = t.widget<FilterChip>(find.byKey(const Key('permRole_settings.permissions.edit_manager')));
        expect(pinned.onSelected, isNull);
        expect(find.byKey(const Key('permReadOnly')), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a manager reads only: no edit, no reset, every chip disabled', (t) async {
      stubPerms(m: _matrix(canEdit: false));
      await pump(t, RolesView(controller: ctl()));
      expect(find.byKey(const Key('permReadOnly')), findsOneWidget);
      expect(find.byKey(const Key('permReset')), findsNothing);
      expect(t.widget<FilterChip>(find.byKey(const Key('permRole_customers.refund_cashier'))).onSelected, isNull);
    });

    testWidgets('owner edits: preview diff, confirm, saved with the version it read', (t) async {
      stubPerms();
      final diff = [PermDiff.fromJson({'action': 'customers.refund', 'field': 'roles', 'before': ['manager', 'owner'], 'after': ['cashier', 'manager', 'owner']})];
      when(() => repo.updatePermissions('st1', any(), preview: true)).thenAnswer((_) async => (success: true, code: null, message: null, matrix: null, diff: diff) as _PermRes);
      when(() => repo.updatePermissions('st1', any(), expectedVersion: 3)).thenAnswer(
        (_) async => (success: true, code: null, message: null, matrix: PermissionMatrix.fromJson(_matrixJson(version: 4, refundRoles: ['cashier', 'manager', 'owner'])), diff: diff) as _PermRes,
      );
      final c = ctl();
      await pump(t, RolesView(controller: c));
      await tapKey(t, 'permRole_customers.refund_cashier');
      expect(find.byKey(const Key('permBar')), findsOneWidget);
      expect(c.changes, {
        'customers.refund': {
          'roles': ['cashier', 'manager', 'owner'],
          'approval': [
            {'enabled': true, 'approver': 'manager'},
          ],
        },
      });
      await tapKey(t, 'permReview');
      expect(find.byKey(const Key('permPreviewSheet')), findsOneWidget);
      expect(find.byKey(const Key('permDiff_customers.refund_roles')), findsOneWidget);
      expect(find.textContaining('Cashier, Manager, Owner'), findsWidgets);
      await tapKey(t, 'permConfirm');
      verify(() => repo.updatePermissions('st1', any(), expectedVersion: 3)).called(1);
      expect(c.matrix.value!.version, 4);
      expect(c.dirty, isFalse);
      expect(find.byKey(const Key('permNotice')), findsOneWidget);
    });

    testWidgets('toggling back to the saved value clears the edit; Discard drops all', (t) async {
      stubPerms();
      final c = ctl();
      await pump(t, RolesView(controller: c));
      await tapKey(t, 'permApproval_customers.refund_0');
      expect(c.dirty, isTrue);
      await tapKey(t, 'permApproval_customers.refund_0');
      expect(c.dirty, isFalse);
      await tapKey(t, 'permApprover_customers.refund_0_owner');
      await tapKey(t, 'permDiscard');
      expect(c.dirty, isFalse);
    });

    testWidgets('VERSION_CONFLICT: the error in words and a Reload that re-reads', (t) async {
      stubPerms();
      when(() => repo.updatePermissions('st1', any(), preview: true)).thenAnswer(
        (_) async => (success: true, code: null, message: null, matrix: null, diff: [PermDiff.fromJson({'action': 'customers.refund', 'field': 'roles', 'before': [], 'after': []})]) as _PermRes,
      );
      when(() => repo.updatePermissions('st1', any(), expectedVersion: 3)).thenAnswer((_) async => (success: false, code: 'VERSION_CONFLICT', message: 'x', matrix: null, diff: <PermDiff>[]) as _PermRes);
      final c = ctl();
      await pump(t, RolesView(controller: c));
      await tapKey(t, 'permRole_customers.refund_cashier');
      await tapKey(t, 'permReview');
      await tapKey(t, 'permConfirm');
      expect(find.textContaining('changed on another device'), findsOneWidget);
      expect(find.byKey(const Key('permReload')), findsOneWidget);
      await tapKey(t, 'permReload');
      verify(() => repo.getPermissionMatrix('st1')).called(2);
      expect(c.conflict.value, isFalse);
    });

    testWidgets('reset to defaults previews first, then resets', (t) async {
      stubPerms();
      when(() => repo.resetPermissions('st1', preview: true)).thenAnswer(
        (_) async => (success: true, code: null, message: null, matrix: null, diff: [PermDiff.fromJson({'action': 'inventory.adjust', 'field': 'roles', 'before': ['cashier', 'manager', 'owner'], 'after': ['manager', 'owner']})]) as _PermRes,
      );
      when(() => repo.resetPermissions('st1')).thenAnswer((_) async => (success: true, code: null, message: null, matrix: _matrix(version: 4), diff: <PermDiff>[]) as _PermRes);
      await pump(t, RolesView(controller: ctl()));
      await tapKey(t, 'permReset');
      expect(find.byKey(const Key('permDiff_inventory.adjust_roles')), findsOneWidget);
      await tapKey(t, 'permConfirm');
      verify(() => repo.resetPermissions('st1')).called(1);
    });

    testWidgets('offline: needs internet, no request; an error: Try again', (t) async {
      offline();
      await pump(t, RolesView(controller: ctl()));
      expect(find.textContaining('internet'), findsWidgets);
      verifyNever(() => repo.getPermissionMatrix(any()));
    });

    testWidgets('a cashier is refused by the server: the error in words', (t) async {
      when(() => repo.getPermissionMatrix('st1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      await pump(t, RolesView(controller: ctl()));
      expect(find.textContaining('Only the owner'), findsOneWidget);
    });
  });

  // ── G4.3 activity log + integrity ────────────────────────────────────────────────────────
  group('G4.3 activity log', () {
    PagedResult<PosAuditLogModel> page(List<PosAuditLogModel> l, {bool more = false}) => (items: l, total: l.length, totalPages: 1, hasMore: more);

    void stubLogs([List<PosAuditLogModel>? l]) => when(
      () => repo.getAuditLogsFiltered(
        'st1',
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        employeeId: any(named: 'employeeId'),
        targetType: any(named: 'targetType'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => page(l ?? [_log('1', 'sale_refunded'), _log('2', 'permissions_changed', employeeId: null, type: 'permission')]));

    PosAuditLogController ctl({Future<void> Function(ShareParams)? share}) => Get.put(
      PosAuditLogController(posRepository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 10, 12), share: share ?? (_) async {}),
      tag: 'a${DateTime.now().microsecondsSinceEpoch}',
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: rows with who and type; last 7 store days by default', (t) async {
        stubLogs();
        await pump(t, PosAuditLogView(controller: ctl()), env);
        expect(find.text('Sale Refunded'), findsOneWidget);
        expect(find.textContaining('Ayesha'), findsOneWidget);
        expect(find.textContaining('Owner / system'), findsOneWidget);
        expect(find.byKey(const Key('auditIntegrity')), findsOneWidget);
        verify(() => repo.getAuditLogsFiltered('st1', from: '2026-11-04', to: '2026-11-10', targetType: null, employeeId: null)).called(1);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('filters go to the server: range, type, person', (t) async {
      stubLogs();
      final c = ctl();
      await pump(t, PosAuditLogView(controller: c));
      await tapKey(t, 'auditRange_yesterday');
      verify(() => repo.getAuditLogsFiltered('st1', from: '2026-11-09', to: '2026-11-09', targetType: null, employeeId: null)).called(1);
      c.setType('permission');
      await settle(t);
      c.setEmployee('e1');
      await settle(t);
      verify(() => repo.getAuditLogsFiltered('st1', from: '2026-11-09', to: '2026-11-09', targetType: 'permission', employeeId: 'e1')).called(1);
      expect(find.text('Permissions'), findsWidgets);
    });

    testWidgets('CSV export shares the rows shown', (t) async {
      stubLogs();
      ShareParams? shared;
      final c = ctl(share: (p) async => shared = p);
      await pump(t, PosAuditLogView(controller: c));
      await tapKey(t, 'auditExport');
      expect(shared!.fileNameOverrides, ['activity-log_2026-11-04_2026-11-10.csv']);
      final csv = String.fromCharCodes(await shared!.files!.single.readAsBytes());
      expect(csv.split('\n').first.trim(), 'When,Who,What,Type,Target');
      expect(csv, contains('Ayesha,Sale Refunded,Sales & refunds,t1'));
    });

    testWidgets('empty, error and offline states', (t) async {
      stubLogs([]);
      await pump(t, PosAuditLogView(controller: ctl()));
      expect(find.byKey(const Key('auditEmpty')), findsOneWidget);
      Get.reset();
      when(() => repo.getAuditLogsFiltered('st1', from: any(named: 'from'), to: any(named: 'to'), targetType: any(named: 'targetType'), employeeId: any(named: 'employeeId'))).thenAnswer((_) async => null);
      await pump(t, PosAuditLogView(controller: ctl()));
      expect(find.text('Try again'), findsOneWidget);
      Get.reset();
      offline();
      await pump(t, PosAuditLogView(controller: ctl()));
      expect(find.textContaining('internet'), findsWidgets);
    });

    testWidgets('integrity: all match', (t) async {
      stubLogs();
      when(() => repo.verifyAuditSeals('st1', from: '2026-11-04', to: '2026-11-10')).thenAnswer(
        (_) async => AuditVerify.fromJson({
          'ok': true,
          'days': 3,
          'results': [
            {'day': '2026-11-08', 'status': 'ok'},
          ],
        }),
      );
      await pump(t, PosAuditLogView(controller: ctl()));
      await tapKey(t, 'auditCheck');
      expect(find.byKey(const Key('auditIntegrityOk')), findsOneWidget);
      expect(find.textContaining('All 3 sealed days still match'), findsOneWidget);
    });

    for (final env in _Env.values) {
      testWidgets('${env.name} integrity: a changed day names the parts; a broken chain says so', (t) async {
        stubLogs();
        when(() => repo.verifyAuditSeals('st1', from: any(named: 'from'), to: any(named: 'to'))).thenAnswer(
          (_) async => AuditVerify.fromJson({
            'ok': false,
            'days': 3,
            'results': [
              {'day': '2026-11-07', 'status': 'ok'},
              {
                'day': '2026-11-08',
                'status': 'changed',
                'changedParts': [
                  {'part': 'refunds', 'sealedCount': 4, 'nowCount': 3},
                ],
              },
              {'day': '2026-11-09', 'status': 'broken_chain'},
            ],
          }),
        );
        await pump(t, PosAuditLogView(controller: ctl()), env);
        await tapKey(t, 'auditCheck');
        expect(find.textContaining('2 of 3 sealed days no longer match'), findsOneWidget);
        expect(find.text('Refunds: 4 sealed, 3 now'), findsOneWidget);
        expect(find.textContaining('broken chain'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('integrity: no sealed days yet; a refusal in words', (t) async {
      stubLogs();
      when(() => repo.verifyAuditSeals('st1', from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => AuditVerify.fromJson({'ok': true, 'days': 0, 'results': []}));
      final c = ctl();
      await pump(t, PosAuditLogView(controller: c));
      await tapKey(t, 'auditCheck');
      expect(find.byKey(const Key('auditNoSeals')), findsOneWidget);
      when(() => repo.verifyAuditSeals('st1', from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => null);
      await tapKey(t, 'auditCheck');
      expect(find.byKey(const Key('auditIntegrityError')), findsOneWidget);
    });
  });

  // ── G4.4 settings hub ────────────────────────────────────────────────────────────────────
  group('G4.4 settings hub', () {
    late List<(int, bool)> applied;
    LocalQueues queues = const LocalQueues();

    StoreSettingsController ctl() => Get.put(
      StoreSettingsController(repository: repo, storeId: 'st1', queues: () => queues, applyLock: (m, b) async => applied.add((m, b)), clock: () => DateTime.utc(2026, 11, 10, 12)),
      tag: 's${DateTime.now().microsecondsSinceEpoch}',
    );

    void stubSettings([StoreSettings? s]) => when(() => repo.getStoreSettings('st1')).thenAnswer((_) async => s ?? _settings());

    setUp(() {
      applied = [];
      queues = const LocalQueues();
    });

    for (final env in _Env.values) {
      testWidgets('${env.name}: the hub lists every area with the current values', (t) async {
        stubSettings();
        await pump(t, SettingsHubView(controller: ctl()), env);
        expect(find.text('Dev Store'), findsOneWidget);
        expect(find.textContaining('80 mm'), findsOneWidget);
        expect(find.textContaining('Auto-lock after 5 min'), findsOneWidget);
        for (final k in ['hubReceipt', 'hubSecurity', 'hubAlerts', 'hubSync']) {
          expect(find.byKey(Key(k), skipOffstage: false), findsOneWidget, reason: k);
        }
        expect(find.byKey(const Key('settingsReadOnly')), findsNothing);
        expect(applied, [(5, false)], reason: 'this till follows the store security settings on load');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a manager reads only', (t) async {
      stubSettings(_settings(canEdit: false));
      final c = ctl();
      await pump(t, SettingsHubView(controller: c));
      expect(find.byKey(const Key('settingsReadOnly')), findsOneWidget);
      await tapKey(t, 'hubSecurity');
      expect(find.byKey(const Key('settingsReadOnly')), findsOneWidget);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('autoLock_10'))).onSelected, isNull);
    });

    for (final env in _Env.values) {
      testWidgets('${env.name} receipt designer: switches redraw the preview; 58 mm narrows it; Save sends only what changed', (t) async {
        stubSettings();
        when(() => repo.updateStoreSettings('st1', any())).thenAnswer(
          (inv) async =>
              (success: true, code: null, message: null, settings: _settings(receipt: {...?(inv.positionalArguments[1] as Map)['receipt'] as Map<String, dynamic>?, 'footer': 'No returns after 7 days'})) as _SetRes,
        );
        final c = ctl();
        await pump(t, ReceiptDesignerView(controller: c), env);
        expect(find.byKey(const Key('receiptPreview_80')), findsOneWidget);
        expect(find.byKey(const Key('previewQr')), findsOneWidget);
        expect(find.text('No returns after 7 days'), findsWidgets);
        await tapKey(t, 'receiptFlag_showQr');
        expect(find.byKey(const Key('previewQr')), findsNothing);
        c.setPaperWidth(58);
        await settle(t);
        expect(find.byKey(const Key('receiptPreview_58')), findsOneWidget);
        expect(t.getSize(find.byKey(const Key('receiptPreview_58'))).width, 220);
        await t.enterText(find.byKey(const Key('receiptText_promoText')), 'Eid sale 10% off');
        await settle(t);
        expect(find.text('Eid sale 10% off'), findsWidgets);
        await tapKey(t, 'receiptSave');
        final sent = verify(() => repo.updateStoreSettings('st1', captureAny())).captured.single as Map;
        expect(sent, {
          'receipt': {'showQr': false, 'defaultPaperWidth': 58, 'promoText': 'Eid sale 10% off'},
        });
        expect(find.byKey(const Key('settingsNotice')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('receipt designer: Discard puts the saved text back; a refusal shows in words', (t) async {
      stubSettings();
      when(() => repo.updateStoreSettings('st1', any())).thenAnswer((_) async => (success: false, code: 'INVALID_SETTINGS', message: 'receipt.promoText is at most 200 characters', settings: null) as _SetRes);
      final c = ctl();
      await pump(t, ReceiptDesignerView(controller: c));
      await t.enterText(find.byKey(const Key('receiptText_footer')), 'Changed');
      await settle(t);
      expect(c.receiptDirty, isTrue);
      await tapKey(t, 'receiptSave');
      expect(find.text('receipt.promoText is at most 200 characters'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus(); // (a focused field keeps scrolling itself into view)
      await settle(t);
      await tapKey(t, 'receiptDiscard');
      expect(c.receiptDirty, isFalse);
      expect(t.widget<TextField>(find.byKey(const Key('receiptText_footer'))).controller!.text, 'No returns after 7 days');
    });

    testWidgets('notifications: a switch saves that one alert', (t) async {
      stubSettings();
      when(() => repo.updateStoreSettings('st1', any())).thenAnswer((_) async => (success: true, code: null, message: null, settings: _settings(alerts: {'lowStock': false})) as _SetRes);
      await pump(t, AlertSettingsView(controller: ctl()));
      for (final k in AlertKeys.all) {
        expect(find.byKey(Key('alert_$k'), skipOffstage: false), findsOneWidget);
      }
      await tapKey(t, 'alert_lowStock');
      verify(
        () => repo.updateStoreSettings('st1', {
          'alerts': {'lowStock': false},
        }),
      ).called(1);
    });

    testWidgets('security: auto-lock and lock-in-background save and drive this till at once', (t) async {
      stubSettings();
      when(() => repo.updateStoreSettings('st1', {'security': {'autoLockMinutes': 15}})).thenAnswer(
        (_) async => (success: true, code: null, message: null, settings: _settings(security: {'autoLockMinutes': 15, 'lockOnBackground': false})) as _SetRes,
      );
      when(() => repo.updateStoreSettings('st1', {'security': {'lockOnBackground': true}})).thenAnswer(
        (_) async => (success: true, code: null, message: null, settings: _settings(security: {'autoLockMinutes': 15, 'lockOnBackground': true})) as _SetRes,
      );
      await pump(t, SecuritySettingsView(controller: ctl()));
      applied.clear();
      await tapKey(t, 'autoLock_15');
      expect(applied.last, (15, false));
      expect(find.textContaining('locks after 15 min'), findsOneWidget);
      await tapKey(t, 'lockOnBackground');
      expect(applied.last, (15, true));
    });

    testWidgets('security offline: the switches say it needs internet and send nothing', (t) async {
      stubSettings();
      final c = ctl();
      await pump(t, SecuritySettingsView(controller: c));
      offline();
      await settle(t);
      expect(await c.setAutoLock(10), isFalse);
      verifyNever(() => repo.updateStoreSettings(any(), any()));
    });

    for (final env in _Env.values) {
      testWidgets('${env.name} backup & sync: local queues, devices, last seal, a wrong device clock', (t) async {
        stubSettings();
        queues = const LocalQueues(sales: 2, salesFailed: 1, cash: 1, team: 0);
        when(() => repo.getSyncStatus('st1')).thenAnswer(
          (_) async => SyncStatus.fromJson({
            'serverTime': '2026-11-10T11:50:00.000Z',
            'timeZone': 'Asia/Karachi',
            'devices': [
              {'id': 'd1', 'name': 'Front till', 'platform': 'ios', 'appVersion': '1.4.0', 'lastSeenAt': '2026-11-10T11:58:00.000Z'},
            ],
            'lastSeal': {'day': '2026-11-09', 'sealedAt': '2026-11-10T09:00:00.000Z', 'records': 212},
          }),
        );
        await pump(t, BackupSyncView(controller: ctl()), env);
        expect(find.byKey(const Key('syncPending')), findsOneWidget);
        expect(find.textContaining('4 records still on this device'), findsOneWidget);
        expect(find.text('1 need attention'), findsOneWidget);
        expect(find.text('Front till'), findsOneWidget);
        expect(find.textContaining('212 records'), findsOneWidget);
        expect(find.byKey(const Key('syncClockGap')), findsOneWidget, reason: 'device 10 min ahead of the server');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('backup & sync offline: the local counts still show; the server part waits', (t) async {
      stubSettings();
      offline();
      await pump(t, BackupSyncView(controller: ctl()));
      expect(find.byKey(const Key('syncAllClear')), findsOneWidget);
      expect(find.textContaining('Offline'), findsOneWidget);
      verifyNever(() => repo.getSyncStatus(any()));
    });
  });

  // ── G4.1 follow-up: a day of the sales report → that store day's sales ───────────────────
  group('G4.1 day orders', () {
    testWidgets('lists the store day\'s sales; a sale opens its detail; an empty day says so', (t) async {
      when(() => repo.getSalesForDay('st1', '2026-11-09', page: any(named: 'page'))).thenAnswer((_) async => (items: [_sale('s1', 'S-0042')], total: 1, totalPages: 1, hasMore: false));
      await pump(t, DayOrdersView(date: '2026-11-09', controller: Get.put(DayOrdersController(date: '2026-11-09', repository: repo, storeId: 'st1'), tag: 'd2026-11-09')));
      expect(find.text('S-0042'), findsOneWidget);
      expect(find.textContaining('1 sale on this store day'), findsOneWidget);
      await tapKey(t, 'daySale_s1');
      expect(find.text('SALE:s1'), findsOneWidget);
    });

    testWidgets('an empty day says so', (t) async {
      when(() => repo.getSalesForDay('st1', '2026-11-08', page: any(named: 'page'))).thenAnswer((_) async => (items: <PosSaleModel>[], total: 0, totalPages: 0, hasMore: false));
      await pump(t, DayOrdersView(date: '2026-11-08', controller: Get.put(DayOrdersController(date: '2026-11-08', repository: repo, storeId: 'st1'), tag: 'd2026-11-08')));
      expect(find.byKey(const Key('dayOrdersEmpty')), findsOneWidget);
    });

    testWidgets('an error: Try again', (t) async {
      when(() => repo.getSalesForDay('st1', '2026-11-07', page: any(named: 'page'))).thenAnswer((_) async => null);
      await pump(t, DayOrdersView(date: '2026-11-07', controller: Get.put(DayOrdersController(date: '2026-11-07', repository: repo, storeId: 'st1'), tag: 'd2026-11-07')));
      expect(find.text('Try again'), findsOneWidget);
    });

    test('the sales report carries the previous period\'s days (no second request)', () {
      final r = parseBizReport(ReportKind.sales, {
        'period': {'from': '2026-11-04', 'to': '2026-11-10'},
        'currency': 'PKR',
        'currencyExponent': 2,
        'totals': {'transactions': 2, 'totalMinor': 1000},
        'byDay': [
          {'day': '2026-11-10', 'transactions': 2, 'totalMinor': 1000},
        ],
        'previous': {
          'period': {'from': '2026-10-28', 'to': '2026-11-03'},
          'totals': {'transactions': 1, 'totalMinor': 500},
          'byDay': [
            {'day': '2026-11-03', 'transactions': 1, 'totalMinor': 500},
          ],
        },
      }) as SalesReport;
      expect(r.previousByDay.single.totalMinor, 500);
      expect(r.previousFrom, '2026-10-28');
    });
  });

  // ── G4.4 security on the device · G4.1 daybook on the store's day ────────────────────────
  group('device follow-through', () {
    test('lock in background: locks on leaving the app only when the owner asked and someone is signed in', () async {
      var signedIn = true;
      final lock = IdleLockService(posRepository: repo, employeeSignedIn: () => signedIn, checkEvery: const Duration(days: 1))..onInit();
      addTearDown(lock.onClose);
      await Future<void>.delayed(Duration.zero);
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lock.locked.value, isFalse, reason: 'off by default');
      lock.lockOnBackground.value = true;
      signedIn = false;
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lock.locked.value, isFalse, reason: 'nobody signed in');
      signedIn = true;
      lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(lock.locked.value, isFalse, reason: 'inactive (a system sheet) is not leaving the app');
      lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(lock.locked.value, isTrue);
    });

    test('the daybook opens on the STORE\'s today, not the device date', () async {
      when(() => repo.getDaybookDay('st1', date: any(named: 'date'))).thenAnswer((_) async => null);
      final c = DaybookController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 23, 30), share: (_) async {}, storeName: () async => 'Dev Store')..onInit();
      addTearDown(c.onClose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(() => repo.getDaybookDay('st1', date: '2026-11-10')).called(1);
      verifyNever(() => repo.getDaybookDay('st1', date: '2026-11-09'));
      expect(c.isToday, isTrue);
    });
  });
}
