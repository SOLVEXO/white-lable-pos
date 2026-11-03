import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

/// A sale rung up (or attempted) while the server could not be reached, kept on the device until it syncs.
///
/// `id` is the SAME idempotency key sent to the backend (the unique key on `Sale.idempotencyKey`), so replaying a
/// row — after a timeout, a restart, an app update — can never create a second sale. The payload carries the time
/// the sale was really made (`clientCreatedAt`), the `settingsVersion` it was priced with and its `sessionId`.
///
/// Statuses:
///  * `pending`  — waiting to be (re)sent; retried automatically with backoff.
///  * `failed`   — the server gave a definite "no" (see [errorCode]); needs a person. Never dropped silently.
///  * `discarding` — a manager chose to give up on it with a [discardReason]; kept locally until that decision is
///    recorded in the server's audit log, then removed.
class PendingSaleRecord {
  final String id;
  final Map<String, dynamic> payload;
  final String status; // pending | failed | discarding
  final String? errorMessage;
  final String? errorCode;
  final DateTime createdAt;
  final String storeId;
  final String sessionId;

  /// The PIN-session token of the employee who made the sale — kept ONLY when a discount needs a manager's
  /// authority at sync time (the server checks it was valid when the sale was made).
  final String? employeeToken;
  final int attempts;
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;
  final String? discardReason;
  final String? discardedBy;

  /// The row's encrypted contents could not be read (the device key is gone / data damaged). The row is KEPT and
  /// shown for a manager to discard — never dropped, never replayed blind.
  final bool unreadable;

  /// Provisional receipt number (`OFF-<device>-<seq>`, Q7) given when the sale was queued. Informational only: the
  /// server assigns the real receipt number and never sees this one. Null for rows queued before it existed.
  final String? provisionalNumber;

  PendingSaleRecord({
    required this.id,
    required this.payload,
    required this.status,
    this.errorMessage,
    this.errorCode,
    required this.createdAt,
    this.storeId = '',
    this.sessionId = '',
    this.employeeToken,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastAttemptAt,
    this.discardReason,
    this.discardedBy,
    this.unreadable = false,
    this.provisionalNumber,
  });

  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
  bool get isDiscarding => status == 'discarding';

  /// Still has money/stock consequences that nobody has resolved: pending or failed (not a recorded discard).
  bool get isUnresolved => isPending || isFailed;

  /// When the sale was really made (falls back to when it was queued).
  DateTime get madeAt => DateTime.tryParse(payload['clientCreatedAt'] as String? ?? '') ?? createdAt;

  /// A short human summary for the Needs-attention list.
  String get summary {
    final items = (payload['items'] as List?) ?? const [];
    final qty = items.fold<int>(0, (s, i) => s + ((i as Map)['qty'] as num? ?? 0).toInt());
    return '${items.length} line${items.length == 1 ? '' : 's'}, $qty item${qty == 1 ? '' : 's'}';
  }

  /// What the device showed the customer (what was charged), if recorded.
  double? get deviceTotal => (payload['clientTotal'] as num?)?.toDouble();

  factory PendingSaleRecord.fromRow(Map<String, dynamic> row, {bool unreadable = false}) => PendingSaleRecord(
        id: row['id'] as String,
        payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        status: row['status'] as String,
        errorMessage: row['errorMessage'] as String?,
        errorCode: row['errorCode'] as String?,
        createdAt: DateTime.parse(row['createdAt'] as String),
        storeId: row['storeId'] as String? ?? '',
        sessionId: row['sessionId'] as String? ?? '',
        employeeToken: row['employeeToken'] as String?,
        attempts: (row['attempts'] as int?) ?? 0,
        nextAttemptAt: row['nextAttemptAt'] != null ? DateTime.tryParse(row['nextAttemptAt'] as String) : null,
        lastAttemptAt: row['lastAttemptAt'] != null ? DateTime.tryParse(row['lastAttemptAt'] as String) : null,
        discardReason: row['discardReason'] as String?,
        discardedBy: row['discardedBy'] as String?,
        unreadable: unreadable,
        provisionalNumber: row['provisionalNumber'] as String?,
      );
}

