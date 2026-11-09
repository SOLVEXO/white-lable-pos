// G3.3 customer controllers against a mocked PosRepository: search (debounce, newest wins, offline memory), create / edit
// (validation codes, forbidden, offline, double submit), profile (role differences, offline memory) and the manual credit adjustment.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pos_g3_caches.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/credit_adjust_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_profile_controller.dart';

import 'support/g3_fixtures.dart';

class _MockRepo extends Mock implements PosRepository {}

void main() {
  late _MockRepo repo;
  late CustomerCache cache;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    repo = _MockRepo();
    cache = testCustomerCache();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
  });

  group('CustomerCache', () {
    test('remembers searches and profiles per store, sealed (not readable as plain text), and forgets another store', () async {
      await cache.saveSearch('st1', 'dev', customerPage([customer()]));
      await cache.saveProfile('st1', profile());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pos_customer_cache')!.contains('Dev Customer'), isFalse);
      final page = await cache.loadSearch('st1', 'dev');
      expect(page!.items.single.name, 'Dev Customer');
      expect(page.asOf, isNotNull);
      expect(page.cur, const InvCur('USD', 2));
      expect((await cache.loadProfile('st1', 'c1'))!.asOf, isNotNull);
      expect(await cache.loadSearch('st2', 'dev'), isNull);
    });

    test('a search never made offline is answered from what was remembered, filtered by the typed text', () async {
      await cache.saveSearch('st1', '', customerPage([customer(id: 'a', name: 'Alice'), customer(id: 'b', name: 'Bob', phone: '0311')]));
      final page = await cache.loadSearch('st1', 'bo');
      expect(page!.items.map((c) => c.name), ['Bob']);
    });

    test('caps the searches at 10 and the profiles at 50', () async {
      for (var i = 0; i < 12; i++) {
        await cache.saveSearch('st1', 'q$i', customerPage([customer()]));
      }
      expect(await cache.loadSearch('st1', 'q0'), isNotNull); // filtered fallback still answers
      for (var i = 0; i < 55; i++) {
        await cache.saveProfile('st1', profile(id: 'p$i'));
      }
      expect(await cache.loadProfile('st1', 'p0'), isNull);
      expect(await cache.loadProfile('st1', 'p54'), isNotNull);
    });

    test('a corrupt blob reads as empty', () async {
      SharedPreferences.setMockInitialValues({'pos_customer_cache': 'garbage'});
      expect(await cache.loadSearch('st1', ''), isNull);
    });
  });

  group('CustomerListController', () {
    CustomerListController make({Duration debounce = const Duration(milliseconds: 30)}) => CustomerListController(repository: repo, cache: cache, storeId: 'st1', debounce: debounce);
    Future<void> pause([int ms = 80]) => Future<void>.delayed(Duration(milliseconds: ms));

    test('loads the recent customers on open with the response currency', () async {
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer()]));
      final c = make()..onInit();
      await pause();
      expect(c.items.single.name, 'Dev Customer');
      expect(c.cur.value, const InvCur('USD', 2));
      expect(c.loading.value, isFalse);
      expect(c.asOf.value, isNull);
      c.onClose();
    });

    test('typing is debounced into one search and the NEWEST search wins over a slower older one', () async {
      final slow = Completer<PosCustomerPage?>();
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer(name: 'All')]));
      when(() => repo.searchPosCustomers('st1', 'a')).thenAnswer((_) => slow.future);
      when(() => repo.searchPosCustomers('st1', 'ab')).thenAnswer((_) async => customerPage([customer(name: 'Abby')]));
      final c = make(debounce: const Duration(milliseconds: 20))..onInit();
      await pause();
      c.onQueryChanged('a');
      await pause(40); // search 'a' is now in flight (slow)
      c.onQueryChanged('ab');
      await pause(60);
      expect(c.items.single.name, 'Abby');
      slow.complete(customerPage([customer(name: 'STALE')]));
      await pause(20);
      expect(c.items.single.name, 'Abby');
      verify(() => repo.searchPosCustomers('st1', 'a')).called(1);
      c.onClose();
    });

    test('quick keystrokes become a single request', () async {
      when(() => repo.searchPosCustomers(any(), any())).thenAnswer((_) async => customerPage([customer()]));
      final c = make(debounce: const Duration(milliseconds: 40))..onInit();
      await pause();
      clearInteractions(repo);
      c.onQueryChanged('d');
      c.onQueryChanged('de');
      c.onQueryChanged('dev');
      await pause(120);
      verify(() => repo.searchPosCustomers('st1', 'dev')).called(1);
      verifyNever(() => repo.searchPosCustomers('st1', 'de'));
      c.onClose();
    });

    test('offline (no answer, no code): the remembered results show with an as-of time; nothing remembered gives an honest message', () async {
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer()]));
      var c = make()..onInit();
      await pause();
      c.onClose();
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => null);
      c = make()..onInit();
      await pause();
      expect(c.items.single.name, 'Dev Customer');
      expect(c.asOf.value, isNotNull);
      c.onClose();

      await cache.clear();
      c = make()..onInit();
      await pause();
      expect(c.items, isEmpty);
      expect(c.error.value, contains('No internet'));
      c.onClose();
    });

    test('a refusal from the server (code present) is an error, not a silent cache fallback', () async {
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_PIN_REQUIRED');
      final c = make()..onInit();
      await pause();
      expect(c.error.value, 'Sign in with your PIN first.');
      c.onClose();
    });

    test('a new customer is put on top without a request', () async {
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer(id: 'a')]));
      final c = make()..onInit();
      await pause();
      c.upsert(customer(id: 'n', name: 'New'));
      expect(c.items.map((e) => e.id), ['n', 'a']);
      c.upsert(customer(id: 'a', name: 'Renamed'));
      expect(c.items.map((e) => e.name), ['Renamed', 'New']);
      c.onClose();
    });
  });

  group('CustomerFormController', () {
    CustomerFormController make({PosCustomer? existing}) => CustomerFormController(repository: repo, storeId: 'st1', existing: existing);

    void stubCreate(({bool success, String? message, String? code, PosCustomer? customer}) Function() f) => when(() => repo.createPosCustomer('st1', any())).thenAnswer((_) async => f());
    void stubUpdate(({bool success, String? message, String? code, PosCustomer? customer}) Function() f) => when(() => repo.updatePosCustomer('st1', any(), any())).thenAnswer((_) async => f());

    test('only the name is required: Save is off for an empty name; a name alone is sent as {name}', () async {
      final c = make();
      expect(c.canSubmit, isFalse);
      c.name.value = '  ';
      expect(await c.submit(), isNull);
      expect(c.fieldErrors['name'], 'Enter the customer\'s name.');
      c.name.value = 'Sara';
      expect(c.canSubmit, isTrue);
      Map<String, dynamic>? sent;
      when(() => repo.createPosCustomer('st1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[1] as Map<String, dynamic>;
        return (success: true, message: null, code: null, customer: customer(name: 'Sara'));
      });
      expect((await c.submit())!.name, 'Sara');
      expect(sent, {'name': 'Sara'}); // NTN / CNIC / registration type are never forced
    });

    test('filled fields are sent trimmed; registration type toggles and can be left unset', () async {
      final c = make()
        ..name.value = 'Sara'
        ..phone.value = ' 0300 '
        ..ntn.value = '12-34'
        ..group.value = 'VIP'
        ..marketingConsent.value = true;
      c.setRegistrationType('registered');
      c.setRegistrationType('registered'); // tapping again clears it
      expect(c.registrationType.value, isNull);
      c.setRegistrationType('unregistered');
      Map<String, dynamic>? sent;
      when(() => repo.createPosCustomer('st1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[1] as Map<String, dynamic>;
        return (success: true, message: null, code: null, customer: customer());
      });
      await c.submit();
      expect(sent, {'name': 'Sara', 'phone': '0300', 'ntn': '12-34', 'group': 'VIP', 'marketingConsent': true, 'registrationType': 'unregistered'});
    });

    for (final (code, field) in const [
      ('PHONE_INVALID', 'phone'),
      ('EMAIL_INVALID', 'email'),
      ('NTN_INVALID', 'ntn'),
      ('CNIC_INVALID', 'cnic'),
      ('REGISTRATION_TYPE_INVALID', 'registrationType'),
      ('NAME_REQUIRED', 'name'),
      ('PHONE_IN_USE', 'phone'),
    ]) {
      test('$code is shown under the $field field in plain words', () async {
        stubCreate(() => (success: false, message: 'raw server text', code: code, customer: null));
        final c = make()..name.value = 'Sara';
        expect(await c.submit(), isNull);
        expect(c.fieldErrors[field], isNotNull);
        expect(c.fieldErrors[field], isNot('raw server text'));
        expect(c.error.value, isNull);
        expect(c.busy.value, isFalse);
      });
    }

    test('an unknown refusal is a general error with the server message', () async {
      stubCreate(() => (success: false, message: 'Server says no', code: null, customer: null));
      final c = make()..name.value = 'Sara';
      await c.submit();
      expect(c.error.value, 'Server says no');
    });

    test('the same phone returns the existing customer: the result carries existing = true', () async {
      stubCreate(() => (success: true, message: null, code: null, customer: customer(existing: true)));
      final c = make()..name.value = 'Sara';
      expect((await c.submit())!.existing, isTrue);
    });

    test('a second tap while a save runs does nothing (one request)', () async {
      final gate = Completer<({bool success, String? message, String? code, PosCustomer? customer})>();
      when(() => repo.createPosCustomer('st1', any())).thenAnswer((_) => gate.future);
      final c = make()..name.value = 'Sara';
      final first = c.submit();
      await Future<void>.delayed(Duration.zero);
      expect(c.busy.value, isTrue);
      expect(c.canSubmit, isFalse);
      expect(await c.submit(), isNull);
      gate.complete((success: true, message: null, code: null, customer: customer()));
      await first;
      verify(() => repo.createPosCustomer('st1', any())).called(1);
    });

    test('offline: "Needs internet", nothing is sent, nothing is queued', () async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      final c = make()..name.value = 'Sara';
      expect(await c.submit(), isNull);
      expect(c.error.value, startsWith('Needs internet'));
      verifyNever(() => repo.createPosCustomer(any(), any()));
    });

    test('edit: prefilled, only the changed fields are sent, an emptied field is sent empty to clear it', () async {
      final c = make(
        existing: customer(phone: '0300', email: 'a@b.co'),
      );
      expect(c.name.value, 'Dev Customer');
      expect(c.phone.value, '0300');
      c.name.value = 'Renamed';
      c.email.value = '';
      Map<String, dynamic>? sent;
      when(() => repo.updatePosCustomer('st1', 'c1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[2] as Map<String, dynamic>;
        return (success: true, message: null, code: null, customer: customer(name: 'Renamed'));
      });
      expect((await c.submit())!.name, 'Renamed');
      expect(sent, {'name': 'Renamed', 'email': ''});
    });

    test('edit by a cashier: POS_ACTION_FORBIDDEN is said plainly; a taken phone is PHONE_IN_USE on the phone field', () async {
      stubUpdate(() => (success: false, message: 'x', code: 'POS_ACTION_FORBIDDEN', customer: null));
      var c = make(existing: customer())..name.value = 'Other';
      await c.submit();
      expect(c.error.value, 'Only a manager or the owner can do this.');
      stubUpdate(() => (success: false, message: 'x', code: 'PHONE_IN_USE', customer: null));
      c = make(existing: customer())..phone.value = '0333';
      await c.submit();
      expect(c.fieldErrors['phone'], 'Another customer already uses that phone number.');
    });
  });

  group('CustomerProfileController', () {
    CustomerProfileController make() => CustomerProfileController(customerId: 'c1', repository: repo, cache: cache, storeId: 'st1');
    Future<void> pause([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

    test('a manager gets lifetime spend and the credit ledger', () async {
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile(lifetime: 123400));
      when(() => repo.getCustomerCredit('st1', 'c1')).thenAnswer((_) async => CreditLedgerPage(enabled: true, cur: const InvCur('USD', 2), items: [creditEntry()]));
      final c = make()..onInit();
      await pause();
      expect(c.canManage, isTrue);
      expect(c.profile.value!.lifetimeSpendMinor, 123400);
      expect(c.ledger, hasLength(1));
      verify(() => repo.getCustomerCredit('st1', 'c1')).called(1);
    });

    test('a cashier gets no lifetime spend and the ledger is never requested', () async {
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile());
      final c = make()..onInit();
      await pause();
      expect(c.canManage, isFalse);
      expect(c.profile.value!.lifetimeSpendMinor, isNull);
      verifyNever(() => repo.getCustomerCredit(any(), any(), page: any(named: 'page')));
    });

    test('a ledger refusal is shown under the history, the profile still shows', () async {
      SharedPreferences.setMockInitialValues({'store_id': 'st1', 'pos_employee_role': 'manager'});
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile(lifetime: 1));
      when(() => repo.getCustomerCredit('st1', 'c1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final c = make()..onInit();
      await pause();
      expect(c.profile.value, isNotNull);
      expect(c.ledgerError.value, 'Only a manager or the owner can do this.');
    });

    test('offline: the remembered profile is shown with its as-of time; unknown customer is an honest message', () async {
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile());
      var c = make()..onInit();
      await pause();
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => null);
      c = make()..onInit();
      await pause();
      expect(c.profile.value!.asOf, isNotNull);
      await cache.clear();
      c = make()..onInit();
      await pause();
      expect(c.profile.value, isNull);
      expect(c.error.value, contains('No internet'));
    });

    test('a not-found style refusal is mapped to words', () async {
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_PIN_REQUIRED');
      final c = make()..onInit();
      await pause();
      expect(c.error.value, 'Sign in with your PIN first.');
    });

    test('applyEdit shows the saved details at once and keeps the balances', () async {
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile());
      final c = make()..onInit();
      await pause();
      c.applyEdit(customer(name: 'Renamed'));
      expect(c.profile.value!.customer.name, 'Renamed');
      expect(c.profile.value!.customer.creditBalanceMinor, 2000);
    });
  });

  group('CreditAdjustController', () {
    CreditAdjustController make({int exp = 2}) => CreditAdjustController(customerId: 'c1', exponent: exp, repository: repo, storeId: 'st1');

    test('the typed amount becomes a signed integer of MINOR units using the response exponent', () {
      final c = make();
      c.amountText.value = '5';
      expect(c.signedMinor, 500);
      c.amountText.value = '12.5';
      expect(c.signedMinor, 1250);
      c.amountText.value = '12,05';
      expect(c.signedMinor, 1205);
      c.adding.value = false;
      expect(c.signedMinor, -1205);
      c.amountText.value = '1.234'; // more decimals than the currency has
      expect(c.signedMinor, isNull);
      c.amountText.value = '0';
      expect(c.signedMinor, isNull);
      c.amountText.value = 'abc';
      expect(c.signedMinor, isNull);
      expect((make(exp: 0)..amountText.value = '7').signedMinor, 7);
      expect((make(exp: 3)..amountText.value = '1.5').signedMinor, 1500);
    });

    test('a note is required; without it Confirm is off and submit says why', () async {
      final c = make()..amountText.value = '5';
      expect(c.canSubmit, isFalse);
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Add a short note explaining the change.');
      verifyNever(
        () => repo.adjustCustomerCredit(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          note: any(named: 'note'),
        ),
      );
    });

    test('sends the signed minor amount and the note; success returns true', () async {
      when(() => repo.adjustCustomerCredit('st1', 'c1', amountMinor: -500, note: 'goodwill')).thenAnswer((_) async => (success: true, message: null, code: null));
      final c = make()
        ..amountText.value = '5'
        ..adding.value = false
        ..note.value = 'goodwill';
      expect(await c.submit(), isTrue);
      expect(c.error.value, isNull);
    });

    test('POS_OWNER_REQUIRED tells the user the OWNER must do it; other codes are plain too', () async {
      when(
        () => repo.adjustCustomerCredit(
          'st1',
          'c1',
          amountMinor: any(named: 'amountMinor'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_OWNER_REQUIRED'));
      final c = make()
        ..amountText.value = '5000'
        ..note.value = 'n';
      expect(await c.submit(), isFalse);
      expect(c.error.value, contains('owner must make this change'));
      when(
        () => repo.adjustCustomerCredit(
          'st1',
          'c1',
          amountMinor: any(named: 'amountMinor'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'STORE_CREDIT_NOT_ENABLED'));
      await c.submit();
      expect(c.error.value, 'Store credit is not switched on for this store.');
      when(
        () => repo.adjustCustomerCredit(
          'st1',
          'c1',
          amountMinor: any(named: 'amountMinor'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_ACTION_FORBIDDEN'));
      await c.submit();
      expect(c.error.value, 'Only a manager or the owner can do this.');
    });

    test('double tap: one request; offline: nothing is sent', () async {
      final gate = Completer<({bool success, String? message, String? code})>();
      when(
        () => repo.adjustCustomerCredit(
          'st1',
          'c1',
          amountMinor: any(named: 'amountMinor'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) => gate.future);
      final c = make()
        ..amountText.value = '5'
        ..note.value = 'n';
      final a = c.submit();
      await Future<void>.delayed(Duration.zero);
      expect(await c.submit(), isFalse);
      gate.complete((success: true, message: null, code: null));
      await a;
      verify(
        () => repo.adjustCustomerCredit(
          'st1',
          'c1',
          amountMinor: any(named: 'amountMinor'),
          note: any(named: 'note'),
        ),
      ).called(1);

      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      clearInteractions(repo);
      final off = make()
        ..amountText.value = '5'
        ..note.value = 'n';
      expect(await off.submit(), isFalse);
      expect(off.error.value, 'Needs internet.');
      verifyNever(
        () => repo.adjustCustomerCredit(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          note: any(named: 'note'),
        ),
      );
    });
  });
}
