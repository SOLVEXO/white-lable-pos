// G2.4 screens: digital receipt on the success screen, reason picker, offline mode, owner business verification (KYB) + its privacy rules.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/kyb_models.dart';
import 'package:solvexo_pos/app/data/repositories/kyb_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/controllers/pos_kyb_controller.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/views/pos_kyb_view.dart';
import 'package:solvexo_pos/app/modules/pos_offline/controllers/pos_offline_controller.dart';
import 'package:solvexo_pos/app/modules/pos_offline/views/pos_offline_view.dart';
import 'package:solvexo_pos/app/platform/screen_privacy.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

import 'support/sale_harness.dart';

class MockSync extends Mock implements PendingSaleSyncService {}

class MockPicker extends Mock implements ImagePicker {}

class FakeKyb implements KybRepository {
  KybView current = const KybView(status: 'draft', requiredDocuments: ['owner_cnic', 'bank_proof'], optionalDocuments: ['address_proof'], missingDocuments: ['owner_cnic', 'bank_proof']);
  final List<Map<String, dynamic>> saved = [];
  final List<String> uploaded = [];
  final List<String> removed = [];
  int submits = 0;
  int gets = 0;
  String? failWith;

  @override
  Future<KybResult> get(String storeId) async {
    gets++;
    return failWith != null ? (view: null, message: failWith) : (view: current, message: null);
  }

  @override
  Future<KybResult> saveDraft(String storeId, Map<String, dynamic> fields) async {
    saved.add(fields);
    return (view: current, message: null);
  }

  @override
  Future<KybResult> uploadDocument(String storeId, {required String type, required File file}) async {
    uploaded.add('$type:${file.path}');
    return (view: current, message: null);
  }

  @override
  Future<KybResult> removeDocument(String storeId, String docId) async {
    removed.add(docId);
    return (view: current, message: null);
  }

  @override
  Future<KybResult> submit(String storeId) async {
    submits++;
    current = KybView(status: 'submitted', requiredDocuments: current.requiredDocuments);
    return (view: current, message: null);
  }
}

