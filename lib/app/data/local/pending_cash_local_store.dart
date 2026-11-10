import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';

/// What a queued cash request is.
abstract final class PendingCashKind {
  static const movement = 'movement', expense = 'expense', receipt = 'receipt';
}

/// One cash request made while the server could not be reached (a cash in / out, a DRAWER expense, or the photo of an expense),
/// kept on the device until it syncs. [id] is the request id sent to the server (`requestId`, its idempotency key), so replaying a row
/// after a timeout, a restart or an app update can never book it twice. [seq] fixes the order they are sent in.
///
///  * `pending` — waiting to be (re)sent, retried automatically with backoff.
///  * `failed`  — the server gave a definite "no" ([errorCode]): the shift closed meanwhile, over the limit with nobody to approve … It is
///    never retried by itself; it waits under Needs attention to be retried or dismissed.
class PendingCashRecord {
  PendingCashRecord({
    required this.seq,
    required this.id,
    required this.kind,
    required this.payload,
    required this.status,
    required this.createdAt,
    this.storeId = '',
    this.sessionId = '',
    this.refId,
    this.employeeToken,
    this.errorCode,
    this.errorMessage,
    this.attempts = 0,
    this.nextAttemptAt,
    this.unreadable = false,
  });
  final int seq;
  final String id, kind, status, storeId, sessionId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// a receipt photo points at the request id of the expense it belongs to
  final String? refId;

  /// the PIN-session token of the employee who made the request: the replay is authorised as them. Cleared by a manual retry (the current
  /// session is used then), since a token from hours ago may have expired.
  final String? employeeToken;
  final String? errorCode, errorMessage;
  final int attempts;
  final DateTime? nextAttemptAt;
  final bool unreadable;

  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
  bool get isMovement => kind == PendingCashKind.movement;
  bool get isExpense => kind == PendingCashKind.expense;
  bool get isReceipt => kind == PendingCashKind.receipt;

  int get amountMinor => (payload['amountMinor'] as num?)?.toInt() ?? 0;
  DateTime get madeAt => DateTime.tryParse('${payload['occurredAt'] ?? ''}')?.toLocal() ?? createdAt;
  String? get currency => payload['currency'] as String?;
  int? get exponent => (payload['currencyExponent'] as num?)?.toInt();

  /// A short human summary ("Cash out · Bank deposit", "Expense · Rent", "Receipt photo").
  String get title => switch (kind) {
    PendingCashKind.movement => '${payload['type'] == 'cash_in' ? 'Cash in' : 'Cash out'} · ${_label(payload['category'])}',
    PendingCashKind.expense => 'Expense · ${_label(payload['category'])}',
    _ => 'Receipt photo',
  };
  static String _label(dynamic c) {
    final t = '$c'.replaceAll('_', ' ');
    return t.isEmpty ? 'other' : '${t[0].toUpperCase()}${t.substring(1)}';
  }

  factory PendingCashRecord.fromRow(Map<String, dynamic> row, {bool unreadable = false}) => PendingCashRecord(
    seq: row['seq'] as int,
    id: row['id'] as String,
    kind: row['kind'] as String,
    payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    status: row['status'] as String,
    createdAt: DateTime.parse(row['createdAt'] as String),
    storeId: row['storeId'] as String? ?? '',
    sessionId: row['sessionId'] as String? ?? '',
    refId: row['refId'] as String?,
    employeeToken: row['employeeToken'] as String?,
    errorCode: row['errorCode'] as String?,
    errorMessage: row['errorMessage'] as String?,
    attempts: (row['attempts'] as int?) ?? 0,
    nextAttemptAt: row['nextAttemptAt'] != null ? DateTime.tryParse(row['nextAttemptAt'] as String) : null,
    unreadable: unreadable,
  );
}

/// On-device queue of cash requests made offline. A SEPARATE database from the sale queue (nothing of the sale queue is touched). The payload,
/// the employee token and the error text are encrypted like the sale queue's. Rows are never deleted by sign-out, only by a successful sync or a
/// dismissal.
class PendingCashLocalStore {
  PendingCashLocalStore({Database? database, this.dbPath, QueueCipher? cipher})
    : _db = database,
      _cipher = cipher ?? AesGcmQueueCipher();

  final QueueCipher _cipher;
  final String? dbPath;
  Database? _db;

