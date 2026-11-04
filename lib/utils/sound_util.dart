import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class SoundUtil {
  static final _player = AudioPlayer();

  /// Tests switch this off so a toast doesn't try to start the audio plugin. Production code never touches it.
  @visibleForTesting
  static bool enabled = true;

  static Future<void> play(String path) async {
    if (!enabled) return;
    await _player.play(AssetSource(path));
  }
}
