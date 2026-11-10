import 'package:solvexo_pos/app/modules/pos_reports/controllers/pulse_controller.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:solvexo_pos/app/components/network_status_banner.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/config/app_brand.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/config/debug_launch_params.dart';
import 'package:solvexo_pos/config/telemetry.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/pos_lock_overlay.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/network/dio_service.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/firebase_options.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

void main() {
  // Release builds: no print()/debugPrint output (it can carry request data) and every uncaught error goes to Crashlytics, scrubbed.
  runZonedGuarded(
    () => _bootstrap(),
    (error, stack) => Telemetry.record(error, stack, fatal: true),
    zoneSpecification: kReleaseMode ? ZoneSpecification(print: (self, parent, zone, line) {}) : null,
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerDesignFontLicenses();
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};

  // A release build never starts against a missing, non-https or local backend.
  final envProblem = AppEnv.validate(release: kReleaseMode);
  if (envProblem != null) {
    runApp(_ConfigErrorApp(message: envProblem));
    return;
  }

  DioService.onForceLogout = () {
    if (Get.currentRoute != Routes.posLogin) {
      Get.offAllNamed(Routes.posLogin);
    }
  };

  DioService.onDeviceRevoked = (code) async {
    if (Get.isRegistered<PosDeviceService>()) await Get.find<PosDeviceService>().handleRevoked(code);
    if (Get.currentRoute != Routes.posLogin) Get.offAllNamed(Routes.posLogin);
  };

  DioService.onLegacyAuthDisabled = () {
    if (Get.currentRoute != Routes.posDeviceSetup && !AppPreferences.cachedDeviceMode) Get.toNamed(Routes.posDeviceSetup);
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Telemetry.init();
  Telemetry.installHandlers();

  await SharedPreferences.getInstance();
  await DebugLaunchParams.seed(); // debug builds only; no-op unless a SEED= launch parameter is set
  // Warms AppPreferences' sync in-memory cache so PosAccessMiddleware can
  // guard routes without an async gap — see AppPreferences.warmCache().
  await AppPreferences.warmCache();
  // Last-known store currency, so amounts render in the right currency/decimals before settings load.
  final cachedCurrency = await AppPreferences.getStoreCurrency();
  Money.configure(currency: cachedCurrency.code, exponent: cachedCurrency.exponent);
  // Re-verifies the cached role against a fresh server call rather than
  // trusting it indefinitely (Phase 4) — fired in the background, same
  // non-blocking pattern as the other background refreshes,
  // rather than delaying boot on a network round-trip. Only worth calling
  // if a session already exists; a fresh install has no token to check.
  // (A registered device's token can't read the account profile — and its role was set locally at registration.)
  if ((AppPreferences.cachedToken ?? '').isNotEmpty && !AppPreferences.cachedDeviceMode) {
    unawaited(
      AuthRepository().getProfile().then((role) {
        if (role != null && role.isNotEmpty) AppPreferences.setUserRole(role);
      }),
    );
  }
  await Get.put(NetworkStatusService(), permanent: true).init();
  // Must come after NetworkStatusService — it looks that up in its own
  // init() to listen for reconnects and drain the offline sale queue.
  await Get.put(PendingSaleSyncService(hasCredentials: () => (AppPreferences.cachedToken ?? '').isNotEmpty), permanent: true).init();
  // G3.5: the separate offline queue of cash in / out, drawer expenses and receipt photos (the sale queue above is untouched).
  await Get.put(PendingCashSyncService(hasCredentials: () => (AppPreferences.cachedToken ?? '').isNotEmpty), permanent: true).init();
  // G3.6: the offline queue of clock events and the clock controller shared by the clock screen, the Home card and the hub badge.
  await Get.put(PendingTeamSyncService(hasCredentials: () => (AppPreferences.cachedToken ?? '').isNotEmpty), permanent: true).init();
  Get.put(TeamClockController(), permanent: true);
  // G4.0: the business pulse shared by the pulse screen and the manager's Home card (it asks nothing until a manager opens Home).
  Get.put(BusinessPulseController(), permanent: true);
  Get.put(PosEntitlementService(), permanent: true);
  Get.put(
    PosDeviceService(
      unresolvedSales: () async => Get.find<PendingSaleSyncService>().unresolvedCount.value,
      onRegistered: () => Get.find<PendingSaleSyncService>().syncNow(ignoreBackoff: true),
    ),
    permanent: true,
  );
  Get.put(IdleLockService(), permanent: true);
  await Get.put(ThermalPrinterService(), permanent: true).init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveSizer(
      builder: (context, orientation, screenType) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: AppBrand.posName,
          // "Ink & Ember" theme. Locked to light for now: un-migrated screens
          // hard-code light colours and would be unreadable under a dark theme.
          // Dark switches on per migrated screen / at the Phase 5 parity pass.
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: DebugLaunchParams.themeMode, // light unless a debug THEME=dark launch parameter says otherwise
          initialRoute: AppPages.initialRoute,
          getPages: AppPages.routes,
          // Clamp OS accessibility text scaling so extreme settings can't
          // compound with CustomText's device-pixel-ratio-driven `.sp` and
          // blow out hand-fit layouts — same clamp as the buyer app.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(
                  mq.textScaler.scale(1).clamp(0.9, 1.2),
                ),
              ),
              // Status-bar icons and clock follow the theme on EVERY screen (dark icons on the light surfaces, light icons on dark) —
              // without this, screens with no AppBar left a white clock on the cream background. An always-dark screen (InkScope with
              // lightStatusBar) sets its own, closer region and wins.
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
                child: DebugLaunchParams.wrapLandscape(context, PosLockOverlay(child: NetworkStatusBanner(child: child!))),
              ),
            );
          },
        );
      },
    );
  }
}

/// Shown instead of the app when the build's environment configuration is unacceptable (see AppEnv.validate).
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Build configuration error\n\n$message', textAlign: TextAlign.center)))),
      );
}