/// What the device remembers about an offline receipt after (and before) the sale reaches the server: the provisional
/// number, the receipt as it was shown, and — once synced — the REAL number the server gave the sale.
class OfflineReceiptRecord {
  final String key;
  final String provisionalNumber;
  final ReceiptData? snapshot; // null until the till saved it (or if it can't be read)
  final String? realNumber;
  final String? saleId;
  const OfflineReceiptRecord({required this.key, required this.provisionalNumber, this.snapshot, this.realNumber, this.saleId});

  bool get isSynced => realNumber != null && realNumber!.isNotEmpty;

  /// The receipt to show NOW: the provisional one (with its pending note) while unsynced; after sync the same sale under
  /// its real number, still carrying the provisional number as a reference.
  ReceiptData? get receipt {
    final s = snapshot;
    if (s == null) return null;
    return isSynced ? s.copyWith(receiptNumber: realNumber, clearOfflineNote: true, offlineRef: provisionalNumber) : s;
  }
}

/// On-device queue for sales made while offline: one table, a handful of rows. Rows belong to a store+session and
/// are NEVER deleted by sign-out — only by a successful sync or a manager's recorded discard.
class PendingSaleLocalStore {
  PendingSaleLocalStore({Database? database, this.dbPath, QueueCipher? cipher})
      : _db = database,
        _cipher = cipher ?? AesGcmQueueCipher();

  final QueueCipher _cipher;

  static const _dbName = 'pos_pending_sales.db';
  static const _table = 'pending_sales';
  static const _version = 4;
  static const _seqTable = 'offline_receipt_seq';
  static const _receiptTable = 'offline_receipts';

