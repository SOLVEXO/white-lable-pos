import 'package:solvexo_pos/app/data/local/queue_cipher.dart';

/// Encrypts the text a store keeps in SharedPreferences with the offline queue's AES-256-GCM key (no new key, no new package).
///
/// [open] never throws. Three outcomes:
///  * a `v2:` / `v1:` value that decrypts → [SealedRead.text];
///  * a value that is not encrypted at all → LEGACY plaintext written by an older build: returned as-is with [SealedRead.legacyPlain]
///    so the caller re-saves it encrypted (the migration, on first read);
///  * a value that cannot be decrypted (key lost, data damaged, or TAMPERED — GCM authenticates) → [SealedRead.unreadable]: the
///    caller drops it and starts clean (a cart / cache / checkout intent is rebuildable) — never a crash.
class SealedText {
  SealedText({QueueCipher? cipher}) : _cipher = cipher ?? AesGcmQueueCipher.shared;
  final QueueCipher _cipher;

  Future<String> seal(String plain) => _cipher.encrypt(plain);

  Future<SealedRead> open(String raw) async {
    final encrypted = raw.startsWith(AesGcmQueueCipher.currentPrefix) || raw.startsWith(AesGcmQueueCipher.legacyPrefix);
    if (!encrypted) return SealedRead(raw, legacyPlain: true);
    try {
      return SealedRead(await _cipher.decrypt(raw));
    } catch (_) {
      return const SealedRead(null, unreadable: true);
    }
  }
}

class SealedRead {
  const SealedRead(this.text, {this.legacyPlain = false, this.unreadable = false});
  final String? text;
  final bool legacyPlain;
  final bool unreadable;
}
