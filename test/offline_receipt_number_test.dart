// Q7: a sale rung up offline gets a provisional receipt number `OFF-<device>-<seq>`. The sequence is per device, only
// goes up and survives a restart; the receipt shows the number and an "offline — pending sync" note (screen text,
// thermal bytes, PDF); after sync the SAME receipt shows the server's real number and keeps the OFF number as a reference.
// The provisional number is never part of what is sent to the server.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';

AesGcmQueueCipher _cipher() => AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 9)));

Map<String, dynamic> _payload(String session) => {
      'storeId': 's1', 'sessionId': session, 'items': [{'variantId': 'v', 'qty': 2, 'unitPrice': 5.0}], 'clientTotal': 10.0,
      'clientCreatedAt': '2026-11-02T10:00:00.000Z', 'settingsVersion': 3, 'offline': true, 'idempotencyKey': 'k',
    };

ReceiptData _offlineReceipt(String number) => ReceiptData.forOfflineSale(
      provisionalNumber: number,
      madeAt: DateTime(2026, 11, 2, 10),
      currency: 'USD',
      exponent: 2,
      items: [(name: 'Latte', qty: 2, unitPrice: 5.0)],
      subtotal: 10,
      discount: 0,
      tax: 1,
      taxLabel: 'Tax (10%)',
      total: 11,
      payments: [(method: 'cash', amount: 11, reference: null)],
      cashTendered: 20,
      change: 9,
      cashier: 'Sam',
      customer: 'Secret Customer Name',
    );

String _text(List<int> bytes) => latin1.decode(bytes.where((b) => b >= 32 || b == 10).toList(), allowInvalid: true);

