import 'dart:async';
import 'package:solvexo_pos/app/components/network_status_banner.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/network/dio_service.dart';
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

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await SharedPreferences.getInstance();
  // Warms AppPreferences' sync in-memory cache so PosAccessMiddleware can
  // guard routes without an async gap — see AppPreferences.warmCache().
  await AppPreferences.warmCache();
  // Re-verifies the cached role against a fresh server call rather than
  // trusting it indefinitely (Phase 4) — fired in the background, same
  // non-blocking pattern as BrandingService.refreshFromBackend below,
  // rather than delaying boot on a network round-trip. Only worth calling
  // if a session already exists; a fresh install has no token to check.
  if ((AppPreferences.cachedToken ?? '').isNotEmpty) {
    unawaited(
      AuthRepository().getProfile().then((role) {
        if (role != null && role.isNotEmpty) AppPreferences.setUserRole(role);
      }),
    );
  }
  // Loads any cached branding instantly, then refreshes from the backend in
  // the background; see BrandingService's doc comment.
  await Get.put(BrandingService(), permanent: true).init();
  await Get.put(NetworkStatusService(), permanent: true).init();
  // Must come after NetworkStatusService — it looks that up in its own
  // init() to listen for reconnects and drain the offline sale queue.
  await Get.put(PendingSaleSyncService(), permanent: true).init();
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
          title: '${Get.find<BrandingService>().config.value.appName} POS',
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
              child: NetworkStatusBanner(child: child!),
            );
          },
        );
      },
    );
  }
}
