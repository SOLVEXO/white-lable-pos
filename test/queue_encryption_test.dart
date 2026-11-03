// The offline queue is encrypted at rest (AES-256-GCM, key in the Keychain/Keystore) and existing plaintext data is
// migrated without losing a single row.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AesGcmQueueCipher cipher([int seed = 7]) => AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, seed)));

/// A cipher that fails after [okCount] successful encryptions — simulates the key becoming unavailable / a crash midway.
class FlakyCipher implements QueueCipher {
  FlakyCipher(this.inner, this.okCount);
  final QueueCipher inner;
  int okCount;
  @override
  Future<String> encrypt(String plain) async {
    if (okCount-- <= 0) throw StateError('keystore unavailable');
    return inner.encrypt(plain);
  }

  @override
  Future<String> decrypt(String c) => inner.decrypt(c);
}

Map<String, dynamic> payload(String n) => {'storeId': 's1', 'sessionId': 'A', 'items': [{'variantId': 'secret-variant-$n', 'qty': 2}], 'clientTotal': 123.45, 'settingsVersion': 3};

void main() {
  late Directory tmp;
  late String dbFile;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('qenc_');
    dbFile = '${tmp.path}/q.db';
  });
  tearDown(() async => tmp.delete(recursive: true));

  Future<List<Map<String, Object?>>> rawRows() async {
    final db = await databaseFactoryFfi.openDatabase(dbFile);
    final rows = await db.query('pending_sales', orderBy: 'createdAt ASC');
    await db.close();
    return rows;
  }

  group('AesGcmQueueCipher', () {
    test('round trips, and the same text never encrypts to the same value (random nonce)', () async {
      final c = cipher();
      final a = await c.encrypt('hello 123');
      final b = await c.encrypt('hello 123');
      expect(a, startsWith('v2:'));
      expect(a, isNot(b));
      expect(await c.decrypt(a), 'hello 123');
      expect(await c.decrypt(b), 'hello 123');
    });

    test('tampering is DETECTED (authenticated encryption), not silently decrypted to garbage', () async {
      final c = cipher();
      final enc = await c.encrypt('{"total":10}');
      final bytes = base64Decode(enc.substring(3));
      bytes[bytes.length ~/ 2] ^= 0x01;
      expect(() => c.decrypt('v2:${base64Encode(bytes)}'), throwsA(isA<QueueDecryptException>()));
    });

    test('a different key cannot read it', () async {
      final enc = await cipher(1).encrypt('secret');
      expect(() => cipher(2).decrypt(enc), throwsA(isA<QueueDecryptException>()));
    });

    test('values written by app versions up to 5F (`v1:`, same AES-256-GCM layout) still decrypt unchanged', () async {
      final c = cipher();
      final v2 = await c.encrypt('legacy value');
      final asV1 = 'v1:${v2.substring(3)}';
      expect(await c.decrypt(asV1), 'legacy value');
    });

    test('a pinned AES-256-GCM vector decrypts (the OS providers must produce/accept exactly this standard layout)', () async {
      // key = 32 x 0x07, nonce = 12 x 0x01, plaintext "pos-queue" — produced independently by the package's reference AES-GCM
      final algo = AesGcm.with256bits();
      final box = await algo.encrypt(utf8.encode('pos-queue'), secretKey: SecretKey(List.filled(32, 7)), nonce: List.filled(12, 1));
      final bytes = box.concatenation();
      expect(bytes.length, 12 + 9 + 16);
      expect(bytes.sublist(0, 12), List.filled(12, 1));
      expect(await cipher().decrypt('v2:${base64Encode(bytes)}'), 'pos-queue');
    });

    test('which provider runs is observable (host VM has no OS plugin → pure-Dart fallback, same output format)', () {
      expect(AesGcmQueueCipher.usesOsCrypto, isFalse);
    });

    test('plaintext is refused (not an encrypted value)', () {
      expect(() => cipher().decrypt('{"a":1}'), throwsA(isA<QueueDecryptException>()));
    });

    test('the key is generated once, stored in secure storage (not in the database) and reused', () async {
      final mem = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
        final args = (call.arguments as Map).cast<String, dynamic>();
        switch (call.method) {
          case 'write':
            mem[args['key'] as String] = args['value'] as String;
            return null;
          case 'read':
            return mem[args['key'] as String];
          default:
            return null;
        }
      });
      final first = AesGcmQueueCipher(storage: const FlutterSecureStorage());
      final enc = await first.encrypt('persist me');
      expect(mem.keys, ['pos_queue_encryption_key']);
      expect(base64Decode(mem['pos_queue_encryption_key']!).length, 32);
      // "app restart": a new cipher object reads the same key back and can decrypt
      final second = AesGcmQueueCipher(storage: const FlutterSecureStorage());
      expect(await second.decrypt(enc), 'persist me');
      expect(mem.length, 1, reason: 'no second key was generated');
    });
  });

  group('encrypted at rest', () {
    test('the database file holds NO readable sale contents, token, error text or discard reason', () async {
      final store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      await store.enqueue('k1', payload('1'), employeeToken: 'eyJ.manager.token');
      await store.markFailed('k1', 'Insufficient stock for TEA-1');
      await store.enqueue('k2', payload('2'));
      await store.markDiscarding('k2', reason: 'customer left the shop', discardedBy: 'm1', managerToken: 'eyJ.mgr2.token');
      await store.close();

      final rows = await rawRows();
      final everything = rows.map((r) => r.values.join('|')).join('\n');
      for (final secret in ['secret-variant', '123.45', 'eyJ.manager', 'eyJ.mgr2', 'Insufficient stock', 'customer left']) {
        expect(everything, isNot(contains(secret)), reason: '"$secret" must not be readable on disk');
      }
      expect(rows.every((r) => r['enc'] == 2), isTrue);
      expect((rows.first['payload'] as String), startsWith('v2:'));
      // routing columns stay queryable
      expect(rows.first['storeId'], 's1');
      expect(rows.first['sessionId'], 'A');
    });

    test('everything still round trips through the store, including after a restart', () async {
      var store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      await store.enqueue('k1', payload('1'), employeeToken: 'tok');
      await store.markFailed('k1', 'rejected: too old', errorCode: 'OFFLINE_SALE_TOO_OLD');
      await store.close();
      store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      final r = (await store.getById('k1'))!;
      expect(r.payload['clientTotal'], 123.45);
      expect(r.employeeToken, 'tok');
      expect(r.errorMessage, 'rejected: too old');
      expect(r.errorCode, 'OFFLINE_SALE_TOO_OLD');
      expect(r.unreadable, isFalse);
      await store.close();
    });

    test('a row that cannot be decrypted (key lost) is KEPT, shown as failed/unreadable, counted as unresolved, and can be discarded — never dropped', () async {
      var store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher(1));
      await store.enqueue('k1', payload('1'));
      await store.close();

      store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher(2)); // a different (new) key
      final r = (await store.getById('k1'))!;
      expect(r.unreadable, isTrue);
      expect(r.isFailed, isTrue, reason: 'never replayed blind');
      expect(r.errorMessage, contains('could not be read'));
      expect(r.storeId, 's1');
      expect(r.sessionId, 'A');
      expect(await store.countUnresolved(sessionId: 'A'), 1, reason: 'it still blocks closing the shift');
      await store.markDiscarding('k1', reason: 'device key lost; confirmed with the customer', discardedBy: 'm1');
      expect((await store.getById('k1'))!.isDiscarding, isTrue);
      await store.close();
    });
  });

  group('migration of existing plaintext data', () {
    Future<void> seedPlainV2() async {
      final db = await databaseFactoryFfi.openDatabase(dbFile, options: OpenDatabaseOptions(version: 2, onCreate: (db, _) async {
        await db.execute('''CREATE TABLE pending_sales (id TEXT PRIMARY KEY, payload TEXT NOT NULL, status TEXT NOT NULL, errorMessage TEXT, errorCode TEXT,
          createdAt TEXT NOT NULL, storeId TEXT, sessionId TEXT, employeeToken TEXT, attempts INTEGER NOT NULL DEFAULT 0, nextAttemptAt TEXT, lastAttemptAt TEXT,
          discardReason TEXT, discardedBy TEXT)''');
        for (var i = 1; i <= 3; i++) {
          await db.insert('pending_sales', {
            'id': 'old-$i', 'payload': jsonEncode(payload('$i')), 'status': i == 2 ? 'failed' : 'pending', 'errorMessage': i == 2 ? 'old failure text' : null,
            'errorCode': i == 2 ? 'X' : null, 'createdAt': '2026-11-01T09:0$i:00.000', 'storeId': 's1', 'sessionId': 'A', 'employeeToken': i == 1 ? 'plain.token' : null,
            'discardReason': i == 3 ? 'plain reason' : null, 'discardedBy': i == 3 ? 'm1' : null,
          });
        }
      }));
      await db.close();
    }

    test('v2 plaintext rows are encrypted on first open with NOTHING lost (same ids, status, contents)', () async {
      await seedPlainV2();
      final store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      final rows = await store.getAll();
      expect(rows.map((r) => r.id), ['old-1', 'old-2', 'old-3']);
      expect(rows[0].payload['clientTotal'], 123.45);
      expect(rows[0].employeeToken, 'plain.token');
      expect(rows[1].errorMessage, 'old failure text');
      expect(rows[1].errorCode, 'X');
      expect(rows[1].isFailed, isTrue);
      expect(rows[2].discardReason, 'plain reason');
      expect(rows.every((r) => !r.unreadable), isTrue);
      await store.close();

      final raw = await rawRows();
      expect(raw.map((r) => r.values.join('|')).join(), isNot(contains('secret-variant')));
      expect(raw.map((r) => r.values.join('|')).join(), isNot(contains('plain.token')));
      expect(raw.every((r) => r['enc'] == 2), isTrue);
    });

    test('migration is idempotent (opening again changes nothing)', () async {
      await seedPlainV2();
      var store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      await store.getAll();
      await store.close();
      final before = await rawRows();
      store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      await store.getAll();
      await store.close();
      expect((await rawRows()).map((r) => r['payload']), before.map((r) => r['payload']), reason: 'ciphertext is not re-encrypted');
    });

    test('a failure midway (key unavailable) loses nothing: migrated rows are encrypted, the rest stay readable plaintext, the next open finishes', () async {
      await seedPlainV2();
      // old-1 needs 2 encryptions (payload + token); allow exactly that, then fail
      var store = PendingSaleLocalStore(dbPath: dbFile, cipher: FlakyCipher(cipher(), 2));
      final during = await store.getAll();
      expect(during.length, 3, reason: 'every row is still there');
      expect(during.map((r) => r.payload['clientTotal']), [123.45, 123.45, 123.45]);
      await store.close();
      var raw = await rawRows();
      expect(raw.where((r) => r['enc'] == 2).length, 1);
      expect(raw.where((r) => r['enc'] == 0).length, 2);

      store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      expect((await store.getAll()).length, 3);
      await store.close();
      raw = await rawRows();
      expect(raw.every((r) => r['enc'] == 2), isTrue);
    });

    /// A database written by 5F: schema v3, enc = 1, every value `v1:`-tagged.
    Future<void> seedEncV1({int rows = 3}) async {
      final c = cipher();
      Future<String> v1(String plain) async => 'v1:${(await c.encrypt(plain)).substring(3)}';
      final db = await databaseFactoryFfi.openDatabase(dbFile, options: OpenDatabaseOptions(version: 3, onCreate: (db, _) async {
        await db.execute('''CREATE TABLE pending_sales (id TEXT PRIMARY KEY, payload TEXT NOT NULL, status TEXT NOT NULL, errorMessage TEXT, errorCode TEXT,
          createdAt TEXT NOT NULL, storeId TEXT, sessionId TEXT, employeeToken TEXT, attempts INTEGER NOT NULL DEFAULT 0, nextAttemptAt TEXT, lastAttemptAt TEXT,
          discardReason TEXT, discardedBy TEXT, enc INTEGER NOT NULL DEFAULT 1)''');
        for (var i = 1; i <= rows; i++) {
          await db.insert('pending_sales', {
            'id': '5f-$i', 'payload': await v1(jsonEncode(payload('$i'))), 'status': i == 2 ? 'failed' : 'pending', 'errorMessage': i == 2 ? await v1('5F failure') : null,
            'errorCode': i == 2 ? 'X' : null, 'createdAt': '2026-11-01T09:0$i:00.000', 'storeId': 's1', 'sessionId': 'A', 'employeeToken': i == 1 ? await v1('tok.5f') : null, 'enc': 1,
          });
        }
      }));
      await db.close();
    }

    test('5F rows (enc=1, v1:) are re-encrypted with the OS-crypto cipher as v2: — every id/status/content preserved', () async {
      await seedEncV1();
      final store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      final rows = await store.getAll();
      expect(rows.map((r) => r.id), ['5f-1', '5f-2', '5f-3']);
      expect(rows[0].payload['clientTotal'], 123.45);
      expect(rows[0].employeeToken, 'tok.5f');
      expect(rows[1].errorMessage, '5F failure');
      expect(rows[1].isFailed, isTrue);
      expect(rows.every((r) => !r.unreadable), isTrue);
      await store.close();
      final raw = await rawRows();
      expect(raw.every((r) => r['enc'] == 2), isTrue);
      for (final r in raw) {
        for (final f in ['payload', 'employeeToken', 'errorMessage']) {
          final v = r[f] as String?;
          if (v != null) expect(v, startsWith('v2:'), reason: f);
        }
      }
    });

    test('v1 → v2 migration is idempotent', () async {
      await seedEncV1();
      var store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      await store.getAll();
      await store.close();
      final before = await rawRows();
      store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      await store.getAll();
      await store.close();
      expect((await rawRows()).map((r) => r['payload']), before.map((r) => r['payload']));
    });

    test('crash midway through v1 → v2 loses nothing; the next open finishes', () async {
      await seedEncV1();
      // row 1 = payload + token = 2 encryptions allowed, then the keystore "fails"
      var store = PendingSaleLocalStore(dbPath: dbFile, cipher: FlakyCipher(cipher(), 2));
      final during = await store.getAll();
      expect(during.length, 3);
      expect(during.map((r) => r.payload['clientTotal']), [123.45, 123.45, 123.45]);
      expect(during.every((r) => !r.unreadable), isTrue);
      await store.close();
      var raw = await rawRows();
      expect(raw.where((r) => r['enc'] == 2).length, 1);
      expect(raw.where((r) => r['enc'] == 1).length, 2);
      store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      expect((await store.getAll()).length, 3);
      await store.close();
      raw = await rawRows();
      expect(raw.every((r) => r['enc'] == 2), isTrue);
    });

    test('a v1 row whose key is gone is NOT touched by the migration and stays discardable', () async {
      await seedEncV1(rows: 1);
      final before = (await rawRows()).single['payload'];
      final store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher(99)); // wrong key
      final r = (await store.getById('5f-1'))!;
      expect(r.unreadable, isTrue);
      await store.close();
      final after = (await rawRows()).single;
      expect(after['payload'], before);
      expect(after['enc'], 1);
    });

    test('v1 → v3 in one go (the original schema) also ends encrypted', () async {
      final v1 = await databaseFactoryFfi.openDatabase(dbFile, options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await db.execute('CREATE TABLE pending_sales (id TEXT PRIMARY KEY, payload TEXT NOT NULL, status TEXT NOT NULL, errorMessage TEXT, createdAt TEXT NOT NULL)');
        await db.insert('pending_sales', {'id': 'v1-1', 'payload': jsonEncode(payload('1')), 'status': 'pending', 'createdAt': '2026-11-01T09:00:00.000'});
      }));
      await v1.close();
      final store = PendingSaleLocalStore(dbPath: dbFile, cipher: cipher());
      final r = (await store.getById('v1-1'))!;
      expect(r.payload['clientTotal'], 123.45);
      expect(r.sessionId, 'A');
      await store.close();
      expect((await rawRows()).single['enc'], 2);
    });
  });
}
