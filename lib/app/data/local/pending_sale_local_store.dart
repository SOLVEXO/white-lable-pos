import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';

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
      );
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
  static const _version = 3;

  final String? dbPath;
  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = dbPath ?? join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, version) => db.execute(_createSql),
      onUpgrade: (db, from, to) async {
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
      enc INTEGER NOT NULL DEFAULT 2
    )
  ''';

  /// Adds a sale. If a row with this key already exists it is left exactly as it is (the same intent queued twice
  /// must not reset its retry state or resurrect a failed/discarded one).
  Future<void> enqueue(String id, Map<String, dynamic> payload, {String? employeeToken}) async {
    final db = await _open();
    await db.insert(
      _table,
      {
        'id': id,
        'payload': await _cipher.encrypt(jsonEncode(payload)),
        'status': 'pending',
        'errorMessage': null,
        'createdAt': DateTime.now().toIso8601String(),
        'storeId': payload['storeId'],
        'sessionId': payload['sessionId'],
        'employeeToken': await _enc(employeeToken),
        'attempts': 0,
        'enc': _encCurrent,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
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
