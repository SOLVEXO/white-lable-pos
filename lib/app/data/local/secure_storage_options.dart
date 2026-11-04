import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// iOS Keychain class for everything this app keeps in secure storage (the offline-queue key, tokens, the device credential):
/// readable after the FIRST unlock following a boot — so background sync works while the phone is locked — and bound to this
/// device (`…ThisDeviceOnly`): it never travels in a backup or to another phone. Android Keystore items are device-bound already
/// and Android backups exclude everything (`backup_rules.xml`).
const IOSOptions kFirstUnlockThisDevice = IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

const MacOsOptions _kFirstUnlockThisDeviceMac = MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

/// The one secure-storage handle the app uses (queue key, tokens, device credential). `mOptions` mirrors `iOptions` only so the
/// class is also visible when the unit tests run on a macOS host; the shipped targets are iOS and Android.
const FlutterSecureStorage kPosSecureStorage = FlutterSecureStorage(iOptions: kFirstUnlockThisDevice, mOptions: _kFirstUnlockThisDeviceMac);