void main() {
  SaleHarness.setUpAllShared();
  registerFallbackValue(ImageSource.camera);
  tearDown(Get.reset);

  Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(390, 844), ThemeData? theme}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(GetMaterialApp(theme: theme ?? AppTheme.light, home: w));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  group('success screen — digital receipt', () {
    late SaleHarness h;
    setUp(() {
      h = SaleHarness();
      h.putController();
    });

    Future<void> mountSuccess(WidgetTester t, {SaleOutcome outcome = SaleOutcome.completed, String? link = 'https://api.solvexo.test/r/abc123', bool withSaleId = true}) async {
      when(() => h.repo.getReceiptLink(any())).thenAnswer((_) async => link);
      final r = ReceiptData.fromSale(sale(total: 12), null, isCopy: false);
      h.c.lastOutcome.value = outcome;
      h.c.lastReceipt.value = withSaleId ? r : r.copyWith().let((x) => ReceiptData(receiptNumber: x.receiptNumber, dateText: x.dateText, customer: x.customer, lines: x.lines, subtotal: x.subtotal, total: x.total, payments: x.payments));
      await pump(t, SaleSuccessView(c: h.c, repository: h.repo));
    }

    testWidgets('a completed sale shows the receipt QR and a Share link button', (t) async {
      await mountSuccess(t);
      expect(find.byKey(const Key('receiptQr')), findsOneWidget);
      expect(find.byKey(const Key('shareReceiptLink')), findsOneWidget);
      expect(find.text('Digital receipt'), findsOneWidget);
      verify(() => h.repo.getReceiptLink('sale-S-0001')).called(1);
    });

    testWidgets('no link (lookup failed): no QR and nothing breaks — print / share PDF still there', (t) async {
      await mountSuccess(t, link: null);
      expect(find.byKey(const Key('receiptQr')), findsNothing);
      expect(find.byKey(const Key('printAgain')), findsOneWidget);
      expect(find.byKey(const Key('shareReceipt')), findsOneWidget);
    });

    testWidgets('a sale saved offline says the QR comes after it syncs, and asks the server for nothing', (t) async {
      await mountSuccess(t, outcome: SaleOutcome.queuedOffline);
      expect(find.byKey(const Key('digitalReceiptOffline')), findsOneWidget);
      expect(find.byKey(const Key('receiptQr')), findsNothing);
      verifyNever(() => h.repo.getReceiptLink(any()));
    });

    testWidgets('dark theme renders the QR on a light quiet zone', (t) async {
      await mountSuccess(t);
      await pump(t, SaleSuccessView(c: h.c, repository: h.repo), theme: AppTheme.dark);
      expect(find.byKey(const Key('receiptQr')), findsOneWidget);
    });
  });

  group('reason picker', () {
    Future<PosReasonChoice?> open(WidgetTester t, PosReasonKind kind) async {
      await pump(t, const Scaffold(body: SizedBox.shrink()));
      PosReasonChoice? result;
      var done = false;
      ReasonPicker.ask(kind).then((v) {
        result = v;
        done = true;
      });
      await t.pumpAndSettle();
      expect(done, isFalse);
      return result;
    }

    for (final kind in PosReasonKind.values) {
      testWidgets('$kind offers the server\'s codes', (t) async {
        await open(t, kind);
        for (final (code, _) in kPosReasons[kind]!) {
          expect(find.byKey(Key('reason_$code')), findsOneWidget, reason: '$kind $code');
        }
        Get.back(); // close the sheet so no animation is left running when the test ends
        await t.pumpAndSettle();
      });
    }

    testWidgets('continue without a choice is refused; a code (with optional note) is returned', (t) async {
      PosReasonChoice? got;
      await pump(t, const Scaffold(body: SizedBox.shrink()));
      ReasonPicker.ask(PosReasonKind.refund).then((v) => got = v);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reasonConfirm')));
      await t.pump();
      expect(find.text('Choose a reason.'), findsOneWidget);
      await t.tap(find.byKey(const Key('reason_wrong_item')));
      await t.enterText(find.byKey(const Key('reasonNote')), 'size M, not L');
      await t.tap(find.byKey(const Key('reasonConfirm')));
      await t.pumpAndSettle();
      expect(got?.code, 'wrong_item');
      expect(got?.note, 'size M, not L');
    });

    testWidgets('"Other" needs a few words', (t) async {
      PosReasonChoice? got;
      await pump(t, const Scaffold(body: SizedBox.shrink()));
      ReasonPicker.ask(PosReasonKind.voidSale).then((v) => got = v);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reason_other')));
      await t.pump();
      await t.tap(find.byKey(const Key('reasonConfirm')));
      await t.pump();
      expect(find.text('Say what happened (a few words).'), findsOneWidget);
      expect(got, isNull);
      await t.enterText(find.byKey(const Key('reasonNote')), 'till froze');
      await t.tap(find.byKey(const Key('reasonConfirm')));
      await t.pumpAndSettle();
      expect(got?.code, 'other');
    });

    testWidgets('cancel returns null (nothing is refunded / voided / discarded)', (t) async {
      PosReasonChoice? got = const PosReasonChoice('x', '');
      await pump(t, const Scaffold(body: SizedBox.shrink()));
      ReasonPicker.ask(PosReasonKind.discard).then((v) => got = v);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('reasonCancel')));
      await t.pumpAndSettle();
      expect(got, isNull);
    });
  });

  group('offline mode screen', () {
    late NetworkStatusService net;
    late MockSync sync;

    Future<void> mountOffline(WidgetTester t, {bool online = true, int pending = 0, int failed = 0, DateTime? last, bool syncing = false, Size size = const Size(390, 844)}) async {
      net = NetworkStatusService()..isOnline.value = online;
      sync = MockSync();
      when(() => sync.pendingCount).thenReturn(pending.obs);
      when(() => sync.failedCount).thenReturn(failed.obs);
      when(() => sync.isSyncing).thenReturn(syncing.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>(last));
      when(() => sync.syncNow(ignoreBackoff: any(named: 'ignoreBackoff'))).thenAnswer((_) async {});
      await pump(t, PosOfflineView(controller: PosOfflineController(network: net, sync: sync)), size: size);
    }

    testWidgets('online: connected, nothing waiting, "not yet" for the last sync, both lists present', (t) async {
      await mountOffline(t);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.byKey(const Key('pendingCount')), findsOneWidget);
      expect(tester(t, 'pendingCount'), '0');
      expect(find.byKey(const Key('lastSync')), findsOneWidget);
      expect(find.textContaining('not yet'), findsOneWidget);
      expect(find.byKey(const Key('worksOffline')), findsOneWidget);
      expect(find.byKey(const Key('needsConnection')), findsOneWidget);
    });

    testWidgets('offline: says so, shows the waiting count and last sync time, and Sync now is disabled', (t) async {
      await mountOffline(t, online: false, pending: 3, last: DateTime(2026, 11, 5, 14, 30));
      expect(find.text('No connection'), findsOneWidget);
      expect(tester(t, 'pendingCount'), '3');
      expect(find.textContaining('5 Nov, 14:30'), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const Key('syncNow'))).onPressed, isNull);
      expect(find.byKey(const Key('openNeedsAttention')), findsOneWidget);
    });

    testWidgets('the lists say what works (cash, recorded card, held, queue) and what does not (Raast QR, coupons)', (t) async {
      await mountOffline(t);
      final works = find.descendant(of: find.byKey(const Key('worksOffline')), matching: find.byType(Text));
      final needs = find.descendant(of: find.byKey(const Key('needsConnection')), matching: find.byType(Text));
      String all(Finder f) => t.widgetList<Text>(f).map((e) => e.data).join('|');
      expect(all(works), allOf(contains('Cash sales'), contains('Card sales recorded'), contains('Held sales'), contains('queued')));
      expect(all(needs), allOf(contains('Raast QR'), contains('Coupons')));
    });

    testWidgets('online with waiting sales: Sync now runs the sync, ignoring the backoff', (t) async {
      await mountOffline(t, pending: 2);
      await t.tap(find.byKey(const Key('syncNow')));
      await t.pump();
      verify(() => sync.syncNow(ignoreBackoff: true)).called(1);
    });

    testWidgets('a rejected sale is counted and called out', (t) async {
      await mountOffline(t, failed: 1);
      expect(tester(t, 'failedCount'), '1');
    });

    testWidgets('tablet and dark render', (t) async {
      await mountOffline(t, size: const Size(1024, 768));
      expect(find.text('Connected'), findsOneWidget);
    });
  });

  group('owner business verification (KYB)', () {
    late FakeKyb repo;
    late MockPicker picker;
    late PosKybController c;
    Worker? lockWorker;
    final lock = false.obs;

    Future<void> mountKyb(WidgetTester t, {KybView? view, Size size = const Size(390, 1400)}) async {
      repo = FakeKyb();
      if (view != null) repo.current = view;
      picker = MockPicker();
      lock.value = false;
      ScreenPrivacy.reset();
      c = PosKybController(repository: repo, picker: picker, storeId: 'store-1', lockWatcher: (ctl) => lockWorker = ever(lock, (l) {
            if (l == true) ctl.wipe();
          }));
      Get.put<PosKybController>(c);
      await pump(t, PosKybView(controller: c), size: size);
    }

    testWidgets('draft: empty form, required documents flagged, Submit disabled until they are uploaded', (t) async {
      await mountKyb(t);
      expect(find.byKey(const Key('kybStatus')), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.byKey(const Key('kybDoc_owner_cnic')), findsOneWidget);
      expect(find.byKey(const Key('kybDoc_bank_proof')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('kybMissingHint')), 300, scrollable: find.byType(Scrollable).first);
      expect(t.widget<AppButton>(find.byKey(const Key('kybSubmit'))).onPressed, isNull);
      expect(find.byKey(const Key('kybMissingHint')), findsOneWidget);
    });

    testWidgets('rejected: shows the reason and lets the owner submit again', (t) async {
      await mountKyb(t, view: const KybView(status: 'rejected', rejectionReason: 'The CNIC photo is unreadable'));
      expect(find.text('Sent back'), findsOneWidget);
      expect(find.byKey(const Key('kybRejection')), findsOneWidget);
      expect(find.text('The CNIC photo is unreadable'), findsOneWidget);
      expect(find.text('Submit again'), findsOneWidget);
    });

    testWidgets('in review: read-only (no Save / Submit / upload buttons)', (t) async {
      await mountKyb(t, view: const KybView(status: 'submitted', requiredDocuments: ['owner_cnic']));
      expect(find.text('In review'), findsOneWidget);
      expect(find.byKey(const Key('kybSave')), findsNothing);
      expect(find.byKey(const Key('kybSubmit')), findsNothing);
      expect(find.byKey(const Key('kybCamera_owner_cnic')), findsNothing);
    });

    testWidgets('verified: says digital payments are on', (t) async {
      await mountKyb(t, view: const KybView(status: 'verified', digitalPaymentsEnabled: true));
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Raast QR payments are on.'), findsOneWidget);
    });

    testWidgets('saved sensitive values show MASKED only and the fields start blank; a blank field is never sent', (t) async {
      await mountKyb(t, view: const KybView(status: 'draft', cnicMasked: '•••••••••1234', ibanMasked: 'PK••••••••••••••••••5678', legalBusinessName: 'Acme'));
      expect(find.textContaining('Saved: •••••••••1234'), findsOneWidget);
      expect(c.cnic.text, isEmpty);
      expect(c.iban.text, isEmpty);
      await t.ensureVisible(find.byKey(const Key('kybSave')));
      await t.tap(find.byKey(const Key('kybSave')));
      await t.pump();
      expect(repo.saved.single.containsKey('cnic'), isFalse);
      expect(repo.saved.single.containsKey('iban'), isFalse);
      expect(repo.saved.single['legalBusinessName'], 'Acme');
    });

    testWidgets('typed sensitive values are sent once and wiped from the form as soon as the server has them', (t) async {
      await mountKyb(t);
      c.cnic.text = '3520212345671';
      c.iban.text = 'PK36SCBL0000001123456702';
      await c.save();
      expect(repo.saved.single['cnic'], '3520212345671');
      expect(c.cnic.text, isEmpty);
      expect(c.iban.text, isEmpty);
    });

    testWidgets('double tap on Save is ONE request', (t) async {
      await mountKyb(t);
      final a = c.save();
      final b = c.save();
      await a;
      expect(await b, isFalse);
      expect(repo.saved, hasLength(1));
    });

    testWidgets('submit saves what is on screen, then submits', (t) async {
      await mountKyb(t, view: const KybView(status: 'draft', requiredDocuments: ['owner_cnic'], missingDocuments: []));
      await c.submit();
      expect(repo.saved, hasLength(1));
      expect(repo.submits, 1);
      expect(c.view.value!.status, 'submitted');
    });

    testWidgets('a photo is uploaded from the picker and the temporary file is DELETED afterwards (nothing is kept on the device)', (t) async {
      await mountKyb(t);
      final file = (await t.runAsync(() async {
        final f = File('${Directory.systemTemp.path}/kyb_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
        await f.writeAsBytes([1, 2, 3]);
        return f;
      }))!;
      when(() => picker.pickImage(source: any(named: 'source'), maxWidth: any(named: 'maxWidth'), imageQuality: any(named: 'imageQuality'), requestFullMetadata: any(named: 'requestFullMetadata'))).thenAnswer((_) async => XFile(file.path));
      await t.runAsync(() => c.pickAndUpload('owner_cnic', ImageSource.camera));
      expect(repo.uploaded.single, startsWith('owner_cnic:'));
      expect(file.existsSync(), isFalse);
    });

    testWidgets('going to the background wipes the form and the loaded application; coming back reloads it from the server', (t) async {
      await mountKyb(t, view: const KybView(status: 'draft', legalBusinessName: 'Acme'));
      c.cnic.text = '3520212345671';
      expect(c.legalName.text, 'Acme');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(c.legalName.text, isEmpty);
      expect(c.cnic.text, isEmpty);
      expect(c.view.value, isNull);
      expect(find.byKey(const Key('privacyCurtain')), findsOneWidget); // the app-switcher snapshot is a plain panel
      final before = repo.gets;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 300));
      expect(repo.gets, before + 1);
      expect(c.legalName.text, 'Acme');
      expect(find.byKey(const Key('privacyCurtain')), findsNothing);
    });

    testWidgets('locking the till wipes the form', (t) async {
      await mountKyb(t, view: const KybView(status: 'draft', legalBusinessName: 'Acme'));
      c.cnic.text = '3520212345671';
      lock.value = true;
      await t.pump();
      expect(c.cnic.text, isEmpty);
      expect(c.view.value, isNull);
      lockWorker?.dispose();
    });

    testWidgets('screenshots are blocked while the screen is up and allowed again when it is left', (t) async {
      await mountKyb(t);
      expect(ScreenPrivacy.holders, 1);
      expect(ScreenPrivacy.calls, [true]);
      Get.delete<PosKybController>(force: true);
      await t.pump();
      expect(ScreenPrivacy.holders, 0);
      expect(ScreenPrivacy.calls, [true, false]);
    });

    testWidgets('tablet + dark render', (t) async {
      await mountKyb(t, size: const Size(1024, 1200));
      expect(find.byKey(const Key('kybStatus')), findsOneWidget);
    });
  });
}

String tester(WidgetTester t, String key) => (t.widget(find.byKey(Key(key))) as Text).data!;

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
