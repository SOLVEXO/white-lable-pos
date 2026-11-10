import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';

/// One clock event (clock in / out, break start / end) made while the server could not be reached. [id] is the request id sent to the server (its
/// idempotency key), so replaying a row after a timeout, a restart or an update can never count it twice. [deviceAt] is the time the person really
/// tapped: the server keeps it, and flags what does not fit instead of refusing it, so hours are never lost to a bad connection. [seq] fixes the order.
///
///  * `pending` - waiting to be (re)sent, retried automatically with backoff.
///  * `failed`  - the server gave a definite "no" ([errorCode], e.g. EMPLOYEE_REQUIRED): it waits under Needs attention for Retry or Dismiss.
class PendingClockRecord {
  PendingClockRecord({
    required this.seq,
    required this.id,
    required this.action,
    required this.deviceAt,
    required this.status,
    required this.createdAt,
    this.note,
    this.storeId = '',
    this.employeeId = '',
    this.employeeToken,
    this.errorCode,
    this.errorMessage,
    this.attempts = 0,
    this.nextAttemptAt,
    this.unreadable = false,
  });
  final int seq;
  final String id, action, status, storeId, employeeId;
  final DateTime deviceAt, createdAt;
  final String? note, employeeToken, errorCode, errorMessage;
  final int attempts;
  final DateTime? nextAttemptAt;
  final bool unreadable;

  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';

  factory PendingClockRecord.fromRow(Map<String, dynamic> row, {bool unreadable = false}) {
    final p = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    return PendingClockRecord(
      seq: row['seq'] as int,
      id: row['id'] as String,
      action: p['action'] as String? ?? '',
      deviceAt: DateTime.tryParse('${p['deviceAt'] ?? ''}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      note: p['note'] as String?,
      status: row['status'] as String,
      createdAt: DateTime.parse(row['createdAt'] as String),
      storeId: row['storeId'] as String? ?? '',
      employeeId: row['employeeId'] as String? ?? '',
      employeeToken: row['employeeToken'] as String?,
      errorCode: row['errorCode'] as String?,
      errorMessage: row['errorMessage'] as String?,
      attempts: (row['attempts'] as int?) ?? 0,
      nextAttemptAt: row['nextAttemptAt'] != null ? DateTime.tryParse(row['nextAttemptAt'] as String) : null,
      unreadable: unreadable,
    );
  }
}

/// On-device queue of clock events made offline. A separate small database (the sale and cash queues are untouched); the payload, the employee token
/// and the error text are encrypted like theirs. Rows are never deleted by sign-out, only by a successful sync or a dismissal.
class PendingTeamLocalStore {
  PendingTeamLocalStore({Database? database, this.dbPath, QueueCipher? cipher}) : _db = database, _cipher = cipher ?? AesGcmQueueCipher();

  final QueueCipher _cipher;
  final String? dbPath;
  Database? _db;

  static const _dbName = 'pos_pending_team.db';
  static const _table = 'pending_team';

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
          payload TEXT NOT NULL,
          status TEXT NOT NULL,
          errorCode TEXT,
          errorMessage TEXT,
          createdAt TEXT NOT NULL,
          storeId TEXT,
          employeeId TEXT,
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

  Future<PendingClockRecord> _decode(Map<String, Object?> row) async {
    final m = Map<String, dynamic>.from(row);
    try {
      m['payload'] = await _cipher.decrypt(m['payload'] as String);
      if (m['employeeToken'] != null) m['employeeToken'] = await _cipher.decrypt(m['employeeToken'] as String);
      if (m['errorMessage'] != null) m['errorMessage'] = await _cipher.decrypt(m['errorMessage'] as String);
      return PendingClockRecord.fromRow(m);
    } on QueueDecryptException {
      return PendingClockRecord.fromRow({
        ...m,
        'payload': '{}',
        'employeeToken': null,
        'errorMessage': 'This clock event could not be read on this device (its encryption key is missing). Dismiss it; a manager can add the time by hand.',
        'status': 'failed',
      }, unreadable: true);
    }
  }

  /// Adds an event at the END of the queue. A request id already queued is left exactly as it is.
  Future<PendingClockRecord> enqueue({
    required String id,
    required String action,
    required DateTime deviceAt,
    required String storeId,
    required String employeeId,
    String? note,
    String? employeeToken,
    DateTime? now,
  }) async {
    final db = await _open();
    await db.insert(_table, {
      'id': id,
      'payload': await _cipher.encrypt(jsonEncode({'action': action, 'deviceAt': deviceAt.toUtc().toIso8601String(), if (note != null && note.trim().isNotEmpty) 'note': note.trim()})),
      'status': 'pending',
      'createdAt': (now ?? DateTime.now()).toIso8601String(),
      'storeId': storeId,
      'employeeId': employeeId,
      'employeeToken': await _enc(employeeToken),
      'attempts': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return (await getById(id))!;
  }

  Future<List<PendingClockRecord>> getAll() async {
    final db = await _open();
    return [for (final r in await db.query(_table, orderBy: 'seq ASC')) await _decode(r)];
  }

  Future<PendingClockRecord?> getById(String id) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : await _decode(rows.first);
  }

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

  /// Back to pending, try now. The stored employee token is dropped: a retry goes out as whoever is signed in.
  Future<void> resetForRetry(String id) async {
    final db = await _open();
    await db.update(_table, {'status': 'pending', 'attempts': 0, 'nextAttemptAt': null, 'errorMessage': null, 'errorCode': null, 'employeeToken': null}, where: 'id = ?', whereArgs: [id]);
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
