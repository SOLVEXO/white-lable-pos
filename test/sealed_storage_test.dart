// G1a follow-up: the cart snapshot, the checkout-intent store and the settings cache are encrypted at rest with the offline queue's
// AES-256-GCM key. Migration of older plaintext, lost key, tampering — none of them may crash or lose a QUEUED sale — plus the
// one-time move of the existing key to the first-unlock / this-device keychain class.
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/local/pos_local_caches.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';

SecretKey _key(int seed) => SecretKey(List<int>.generate(32, (i) => (i * 7 + seed) & 0xff));
SealedText _sealedWith(int seed) => SealedText(cipher: AesGcmQueueCipher(fixedKey: _key(seed)));

CartSnapshot _cart({String customer = 'Ayesha Khan'}) => CartSnapshot(
      storeId: 'store-1',
      sessionId: 'session-1',
      lines: const [CartLineSnapshot(product: {'productId': 'p1', 'name': 'Tea'}, variantId: 'v1', qty: 2)],
      customerName: customer,
      customerId: 'cust-9',
      note: 'gift wrap',
      pendingKey: 'checkout-key-777',
      pendingAt: DateTime(2026, 11, 4, 10),
      savedAt: DateTime(2026, 11, 4, 10),
    );

const _settings = PosSettingsModel(storeId: 'store-1', taxRate: 0.05, businessName: 'Corner Bakery', businessTaxId: 'NTN-7654321', settingsVersion: 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> Function() prefsOf(SharedPreferences p) => () async => p;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('cart snapshot', () {
    test('stored encrypted — no customer name, note, key or product in the stored text — and round-trips', () async {
      final store = CartSnapshotStore(prefs: prefsOf(prefs), clock: () => DateTime(2026, 11, 4, 11), sealed: _sealedWith(1));
      await store.save(_cart());
      final raw = prefs.getString('pos_cart_snapshot')!;
      expect(raw, startsWith('v2:'));
      for (final secret in ['Ayesha', 'gift wrap', 'checkout-key-777', 'cust-9', 'Tea']) {
        expect(raw.contains(secret), isFalse, reason: secret);
      }
      final back = await store.load(storeId: 'store-1', sessionId: 'session-1');
      expect(back!.customerName, 'Ayesha Khan');
      expect(back.pendingKey, 'checkout-key-777');
      expect(back.lines.single.qty, 2);
    });

    test('legacy PLAINTEXT from an older build is read once and re-saved encrypted', () async {
      await prefs.setString('pos_cart_snapshot', jsonEncode(_cart().toJson()));
      final store = CartSnapshotStore(prefs: prefsOf(prefs), clock: () => DateTime(2026, 11, 4, 11), sealed: _sealedWith(1));
      final back = await store.load(storeId: 'store-1', sessionId: 'session-1');
      expect(back!.customerName, 'Ayesha Khan');
      final raw = prefs.getString('pos_cart_snapshot')!;
      expect(raw, startsWith('v2:'));
      expect(raw.contains('Ayesha'), isFalse);
    });

    test('KEY LOST: the snapshot is dropped (empty cart), nothing throws, the unreadable value is removed', () async {
      await CartSnapshotStore(prefs: prefsOf(prefs), clock: () => DateTime(2026, 11, 4, 11), sealed: _sealedWith(1)).save(_cart());
      final withNewKey = CartSnapshotStore(prefs: prefsOf(prefs), clock: () => DateTime(2026, 11, 4, 11), sealed: _sealedWith(2));
      expect(await withNewKey.load(storeId: 'store-1', sessionId: 'session-1'), isNull);
      expect(prefs.containsKey('pos_cart_snapshot'), isFalse);
      // and saving again works with the new key
      await withNewKey.save(_cart(customer: 'Fatima'));
      expect((await withNewKey.load(storeId: 'store-1', sessionId: 'session-1'))!.customerName, 'Fatima');
    });

    test('TAMPERED ciphertext is detected (GCM) and dropped — never loaded as a different cart', () async {
      final store = CartSnapshotStore(prefs: prefsOf(prefs), clock: () => DateTime(2026, 11, 4, 11), sealed: _sealedWith(1));
      await store.save(_cart());
      final raw = prefs.getString('pos_cart_snapshot')!;
      final bytes = base64Decode(raw.substring(3));
      bytes[bytes.length ~/ 2] ^= 0x01; // flip one bit in the middle
      await prefs.setString('pos_cart_snapshot', 'v2:${base64Encode(bytes)}');
      expect(await store.load(storeId: 'store-1', sessionId: 'session-1'), isNull);
      expect(prefs.containsKey('pos_cart_snapshot'), isFalse);
    });

    test('garbage that is not JSON or ciphertext does not crash either', () async {
      await prefs.setString('pos_cart_snapshot', 'not json at all');
      final store = CartSnapshotStore(prefs: prefsOf(prefs), sealed: _sealedWith(1));
      expect(await store.load(storeId: 'store-1', sessionId: 'session-1'), isNull);
    });
  });

  group('settings cache', () {
    test('business name, tax id and receipt text are not in the stored text; round-trips', () async {
      final store = SettingsCacheStore(prefs: prefsOf(prefs), clock: () => DateTime(2026, 11, 4), sealed: _sealedWith(1));
      await store.save(_settings);
      final raw = prefs.getString('pos_settings_cache')!;
      expect(raw, startsWith('v2:'));
      expect(raw.contains('Corner Bakery'), isFalse);
      expect(raw.contains('NTN-7654321'), isFalse);
      final back = await store.load('store-1');
      expect(back!.settings.businessTaxId, 'NTN-7654321');
    });

    test('legacy plaintext migrates; key lost → dropped; tamper → dropped', () async {
      await prefs.setString('pos_settings_cache', jsonEncode({'savedAt': '2026-11-04T00:00:00.000', 'settings': _settings.toCacheJson()}));
      final store = SettingsCacheStore(prefs: prefsOf(prefs), sealed: _sealedWith(1));
      expect((await store.load('store-1'))!.settings.businessName, 'Corner Bakery');
      expect(prefs.getString('pos_settings_cache'), startsWith('v2:')); // migrated

      expect(await SettingsCacheStore(prefs: prefsOf(prefs), sealed: _sealedWith(2)).load('store-1'), isNull); // key lost
      expect(prefs.containsKey('pos_settings_cache'), isFalse);

      await store.save(_settings);
      final bytes = base64Decode(prefs.getString('pos_settings_cache')!.substring(3));
      bytes.last ^= 0x80;
      await prefs.setString('pos_settings_cache', 'v2:${base64Encode(bytes)}');
      expect(await store.load('store-1'), isNull); // tampered
    });
  });

  group('checkout intent store', () {
    IdempotencyIntentStore make(int seed, {String Function()? gen}) =>
        IdempotencyIntentStore(prefs: prefsOf(prefs), clock: () => DateTime(2026, 11, 4, 10), keyGenerator: gen ?? () => 'key-A', sealed: _sealedWith(seed));

    test('the key survives a restart, but is not readable in the stored text', () async {
      expect(await make(1).keyFor('sale:abc'), 'key-A');
      final raw = prefs.getString('pos_idempotency_intents')!;
      expect(raw, startsWith('v2:'));
      expect(raw.contains('key-A'), isFalse);
      expect(raw.contains('sale:abc'), isFalse);
      expect(await make(1, gen: () => 'key-B').keyFor('sale:abc'), 'key-A', reason: 'same intent after a restart → the same key (no duplicate sale)');
    });

    test('legacy plaintext is migrated immediately and still honoured', () async {
      await prefs.setString('pos_idempotency_intents', jsonEncode({'sale:abc': {'key': 'legacy-key', 'at': DateTime(2026, 11, 4, 10).millisecondsSinceEpoch}}));
      expect(await make(1).keyFor('sale:abc'), 'legacy-key');
      expect(prefs.getString('pos_idempotency_intents'), startsWith('v2:'));
    });

    test('key lost or tampered → starts clean and STILL returns a usable key (checkout is never blocked)', () async {
      await make(1).keyFor('sale:abc');
      expect(await make(2, gen: () => 'key-NEW').keyFor('sale:abc'), 'key-NEW'); // wrong key = lost key
      final store = make(1, gen: () => 'key-C');
      await store.keyFor('sale:def');
      final bytes = base64Decode(prefs.getString('pos_idempotency_intents')!.substring(3));
      bytes[5] ^= 0xff;
      await prefs.setString('pos_idempotency_intents', 'v2:${base64Encode(bytes)}');
      expect(await store.keyFor('sale:def'), 'key-C');
    });
  });

  // The keychain accessibility class is an Apple (iOS / macOS) option: on Linux CI the plugin sends no such option, so there is nothing to assert.
  group('the queue key: first-unlock / this-device keychain class migration', skip: (Platform.isIOS || Platform.isMacOS) ? null : 'Apple keychain options only', () {
    late Map<String, String> mem;
    late List<String> log;
    void mockStorage() {
      mem = {};
      log = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
        final a = (call.arguments as Map).cast<String, dynamic>();
        log.add('${call.method}:${a['key']}${call.method == 'write' ? ':${(a['options'] as Map?)?['accessibility'] ?? '-'}' : ''}');
        switch (call.method) {
          case 'write':
            mem[a['key'] as String] = a['value'] as String;
            return null;
          case 'read':
            return mem[a['key'] as String];
          case 'delete':
            mem.remove(a['key'] as String);
            return null;
          case 'containsKey':
            return mem.containsKey(a['key'] as String);
          default:
            return null;
        }
      });
    }

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), null));

    test('a NEW key is written with the first_unlock_this_device class', () async {
      mockStorage();
      await AesGcmQueueCipher().encrypt('x');
      expect(log.where((l) => l.startsWith('write:pos_queue_encryption_key:')).single, endsWith('first_unlock_this_device'));
      expect(prefs.getBool('pos_queue_key_keychain_class_v2'), isTrue);
    });

    test('an EXISTING key is moved to the new class without ever changing, and old data still decrypts', () async {
      mockStorage();
      final key = base64Encode(List<int>.generate(32, (i) => i + 1));
      mem['pos_queue_encryption_key'] = key; // written by an older build
      final oldCipher = AesGcmQueueCipher(fixedKey: SecretKey(base64Decode(key)));
      final sealedByOldBuild = await oldCipher.encrypt('unsynced sale');

      final cipher = AesGcmQueueCipher();
      expect(await cipher.decrypt(sealedByOldBuild), 'unsynced sale');
      expect(mem['pos_queue_encryption_key'], key, reason: 'same key material');
      expect(mem.containsKey('pos_queue_encryption_key_migrating'), isFalse, reason: 'temp slot cleaned up');
      expect(log.where((l) => l.startsWith('write:pos_queue_encryption_key:')).last, endsWith('first_unlock_this_device'));
      expect(prefs.getBool('pos_queue_key_keychain_class_v2'), isTrue);
      // the migration runs once
      final writesBefore = log.where((l) => l.startsWith('write')).length;
      await AesGcmQueueCipher().decrypt(sealedByOldBuild);
      expect(log.where((l) => l.startsWith('write')).length, writesBefore);
    });

    test('CRASH between delete and re-add: the key is restored from the temp slot, never regenerated', () async {
      mockStorage();
      final key = base64Encode(List<int>.generate(32, (i) => 200 - i));
      mem['pos_queue_encryption_key_migrating'] = key; // the main slot is gone
      final enc = await AesGcmQueueCipher(fixedKey: SecretKey(base64Decode(key))).encrypt('queued');
      expect(await AesGcmQueueCipher().decrypt(enc), 'queued');
      expect(mem['pos_queue_encryption_key'], key);
    });

    test('a storage failure during the migration never crashes and never loses the key', () async {
      mockStorage();
      final key = base64Encode(List<int>.generate(32, (i) => i * 3));
      mem['pos_queue_encryption_key'] = key;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
        final a = (call.arguments as Map).cast<String, dynamic>();
        if (call.method == 'write' && a['key'] == 'pos_queue_encryption_key_migrating') throw PlatformException(code: 'boom');
        if (call.method == 'read') return mem[a['key'] as String];
        return null;
      });
      final enc = await AesGcmQueueCipher(fixedKey: SecretKey(base64Decode(key))).encrypt('queued');
      expect(await AesGcmQueueCipher().decrypt(enc), 'queued');
      expect(mem['pos_queue_encryption_key'], key);
    });
  });
}
