import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
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

/// AES-256-GCM (authenticated: tampering is detected, not just hidden). Format: `v1:` + base64(nonce ‖ ciphertext ‖ mac).
/// The 256-bit key is generated once on the device and lives in the Keychain/Keystore (flutter_secure_storage) —
/// never in SharedPreferences, never in the database it protects.
class AesGcmQueueCipher implements QueueCipher {
  AesGcmQueueCipher({FlutterSecureStorage? storage, SecretKey? fixedKey})
      : _storage = storage ?? const FlutterSecureStorage(),
        _key = fixedKey;

  static const _storageKey = 'pos_queue_encryption_key';
  static const _prefix = 'v1:';
  static final _algo = AesGcm.with256bits();

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
    return '$_prefix${base64Encode(box.concatenation())}';
  }

  @override
  Future<String> decrypt(String cipher) async {
    if (!cipher.startsWith(_prefix)) throw QueueDecryptException('not an encrypted value');
    try {
      final bytes = base64Decode(cipher.substring(_prefix.length));
      final box = SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16);
      return utf8.decode(await _algo.decrypt(box, secretKey: await _loadKey()));
    } catch (e) {
      throw QueueDecryptException('could not decrypt (key missing or data damaged): $e');
    }
  }
}
