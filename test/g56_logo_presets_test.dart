// G5.6: the receipt logo (1-bit dithered bitmap per paper width, ESC/POS raster, printed only when the switch is on and a logo is cached, preview,
// owner upload / remove words) and role presets (proposed; the owner previews the server's diff, then applies).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/roles_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/roles_view.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/settings_hub_views.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/receipt_logo.dart';

class _Repo extends Mock implements PosRepository {}

typedef _PermRes = ({bool success, String? code, String? message, PermissionMatrix? matrix, List<PermDiff> diff});

Uint8List _rgba(int w, int h, int Function(int x, int y) lum, {int alpha = 255}) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final l = lum(x, y);
      b[i] = l;
      b[i + 1] = l;
      b[i + 2] = l;
      b[i + 3] = alpha;
    }
  }
  return b;
}

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

ReceiptData _receipt({String? logoUrl}) => ReceiptData(receiptNumber: 'S-1', dateText: '2026-11-12 10:00', customer: null, lines: const [], subtotal: 'PKR 10.00', total: 'PKR 10.00', payments: const [], logoUrl: logoUrl);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(_FakeFile());
  });

  group('dithering and raster', () {
    test('black stays black, white stays white, transparent is paper; width padded to a multiple of 8', () {
      final black = ReceiptLogo.dither(_rgba(10, 2, (_, __) => 0), 10, 2);
      expect([black.width, black.height, black.bytesPerRow], [16, 2, 2]);
      expect(black.dot(0, 0) && black.dot(9, 1), isTrue);
      expect(black.dot(12, 0), isFalse); // the padding is white
      final white = ReceiptLogo.dither(_rgba(8, 2, (_, __) => 255), 8, 2);
      expect(white.bits.every((b) => b == 0), isTrue);
      final clear = ReceiptLogo.dither(_rgba(8, 2, (_, __) => 0, alpha: 0), 8, 2);
      expect(clear.bits.every((b) => b == 0), isTrue);
    });

    test('a mid-grey dithers to about half the dots (not all or nothing)', () {
      final g = ReceiptLogo.dither(_rgba(64, 64, (_, __) => 128), 64, 64);
      var on = 0;
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          if (g.dot(x, y)) on++;
        }
      }
      expect(on / (64 * 64), closeTo(0.5, 0.06));
    });

    test('ESC/POS: centred GS v 0 with the right size header, then left again; cache JSON round-trips', () {
      final b = ReceiptLogo.dither(_rgba(16, 3, (_, __) => 0), 16, 3);
      final e = b.escPos();
      expect(e.sublist(0, 11), [0x1B, 0x61, 1, 0x1D, 0x76, 0x30, 0, 2, 0, 3, 0]);
      expect(e.sublist(e.length - 3), [0x1B, 0x61, 0]);
      final back = LogoBitmap.fromJson(b.toJson())!;
      expect([back.width, back.height, back.bits], [b.width, b.height, b.bits]);
      expect(ReceiptLogo.widthFor(58), 256);
      expect(ReceiptLogo.widthFor(80), 384);
    });

    test('the receipt prints the cached logo only when the receipt asks for it (switch on + uploaded)', () async {
      ReceiptLogoStore.clear();
      final b = ReceiptLogo.dither(_rgba(16, 3, (_, __) => 0), 16, 3);
      ReceiptLogoStore.put('https://cdn/logo.png', 80, b);
      final head = b.escPos().sublist(3, 11);
      expect(_contains(await ReceiptEscPosBuilder.build(data: _receipt(logoUrl: 'https://cdn/logo.png')), head), isTrue);
      expect(_contains(await ReceiptEscPosBuilder.build(data: _receipt()), head), isFalse);
      expect(_contains(await ReceiptEscPosBuilder.build(data: _receipt(logoUrl: 'https://cdn/other.png')), head), isFalse); // not cached → no logo, still prints
    });

    test('settings: the logo prints only with the designer switch on', () {
      final on = PosSettingsModel.fromJson({'storeId': 's', 'receiptLogoUrl': 'https://cdn/l.png', 'receiptOptions': {'showLogo': true}});
      final off = PosSettingsModel.fromJson({'storeId': 's', 'receiptLogoUrl': 'https://cdn/l.png', 'receiptOptions': {'showLogo': false}});
      expect([on.receiptLogoUrlToPrint, off.receiptLogoUrlToPrint], ['https://cdn/l.png', null]);
      expect(PosSettingsModel.fromJson(on.toCacheJson()).receiptLogoUrl, 'https://cdn/l.png'); // the offline settings cache keeps it
    });
  });

  group('designer logo', () {
    test('upload / remove: settings replaced, preview refreshed, errors in plain words', () async {
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      final repo = _Repo();
      final c = StoreSettingsController(repository: repo, storeId: 'st1');
      final bmp = ReceiptLogo.dither(_rgba(8, 8, (_, __) => 0), 8, 8);
      c.logoLoader = (url, mm) async => bmp;
      final withLogo = StoreSettings.fromJson({'receipt': {'logoUrl': 'https://cdn/l.png', 'showLogo': true}, 'security': {}, 'canEdit': true});
      when(() => repo.uploadReceiptLogo('st1', any())).thenAnswer((_) async => (success: true, code: null, message: null, settings: withLogo));
      when(() => repo.removeReceiptLogo('st1')).thenAnswer((_) async => (success: false, code: 'POS_ACTION_FORBIDDEN', message: 'no', settings: null));
      await c.uploadLogo(_FakeFile());
      await Future<void>.delayed(Duration.zero);
      expect(c.settings.value!.receiptLogoUrl, 'https://cdn/l.png');
      expect(c.logoPreview.value, same(bmp));
      await c.removeLogo();
      expect(c.logoError.value, 'Only the owner can change the logo.');
      expect(StoreSettingsController.logoErrorMessage('FILE_TYPE', null), 'Use a JPEG, PNG or WebP image.');
    });

    testWidgets('the preview draws the dots instead of the placeholder icon', (t) async {
      final bmp = ReceiptLogo.dither(_rgba(16, 8, (_, __) => 0), 16, 8);
      await t.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: ReceiptPreview(options: const ReceiptOptions(), storeName: 'Shop', logo: bmp))));
      expect(find.byKey(const Key('previewLogoBitmap')), findsOneWidget);
      expect(find.byKey(const Key('previewLogo')), findsNothing);
    });
  });

  group('role presets', () {
    Map<String, dynamic> matrix() => {
          'version': 3,
          'canEdit': true,
          'actions': [{'action': 'inventory.adjust', 'label': 'Adjust stock', 'roles': ['cashier', 'manager', 'owner'], 'defaultRoles': ['cashier', 'manager', 'owner']}],
          'presets': [
            {'key': 'standard', 'label': 'Standard', 'summary': 'Defaults', 'status': 'proposed'},
            {'key': 'strict', 'label': 'Strict (owner away)', 'summary': 'Tighter', 'status': 'proposed'},
          ],
        };

    testWidgets('owner: Presets → pick → server preview → apply (with the version); "Proposed" shown', (t) async {
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Get.reset();
      final repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getPermissionMatrix('st1')).thenAnswer((_) async => PermissionMatrix.fromJson(matrix()));
      when(() => repo.applyRolePreset('st1', 'strict', preview: true)).thenAnswer(
        (_) async => (success: true, code: null, message: null, matrix: null, diff: [PermDiff.fromJson({'action': 'inventory.adjust', 'field': 'roles', 'before': ['cashier', 'manager', 'owner'], 'after': ['manager', 'owner']})]) as _PermRes,
      );
      when(() => repo.applyRolePreset('st1', 'strict', expectedVersion: 3)).thenAnswer((_) async => (success: true, code: null, message: null, matrix: PermissionMatrix.fromJson({...matrix(), 'version': 4}), diff: <PermDiff>[]) as _PermRes);
      t.view.physicalSize = const Size(430, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = Get.put(RolesController(repository: repo, storeId: 'st1'), tag: 'p');
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: RolesView(controller: c))));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(PermissionMatrix.fromJson(matrix()).presets.map((p) => p.proposed), [true, true]);
      await t.tap(find.byKey(const Key('permPresets')));
      await t.pumpAndSettle();
      expect(find.text('Proposed'), findsNWidgets(2));
      await t.tap(find.byKey(const Key('preset_strict')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('permDiff_inventory.adjust_roles')), findsOneWidget);
      await t.tap(find.byKey(const Key('permConfirm')));
      await t.pumpAndSettle();
      verify(() => repo.applyRolePreset('st1', 'strict', expectedVersion: 3)).called(1);
      expect(c.matrix.value!.version, 4);
      expect(c.notice.value, contains('Strict (owner away)'));
    });
  });
}

class _FakeFile extends Fake implements File {
  @override
  String get path => '/tmp/logo.png';
}
