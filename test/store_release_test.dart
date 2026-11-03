// 5F — release/store configuration guards: environment validation, PII scrubbing, account deletion UI, and static checks on the
// native manifests so a store-compliance setting can't silently regress.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/common_models/social_login_model.dart';
import 'package:solvexo_pos/app/data/repositories/account_repository.dart';
import 'package:solvexo_pos/app/data/services/social_auth_service.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/delete_account_view.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/config/telemetry.dart';

class MockAccountRepo extends Mock implements AccountRepository {}

class MockSocial extends Mock implements SocialAuthService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('environment config', () {
    String? v(String url, {bool release = true, String env = 'prod'}) => AppEnv.validate(release: release, env: env, baseUrl: url);

    test('release refuses a missing, non-https, local or dev configuration', () {
      expect(v(''), contains('API_BASE_URL is empty'));
      expect(v('http://api.solvexo.store'), contains('https'));
      expect(v('https://localhost:3000'), contains('local'));
      expect(v('https://10.0.2.2'), contains('local'));
      expect(v('https://192.168.1.5'), contains('local'));
      expect(v('https://printer.local'), contains('local'));
      expect(v('not a url'), isNotNull);
    });

    test('release accepts https staging/prod; debug accepts http dev', () {
      expect(v('https://api.solvexo.store', env: 'prod'), isNull);
      expect(v('https://staging.api.solvexo.store', env: 'staging'), isNull);
      expect(v('http://localhost:3000', release: false, env: 'dev'), isNull);
      expect(v('', release: false), isNotNull); // an empty URL is never acceptable
    });

    test('the API URL is defined in exactly one place (ApiConstants) and is https', () {
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        for (final line in f.readAsLinesSync()) {
          final t = line.trim();
          if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) continue;
          if (RegExp(r'''['"]https?://[a-z0-9]''', caseSensitive: false).hasMatch(t) && !t.contains("startsWith('http")) hits.add('${f.path}: $t');
        }
      }
      expect(hits, hasLength(1));
      expect(hits.single, contains('api_constaints.dart'));
      expect(hits.single, contains("'https://"));
      expect(AppEnv.validate(release: true, baseUrl: ApiConstants.baseUrl), isNull); // the shipped default is release-valid
    });
  });

  group('crash reporting carries no personal data', () {
    test('scrubs emails, phones, tokens, PINs, passwords, long ids', () {
      const raw = 'Failed for ann@shop.com phone +92 300 1234567 token eyJhbGciOi.eyJzdWIiOiIx.abcDEF pin: 1234 password=hunter2 Bearer abc.def.ghi id 5f1d7f3a9c2b4e0012ab34cd5f1d7f3a9c2b4e00';
      final s = Telemetry.scrub(raw);
      for (final leak in ['ann@shop.com', '300 1234567', 'eyJhbGci', '1234', 'hunter2', 'abc.def.ghi', '5f1d7f3a9c2b4e00']) {
        expect(s.contains(leak), isFalse, reason: '"$leak" leaked in: $s');
      }
      expect(s, contains('[email]'));
    });

    test('HTTP failures are reported as METHOD /path/:id -> status, never with query or body', () {
      expect(Telemetry.scrubPath('https://api.x/api/pos/sales/65a1b2c3d4e5f60718293a4b/refund?customer=Ann&phone=555'), '/api/pos/sales/:id/refund');
    });

    test('long messages are truncated', () => expect(Telemetry.scrub('x ' * 1000).length, lessThanOrEqualTo(601)));
  });

  group('delete account screen', () {
    late MockAccountRepo repo;
    setUp(() {
      Get.reset();
      OwnerSession.end();
      SharedPreferences.setMockInitialValues({'pos_sound_effects': false});
      repo = MockAccountRepo();
      when(() => repo.authMethods()).thenAnswer((_) async => const DeletionAuthMethods());
    });
    Widget app({SocialAuthService? social}) => ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(home: DeleteAccountView(repository: repo, socialAuth: social, skipUnsyncedGuard: true)));

    testWidgets('states the consequences and cannot be submitted without the password AND the confirmation', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.textContaining('permanently removes'), findsOneWidget);
      expect(find.textContaining('30 days'), findsOneWidget);
      expect(find.textContaining('kept as the law requires'), findsOneWidget);
      FilledButton btn() => tester.widget<FilledButton>(find.byKey(const Key('deleteSubmit'), skipOffstage: false));
      expect(btn().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('deletePassword')), 'pw');
      await tester.pump();
      expect(btn().onPressed, isNull); // still needs the checkbox
      await tester.tap(find.byKey(const Key('deleteConfirm')));
      await tester.pump();
      expect(btn().onPressed, isNotNull);
      verifyNever(() => repo.requestDeletion(password: any(named: 'password'), reauth: any(named: 'reauth')));
    });

    testWidgets('wrong password / open shift / social-only account show a clear message and delete nothing', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('deletePassword')), 'bad');
      await tester.ensureVisible(find.byKey(const Key('deleteConfirm')));
      await tester.tap(find.byKey(const Key('deleteConfirm')));
      await tester.pump();
      for (final c in [
        (DeletionOutcome.wrongPassword, 'not correct'),
        (DeletionOutcome.openSessions, 'Close every open register shift'),
        (DeletionOutcome.needsWeb, 'no password to confirm with'),
      ]) {
        when(() => repo.requestDeletion(password: 'bad')).thenAnswer((_) async => (outcome: c.$1, scheduledFor: null, message: null));
        await tester.ensureVisible(find.byKey(const Key('deleteSubmit')));
        await tester.tap(find.byKey(const Key('deleteSubmit')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
        expect(find.textContaining(c.$2, findRichText: true, skipOffstage: false), findsWidgets, reason: '${c.$1}');
      }
    });

    group('social owners', () {
      const googleId = SocialLoginModel(authProvider: 'google', socialId: 'g-1', userName: 'A', token: 'tok-g');
      const appleId = SocialLoginModel(authProvider: 'apple', socialId: 'a-1', userName: 'A', token: 'tok-a');

      testWidgets('Google-only owner: no password field, re-authenticates with Google and the provider payload is sent', (tester) async {
        when(() => repo.authMethods()).thenAnswer((_) async => const DeletionAuthMethods(hasPassword: false, authProvider: 'google'));
        final social = MockSocial();
        when(() => social.signInWithGoogle()).thenAnswer((_) async => googleId);
        when(() => repo.requestDeletion(reauth: any(named: 'reauth'))).thenAnswer((_) async => (outcome: DeletionOutcome.wrongIdentity, scheduledFor: null, message: null));
        await tester.pumpWidget(app(social: social));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deletePassword')), findsNothing);
        FilledButton btn() => tester.widget<FilledButton>(find.byKey(const Key('deleteWithProvider')));
        expect(btn().onPressed, isNull); // confirmation first
        await tester.ensureVisible(find.byKey(const Key('deleteConfirm')));
        await tester.tap(find.byKey(const Key('deleteConfirm')));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('deleteWithProvider')));
        await tester.tap(find.byKey(const Key('deleteWithProvider')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
        final sent = verify(() => repo.requestDeletion(reauth: captureAny(named: 'reauth'))).captured.single as SocialLoginModel;
        expect((sent.authProvider, sent.socialId, sent.token), ('google', 'g-1', 'tok-g'));
        expect(find.textContaining('does not match this owner account', skipOffstage: false), findsWidgets);
      });

      testWidgets('Apple owner uses Apple (on iOS only)', (tester) async {
        when(() => repo.authMethods()).thenAnswer((_) async => const DeletionAuthMethods(hasPassword: false, authProvider: 'apple'));
        final social = MockSocial();
        when(() => social.signInWithApple()).thenAnswer((_) async => appleId);
        await tester.pumpWidget(app(social: social));
        await tester.pumpAndSettle();
        if (SocialAuthService.appleSupported) {
          expect(find.textContaining('with Apple and delete'), findsOneWidget);
        } else {
          expect(find.byKey(const Key('deleteWithProvider')), findsNothing);
          expect(find.textContaining('only available on iPhone'), findsOneWidget);
        }
      });

      testWidgets('cancelled provider sign-in deletes nothing', (tester) async {
        when(() => repo.authMethods()).thenAnswer((_) async => const DeletionAuthMethods(hasPassword: false, authProvider: 'google'));
        final social = MockSocial();
        when(() => social.signInWithGoogle()).thenAnswer((_) async => null);
        await tester.pumpWidget(app(social: social));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('deleteConfirm')));
        await tester.tap(find.byKey(const Key('deleteConfirm')));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('deleteWithProvider')));
        await tester.tap(find.byKey(const Key('deleteWithProvider')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
        verifyNever(() => repo.requestDeletion(reauth: any(named: 'reauth')));
        expect(find.textContaining('Nothing was deleted', skipOffstage: false), findsWidgets);
      });

      testWidgets('password + Google owner sees both ways', (tester) async {
        when(() => repo.authMethods()).thenAnswer((_) async => const DeletionAuthMethods(hasPassword: true, authProvider: 'google'));
        await tester.pumpWidget(app(social: MockSocial()));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deletePassword')), findsOneWidget);
        expect(find.byKey(const Key('deleteWithProvider'), skipOffstage: false), findsOneWidget);
      });
    });
  });

  group('native store configuration (static)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    test('Android: minimal permissions, BT scan never for location, backup excluded, no cleartext', () {
      final perms = RegExp(r'uses-permission android:name="([^"]+)"(?![^>]*tools:node="remove")').allMatches(manifest).map((m) => m.group(1)!.split('.').last).toSet();
      expect(perms, {'INTERNET', 'ACCESS_NETWORK_STATE', 'CAMERA', 'BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT', 'BLUETOOTH', 'BLUETOOTH_ADMIN', 'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION'});
      expect(manifest, contains('neverForLocation'));
      for (final legacy in ['android.permission.BLUETOOTH"', 'BLUETOOTH_ADMIN"', 'ACCESS_FINE_LOCATION"', 'ACCESS_COARSE_LOCATION"']) {
        expect(RegExp('${RegExp.escape(legacy)}[^>]*maxSdkVersion="30"').hasMatch(manifest), isTrue, reason: legacy);
      }
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(manifest, contains('@xml/data_extraction_rules'));
      expect(manifest, contains('@xml/backup_rules'));
      for (final f in ['backup_rules.xml', 'data_extraction_rules.xml']) {
        final x = File('android/app/src/main/res/xml/$f').readAsStringSync();
        for (final d in ['database', 'sharedpref', 'file']) {
          expect(x, contains('domain="$d"'));
        }
      }
    });

    test('Android: R8 on, proguard rules, targets API 36, release signing fails clearly, secrets git-ignored', () {
      expect(gradle, contains('isMinifyEnabled = true'));
      expect(gradle, contains('isShrinkResources = true'));
      expect(gradle, contains('proguard-rules.pro'));
      expect(gradle, contains('targetSdk = 36'));
      expect(gradle, contains('compileSdk = 36'));
      expect(gradle, contains('android/key.properties is missing'));
      final rules = File('android/app/proguard-rules.pro').readAsStringSync();
      for (final k in ['sqflite', 'fluttersecurestorage', 'print_bluetooth_thermal', 'mobile_scanner', 'firebase']) {
        expect(rules, contains(k));
      }
      final ignore = File('android/.gitignore').readAsStringSync();
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('*.keystore'));
      expect(ignore, contains('*.jks'));
    });

    test('iOS: usage strings for every used permission, export-compliance key, privacy manifest in the target', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      for (final k in ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription', 'NSBluetoothAlwaysUsageDescription', 'NSLocalNetworkUsageDescription', 'ITSAppUsesNonExemptEncryption']) {
        expect(plist, contains(k));
      }
      expect(plist, contains('Solvexo POS'));
      expect(plist, isNot(contains('NSLocation')));
      expect(plist, isNot(contains('NSMicrophone')));
      final priv = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
      expect(priv, contains('NSPrivacyTracking'));
      expect(priv, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
      expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(), contains('PrivacyInfo.xcprivacy in Resources'));
    });

    test('unused picker plugin removed, crash reporting present', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('file_picker'), isFalse);
      expect(pubspec, contains('firebase_crashlytics'));
    });
  });
}
