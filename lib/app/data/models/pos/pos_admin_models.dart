/// G4.2 – G4.4 read models: the store's permission matrix (roles & approvals), the audit seals' integrity check, the store settings the settings hub
/// edits (receipt designer, in-app alerts, security, profile) and the backup / sync read-out.
library;

int _int(dynamic v) => v is num ? v.toInt() : 0;
String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];
Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};
List<String> _strings(dynamic v) => v is List ? [for (final e in v) '$e'] : const [];
DateTime? _date(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

// ── G4.2 · roles & permissions ────────────────────────────────────────────────
abstract final class PermRole {
  static const cashier = 'cashier', manager = 'manager', owner = 'owner';
  static const all = [cashier, manager, owner];
  static String label(String r) => switch (r) {
    cashier => 'Cashier',
    manager => 'Manager',
    owner => 'Owner',
    _ => r,
  };
}

/// One approval rule of an action: above [limitLabel] (or always) the [approver] must approve; the owner may switch it off or re-route it.
class PermApproval {
  const PermApproval({this.limit, this.limitLabel, this.measures, this.always = false, required this.defaultApprover, required this.approver, this.enabled = true});
  final String? limit, limitLabel, measures;
  final bool always, enabled;
  final String defaultApprover, approver;

  bool get changed => !enabled || approver != defaultApprover;
  PermApproval copyWith({bool? enabled, String? approver}) =>
      PermApproval(limit: limit, limitLabel: limitLabel, measures: measures, always: always, defaultApprover: defaultApprover, approver: approver ?? this.approver, enabled: enabled ?? this.enabled);

  /// "Above Cash out a cashier may make alone" / "Every time"
  String get when => always ? 'Every time' : (limitLabel == null ? 'Above the limit' : 'Above: $limitLabel');

  factory PermApproval.fromJson(Map<String, dynamic> j) => PermApproval(
    limit: _str(j['limit']),
    limitLabel: _str(j['limitLabel']),
    measures: _str(j['measures']),
    always: j['always'] == true,
    defaultApprover: _str(j['defaultApprover']) ?? PermRole.manager,
    approver: _str(j['approver']) ?? _str(j['defaultApprover']) ?? PermRole.manager,
    enabled: j['enabled'] != false,
  );
}

class PermAction {
  const PermAction({required this.action, required this.label, this.pinned = false, this.changed = false, this.defaultRoles = const [], this.roles = const [], this.approval = const []});
  final String action, label;
  final bool pinned, changed;
  final List<String> defaultRoles, roles;
  final List<PermApproval> approval;

  /// inventory · customers · supply · cash · team · reports · catalog · settings (the screen's groups)
  String get area => permArea(action);

  factory PermAction.fromJson(Map<String, dynamic> j) => PermAction(
    action: '${j['action'] ?? ''}',
    label: _str(j['label']) ?? '${j['action'] ?? ''}',
    pinned: j['pinned'] == true,
    changed: j['changed'] == true,
    defaultRoles: _strings(j['defaultRoles']),
    roles: _strings(j['roles']),
    approval: [for (final a in _maps(j['approval'])) PermApproval.fromJson(a)],
  );
}

/// The screen's groups, in order.
const permAreas = ['inventory', 'customers', 'supply', 'cash', 'team', 'reports', 'catalog', 'settings', 'other'];

String permArea(String action) {
  final head = action.split('.').first;
  return switch (head) {
    'inventory' || 'stock' || 'lots' => 'inventory',
    'customers' || 'storeCredit' || 'loyalty' => 'customers',
    'supply' || 'suppliers' => 'supply',
    'cash' || 'expenses' || 'session' || 'shift' => 'cash',
    'team' || 'attendance' || 'roster' => 'team',
    'reports' || 'audit' => 'reports',
    'catalog' || 'products' => 'catalog',
    'settings' => 'settings',
    _ => 'other',
  };
}

String permAreaLabel(String area) => switch (area) {
  'inventory' => 'Inventory',
  'customers' => 'Customers, credit & loyalty',
  'supply' => 'Suppliers & purchasing',
  'cash' => 'Cash & expenses',
  'team' => 'Team & attendance',
  'reports' => 'Reports & audit',
  'catalog' => 'Catalog',
  'settings' => 'Settings',
  _ => 'Other',
};

class PermissionMatrix {
  const PermissionMatrix({required this.version, required this.canEdit, this.actions = const []});
  final int version;
  final bool canEdit;
  final List<PermAction> actions;
  factory PermissionMatrix.fromJson(Map<String, dynamic> j) =>
      PermissionMatrix(version: _int(j['version']), canEdit: j['canEdit'] == true, actions: [for (final a in _maps(j['actions'])) PermAction.fromJson(a)]);
}

/// One line of the server's preview: what changes for an action (`roles` or `approval`), before → after.
class PermDiff {
  const PermDiff({required this.action, required this.field, this.before, this.after});
  final String action, field;
  final dynamic before, after;
  factory PermDiff.fromJson(Map<String, dynamic> j) => PermDiff(action: '${j['action'] ?? ''}', field: '${j['field'] ?? ''}', before: j['before'], after: j['after']);

  static String _roles(dynamic v) => v is List && v.isNotEmpty ? v.map((r) => PermRole.label('$r')).join(', ') : 'nobody';
  static String _approval(dynamic v) {
    if (v is! List || v.isEmpty) return 'no approval';
    return v
        .map((a) {
          final m = a is Map ? a : const {};
          final who = PermRole.label('${m['approver'] ?? 'manager'}');
          return m['always'] == true ? '$who approves every time' : '$who approves above the limit';
        })
        .join('; ');
  }

  String get beforeText => field == 'roles' ? _roles(before) : _approval(before);
  String get afterText => field == 'roles' ? _roles(after) : _approval(after);
  String get fieldLabel => field == 'roles' ? 'Who may' : 'Approval';
}

String permErrorMessage(String? code, {String? fallback}) => switch (code) {
  'VERSION_CONFLICT' => 'The permissions were changed on another device. Reload to see the latest and make your change again.',
  'INVALID_PERMISSIONS' => 'That change is not allowed (the owner keeps every permission, and the permission settings themselves cannot change).',
  'CHANGES_REQUIRED' => 'Nothing to save.',
  'POS_ACTION_FORBIDDEN' => 'Only the owner can change roles and permissions.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  _ => fallback ?? 'Something went wrong. Please try again.',
};

// ── G4.3 · audit seals ────────────────────────────────────────────────────────
class SealPartChange {
  const SealPartChange(this.part, this.sealedCount, this.nowCount);
  final String part;
  final int sealedCount, nowCount;

  String get label => switch (part) {
    'audit_log' => 'Activity log',
    'payments' => 'Payments',
    'refunds' => 'Refunds',
    'credit_notes' => 'Credit notes',
    'stock_movements' => 'Stock movements',
    'store_credit' => 'Store credit',
    'supplier_ledger' => 'Supplier ledger',
    'goods_receipts' => 'Goods receipts',
    'expenses' => 'Expenses',
    'expense_events' => 'Expense approvals',
    'attendance' => 'Attendance',
    _ => part.replaceAll('_', ' '),
  };
}

class SealDay {
  const SealDay({required this.day, required this.status, this.sealedAt, this.count = 0, this.changedParts = const []});
  final String day, status; // ok | changed | broken_chain
  final DateTime? sealedAt;
  final int count;
  final List<SealPartChange> changedParts;
  bool get ok => status == 'ok';
  factory SealDay.fromJson(Map<String, dynamic> j) => SealDay(
    day: '${j['day'] ?? ''}',
    status: '${j['status'] ?? 'ok'}',
    sealedAt: _date(j['sealedAt']),
    count: _int(j['count']),
    changedParts: [for (final p in _maps(j['changedParts'])) SealPartChange('${p['part'] ?? ''}', _int(p['sealedCount']), _int(p['nowCount']))],
  );
}

class AuditVerify {
  const AuditVerify({required this.ok, this.days = 0, this.results = const []});
  final bool ok;
  final int days;
  final List<SealDay> results;
  factory AuditVerify.fromJson(Map<String, dynamic> j) => AuditVerify(ok: j['ok'] == true, days: _int(j['days']), results: [for (final r in _maps(j['results'])) SealDay.fromJson(r)]);
}

// ── G4.4 · store settings ─────────────────────────────────────────────────────
class ReceiptOptions {
  const ReceiptOptions({
    this.showLogo = true,
    this.showStoreAddress = true,
    this.showTaxId = true,
    this.showTaxBreakdown = true,
    this.showQr = true,
    this.showCashierName = true,
    this.showCustomerName = true,
    this.showLoyaltyBalance = true,
    this.showBarcode = false,
    this.defaultPaperWidth = 80,
    this.promoText,
    this.header,
    this.footer,
  });
  final bool showLogo, showStoreAddress, showTaxId, showTaxBreakdown, showQr, showCashierName, showCustomerName, showLoyaltyBalance, showBarcode;
  final int defaultPaperWidth;
  final String? promoText, header, footer;

  /// the on/off switches, in the order the designer shows them
  static const flags = ['showLogo', 'showStoreAddress', 'showTaxId', 'showTaxBreakdown', 'showQr', 'showCashierName', 'showCustomerName', 'showLoyaltyBalance', 'showBarcode'];
  static String flagLabel(String k) => switch (k) {
    'showLogo' => 'Store logo',
    'showStoreAddress' => 'Store address',
    'showTaxId' => 'Tax ID (NTN / STRN)',
    'showTaxBreakdown' => 'Tax breakdown',
    'showQr' => 'QR code (digital receipt)',
    'showCashierName' => 'Cashier name',
    'showCustomerName' => 'Customer name',
    'showLoyaltyBalance' => 'Loyalty points balance',
    'showBarcode' => 'Receipt number barcode',
    _ => k,
  };

  /// switches the thermal / PDF receipt does not print yet (the setting is kept; the preview shows it)
  static const notPrintedYet = {'showLogo', 'showQr', 'showLoyaltyBalance', 'showBarcode'};

  bool flag(String k) => toJson()[k] == true;

  Map<String, dynamic> toJson() => {
    'showLogo': showLogo,
    'showStoreAddress': showStoreAddress,
    'showTaxId': showTaxId,
    'showTaxBreakdown': showTaxBreakdown,
    'showQr': showQr,
    'showCashierName': showCashierName,
    'showCustomerName': showCustomerName,
    'showLoyaltyBalance': showLoyaltyBalance,
    'showBarcode': showBarcode,
    'defaultPaperWidth': defaultPaperWidth,
    'promoText': promoText,
    'header': header,
    'footer': footer,
  };

  ReceiptOptions withFlag(String k, bool v) => ReceiptOptions.fromJson({...toJson(), k: v});
  ReceiptOptions copyWith({int? defaultPaperWidth, String? promoText, String? header, String? footer}) =>
      ReceiptOptions.fromJson({...toJson(), 'defaultPaperWidth': ?defaultPaperWidth, 'promoText': ?promoText, 'header': ?header, 'footer': ?footer});

  factory ReceiptOptions.fromJson(Map<String, dynamic> j) {
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    return ReceiptOptions(
      showLogo: b('showLogo', true),
      showStoreAddress: b('showStoreAddress', true),
      showTaxId: b('showTaxId', true),
      showTaxBreakdown: b('showTaxBreakdown', true),
      showQr: b('showQr', true),
      showCashierName: b('showCashierName', true),
      showCustomerName: b('showCustomerName', true),
      showLoyaltyBalance: b('showLoyaltyBalance', true),
      showBarcode: b('showBarcode', false),
      defaultPaperWidth: j['defaultPaperWidth'] == 58 ? 58 : 80,
      promoText: _str(j['promoText']),
      header: _str(j['header']),
      footer: _str(j['footer']),
    );
  }
}

/// The in-app alerts managers see.
abstract final class AlertKeys {
  static const all = ['lowStock', 'expiringLots', 'largeRefund', 'cashVariance', 'attendanceAnomalies', 'unsyncedSales', 'sealFailure'];
  static String label(String k) => switch (k) {
    'lowStock' => 'Low stock',
    'expiringLots' => 'Lots about to expire',
    'largeRefund' => 'Large refunds',
    'cashVariance' => 'Cash differences at shift close',
    'attendanceAnomalies' => 'Attendance problems',
    'unsyncedSales' => 'Sales not yet synced',
    'sealFailure' => 'Audit integrity failures',
    _ => k,
  };
  static String help(String k) => switch (k) {
    'lowStock' => 'Items at or below their reorder point',
    'expiringLots' => 'Batches close to their expiry date',
    'largeRefund' => 'Refunds above the approval limit',
    'cashVariance' => 'A drawer that did not count up',
    'attendanceAnomalies' => 'Missing clock-outs, overlaps, late syncs',
    'unsyncedSales' => 'Offline sales still on a device',
    'sealFailure' => 'A sealed day that no longer matches',
    _ => '',
  };
}

class SecurityPrefs {
  const SecurityPrefs({this.autoLockMinutes = 5, this.lockOnBackground = false, this.requirePinForReprint = false, this.hideCostsFromManagers = false});
  final int autoLockMinutes;
  final bool lockOnBackground, requirePinForReprint, hideCostsFromManagers;
  factory SecurityPrefs.fromJson(Map<String, dynamic> j) => SecurityPrefs(
    autoLockMinutes: j['autoLockMinutes'] is num ? (j['autoLockMinutes'] as num).toInt() : 5,
    lockOnBackground: j['lockOnBackground'] == true,
    requirePinForReprint: j['requirePinForReprint'] == true,
    hideCostsFromManagers: j['hideCostsFromManagers'] == true,
  );
}

class StoreSettings {
  const StoreSettings({required this.receipt, this.alerts = const {}, required this.security, this.businessName, this.businessAddress, this.businessTaxId, this.timeZone, this.canEdit = false});
  final ReceiptOptions receipt;
  final Map<String, bool> alerts;
  final SecurityPrefs security;
  final String? businessName, businessAddress, businessTaxId, timeZone;
  final bool canEdit;

  bool alert(String k) => alerts[k] ?? true;

  factory StoreSettings.fromJson(Map<String, dynamic> j) {
    final pr = _map(j['profile']);
    return StoreSettings(
      receipt: ReceiptOptions.fromJson(_map(j['receipt'])),
      alerts: {for (final e in _map(j['alerts']).entries) e.key: e.value == true},
      security: SecurityPrefs.fromJson(_map(j['security'])),
      businessName: _str(pr['businessName']),
      businessAddress: _str(pr['businessAddress']),
      businessTaxId: _str(pr['businessTaxId']),
      timeZone: _str(j['timeZone']),
      canEdit: j['canEdit'] == true,
    );
  }
}

String settingsErrorMessage(String? code, {String? message}) => switch (code) {
  'INVALID_SETTINGS' => message ?? 'That value is not allowed.',
  'NOTHING_TO_CHANGE' => 'Nothing to change.',
  'POS_ACTION_FORBIDDEN' => 'Only the owner can change these settings.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  _ => message ?? 'Something went wrong. Please try again.',
};

class SyncDevice {
  const SyncDevice({required this.id, this.name, this.platform, this.appVersion, this.lastSeenAt});
  final String id;
  final String? name, platform, appVersion;
  final DateTime? lastSeenAt;
}

class SyncStatus {
  const SyncStatus({this.serverTime, this.timeZone, this.devices = const [], this.lastSealDay, this.lastSealAt, this.lastSealRecords = 0});
  final DateTime? serverTime;
  final String? timeZone;
  final List<SyncDevice> devices;
  final String? lastSealDay;
  final DateTime? lastSealAt;
  final int lastSealRecords;

  factory SyncStatus.fromJson(Map<String, dynamic> j) {
    final seal = j['lastSeal'] is Map ? _map(j['lastSeal']) : null;
    return SyncStatus(
      serverTime: _date(j['serverTime']),
      timeZone: _str(j['timeZone']),
      devices: [
        for (final d in _maps(j['devices']))
          SyncDevice(id: '${d['id'] ?? ''}', name: _str(d['name']), platform: _str(d['platform']), appVersion: _str(d['appVersion']), lastSeenAt: _date(d['lastSeenAt'])),
      ],
      lastSealDay: seal == null ? null : _str(seal['day']),
      lastSealAt: seal == null ? null : _date(seal['sealedAt']),
      lastSealRecords: seal == null ? 0 : _int(seal['records']),
    );
  }

  /// device clock minus server clock (a big gap makes offline times unreliable)
  Duration? clockGap(DateTime deviceNow) => serverTime == null ? null : deviceNow.difference(serverTime!);
}
