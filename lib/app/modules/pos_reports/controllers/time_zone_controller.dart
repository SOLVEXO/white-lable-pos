import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';

/// Common zones for the picker; Pakistan first (most stores), then the region and the rest of the world. The server validates any IANA name.
const commonTimeZones = <String>[
  'Asia/Karachi',
  'Asia/Dubai',
  'Asia/Riyadh',
  'Asia/Qatar',
  'Asia/Kuwait',
  'Asia/Muscat',
  'Asia/Bahrain',
  'Asia/Kabul',
  'Asia/Tehran',
  'Asia/Kolkata',
  'Asia/Dhaka',
  'Asia/Kathmandu',
  'Asia/Colombo',
  'Asia/Tashkent',
  'Asia/Almaty',
  'Asia/Bangkok',
  'Asia/Jakarta',
  'Asia/Kuala_Lumpur',
  'Asia/Singapore',
  'Asia/Shanghai',
  'Asia/Hong_Kong',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Perth',
  'Australia/Sydney',
  'Pacific/Auckland',
  'Europe/Istanbul',
  'Europe/Moscow',
  'Europe/Athens',
  'Europe/Berlin',
  'Europe/Paris',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Amsterdam',
  'Europe/London',
  'Europe/Dublin',
  'Africa/Cairo',
  'Africa/Johannesburg',
  'Africa/Nairobi',
  'Africa/Lagos',
  'America/Sao_Paulo',
  'America/New_York',
  'America/Toronto',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'UTC',
];

/// G4.0 store time zone: everyone reads it (with today's store date); only the OWNER changes it (the server enforces: settings.store.edit).
class TimeZoneController extends GetxController {
  TimeZoneController({PosRepository? repository, String? storeId, Future<bool> Function()? isOwner, DateTime Function()? clock})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _isOwner = isOwner ?? (() async => (await PosAccess.current()).isOwner),
      _clock = clock ?? DateTime.now;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final Future<bool> Function() _isOwner;
  final DateTime Function() _clock;

  final Rxn<StoreTimeZone> zone = Rxn<StoreTimeZone>();
  final RxBool loading = true.obs;
  final RxBool saving = false.obs;
  final RxnString error = RxnString();
  final RxnString saveError = RxnString();
  final RxnString saved = RxnString();
  final RxBool canEdit = false.obs;
  final RxString search = ''.obs;
  Worker? _online;

  /// the list, filtered by [search]; the current zone is always offered even when it is not a common one
  List<String> get zones {
    final cur = zone.value?.timeZone;
    final all = [...commonTimeZones, if (cur != null && !commonTimeZones.contains(cur)) cur];
    final q = search.value.trim().toLowerCase().replaceAll(' ', '_');
    return q.isEmpty ? all : all.where((z) => z.toLowerCase().contains(q)).toList();
  }

  @override
  void onInit() {
    super.onInit();
    _isOwner().then((v) => canEdit.value = v);
    load();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && zone.value == null) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    error.value = null;
    if (!reportsOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final z = await _repo.getStoreTimeZone(await reportsStoreId(_storeIdOverride));
    if (z == null) {
      error.value = reportErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the time zone. Try again.');
    } else {
      zone.value = z;
      StoreDay.remember(z, _clock());
    }
    loading.value = false;
  }

  /// Owner only; returns true when the server took it.
  Future<bool> choose(String tz) async {
    if (saving.value || !canEdit.value || tz == zone.value?.timeZone) return false;
    saveError.value = null;
    saved.value = null;
    if (!reportsOnline()) {
      saveError.value = 'Changing the time zone needs an internet connection.';
      return false;
    }
    saving.value = true;
    final r = await _repo.setStoreTimeZone(await reportsStoreId(_storeIdOverride), tz);
    saving.value = false;
    if (!r.success) {
      saveError.value = reportErrorMessage(r.code, fallback: r.message ?? 'Could not change the time zone.');
      return false;
    }
    if (r.zone != null) {
      zone.value = r.zone;
      StoreDay.remember(r.zone!, _clock());
    } else {
      await load();
    }
    saved.value = 'The store now runs on $tz. Reports and the daybook count days in this zone.';
    return true;
  }
}