  static const _dbName = 'pos_pending_cash.db';
  static const _table = 'pending_cash';

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = dbPath ?? join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE $_table (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          payload TEXT NOT NULL,
          status TEXT NOT NULL,
          errorCode TEXT,
          errorMessage TEXT,
          createdAt TEXT NOT NULL,
          storeId TEXT,
          sessionId TEXT,
          refId TEXT,
          employeeToken TEXT,
          attempts INTEGER NOT NULL DEFAULT 0,
          nextAttemptAt TEXT,
          lastAttemptAt TEXT
        )
      '''),
    );
    return _db!;
  }

  Future<String?> _enc(String? v) async => v == null ? null : _cipher.encrypt(v);

  Future<PendingCashRecord> _decode(Map<String, Object?> row) async {
    final m = Map<String, dynamic>.from(row);
    try {
      m['payload'] = await _cipher.decrypt(m['payload'] as String);
      if (m['employeeToken'] != null) m['employeeToken'] = await _cipher.decrypt(m['employeeToken'] as String);
      if (m['errorMessage'] != null) m['errorMessage'] = await _cipher.decrypt(m['errorMessage'] as String);
      return PendingCashRecord.fromRow(m);
    } on QueueDecryptException {
      return PendingCashRecord.fromRow({
        ...m,
        'payload': '{}',
        'employeeToken': null,
        'errorMessage': 'This entry could not be read on this device (its encryption key is missing). Dismiss it and record it again.',
        'status': 'failed',
      }, unreadable: true);
    }
  }

  /// Adds a request at the END of the queue. A request id already queued is left exactly as it is (the same intent queued twice never
  /// resets its retry state or its place in line). Returns the stored row.
  Future<PendingCashRecord> enqueue({
    required String id,
    required String kind,
    required Map<String, dynamic> payload,
    required String storeId,
    String sessionId = '',
    String? refId,
    String? employeeToken,
    DateTime? now,
  }) async {
    final db = await _open();
    final token = await _enc(employeeToken);
    final enc = await _cipher.encrypt(jsonEncode(payload));
    await db.insert(_table, {
      'id': id,
      'kind': kind,
      'payload': enc,
      'status': 'pending',
      'createdAt': (now ?? DateTime.now()).toIso8601String(),
      'storeId': storeId,
      'sessionId': sessionId,
      'refId': refId,
      'employeeToken': token,
      'attempts': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return (await getById(id))!;
  }

  Future<List<PendingCashRecord>> getAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'seq ASC');
    return [for (final r in rows) await _decode(r)];
  }

  Future<PendingCashRecord?> getById(String id) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : await _decode(rows.first);
  }

  Future<int> _count(String where, [List<Object?> args = const []]) async => Sqflite.firstIntValue(await (await _open()).rawQuery('SELECT COUNT(*) AS c FROM $_table WHERE $where', args)) ?? 0;

  Future<int> countPending({String? sessionId}) => sessionId == null ? _count("status = 'pending'") : _count("status = 'pending' AND sessionId = ?", [sessionId]);
  Future<int> countFailed({String? sessionId}) => sessionId == null ? _count("status = 'failed'") : _count("status = 'failed' AND sessionId = ?", [sessionId]);

  Future<void> markFailed(String id, String errorMessage, {String? errorCode}) async {
    final db = await _open();
    await db.update(_table, {'status': 'failed', 'errorMessage': await _enc(errorMessage), 'errorCode': errorCode}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> recordAttempt(String id, {required int attempts, required DateTime nextAttemptAt, String? errorMessage}) async {
    final db = await _open();
    await db.update(
      _table,
      {'attempts': attempts, 'nextAttemptAt': nextAttemptAt.toIso8601String(), 'lastAttemptAt': DateTime.now().toIso8601String(), 'errorMessage': await _enc(errorMessage)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Back to pending, try now. The stored employee token is dropped: a retry from Needs attention goes out as whoever is signed in.
  Future<void> resetForRetry(String id) async {
    final db = await _open();
    await db.update(_table, {'status': 'pending', 'attempts': 0, 'nextAttemptAt': null, 'errorMessage': null, 'errorCode': null, 'employeeToken': null}, where: 'id = ?', whereArgs: [id]);
  }

  /// The expense reached the server: its photo (queued under the expense's request id) now knows where to go.
  Future<void> attachExpenseId(String expenseRequestId, String expenseId) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'refId = ?', whereArgs: [expenseRequestId]);
    for (final r in rows) {
      final rec = await _decode(r);
      if (rec.unreadable) continue;
      await db.update(_table, {'payload': await _cipher.encrypt(jsonEncode({...rec.payload, 'expenseId': expenseId}))}, where: 'id = ?', whereArgs: [rec.id]);
    }
  }

  Future<List<PendingCashRecord>> childrenOf(String id) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'refId = ?', whereArgs: [id], orderBy: 'seq ASC');
    return [for (final r in rows) await _decode(r)];
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
