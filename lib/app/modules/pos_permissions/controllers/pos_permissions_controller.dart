import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

/// What the till can ask the phone for. Each one has a plain reason and a plain "without it" (the feature degrades, it never breaks).
enum AppPermission { camera, bluetooth, localNetwork, notifications }

enum PermState {
  granted,
  denied,

  /// The user said "don't ask again" (or iOS will not ask a second time): only the system Settings can change it.
  permanentlyDenied,

  /// Cannot be read from the app (iOS never tells an app its Local Network answer) — asked by the system the first time it is used.
  unknown,

  /// Not used by this version / not applicable on this platform.
  notRequired,
}

/// The only place that talks to `permission_handler`, so the screen and its rules are testable.
abstract class PermissionGateway {
  Future<PermState> status(AppPermission p);
  Future<PermState> request(AppPermission p);
  Future<void> openSettings();
}

class SystemPermissionGateway implements PermissionGateway {
  List<Permission>? _of(AppPermission p) {
    switch (p) {
      case AppPermission.camera:
        return [Permission.camera];
      case AppPermission.bluetooth:
        return Platform.isAndroid ? [Permission.bluetoothScan, Permission.bluetoothConnect] : [Permission.bluetooth];
      case AppPermission.localNetwork:
      case AppPermission.notifications:
        return null; // no API (iOS Local Network) / not used by this version
    }
  }

  static PermState _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return PermState.granted;
    if (s.isPermanentlyDenied) return PermState.permanentlyDenied;
    if (s.isRestricted) return PermState.permanentlyDenied; // parental controls / MDM: only Settings (or the admin) can lift it
    return PermState.denied;
  }

  static PermState _worst(Iterable<PermState> all) {
    if (all.any((s) => s == PermState.permanentlyDenied)) return PermState.permanentlyDenied;
    if (all.any((s) => s == PermState.denied)) return PermState.denied;
    return PermState.granted;
  }

  @override
  Future<PermState> status(AppPermission p) async {
    final list = _of(p);
    if (list == null) return p == AppPermission.localNetwork && Platform.isIOS ? PermState.unknown : PermState.notRequired;
    return _worst([for (final x in list) _map(await x.status)]);
  }

  @override
  Future<PermState> request(AppPermission p) async {
    final list = _of(p);
    if (list == null) return status(p);
    return _worst([for (final x in list) _map(await x.request())]);
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

class PermissionRow {
  PermissionRow({required this.permission, required this.title, required this.why, required this.without});
  final AppPermission permission;
  final String title;

  /// Why the till asks, in a sentence a shopkeeper understands.
  final String why;

  /// What still works without it.
  final String without;
}

/// "Permissions" — shown once after the device is set up and reachable later from More. Skippable: nothing here blocks selling.
class PosPermissionsController extends GetxController with WidgetsBindingObserver {
  PosPermissionsController({PermissionGateway? gateway, bool? ios, bool? afterSetup})
      : _gateway = gateway ?? SystemPermissionGateway(),
        isIos = ios ?? Platform.isIOS,
        _afterSetupOverride = afterSetup;

  final PermissionGateway _gateway;
  final bool isIos;
  final bool? _afterSetupOverride;

  late final bool afterSetup;
  final RxMap<AppPermission, PermState> states = <AppPermission, PermState>{}.obs;
  final RxBool busy = false.obs;

  late final List<PermissionRow> rows = [
    PermissionRow(
      permission: AppPermission.camera,
      title: 'Camera',
      why: 'Scans product barcodes at the till and photographs your business documents for verification.',
      without: 'You can still type a barcode or search by name, and upload documents from your files.',
    ),
    PermissionRow(
      permission: AppPermission.bluetooth,
      title: 'Bluetooth',
      why: 'Finds and connects to your receipt printer. It is not used to track location or talk to other devices.',
      without: 'Receipts can still be shared as a PDF or link; printing waits until you allow it.',
    ),
    if (isIos)
      PermissionRow(
        permission: AppPermission.localNetwork,
        title: 'Local network',
        why: 'Connects to a receipt printer on your shop Wi-Fi / Ethernet. iOS asks the first time you use a network printer.',
        without: 'Bluetooth printers and PDF receipts are not affected.',
      ),
    PermissionRow(
      permission: AppPermission.notifications,
      title: 'Notifications',
      why: 'This version sends no notifications, so nothing is asked.',
      without: 'Nothing changes. Sync status is always on the Offline mode screen.',
    ),
  ];

  @override
  void onInit() {
    super.onInit();
    afterSetup = _afterSetupOverride ?? (Get.arguments is Map && (Get.arguments as Map)['afterSetup'] == true);
    WidgetsBinding.instance.addObserver(this);
    refreshAll();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  /// Back from the system Settings: re-read everything.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshAll();
  }

  Future<void> refreshAll() async {
    for (final r in rows) {
      try {
        states[r.permission] = await _gateway.status(r.permission);
      } catch (_) {
        states[r.permission] = PermState.unknown; // never block on a failed read
      }
    }
  }

  PermState stateOf(AppPermission p) => states[p] ?? PermState.unknown;

  /// What the row's button does: ask (denied / not asked yet) or open the system Settings (permanently denied). Nothing when granted / not used.
  Future<void> act(AppPermission p) async {
    if (busy.value) return;
    final s = stateOf(p);
    if (s == PermState.granted || s == PermState.notRequired || s == PermState.unknown && p == AppPermission.localNetwork) return;
    busy.value = true;
    try {
      if (s == PermState.permanentlyDenied) {
        await _gateway.openSettings();
      } else {
        states[p] = await _gateway.request(p);
      }
    } catch (_) {
      // a plugin failure must not break the screen; the status is simply unchanged
    } finally {
      busy.value = false;
    }
  }

  /// Label of the row's button, or null when there is nothing to press.
  String? actionLabel(AppPermission p) {
    switch (stateOf(p)) {
      case PermState.granted:
      case PermState.notRequired:
        return null;
      case PermState.permanentlyDenied:
        return 'Open Settings';
      case PermState.denied:
        return 'Allow';
      case PermState.unknown:
        return p == AppPermission.localNetwork ? null : 'Allow';
    }
  }
}
