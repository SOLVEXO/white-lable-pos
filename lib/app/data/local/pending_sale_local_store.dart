import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// A sale queued locally because [createSale] failed with a connectivity
/// error. `id` is the same idempotency key sent (or that will be sent) to
/// the backend, so a retry can never create a duplicate sale server-side —
/// see the `idempotencyKey` handling in `PosRepository.createSale`.
class PendingSaleRecord {
  final String id;
  final Map<String, dynamic> payload;
  final String status; // 'pending' | 'failed'
  final String? errorMessage;
  final DateTime createdAt;

  PendingSaleRecord({
    required this.id,
    required this.payload,
    required this.status,
    this.errorMessage,
    required this.createdAt,
  });

  factory PendingSaleRecord.fromRow(Map<String, dynamic> row) => PendingSaleRecord(
        id: row['id'] as String,
        payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        status: row['status'] as String,
        errorMessage: row['errorMessage'] as String?,
        createdAt: DateTime.parse(row['createdAt'] as String),
      );
}

/// On-device queue for sales made while offline. Kept deliberately small —
/// no migrations framework, no ORM — this is one table with a handful of
/// rows at a time (a store isn't running hundreds of concurrent offline
/// sales), synced out as soon as `NetworkStatusService` reports a
/// reconnect; see `PendingSaleSyncService`.
class PendingSaleLocalStore {
  static const _dbName = 'pos_pending_sales.db';
  static const _table = 'pending_sales';

  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final path = join(dir, _dbName);
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_table (
          id TEXT PRIMARY KEY,
          payload TEXT NOT NULL,
          status TEXT NOT NULL,
          errorMessage TEXT,
          createdAt TEXT NOT NULL
        )
      '''),
    );
    _db = db;
    return db;
  }

  Future<void> enqueue(String id, Map<String, dynamic> payload) async {
    final db = await _open();
    await db.insert(
      _table,
      {
        'id': id,
        'payload': jsonEncode(payload),
        'status': 'pending',
        'errorMessage': null,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingSaleRecord>> getAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'createdAt ASC');
    return rows.map(PendingSaleRecord.fromRow).toList();
  }

  Future<int> countPending() async {
    final db = await _open();
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM $_table WHERE status = 'pending'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markFailed(String id, String errorMessage) async {
    final db = await _open();
    await db.update(
      _table,
      {'status': 'failed', 'errorMessage': errorMessage},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> remove(String id) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