void main() {
  late Directory tmp;
  late String dbFile;
  late PendingSaleLocalStore store;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Get.testMode = true;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pos_offline_receipt_');
    dbFile = '${tmp.path}/q.db';
    store = PendingSaleLocalStore(dbPath: dbFile, cipher: _cipher());
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  group('provisional number sequence', () {
    test('device short = the LAST 6 letters/digits of the id, upper-case (ObjectId prefixes are timestamps)', () {
      expect(PendingSaleLocalStore.deviceShortOf('6ae9a2e26106e636cc7cb4bb'), '7CB4BB');
      expect(PendingSaleLocalStore.deviceShortOf('ab-c'), 'ABC');
      expect(PendingSaleLocalStore.deviceShortOf(null), 'LOCAL');
      expect(PendingSaleLocalStore.deviceShortOf(''), 'LOCAL');
    });

    test('numbers go up by one per device, in order, formatted OFF-<device>-<0001…>', () async {
      expect(await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0001');
      expect(await store.enqueue('k2', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0002');
      expect(await store.enqueue('k3', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0003');
      expect((await store.getById('k2'))!.provisionalNumber, 'OFF-AAAAAA-0002', reason: 'stored with the queued row');
    });

    test('each device has its own sequence', () async {
      expect(await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0001');
      expect(await store.enqueue('k2', _payload('A'), deviceShort: 'BBBBBB'), 'OFF-BBBBBB-0001');
      expect(await store.enqueue('k3', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0002');
    });

    test('the sequence survives a restart and is never reused, even after the synced rows are gone', () async {
      await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      await store.enqueue('k2', _payload('A'), deviceShort: 'AAAAAA');
      await store.remove('k1'); // synced
      await store.remove('k2');
      await store.close();

      final reopened = PendingSaleLocalStore(dbPath: dbFile, cipher: _cipher());
      expect(await reopened.enqueue('k3', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0003', reason: 'never goes back, never reused');
      await reopened.close();
    });

    test('the same intent queued twice keeps its number and does not burn another', () async {
      final first = await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      final again = await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      expect(again, first);
      expect(await store.enqueue('k2', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0002');
    });

    test('a key that comes back after it was synced and removed gets its old number, not a new one', () async {
      final n = await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      await store.remove('k1');
      expect(await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA'), n);
      expect(await store.enqueue('k2', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0002');
    });

    test('the STORED payload has no OFF- number (it is sent only as the separate provisionalNumber field at submit time)', () async {
      await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      final r = (await store.getById('k1'))!;
      expect(jsonEncode(r.payload), isNot(contains('OFF-')));
      expect(r.payload.keys, unorderedEquals(_payload('A').keys), reason: 'payload is exactly what the repository built');
    });

    test('a v3 database (no provisional column) upgrades in place, old rows stay readable, and re-opening is harmless', () async {
      final v3 = await databaseFactoryFfi.openDatabase(dbFile, options: OpenDatabaseOptions(version: 3, onCreate: (db, _) async {
        await db.execute('''CREATE TABLE pending_sales (id TEXT PRIMARY KEY, payload TEXT NOT NULL, status TEXT NOT NULL, errorMessage TEXT, errorCode TEXT,
          createdAt TEXT NOT NULL, storeId TEXT, sessionId TEXT, employeeToken TEXT, attempts INTEGER NOT NULL DEFAULT 0, nextAttemptAt TEXT,
          lastAttemptAt TEXT, discardReason TEXT, discardedBy TEXT, enc INTEGER NOT NULL DEFAULT 2)''');
        await db.insert('pending_sales', {
          'id': 'old', 'payload': await _cipher().encrypt(jsonEncode(_payload('A'))), 'status': 'pending', 'createdAt': '2026-11-01T09:00:00.000',
          'storeId': 's1', 'sessionId': 'A', 'enc': 2,
        });
      }));
      await v3.close();

      final old = (await store.getById('old'))!;
      expect(old.provisionalNumber, isNull, reason: 'rows queued before the feature have no number — and are not renumbered');
      expect(old.payload['clientTotal'], 10.0);
      expect(await store.enqueue('new', _payload('A'), deviceShort: 'AAAAAA'), 'OFF-AAAAAA-0001');
      await store.close();

      final again = PendingSaleLocalStore(dbPath: dbFile, cipher: _cipher());
      expect((await again.getById('old'))!.payload['clientTotal'], 10.0);
      expect((await again.getById('new'))!.provisionalNumber, 'OFF-AAAAAA-0001');
      await again.close();
    });
  });

  group('the offline receipt', () {
    test('shows the OFF number and the pending note in the shared text', () {
      final t = _offlineReceipt('OFF-AAAAAA-0001').toPlainText();
      expect(t, contains('Receipt OFF-AAAAAA-0001'));
      expect(t, contains(ReceiptData.offlinePendingNote));
      expect(t, contains('Tendered USD 20.00'));
    });

    test('thermal bytes carry the OFF number and the note', () async {
      final t = _text(await ReceiptEscPosBuilder.build(data: _offlineReceipt('OFF-AAAAAA-0001'), paperSize: PaperSize.mm58));
      expect(t, contains('OFF-AAAAAA-0001'));
      expect(t, contains(ReceiptData.offlinePendingNote));
    });

    test('the PDF is built from the same data (offline receipt renders)', () async {
      final bytes = await ReceiptPdfBuilder.build(data: _offlineReceipt('OFF-AAAAAA-0001'));
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('JSON round trip keeps every field (it is stored and reprinted later)', () {
      final r = _offlineReceipt('OFF-AAAAAA-0001');
      final back = ReceiptData.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.toPlainText(), r.toPlainText());
      expect(back.offlineNote, ReceiptData.offlinePendingNote);
    });
  });

  group('after sync', () {
    test('the stored receipt turns into the real one: real number, no pending note, OFF number kept as a reference', () async {
      final svc = PendingSaleSyncService(localStore: store, currentStoreId: () async => 's1', currentDeviceId: () async => '000000000000000000AAAAAA', persistLastSync: false);
      await svc.enqueue('k1', _payload('A'));
      final number = (await svc.provisionalNumberFor('k1'))!;
      expect(number, 'OFF-AAAAAA-0001');
      await svc.saveOfflineReceipt('k1', _offlineReceipt(number));

      final before = (await svc.offlineReceiptFor('k1'))!;
      expect(before.isSynced, isFalse);
      expect(before.receipt!.receiptNumber, number);
      expect(before.receipt!.offlineNote, isNotNull);

      await store.remove('k1'); // the queue row goes once the server has the sale…
      await svc.noteSynced('k1', realNumber: 'POS-00042', saleId: 'sale-1'); // …the mapping stays
      final after = (await svc.offlineReceiptFor('k1'))!;
      expect(after.isSynced, isTrue);
      expect(after.realNumber, 'POS-00042');
      final r = after.receipt!;
      expect(r.receiptNumber, 'POS-00042');
      expect(r.offlineNote, isNull);
      expect(r.offlineRef, number);
      expect(r.toPlainText(), contains('Offline ref $number'));
      expect(r.toPlainText(), isNot(contains(ReceiptData.offlinePendingNote)));
      expect(r.total, 'USD 11.00');
    });

    test('a sale opened from the server list can find its offline reference (by real number or sale id)', () async {
      await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      await store.noteSynced('k1', realNumber: 'POS-00042', saleId: 'sale-1');
      expect((await store.receiptByRealNumber('POS-00042'))!.provisionalNumber, 'OFF-AAAAAA-0001');
      expect((await store.receiptByRealNumber('sale-1'))!.provisionalNumber, 'OFF-AAAAAA-0001');
      expect(await store.receiptByRealNumber('POS-99999'), isNull);
    });

    test('noting the same sync twice (a replay returns the same sale) changes nothing', () async {
      await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      await store.noteSynced('k1', realNumber: 'POS-00042', saleId: 'sale-1');
      await store.noteSynced('k1', realNumber: 'POS-00042', saleId: 'sale-1');
      expect((await store.receiptByKey('k1'))!.realNumber, 'POS-00042');
    });

    test('an empty real number is ignored (the unsynced receipt is not broken by a malformed response)', () async {
      final svc = PendingSaleSyncService(localStore: store, currentStoreId: () async => 's1', currentDeviceId: () async => 'AAAAAA', persistLastSync: false);
      await svc.enqueue('k1', _payload('A'));
      await svc.noteSynced('k1', realNumber: '');
      expect((await svc.offlineReceiptFor('k1'))!.isSynced, isFalse);
    });
  });

  group('encryption at rest', () {
    test('the receipt snapshot (customer name, amounts) is encrypted in the database file', () async {
      await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      await store.saveReceiptSnapshot('k1', _offlineReceipt('OFF-AAAAAA-0001'));
      await store.close();

      final raw = await databaseFactoryFfi.openDatabase(dbFile);
      final rows = await raw.query('offline_receipts');
      await raw.close();
      final snap = rows.single['snapshot'] as String;
      expect(snap, startsWith('v2:'));
      expect(snap, isNot(contains('Secret Customer Name')));
      expect(rows.single['provisional'], 'OFF-AAAAAA-0001', reason: 'the number itself is not secret');

      final reopened = PendingSaleLocalStore(dbPath: dbFile, cipher: _cipher());
      expect((await reopened.receiptByKey('k1'))!.snapshot!.customer, 'Secret Customer Name');
      await reopened.close();
    });

    test('with the key gone the snapshot is unreadable but the number mapping still works', () async {
      await store.enqueue('k1', _payload('A'), deviceShort: 'AAAAAA');
      await store.saveReceiptSnapshot('k1', _offlineReceipt('OFF-AAAAAA-0001'));
      await store.close();

      final other = PendingSaleLocalStore(dbPath: dbFile, cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 1))));
      final rec = (await other.receiptByKey('k1'))!;
      expect(rec.snapshot, isNull);
      expect(rec.provisionalNumber, 'OFF-AAAAAA-0001');
      await other.close();
    });
  });
}
