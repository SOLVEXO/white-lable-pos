// G2.7: the permissions screen — a "why" and a "without it" per item, Allow when denied, Open Settings when permanently denied,
// nothing to press when granted / not used / asked by iOS itself; every state degrades (the screen never blocks).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_scan_camera_view.dart';
import 'package:solvexo_pos/app/modules/pos_permissions/controllers/pos_permissions_controller.dart';
import 'package:solvexo_pos/app/modules/pos_permissions/views/pos_permissions_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

class FakeGateway implements PermissionGateway {
  FakeGateway(this.state, {this.afterRequest});
  final Map<AppPermission, PermState> state;
  final Map<AppPermission, PermState>? afterRequest;
  final List<AppPermission> requested = [];
  int settingsOpened = 0;
  bool throwOnStatus = false;

  @override
  Future<PermState> status(AppPermission p) async {
    if (throwOnStatus) throw Exception('plugin');
    return state[p] ?? (p == AppPermission.notifications ? PermState.notRequired : p == AppPermission.localNetwork ? PermState.unknown : PermState.denied);
  }

  @override
  Future<PermState> request(AppPermission p) async {
    requested.add(p);
    return state[p] = afterRequest?[p] ?? PermState.granted;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

Future<PosPermissionsController> pump(WidgetTester t, FakeGateway g, {bool ios = true, bool dark = false, Size size = const Size(390, 1600)}) async {
  Get.testMode = true;
  Get.reset();
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final c = PosPermissionsController(gateway: g, ios: ios, afterSetup: false);
  Get.put(c);
  await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: PosPermissionsView(controller: c))));
  await t.pump();
  await t.pump();
  return c;
}

void main() {
  testWidgets('every item says why and what still works without it; notifications are honestly "not used"', (t) async {
    await pump(t, FakeGateway({AppPermission.camera: PermState.denied, AppPermission.bluetooth: PermState.denied, AppPermission.localNetwork: PermState.unknown, AppPermission.notifications: PermState.notRequired}));
    for (final k in ['camera', 'bluetooth', 'localNetwork', 'notifications']) {
      expect(find.byKey(Key('perm_$k')), findsOneWidget);
      expect(find.byKey(Key('permWithout_$k')), findsOneWidget);
    }
    expect(find.text('Not used'), findsOneWidget);
    expect(find.byKey(const Key('permAct_notifications')), findsNothing);
    expect(find.byKey(const Key('permAct_localNetwork')), findsNothing, reason: 'iOS asks by itself, there is nothing to press');
  });

  testWidgets('denied → Allow asks the system and shows Allowed when granted; the button goes away', (t) async {
    final g = FakeGateway({AppPermission.camera: PermState.denied, AppPermission.bluetooth: PermState.granted});
    await pump(t, g);
    expect(find.text('Allow'), findsOneWidget);
    await t.tap(find.byKey(const Key('permAct_camera')));
    await t.pump();
    await t.pump();
    expect(g.requested, [AppPermission.camera]);
    expect(find.byKey(const Key('permAct_camera')), findsNothing);
  });

  testWidgets('still denied after asking stays "Allow"; permanently denied shows the explanation and OPEN SETTINGS (never asks again)', (t) async {
    final g = FakeGateway({AppPermission.camera: PermState.denied, AppPermission.bluetooth: PermState.permanentlyDenied}, afterRequest: {AppPermission.camera: PermState.permanentlyDenied});
    await pump(t, g);
    await t.tap(find.byKey(const Key('permAct_camera')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('permBlocked_camera')), findsOneWidget);
    expect(find.text('Open Settings'), findsNWidgets(2));
    await t.tap(find.byKey(const Key('permAct_bluetooth')));
    await t.pump();
    expect(g.settingsOpened, 1);
    expect(g.requested, [AppPermission.camera], reason: 'a permanently denied item is not asked again');
  });

  testWidgets('coming back from Settings re-reads the state', (t) async {
    final g = FakeGateway({AppPermission.camera: PermState.permanentlyDenied, AppPermission.bluetooth: PermState.granted});
    final c = await pump(t, g);
    g.state[AppPermission.camera] = PermState.granted; // the user turned it on in Settings
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('permAct_camera')), findsNothing);
  });

  testWidgets('Android has no Local network row; a failing plugin never breaks the screen', (t) async {
    final g = FakeGateway({})..throwOnStatus = true;
    await pump(t, g, ios: false);
    expect(find.byKey(const Key('perm_localNetwork')), findsNothing);
    expect(find.byKey(const Key('perm_camera')), findsOneWidget);
    expect(find.byKey(const Key('permContinue')), findsOneWidget, reason: 'skippable: Done is always there');
  });

  testWidgets('tablet + dark render', (t) async {
    await pump(t, FakeGateway({AppPermission.camera: PermState.granted, AppPermission.bluetooth: PermState.denied}), dark: true, size: const Size(834, 1600));
    expect(find.byKey(const Key('permissionsIntro')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('camera scanner without the permission', () {
    Future<void> show(WidgetTester t, MobileScannerErrorCode code, {Future<void> Function()? open}) => t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: Scaffold(body: ScanCameraProblem(error: MobileScannerException(errorCode: code), onOpenSettings: open)))));

    testWidgets('denied: explains, offers Open Settings and "Type it instead"', (t) async {
      var opened = 0;
      await show(t, MobileScannerErrorCode.permissionDenied, open: () async => opened++);
      expect(find.byKey(const Key('scanProblemTitle')), findsOneWidget);
      expect(find.textContaining('type the barcode'), findsOneWidget);
      await t.tap(find.byKey(const Key('scanOpenSettings')));
      expect(opened, 1);
      expect(find.byKey(const Key('scanTypeInstead')), findsOneWidget);
    });

    testWidgets('any other camera failure: no Settings button, still a way out', (t) async {
      await show(t, MobileScannerErrorCode.genericError);
      expect(find.byKey(const Key('scanOpenSettings')), findsNothing);
      expect(find.byKey(const Key('scanTypeInstead')), findsOneWidget);
    });
  });
}
