import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts the sensitive columns of the offline queue (sale contents, the employee token kept for an authorised
/// discount, error text, discard reason) so a lost/copied device or a backup does not expose them.
abstract class QueueCipher {
  Future<String> encrypt(String plain);

  /// Throws [QueueDecryptException] when the text can't be decrypted (wrong/missing key, damaged data).
  Future<String> decrypt(String cipher);
}

class QueueDecryptException implements Exception {
  final String message;
  QueueDecryptException(this.message);
  @override
  String toString() => 'QueueDecryptException: $message';
}

/// AES-256-GCM (authenticated: tampering is detected, not just hidden). Format: `<tag>` + base64(nonce ‖ ciphertext ‖ mac).
/// The 256-bit key is generated once on the device and lives in the Keychain/Keystore (flutter_secure_storage) —
/// never in SharedPreferences, never in the database it protects.
///
/// WHICH CRYPTO RUNS: the cipher goes through `Cryptography.instance`. With `cryptography_flutter` (auto-registered on iOS
/// and Android) that is the operating system's own AES-GCM — **CryptoKit `AES.GCM` on iOS, `javax.crypto` `AES/GCM/NoPadding`
/// on Android** — so the app ships no cryptographic implementation of its own (relevant to the export-compliance answer; see
/// docs/store_submission_checklist.md §2). Where the plugin isn't registered (unit tests on the host VM) the package's pure-Dart
/// AES-GCM is used; it produces byte-identical output.
///
/// Versions: `v1:` = written by app versions up to 5F with the pure-Dart implementation; `v2:` = written by the OS provider.
/// The two are the same standard AES-256-GCM with the same 12-byte nonce / 16-byte tag layout and the same key, so a `v1:` value
/// decrypts unchanged; the store re-tags rows to `v2:` in place (see PendingSaleLocalStore) so every row records which scheme made it.
class AesGcmQueueCipher implements QueueCipher {
  AesGcmQueueCipher({FlutterSecureStorage? storage, SecretKey? fixedKey})
      : _storage = storage ?? const FlutterSecureStorage(),
        _key = fixedKey;

  /// Secure-storage slot of the queue's AES key. Anything that wipes secure storage must keep it while sales are unsynced.
  static const storageKey = 'pos_queue_encryption_key';
  static const _storageKey = storageKey;
  static const legacyPrefix = 'v1:';
  static const currentPrefix = 'v2:';

  /// True when the encryption below runs on the OS crypto provider (iOS/Android with the plugin registered).
  static bool get usesOsCrypto => FlutterCryptography.isPluginPresent;

  /// Resolved on every use so the provider registered at startup is the one used.
  static AesGcm get _algo => Cryptography.instance.aesGcm(secretKeyLength: 32);

  final FlutterSecureStorage _storage;
  SecretKey? _key;

  Future<SecretKey> _loadKey() async {
    final cached = _key;
    if (cached != null) return cached;
    var b64 = await _storage.read(key: _storageKey);
    if (b64 == null || b64.isEmpty) {
      final r = Random.secure();
      b64 = base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await _storage.write(key: _storageKey, value: b64);
    }
    return _key = SecretKey(base64Decode(b64));
  }

  @override
  Future<String> encrypt(String plain) async {
    final box = await _algo.encrypt(utf8.encode(plain), secretKey: await _loadKey());
    return '$currentPrefix${base64Encode(box.concatenation())}';
  }

  @override
  Future<String> decrypt(String cipher) async {
    final tag = cipher.startsWith(currentPrefix) ? currentPrefix : cipher.startsWith(legacyPrefix) ? legacyPrefix : null;
    if (tag == null) throw QueueDecryptException('not an encrypted value');
    try {
      final bytes = base64Decode(cipher.substring(tag.length));
      final box = SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16);
      return utf8.decode(await _algo.decrypt(box, secretKey: await _loadKey()));
    } catch (e) {
      throw QueueDecryptException('could not decrypt (key missing or data damaged): $e');
    }
  }
}
