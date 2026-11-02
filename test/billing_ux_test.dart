// 5E — the app only READS the POS plan entitlement: no purchase path, neutral inactive screen, read-only status, expiry banner.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/modules/pos_plan/views/plan_expiry_banner.dart';
import 'package:solvexo_pos/app/modules/pos_plan/views/pos_plan_inactive_view.dart';
import 'package:solvexo_pos/app/modules/pos_plan/views/pos_plan_status_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/app_brand.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';

class MockSubRepo extends Mock implements PosSubscriptionRepository {}

PosSubscriptionStatusModel _active(int days, {bool enforced = true}) => PosSubscriptionStatusModel(
      status: PosSubscriptionStatusValue.active,
      enforced: enforced,
      planName: 'Pro 30',
      purchasedAt: DateTime(2026, 1, 1),
      expiresAt: DateTime.now().add(Duration(days: days)),
      daysRemaining: days,
    );

Widget _app(Widget home) => ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(
      home: home,
      getPages: [GetPage(name: Routes.posPinLogin, page: () => const Scaffold(body: Text('PIN SCREEN')))],
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.reset();
    SharedPreferences.setMockInitialValues({'store_id': 's1', 'pos_sound_effects': false});
  });

  group('no purchase surface left in the app', () {
    test('source contains no plan list, checkout, Stripe or WebView code', () {
      final banned = ['checkout-session', 'createCheckoutSession', 'webview_flutter', 'WebViewController', 'pos-plans', 'getPlans', 'PosPlanModel', 'Paywall'];
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        for (final b in banned) {
          if (text.contains(b)) hits.add('${f.path}: $b');
        }
      }
      expect(hits, isEmpty);
      expect(File('pubspec.yaml').readAsStringSync().contains('webview_flutter'), isFalse);
    });

    test('Solvexo POS is one fixed brand (no fetched/white-label config)', () {
      expect(AppBrand.posName, 'Solvexo POS');
      expect(AppColors.primaryColor, AppBrand.primary);
      expect(Directory('lib').listSync(recursive: true).whereType<File>().any((f) => f.path.contains('branding')), isFalse);
      expect(File('lib/app/network/api_constaints.dart').readAsStringSync().contains('branding/config'), isFalse);
    });
  });

  group('expiry banner (owner, informational)', () {
    test('shows only for an ACTIVE plan with 7 days or fewer left', () {
      expect(PlanExpiryBanner.shouldShow(_active(7)), isTrue);
      expect(PlanExpiryBanner.shouldShow(_active(1)), isTrue);
      expect(PlanExpiryBanner.shouldShow(_active(8)), isFalse);
      expect(PlanExpiryBanner.shouldShow(null), isFalse);
      expect(PlanExpiryBanner.shouldShow(const PosSubscriptionStatusModel(status: PosSubscriptionStatusValue.expired)), isFalse);
      expect(PlanExpiryBanner.shouldShow(PosSubscriptionStatusModel.unknown()), isFalse);
    });

    testWidgets('says when access ends — with no price, no link, no button', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlanExpiryBanner(status: _active(5)))));
      expect(find.byKey(const Key('planExpiryBanner')), findsOneWidget);
      expect(find.textContaining('5 days left'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.textContaining(RegExp(r'[\$€£]|buy|renew|upgrade|purchase', caseSensitive: false)), findsNothing);
    });

    testWidgets('renders nothing when there is nothing to warn about', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlanExpiryBanner(status: _active(30)))));
      expect(find.byKey(const Key('planExpiryBanner')), findsNothing);
    });
  });

  group('plan not active screen', () {
    testWidgets('is neutral: message, Refresh and Sign out only', (tester) async {
      await tester.pumpWidget(_app(PosPlanInactiveView(repository: MockSubRepo())));
      expect(find.text("POS plan isn't active for this store"), findsOneWidget);
      expect(find.byKey(const Key('planInactiveRefresh')), findsOneWidget);
      expect(find.byKey(const Key('planInactiveSignOut')), findsOneWidget);
      expect(find.textContaining(RegExp(r'[\$€£]|buy|renew|upgrade|purchase|http|www', caseSensitive: false)), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('Refresh: still inactive → stays with a note; backend unreachable → says so', (tester) async {
      final repo = MockSubRepo();
      when(() => repo.getStatus('s1')).thenAnswer((_) async => const PosSubscriptionStatusModel(status: PosSubscriptionStatusValue.expired, enforced: true));
      await tester.pumpWidget(_app(PosPlanInactiveView(repository: repo)));
      await tester.tap(find.byKey(const Key('planInactiveRefresh')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text("The plan still isn't active."), findsOneWidget);

      when(() => repo.getStatus('s1')).thenAnswer((_) async => PosSubscriptionStatusModel.unknown());
      await tester.tap(find.byKey(const Key('planInactiveRefresh')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.textContaining("Couldn't check"), findsOneWidget);
    });

    testWidgets('Refresh: once the plan is active (or the backend is not enforcing) the app moves on to PIN login', (tester) async {
      final repo = MockSubRepo();
      when(() => repo.getStatus('s1')).thenAnswer((_) async => _active(20));
      await tester.pumpWidget(_app(PosPlanInactiveView(repository: repo)));
      await tester.tap(find.byKey(const Key('planInactiveRefresh')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('PIN SCREEN'), findsOneWidget);
    });
  });

  group('owner plan status screen (read-only)', () {
    testWidgets('shows plan name, state and expiry date; offers nothing but Refresh', (tester) async {
      final repo = MockSubRepo();
      when(() => repo.getStatus('s1')).thenAnswer((_) async => _active(5));
      await tester.pumpWidget(_app(PosPlanStatusView(repository: repo)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('Pro 30'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Expires'), findsOneWidget);
      expect(find.byKey(const Key('planExpiryBanner')), findsOneWidget); // 5 days left
      expect(find.textContaining(RegExp(r'[\$€£]|buy|renew|upgrade|purchase', caseSensitive: false)), findsNothing);
    });

    testWidgets('an expired plan reads "Expired" and shows no banner', (tester) async {
      final repo = MockSubRepo();
      when(() => repo.getStatus('s1')).thenAnswer((_) async => PosSubscriptionStatusModel(status: PosSubscriptionStatusValue.expired, planName: 'Pro 30', expiresAt: DateTime(2026, 1, 1)));
      await tester.pumpWidget(_app(PosPlanStatusView(repository: repo)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('Expired'), findsOneWidget);
      expect(find.byKey(const Key('planExpiryBanner')), findsNothing);
    });
  });
}
