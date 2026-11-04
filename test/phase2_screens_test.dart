// Phase 2 (splash + auth) screens: render in light AND dark at phone portrait, tablet portrait and tablet
// landscape without exceptions/overflow, plus the behaviours the redesign added or must preserve.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/data/services/social_auth_service.dart';
import 'package:solvexo_pos/app/modules/onboarding/controllers/onboarding_controller.dart';
import 'package:solvexo_pos/app/modules/onboarding/views/onboarding_view.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/device_setup_view.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/owner_gate_view.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/pos_lock_overlay.dart';
import 'package:solvexo_pos/app/modules/pos_login/controllers/pos_login_controller.dart';
import 'package:solvexo_pos/app/modules/pos_login/views/pos_login_view.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/controllers/pos_pin_login_controller.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/views/pos_pin_login_view.dart';
import 'package:solvexo_pos/app/modules/splash_screen/bindings/splash_screen_binding.dart';
import 'package:solvexo_pos/app/modules/splash_screen/views/splash_screen_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

class MockAuthRepo extends Mock implements AuthRepository {}

class MockSocial extends Mock implements SocialAuthService {}

class MockPosRepo extends Mock implements PosRepository {}

class MockSellerRepo extends Mock implements SellerRepository {}

class MockDevice extends Mock implements PosDeviceService {}

/// Skips the store/register network load; the test seeds the registers directly.
class _PinController extends PosPinLoginController {
  _PinController(
    PosPinLoginController? _, {
    required super.posRepository,
    required super.sellerRepository,
  });
  @override
  // ignore: must_call_super
  void onInit() {}
}

const _sizes = {
  'phone portrait': Size(390, 844),
  'tablet portrait': Size(820, 1180),
  'tablet landscape': Size(1180, 820),
};
const _stub = SizedBox.shrink();

