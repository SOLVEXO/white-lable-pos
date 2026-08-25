import 'package:audioplayers/audioplayers.dart';

class SoundUtil {
  static final _player = AudioPlayer();

  static Future<void> play(String path) async {
    await _player.play(AssetSource(path));
  }
}
