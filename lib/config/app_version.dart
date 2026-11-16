/// G5.1: the app's version and build number, as in `pubspec.yaml` (`version: 1.0.2+104`). Kept as constants so the About screen needs no extra
/// package; `test/app_version_test.dart` fails if this file and pubspec.yaml disagree — bump both together.
abstract final class AppVersion {
  static const String version = '1.0.2';
  static const String build = '104';
  static String get label => '$version ($build)';
}
