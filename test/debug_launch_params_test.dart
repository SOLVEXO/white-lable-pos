// The debug launch helpers must never do anything in a release build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/config/debug_launch_params.dart';

void main() {
  final src = File('lib/config/debug_launch_params.dart').readAsStringSync();

  /// The text of the member whose declaration contains [signature], up to its first statement.
  String firstStatement(String signature) {
    final i = src.indexOf(signature);
    expect(i, greaterThanOrEqualTo(0), reason: '$signature not found');
    final open = src.indexOf('{', i);
    return src.substring(open + 1, src.indexOf(';', open)).trim();
  }

  test('every entry point starts with a const kDebugMode guard', () {
    for (final sig in [
      'static String? get(String key)',
      'static Future<void> seed()',
      'static ThemeMode get themeMode',
      'static Widget wrapLandscape(',
    ]) {
      expect(firstStatement(sig), startsWith('if (!kDebugMode)'), reason: sig);
    }
  });

  test(
    'nothing in the file is read from assets, and the parameters file is only an external dart-define path',
    () {
      expect(src.contains('rootBundle'), isFalse);
      expect(src.contains("String.fromEnvironment('DBG_PARAMS_FILE')"), isTrue);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('params'),
        isFalse,
        reason: 'no parameters/seed file may be listed as an asset',
      );
      expect(pubspec.contains('DBG_PARAMS_FILE'), isFalse);
    },
  );

  test('with no DBG_PARAMS_FILE the helpers are inert', () async {
    expect(DebugLaunchParams.get('SEED'), isNull);
    await DebugLaunchParams.seed(); // returns immediately; touches no preferences
  });

  test(
    'no release code path references the seed or the gallery route unguarded',
    () {
      final pages = File('lib/app/routes/app_pages.dart').readAsStringSync();
      expect(
        pages.contains('if (kDebugMode) GetPage(name: Routes.designGallery'),
        isTrue,
      );
      expect(
        pages.contains(
          'kDebugMode ? _debugInitialRoute() : Routes.splashScreen',
        ),
        isTrue,
      );
    },
  );
}
