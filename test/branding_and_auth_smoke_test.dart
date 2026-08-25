// Smoke test for this app's architecture: POS is fully standalone — it owns
// its own copies of BrandingConfigModel/AuthRepository/etc, no path
// dependency on book_store_app. This just confirms that wiring resolves and
// behaves as expected from POS's own package — pure Dart, no platform
// channels needed.

import 'package:solvexo_pos/app/data/models/branding/branding_config_model.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('POS can construct and use its own BrandingConfigModel', () {
    final defaults = BrandingConfigModel.defaults();
    expect(defaults.appName, 'Solvexo');
    expect(defaults.primaryColor, const Color(0xFFd97757));

    // A tenant config as POS would receive it from BrandingService.
    final tenant = BrandingConfigModel.fromJson({
      'appName': 'Acme',
      'primaryColor': '#112233',
      'featureFlags': {'posAuditLog': false},
    });
    expect(tenant.appName, 'Acme');
    expect(tenant.isFeatureEnabled('posAuditLog'), false);
  });

  test('POS can construct its own AuthRepository (Google Sign-In, socialLogin+logout)', () {
    expect(() => AuthRepository(), returnsNormally);
  });
}
