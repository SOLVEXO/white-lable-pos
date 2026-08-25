import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:solvexo_pos/app/network/dio_service.dart';
import 'package:solvexo_pos/firebase_options.dart';
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

  // Own copy of the buyer app's Firebase project config for now — see
  // firebase_options.dart / the native-registration follow-up noted there.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await SharedPreferences.getInstance();
  // Loads any cached branding instantly, then refreshes from the backend in
  // the background; see BrandingService's doc comment.
  await Get.put(BrandingService(), permanent: true).init();

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
              child: child!,
            );
          },
        );
      },
    );
  }
}