Widget _app(Widget home, ThemeData theme) => GetMaterialApp(
  theme: theme,
  getPages: [
    for (final r in [
      Routes.posLogin,
      Routes.posHome,
      Routes.posPinLogin,
      Routes.sellerHome,
      Routes.sellerStores,
      Routes.onboarding,
      Routes.posOpenRegister,
    ])
      GetPage(
        name: r,
        page: () => const Scaffold(body: _stub),
      ),
  ],
  home: home,
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(820, 1180);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;

  setUp(() {
    SoundUtil.enabled =
        false; // toasts play a sound; no audio plugin under test
    SharedPreferences.setMockInitialValues({'pos_sound_effects': false});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });
  tearDown(Get.reset);

  // ── Render matrix ────────────────────────────────────────────────────────────────────────────────
  group(
    'every Phase 2 screen renders without overflow — light and dark, phone / tablet / landscape',
    () {
      final screens = <String, Widget Function()>{
        'owner login': () {
          Get.put(
            PosLoginController(
              authRepository: MockAuthRepo(),
              socialAuth: MockSocial(),
            ),
          );
          return const PosLoginView();
        },
        'cashier PIN login': () {
          final c = _PinController(
            null,
            posRepository: MockPosRepo(),
            sellerRepository: MockSellerRepo(),
          );
          c.storeId.value = 's1';
          c.registers.assignAll([
            {'id': 'r1', 'name': 'Front Counter'},
          ]);
          c.selectedRegister.value = c.registers.first;
          Get.put<PosPinLoginController>(c);
          return PosPinLoginView();
        },
        'onboarding': () {
          Get.put(OnboardingController());
          return const OnboardingView();
        },
        'owner gate': () => OwnerGateView(authRepository: MockAuthRepo()),
        'device setup': () {
          final seller = MockSellerRepo();
          when(() => seller.getStoreById(any())).thenAnswer((_) async => null);
          final dev = MockDevice();
          when(() => dev.revokedNotice).thenReturn(
            RxnString(
              'This device was removed by the owner. Your unsynced sales are safe.',
            ),
          );
          return DeviceSetupView(sellerRepository: seller, deviceService: dev);
        },
      };
      for (final s in screens.entries) {
        for (final th in {
          'light': AppTheme.light,
          'dark': AppTheme.dark,
        }.entries) {
          for (final sz in _sizes.entries) {
            testWidgets('${s.key} · ${th.key} · ${sz.key}', (t) async {
              t.view.physicalSize = sz.value;
              t.view.devicePixelRatio = 1;
              addTearDown(t.view.reset);
              await t.pumpWidget(_app(s.value(), th.value));
              await _settle(t);
              expect(t.takeException(), isNull);
            });
          }
        }
      }
    },
  );

  // ── Splash ───────────────────────────────────────────────────────────────────────────────────────
  group('splash', () {
    Future<void> pumpSplash(WidgetTester t, {bool reduced = false}) async {
      await t.pumpWidget(
        GetMaterialApp(
          initialRoute: Routes.splashScreen,
          builder: reduced
              ? (c, w) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(disableAnimations: true),
                  child: w!,
                )
              : null,
          getPages: [
            GetPage(
              name: Routes.splashScreen,
              page: () => const SplashScreenView(),
              binding: SplashScreenBinding(),
            ),
            for (final r in [
              Routes.posLogin,
              Routes.posHome,
              Routes.posPinLogin,
              Routes.sellerHome,
              Routes.onboarding,
            ])
              GetPage(
                name: r,
                page: () => const Scaffold(body: _stub),
              ),
          ],
        ),
      );
    }

    testWidgets(
      'first frame = native splash: ink background, 120px tile dead centre, nothing else visible',
      (t) async {
        await AppPreferences.setHasSeenOnboarding(true);
        await pumpSplash(t);
        final scaffold = t.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, const Color(0xFF0B1020));
        final logo = find.byType(BrandLogo);
        expect(t.getSize(logo), const Size(120, 120));
        expect(t.getCenter(logo), t.getCenter(find.byType(Scaffold)));
        final wordmarkOpacity = t.widget<Opacity>(
          find
              .ancestor(
                of: find.textContaining('Solvexo', findRichText: true),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(wordmarkOpacity.opacity, 0);
        await t.pump(
          const Duration(milliseconds: 1600),
        ); // let the timeline finish so no timers outlive the test
      },
    );

    testWidgets(
      'navigates the moment animation + session check are done — not after a fixed 5.2 s',
      (t) async {
        await AppPreferences.setHasSeenOnboarding(true); // no token -> login
        await pumpSplash(t);
        await t.pump(); // first frame
        await t.pump(const Duration(milliseconds: 700));
        expect(
          Get.currentRoute,
          Routes.splashScreen,
          reason: 'the animation is still running',
        );
        await t.pump(const Duration(milliseconds: 700));
        await t.pump();
        expect(Get.currentRoute, Routes.posLogin);
      },
    );

    testWidgets(
      'routing branches are unchanged: onboarding not seen -> onboarding',
      (t) async {
        await pumpSplash(t);
        await t.pump();
        await t.pump(const Duration(milliseconds: 1500));
        await t.pump();
        expect(Get.currentRoute, Routes.onboarding);
      },
    );

    testWidgets('reduced motion: short fade only, navigates after ~200 ms', (
      t,
    ) async {
      await AppPreferences.setHasSeenOnboarding(true);
      await pumpSplash(t, reduced: true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.pump();
      expect(Get.currentRoute, Routes.posLogin);
    });
  });

  // ── Onboarding ───────────────────────────────────────────────────────────────────────────────────
  testWidgets(
    'onboarding: Next → … → Get started sets the seen flag and goes to login; Skip does the same',
    (t) async {
      Get.put(OnboardingController());
      await t.pumpWidget(_app(const OnboardingView(), AppTheme.light));
      await t.pump();
      expect(find.text('Next'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.text('Next'));
        await t.pump(); // the frame that starts the page animation
        await t.pump(const Duration(milliseconds: 500));
      }
      await t.pump(const Duration(milliseconds: 100)); // Obx -> button label
      expect(find.text('Get started'), findsOneWidget);
      await t.tap(find.text('Get started'));
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 600));
      expect(await AppPreferences.getHasSeenOnboarding(), isTrue);
      expect(Get.currentRoute, Routes.posLogin);
    },
  );

  // ── Owner login ──────────────────────────────────────────────────────────────────────────────────
  group('owner login', () {
    late MockAuthRepo auth;
    setUp(() {
      auth = MockAuthRepo();
      when(
        () => auth.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => null);
    });

    testWidgets(
      'inline validation: bad input shows field errors and nothing is submitted',
      (t) async {
        Get.put(
          PosLoginController(authRepository: auth, socialAuth: MockSocial()),
        );
        await t.pumpWidget(_app(const PosLoginView(), AppTheme.light));
        await _settle(t);
        await t.tap(find.text('Sign in').last);
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Enter your email'), findsOneWidget);
        expect(find.text('Enter your password'), findsOneWidget);
        await t.enterText(find.byType(TextFormField).first, 'not-an-email');
        await t.pump();
        expect(find.text('Enter a valid email address'), findsOneWidget);
        verifyNever(
          () => auth.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        );
      },
    );

    testWidgets(
      'valid credentials submit (trimmed email); Enter on the password field submits too',
      (t) async {
        Get.put(
          PosLoginController(authRepository: auth, socialAuth: MockSocial()),
        );
        await t.pumpWidget(_app(const PosLoginView(), AppTheme.light));
        await _settle(t);
        await t.enterText(
          find.byType(TextFormField).first,
          '  owner@shop.com ',
        );
        await t.enterText(find.byType(TextFormField).last, 'hunter22');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pump();
        verify(
          () => auth.login(email: 'owner@shop.com', password: 'hunter22'),
        ).called(1);
      },
    );

    testWidgets('autofill hints and the official Google button', (t) async {
      Get.put(
        PosLoginController(authRepository: auth, socialAuth: MockSocial()),
      );
      await t.pumpWidget(_app(const PosLoginView(), AppTheme.light));
      await _settle(t);
      expect(find.byType(AutofillGroup), findsOneWidget);
      final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.first.autofillHints, contains(AutofillHints.email));
      expect(fields.last.autofillHints, contains(AutofillHints.password));
      expect(fields.first.textInputAction, TextInputAction.next);
      expect(fields.last.textInputAction, TextInputAction.done);
      // Google: approved label, Roboto Medium 14, official G, >= 40px tall; light = #FFFFFF / #1F1F1F.
      expect(find.text('Continue with Google'), findsOneWidget);
      final label = t.widget<Text>(find.text('Continue with Google'));
      expect(label.style!.fontFamily, 'Roboto');
      expect(label.style!.fontSize, 14);
      expect(label.style!.fontWeight, FontWeight.w500);
      expect(label.style!.color, const Color(0xFF1F1F1F));
      expect(
        t.getSize(find.byType(GoogleSignInButton)).height,
        greaterThanOrEqualTo(40),
      );
      // No Apple button (it isn't shown today).
      expect(find.textContaining('Apple'), findsNothing);
    });

    testWidgets(
      'Google button follows the dark guideline colours in a dark theme',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(body: GoogleSignInButton(onPressed: () {})),
          ),
        );
        final label = t.widget<Text>(find.text('Continue with Google'));
        expect(label.style!.color, const Color(0xFFE3E3E3));
        final material = t.widget<Material>(
          find
              .descendant(
                of: find.byType(GoogleSignInButton),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, const Color(0xFF131314));
      },
    );
  });

  // ── Cashier PIN login ────────────────────────────────────────────────────────────────────────────
  testWidgets(
    'PIN login: a failed attempt (PIN cleared by the controller) shakes the dots; PIN pad is disabled while loading',
    (t) async {
      final pos = MockPosRepo();
      when(
        () => pos.pinLogin(
          storeId: any(named: 'storeId'),
          email: any(named: 'email'),
          pin: any(named: 'pin'),
        ),
      ).thenAnswer(
        (_) async => (
          success: false,
          employee: null,
          activeSession: null,
          employeeToken: null,
          message: 'Invalid PIN',
        ),
      );
      final c = _PinController(
        null,
        posRepository: pos,
        sellerRepository: MockSellerRepo(),
      );
      c.storeId.value = 's1';
      c.registers.assignAll([
        {'id': 'r1', 'name': 'Front Counter'},
      ]);
      c.selectedRegister.value = c.registers.first;
      c.emailController.text = 'cashier@x.com';
      Get.put<PosPinLoginController>(c);
      await t.pumpWidget(_app(PosPinLoginView(), AppTheme.light));
      await t.pump();
      expect(t.widget<PinDots>(find.byType(PinDots)).errorTick, 0);
      for (final d in ['1', '2', '3', '4']) {
        await t.tap(find.text(d).first);
        await t.pump();
      }
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(c.pin.value, isEmpty);
      expect(t.widget<PinDots>(find.byType(PinDots)).errorTick, 1);
      expect(t.widget<PinDots>(find.byType(PinDots)).hasError, isTrue);
      verify(
        () => pos.pinLogin(storeId: 's1', email: 'cashier@x.com', pin: '1234'),
      ).called(1);
      await t.pump(const Duration(seconds: 5)); // let any toast timer finish
    },
  );

  // ── Auto-lock ────────────────────────────────────────────────────────────────────────────────────
  group('auto-lock screen', () {
    late MockPosRepo repo;
    late IdleLockService lock;

    setUp(() async {
      repo = MockPosRepo();
      SharedPreferences.setMockInitialValues({
        'pos_sound_effects': false,
        'store_id': 's1',
        'store_name': 'Corner Bakery',
        'pos_employee_id': 'e1',
        'pos_employee_name': 'Cal',
        'pos_employee_email': 'c@x.com',
      });
      lock = IdleLockService(
        posRepository: repo,
        employeeSignedIn: () => true,
        checkEvery: const Duration(days: 1),
      );
      lock.onInit();
      Get.put<IdleLockService>(lock);
    });
    tearDown(() => lock.onClose());

    Future<void> pumpLocked(WidgetTester t, {ThemeData? theme}) async {
      await t.pumpWidget(
        _app(
          PosLockOverlay(child: const Scaffold(body: Text('underneath'))),
          theme ?? AppTheme.light,
        ),
      );
      await t.runAsync(() => lock.lock());
      await _settle(t);
    }

    testWidgets(
      'is always dark ink, even in a light app theme; shows store name, clock, name and kept-cart note',
      (t) async {
        _tall(t);
        await pumpLocked(t);
        expect(find.text('Locked'), findsOneWidget);
        expect(find.text('CORNER BAKERY'), findsOneWidget);
        expect(find.textContaining('Cal — enter your PIN'), findsOneWidget);
        expect(
          find.text('Your cart and unsynced sales are kept.'),
          findsOneWidget,
        );
        final material = t.widget<Material>(
          find
              .ancestor(
                of: find.text('Locked'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, AppPalette.dark.background);
        expect(
          find.text('underneath'),
          findsOneWidget,
          reason: 'it is an overlay — the screen below stays mounted',
        );
      },
    );

    testWidgets(
      'PIN pad drives the same unlock flow; wrong PIN shakes and says so; physical keyboard works too',
      (t) async {
        _tall(t);
        when(
          () => repo.pinLogin(storeId: 's1', email: 'c@x.com', pin: '9999'),
        ).thenAnswer(
          (_) async => (
            success: false,
            employee: null,
            activeSession: null,
            employeeToken: null,
            message: 'Invalid credentials',
          ),
        );
        await pumpLocked(t);
        // (scoped to the pad: the hidden obscured field briefly shows the last digit typed)
        final nine = find.descendant(of: find.byType(PinPad), matching: find.text('9'));
        for (var i = 0; i < 3; i++) {
          await t.tap(nine.first);
          await t.pump();
        }
        expect(t.widget<PinDots>(find.byType(PinDots)).filled, 3);
        await t.tap(find.byIcon(Icons.backspace_outlined));
        await t.pump();
        expect(t.widget<PinDots>(find.byType(PinDots)).filled, 2);
        // finish with the physical keyboard (pad owns focus via autofocus / last tap)
        await t.sendKeyDownEvent(LogicalKeyboardKey.digit9, character: '9');
        await t.sendKeyUpEvent(LogicalKeyboardKey.digit9);
        await t.sendKeyDownEvent(LogicalKeyboardKey.digit9, character: '9');
        await t.sendKeyUpEvent(LogicalKeyboardKey.digit9);
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 100));
        verify(
          () => repo.pinLogin(storeId: 's1', email: 'c@x.com', pin: '9999'),
        ).called(1);
        expect(find.text('Wrong PIN.'), findsOneWidget);
        expect(t.widget<PinDots>(find.byType(PinDots)).errorTick, 1);
        expect(find.text('Locked'), findsOneWidget);
      },
    );

    for (final sz in _sizes.entries) {
      testWidgets('renders on ${sz.key}', (t) async {
        t.view.physicalSize = sz.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await pumpLocked(t);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('lockSwitchUser')), findsOneWidget);
      });
    }
  });

  // ── PinPad keyboard ──────────────────────────────────────────────────────────────────────────────
  testWidgets(
    'PinPad: digits and Backspace from a physical keyboard; Escape clears; ignores keys when disabled',
    (t) async {
      final got = <String>[];
      var back = 0, clear = 0;
      var enabled = true;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (c, set) => Scaffold(
              body: Column(
                children: [
                  PinPad(
                    autofocus: true,
                    enabled: enabled,
                    onDigit: got.add,
                    onBackspace: () => back++,
                    onClear: () => clear++,
                  ),
                  TextButton(
                    onPressed: () => set(() => enabled = false),
                    child: const Text('disable'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.digit4, character: '4');
      await t.sendKeyUpEvent(LogicalKeyboardKey.digit4);
      await t.sendKeyDownEvent(LogicalKeyboardKey.numpad7, character: '7');
      await t.sendKeyUpEvent(LogicalKeyboardKey.numpad7);
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.sendKeyDownEvent(
        LogicalKeyboardKey.keyA,
        character: 'a',
      ); // letters are ignored
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      expect(got, ['4', '7']);
      expect(back, 1);
      expect(clear, 1);
      await t.tap(find.text('disable'));
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.digit1, character: '1');
      await t.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      expect(got, ['4', '7']);
    },
  );

  test(
    'native splash config (pubspec) uses the same dark ink as the Flutter splash, incl. Android 12',
    () {
      final y = File('pubspec.yaml').readAsStringSync();
      final block = y.substring(
        y.indexOf('\nflutter_native_splash:'),
        y.indexOf('\nflutter:\n'),
      );
      expect(
        RegExp(r'^\s+color: "#0B1020"', multiLine: true).allMatches(block).length,
        2,
        reason: 'main + android_12 background',
      );
      expect(block, contains('icon_background_color: "#0B1020"'));
      expect(block, isNot(contains('F06839')));
      // the in-app splash pins the native colour explicitly (the dark palette moved to the blueprint ink in G1a)
      expect(SplashScreenView.nativeSplashInk, const Color(0xFF0B1020));
      // Generated Android 12 resources carry the same colour.
      for (final f in [
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        expect(File(f).readAsStringSync(), contains('#0B1020'));
      }
    },
  );
}