  final String? dbPath;
  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = dbPath ?? join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await db.execute(_createSql);
        await _createReceiptTables(db);
      },
      onUpgrade: (db, from, to) async {
        if (from < 4) {
          // v4: provisional offline receipt numbers (column + per-device sequence + provisional→real map). sqflite runs an
          // upgrade in one transaction, and the guards make a re-run harmless.
          final cols = await db.rawQuery('PRAGMA table_info($_table)');
          if (!cols.any((c) => c['name'] == 'provisionalNumber')) await db.execute('ALTER TABLE $_table ADD COLUMN provisionalNumber TEXT');
          await _createReceiptTables(db);
        }
        if (from < 3 && from >= 2) {
          await db.execute('ALTER TABLE $_table ADD COLUMN enc INTEGER NOT NULL DEFAULT 0');
        }
        if (from < 2) {
          for (final col in const [
            'errorCode TEXT',
            'storeId TEXT',
            'sessionId TEXT',
            'employeeToken TEXT',
            'attempts INTEGER NOT NULL DEFAULT 0',
            'nextAttemptAt TEXT',
            'lastAttemptAt TEXT',
            'discardReason TEXT',
            'discardedBy TEXT',
          ]) {
            await db.execute('ALTER TABLE $_table ADD COLUMN $col');
          }
          await db.execute('ALTER TABLE $_table ADD COLUMN enc INTEGER NOT NULL DEFAULT 0');
          // Rows queued by v1 carry their store/session inside the payload — lift them into the new columns.
          final rows = await db.query(_table);
          for (final r in rows) {
            try {
              final p = jsonDecode(r['payload'] as String) as Map<String, dynamic>;
              await db.update(_table, {'storeId': p['storeId'], 'sessionId': p['sessionId']}, where: 'id = ?', whereArgs: [r['id']]);
            } catch (_) {}
          }
        }
      },
    );
    _db = db;
    await _upgradeRows(db);
    return db;
  }

  static Future<void> _createReceiptTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS $_seqTable (device TEXT PRIMARY KEY, last INTEGER NOT NULL)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_receiptTable (
        key TEXT PRIMARY KEY,
        provisional TEXT NOT NULL UNIQUE,
        snapshot TEXT,
        realNumber TEXT,
        saleId TEXT,
        createdAt TEXT NOT NULL,
        syncedAt TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_receipts_real ON $_receiptTable (realNumber)');
  }

  /// `enc` column: 0 = plaintext (written before 5C.1), 1 = encrypted by app versions up to 5F (`v1:`, pure-Dart AES-GCM),
  /// 2 = written by the current OS-crypto cipher (`v2:`). v1 and v2 are the same AES-256-GCM, same key, same layout.
  static const _encCurrent = 2;
  static const _encFields = ['payload', 'employeeToken', 'errorMessage', 'discardReason'];

  /// Brings every older row up to the current scheme: plaintext rows are encrypted, `v1:` values are re-encrypted as `v2:`.
  /// One row per transaction, and a row is only overwritten by values that have just been produced (and only if it hasn't
  /// changed meanwhile), so a crash or a missing key at any moment leaves the row readable as before — nothing is lost, the
  /// next open tries again. A `v1:` value that can't be decrypted (key lost) is left untouched; reads report it `unreadable`.
  Future<void> _upgradeRows(Database db) async {
    final rows = await db.query(
      _table,
      where: "enc < ? OR payload LIKE 'v1:%' OR employeeToken LIKE 'v1:%' OR errorMessage LIKE 'v1:%' OR discardReason LIKE 'v1:%'",
      whereArgs: [_encCurrent],
    );
    for (final r in rows) {
      try {
        final plaintextRow = (r['enc'] as int?) == 0;
        final values = <String, Object?>{};
        for (final f in _encFields) {
          final v = r[f] as String?;
          if (v == null) continue;
          if (plaintextRow) {
            values[f] = await _cipher.encrypt(v);
          } else if (v.startsWith(AesGcmQueueCipher.legacyPrefix)) {
            values[f] = await _cipher.encrypt(await _cipher.decrypt(v));
          }
        }
        values['enc'] = _encCurrent;
        final guard = ['id = ?', 'enc = ?', ..._encFields.map((f) => '$f IS ?')].join(' AND ');
        await db.transaction((txn) => txn.update(_table, values, where: guard, whereArgs: [r['id'], r['enc'], ..._encFields.map((f) => r[f])]));
      } catch (_) {/* keep the row as it is; retried on the next open */}
    }
  }

  Future<String?> _enc(String? v) async => v == null ? null : _cipher.encrypt(v);

  /// Decrypts a stored row into a record. A row that can't be decrypted is returned `unreadable` (kept, shown, never lost).
  Future<PendingSaleRecord> _decode(Map<String, Object?> row) async {
    final m = Map<String, dynamic>.from(row);
    if ((m['enc'] as int?) == 0) return PendingSaleRecord.fromRow(m); // legacy plaintext, upgraded on open
    try {
      m['payload'] = await _cipher.decrypt(m['payload'] as String);
      if (m['employeeToken'] != null) m['employeeToken'] = await _cipher.decrypt(m['employeeToken'] as String);
      if (m['errorMessage'] != null) m['errorMessage'] = await _cipher.decrypt(m['errorMessage'] as String);
      if (m['discardReason'] != null) m['discardReason'] = await _cipher.decrypt(m['discardReason'] as String);
      return PendingSaleRecord.fromRow(m);
    } on QueueDecryptException {
      return PendingSaleRecord.fromRow({
        ...m,
        'payload': '{"storeId":"${m['storeId'] ?? ''}","sessionId":"${m['sessionId'] ?? ''}","items":[]}',
        'employeeToken': null,
        'errorMessage': 'This sale could not be read on this device (its encryption key is missing). A manager must review and discard it.',
        'discardReason': null,
        'status': (m['status'] == 'discarding') ? 'discarding' : 'failed',
      }, unreadable: true);
    }
  }

  static const _createSql = '''
    CREATE TABLE $_table (
      id TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      status TEXT NOT NULL,
      errorMessage TEXT,
      errorCode TEXT,
      createdAt TEXT NOT NULL,
      storeId TEXT,
      sessionId TEXT,
      employeeToken TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      nextAttemptAt TEXT,
      lastAttemptAt TEXT,
      discardReason TEXT,
      discardedBy TEXT,
      enc INTEGER NOT NULL DEFAULT 2,
      provisionalNumber TEXT
    )
  ''';

  /// `OFF-<deviceShort>-<seq>`: the last 6 letters/digits of the device id (a Mongo ObjectId's FIRST characters are its
  /// creation timestamp and identical across devices registered close together; its last ones differ), upper-cased.
  static String deviceShortOf(String? deviceId) {
    final clean = (deviceId ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (clean.isEmpty) return 'LOCAL';
    return clean.length <= 6 ? clean : clean.substring(clean.length - 6);
  }

  /// Adds a sale and gives it a provisional receipt number. If a row with this key already exists it is left exactly as it
  /// is (the same intent queued twice must not reset its retry state, resurrect a failed/discarded one, or burn another
  /// receipt number) and its existing number is returned. The sequence is per device, only ever goes up and is NOT rolled
  /// back when the row is later removed, so a number is never issued twice.
  Future<String?> enqueue(String id, Map<String, dynamic> payload, {String? employeeToken, String? deviceShort}) async {
    final db = await _open();
    final encPayload = await _cipher.encrypt(jsonEncode(payload));
    final encToken = await _enc(employeeToken);
    final short = deviceShortOf(deviceShort);
    return db.transaction<String?>((txn) async {
      final existing = await txn.query(_table, columns: ['provisionalNumber'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (existing.isNotEmpty) return existing.first['provisionalNumber'] as String?;
      final known = await txn.query(_receiptTable, columns: ['provisional'], where: 'key = ?', whereArgs: [id], limit: 1);
      String number;
      if (known.isNotEmpty) {
        number = known.first['provisional'] as String; // row was removed (synced) and the same key came back: same number
      } else {
        await txn.rawInsert('INSERT OR IGNORE INTO $_seqTable (device, last) VALUES (?, 0)', [short]);
        await txn.rawUpdate('UPDATE $_seqTable SET last = last + 1 WHERE device = ?', [short]);
        final seq = Sqflite.firstIntValue(await txn.rawQuery('SELECT last FROM $_seqTable WHERE device = ?', [short])) ?? 1;
        number = 'OFF-$short-${seq.toString().padLeft(4, '0')}';
        await txn.insert(_receiptTable, {'key': id, 'provisional': number, 'createdAt': DateTime.now().toIso8601String()});
      }
      await txn.insert(
        _table,
        {
          'id': id,
          'payload': encPayload,
          'status': 'pending',
          'errorMessage': null,
          'createdAt': DateTime.now().toIso8601String(),
          'storeId': payload['storeId'],
          'sessionId': payload['sessionId'],
          'employeeToken': encToken,
          'attempts': 0,
          'enc': _encCurrent,
          'provisionalNumber': number,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return number;
    });
  }

  /// Keeps the receipt exactly as the till showed it (encrypted: it carries customer name and amounts), so it can be
  /// shown, printed or shared again — and updated with the real number after sync.
  Future<void> saveReceiptSnapshot(String key, ReceiptData receipt) async {
    final db = await _open();
    await db.update(_receiptTable, {'snapshot': await _cipher.encrypt(jsonEncode(receipt.toJson()))}, where: 'key = ?', whereArgs: [key]);
  }

  /// The sale reached the server: remember the real number (idempotent — the replay of the same key returns the same one).
  Future<void> noteSynced(String key, {required String realNumber, String? saleId}) async {
    final db = await _open();
    await db.update(
      _receiptTable,
      {'realNumber': realNumber, 'saleId': saleId, 'syncedAt': DateTime.now().toIso8601String()},
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  Future<OfflineReceiptRecord?> receiptByKey(String key) async => _decodeReceipt(await (await _open()).query(_receiptTable, where: 'key = ?', whereArgs: [key], limit: 1));

  /// The offline receipt behind a server sale (by the sale's real receipt number or id) — for "this sale was made offline as OFF-…".
  Future<OfflineReceiptRecord?> receiptByRealNumber(String realNumberOrSaleId) async => _decodeReceipt(
      await (await _open()).query(_receiptTable, where: 'realNumber = ? OR saleId = ?', whereArgs: [realNumberOrSaleId, realNumberOrSaleId], limit: 1));

  Future<OfflineReceiptRecord?> _decodeReceipt(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return null;
    final r = rows.first;
    ReceiptData? snap;
    final raw = r['snapshot'] as String?;
    if (raw != null) {
      try {
        snap = ReceiptData.fromJson(jsonDecode(await _cipher.decrypt(raw)) as Map<String, dynamic>);
      } catch (_) {
        snap = null; // unreadable (key gone) — the mapping itself is still useful
      }
    }
    return OfflineReceiptRecord(
      key: r['key'] as String,
      provisionalNumber: r['provisional'] as String,
      snapshot: snap,
      realNumber: r['realNumber'] as String?,
      saleId: r['saleId'] as String?,
    );
  }

  Future<List<PendingSaleRecord>> getAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'createdAt ASC');
    return [for (final r in rows) await _decode(r)];
  }

  Future<PendingSaleRecord?> getById(String id) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : await _decode(rows.first);
  }

  /// Pending + failed rows (what still needs to reach the server or be resolved by a manager), optionally limited
  /// to one session and/or store.
  Future<int> countUnresolved({String? sessionId, String? storeId}) async {
    final db = await _open();
    final where = StringBuffer("status IN ('pending','failed')");
    final args = <Object?>[];
    if (sessionId != null) {
      where.write(' AND sessionId = ?');
      args.add(sessionId);
    }
    if (storeId != null) {
      where.write(' AND storeId = ?');
      args.add(storeId);
    }
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $_table WHERE $where', args);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> countPending() async {
    final db = await _open();
    return Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) AS c FROM $_table WHERE status = 'pending'")) ?? 0;
  }

  Future<int> countFailed() async {
    final db = await _open();
    return Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) AS c FROM $_table WHERE status = 'failed'")) ?? 0;
  }

  /// A definite server "no": keep the sale, say why, wait for a person.
  Future<void> markFailed(String id, String errorMessage, {String? errorCode}) async {
    final db = await _open();
    await db.update(_table, {'status': 'failed', 'errorMessage': await _enc(errorMessage), 'errorCode': errorCode, 'enc': _encCurrent}, where: 'id = ?', whereArgs: [id]);
  }

  /// A retryable failure: keep it pending, count the attempt, schedule the next one.
  Future<void> recordAttempt(String id, {required int attempts, required DateTime nextAttemptAt, String? errorMessage}) async {
    final db = await _open();
    await db.update(
      _table,
      {'attempts': attempts, 'nextAttemptAt': nextAttemptAt.toIso8601String(), 'lastAttemptAt': DateTime.now().toIso8601String(), 'errorMessage': await _enc(errorMessage)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Manager pressed Retry: back to pending, try immediately, backoff reset.
  Future<void> resetForRetry(String id) async {
    final db = await _open();
    await db.update(_table, {'status': 'pending', 'attempts': 0, 'nextAttemptAt': null, 'errorMessage': null, 'errorCode': null}, where: 'id = ?', whereArgs: [id]);
  }

  /// A manager gave up on this sale (reason required by the caller). It stays on the device until the discard has
  /// been written to the server's audit log, so a discard can never silently erase a sale.
  Future<void> markDiscarding(String id, {required String reason, required String discardedBy, String? managerToken}) async {
    final db = await _open();
    // `employeeToken` is overwritten with the discarding MANAGER's token: the audit entry must be authorised by them.
    await db.update(_table, {'status': 'discarding', 'discardReason': await _enc(reason), 'discardedBy': discardedBy, 'employeeToken': await _enc(managerToken)}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> remove(String id) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
