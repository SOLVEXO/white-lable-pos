import 'dart:async';
import 'package:solvexo_pos/app/components/network_status_banner.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/config/app_brand.dart';
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
import 'package:get/get.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  await SharedPreferences.getInstance();
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
              child: PosLockOverlay(child: NetworkStatusBanner(child: child!)),
            );
          },
        );
      },
    );
  }
}
