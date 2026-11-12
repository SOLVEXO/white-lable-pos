// G5.4: card on a separate bank terminal (approval code / last 4 / terminal on the payment line when the store's switch is on) and the owner's
// Payments setup screen (Raast verification status, test-mode badge, on / off, error states; card terminal switch; card gateway "not available").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_payments_setup/controllers/pos_payments_setup_controller.dart';
import 'package:solvexo_pos/app/modules/pos_payments_setup/views/pos_payments_setup_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

class _Repo extends Mock implements PosRepository {}

ConnectorsStatus _status({bool terminal = false, String kyb = 'verified', bool enabled = true, bool disabledByStore = false, String? reason, bool testMode = true}) => ConnectorsStatus.fromJson({
      'flags': {'cardExternalTerminal': terminal, 'raastDisabled': disabledByStore},
      'cardGateway': {'provider': 'mock', 'testMode': true, 'configured': true},
      'fiscal': {'provider': null, 'testMode': false, 'configured': false},
      'raast': {'kybStatus': kyb, 'enabled': enabled, 'reason': reason, 'providerKey': 'mock', 'testMode': testMode, 'disabledByStore': disabledByStore},
    });

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });

  group('payment lines', () {
    late _Repo repo;
    late PosHomeController c;
    setUp(() {
      SoundUtil.enabled = false;
      SharedPreferences.setMockInitialValues({'pos_sound_effects': false});
      repo = _Repo();
      c = PosHomeController(posRepository: repo);
      c.storeId.value = 'store-1';
      final p = PosProductModel(productId: 'a', name: 'A', type: 'physical', categoryId: 'c', variants: [PosProductVariant(variantId: 'a1', sku: 'A1', price: 10, stock: 5, isDefault: true)]);
      c.cartItems.add(CartItem(product: p, variant: p.defaultVariant, qty: 1));
      c.selectedPayment.value = PosPaymentMethod.card;
    });

    test('switch off: a card sale sends no terminal fields (unchanged)', () {
      expect(c.paymentLinesForTest(), isNull);
      expect(c.cardApprovalMissing, isFalse);
    });

    test('switch on: the line carries approval code, last 4 and terminal; missing code is flagged', () {
      c.cardExternalTerminal.value = true;
      expect(c.cardApprovalMissing, isTrue);
      c.cardApprovalController.text = ' A1B2C3 ';
      c.cardLast4Controller.text = '4242';
      c.cardTerminalController.text = 'HBL #1';
      final l = c.paymentLinesForTest()!.single;
      expect(l, {'method': 'card', 'amount': c.total, 'approvalCode': 'A1B2C3', 'last4': '4242', 'terminalLabel': 'HBL #1'});
      expect(c.cardApprovalMissing, isFalse);
    });

    test('split: the card row reference is the approval code', () {
      c.cardExternalTerminal.value = true;
      c.isSplitPayment.value = true;
      c.splitLines.add(SplitPaymentLine(PosPaymentMethod.card)..amount.text = '10'..reference.text = 'Z9');
      expect(c.paymentLinesForTest()!.single, containsPair('approvalCode', 'Z9'));
    });
  });

  group('Payments setup', () {
    late _Repo repo;
    setUp(() => repo = _Repo());
    Future<PosPaymentsSetupController> pump(WidgetTester t) async {
      final c = PosPaymentsSetupController(repo: repo, storeId: 'st1');
      final loaded = c.load();
      await t.binding.setSurfaceSize(const Size(430, 1200));
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: PosPaymentsSetupView(key: UniqueKey(), controller: c))));
      await t.runAsync(() => loaded);
      await t.pump(const Duration(milliseconds: 200));
      return c;
    }

    testWidgets('verified + test mode: badges, Raast switch on; turning it off writes raastDisabled=true', (t) async {
      when(() => repo.getConnectors('st1')).thenAnswer((_) async => _status());
      when(() => repo.setConnectors('st1', any())).thenAnswer((_) async => (success: true, code: null, message: null));
      await pump(t);
      expect(find.byKey(const Key('raastTestMode')), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      await t.tap(find.byKey(const Key('raastSwitch')));
      await t.pump(const Duration(milliseconds: 200));
      verify(() => repo.setConnectors('st1', {'raastDisabled': true})).called(1);
    });

    testWidgets('not verified: no switch, a link to business verification instead', (t) async {
      when(() => repo.getConnectors('st1')).thenAnswer((_) async => _status(kyb: 'under_review', enabled: false, reason: 'kyb_under_review'));
      await pump(t);
      expect(find.byKey(const Key('raastSwitch')), findsNothing);
      expect(find.byKey(const Key('raastVerify')), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
    });

    testWidgets('card terminal switch; a refusal is shown in place', (t) async {
      when(() => repo.getConnectors('st1')).thenAnswer((_) async => _status());
      when(() => repo.setConnectors('st1', any())).thenAnswer((_) async => (success: false, code: 'OWNER_REQUIRED', message: 'no'));
      await pump(t);
      await t.tap(find.byKey(const Key('cardTerminalSwitch')));
      await t.pump(const Duration(milliseconds: 200));
      verify(() => repo.setConnectors('st1', {'cardExternalTerminal': true})).called(1);
      expect(find.byKey(const Key('paySetupSaveError')), findsOneWidget);
    });

    testWidgets('load failure: error + reload', (t) async {
      when(() => repo.getConnectors('st1')).thenAnswer((_) async => null);
      await pump(t);
      expect(find.byKey(const Key('paySetupError')), findsOneWidget);
      expect(find.byKey(const Key('paySetupReload')), findsOneWidget);
    });
  });
}
