import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Registers the bundled fonts' SIL OFL 1.1 texts so they show up on Flutter's
/// license page (`showLicensePage`). Safe to call more than once.
void registerDesignFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Manrope'],
      await rootBundle.loadString('assets/app_fonts/manrope/OFL.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['DM Sans'],
      await rootBundle.loadString('assets/app_fonts/dm_sans/OFL.txt'),
    );
  });
}
