import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/worker.dart';
import '../models/client.dart';
import '../models/attendance.dart';

class DatabaseService {
  static const String _dbName     = 'woosin_data.db';
  static const String _dataFolder = 'woosin_data';
  static const int    _dbVersion  = 1;

  // 싱글톤
  static DatabaseService? _instance;
  static Database?        _db;

  DatabaseService._();
  factory DatabaseService() {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  // ── DB 초기화 ─────────────────────────────────────────────
  // FFI 초기화는 main.dart에서 이미 완료됨 — 여기서는 openDatabase만
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final base   = await getApplicationDocumentsDirectory();
    final dir    = Directory(p.join(base.path, _dataFolder));
    if (!await dir.exists()) await dir.create(recursive: true);

    final dbPath = p.join(dir.path, _dbName);

    // FFI 환경: databaseFactory를 통해 열어야 Windows에서 정상 동작
    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _onCreate,
        onOpen: (db) async {
          await db.execute('PRAGMA journal_mode=WAL;');
          await db.execute('PRAGMA foreign_keys=ON;');
        },
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE workers (
        id                 TEXT PRIMARY KEY,
        name               TEXT NOT NULL,
        gender             TEXT NOT NULL DEFAULT '',
        resident_number    TEXT NOT NULL DEFAULT '',
        phone              TEXT NOT NULL,
        address            TEXT NOT NULL DEFAULT '',
        bank_name          TEXT NOT NULL DEFAULT '',
        bank_account       TEXT NOT NULL DEFAULT '',
        career             TEXT NOT NULL DEFAULT '',
        notes              TEXT NOT NULL DEFAULT '',
        id_photo_path      TEXT,
        id_photo_back_path TEXT,
        is_blacklisted     INTEGER NOT NULL DEFAULT 0,
        blacklist_reason   TEXT,
        created_at         TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE clients (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        address         TEXT NOT NULL DEFAULT '',
        contact_person  TEXT NOT NULL DEFAULT '',
        phone           TEXT NOT NULL DEFAULT '',
        email           TEXT NOT NULL DEFAULT '',
        notes           TEXT NOT NULL DEFAULT '',
        created_at      TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance (
        id                      TEXT PRIMARY KEY,
        worker_id               TEXT,
        worker_name             TEXT NOT NULL,
        worker_gender           TEXT NOT NULL DEFAULT '',
        worker_resident_number  TEXT NOT NULL DEFAULT '',
        worker_phone            TEXT NOT NULL DEFAULT '',
        worker_address          TEXT NOT NULL DEFAULT '',
        worker_bank_name        TEXT NOT NULL DEFAULT '',
        worker_bank_account     TEXT NOT NULL DEFAULT '',
        worker_career           TEXT NOT NULL DEFAULT '',
        client_id               TEXT,
        client_name             TEXT NOT NULL,
        client_address          TEXT NOT NULL DEFAULT '',
        work_date               TEXT NOT NULL,
        daily_wage              REAL NOT NULL DEFAULT 0,
        commission_rate         REAL NOT NULL DEFAULT 0,
        commission              REAL NOT NULL DEFAULT 0,
        net_wage                REAL NOT NULL DEFAULT 0,
        notes                   TEXT NOT NULL DEFAULT '',
        id_photo_path           TEXT,
        id_photo_back_path      TEXT,
        is_postpaid             INTEGER NOT NULL DEFAULT 0,
        is_settled              INTEGER NOT NULL DEFAULT 1,
        created_at              TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_workers_name       ON workers(name)');
    await db.execute('CREATE INDEX idx_attendance_date    ON attendance(work_date)');
    await db.execute('CREATE INDEX idx_attendance_settled ON attendance(is_settled)');
  }

  // ── 이미지 경로 변환 ──────────────────────────────────────
  Future<String> get _dataFolderPath async {
    final base = await getApplicationDocumentsDirectory();
    return p.join(base.path, _dataFolder);
  }

  Future<String?> toRelative(String? absPath) async {
    if (absPath == null || absPath.isEmpty) return null;
    if (!p.isAbsolute(absPath)) return absPath;
    final base = await _dataFolderPath;
    if (absPath.startsWith(base)) {
      return p.relative(absPath, from: base).replaceAll('\\', '/');
    }
    return null;
  }

  Future<String?> toAbsolute(String? relPath) async {
    if (relPath == null || relPath.isEmpty) return null;
    if (p.isAbsolute(relPath)) return relPath;
    final base = await _dataFolderPath;
    return p.join(base, relPath.replaceAll('/', p.separator));
  }

  // ── Workers CRUD ──────────────────────────────────────────
  Future<List<Worker>> getAllWorkers() async {
    final db   = await database;
    final rows = await db.query('workers', orderBy: 'name ASC');
    return Future.wait(rows.map((r) async {
      final map = Map<String, dynamic>.from(r);
      map['id_photo_path']      = await toAbsolute(map['id_photo_path']);
      map['id_photo_back_path'] = await toAbsolute(map['id_photo_back_path']);
      return Worker.fromMap(map, map['id'] as String);
    }));
  }

  Future<void> insertWorker(Worker w) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(w.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    await db.insert('workers', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateWorker(Worker w) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(w.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    await db.update('workers', map, where: 'id = ?', whereArgs: [w.id]);
  }

  Future<void> deleteWorker(String id) async {
    final db = await database;
    await db.delete('workers', where: 'id = ?', whereArgs: [id]);
  }

  // ── Clients CRUD ──────────────────────────────────────────
  Future<List<Client>> getAllClients() async {
    final db   = await database;
    final rows = await db.query('clients', orderBy: 'created_at DESC');
    return rows.map((r) => Client.fromMap(r, r['id'] as String)).toList();
  }

  Future<void> insertClient(Client c) async {
    final db = await database;
    await db.insert('clients', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateClient(Client c) async {
    final db = await database;
    await db.update('clients', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<void> deleteClient(String id) async {
    final db = await database;
    await db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  // ── Attendance CRUD ───────────────────────────────────────
  Future<List<Attendance>> getAllAttendance() async {
    final db   = await database;
    final rows = await db.query('attendance',
        orderBy: 'work_date DESC, created_at DESC');
    return Future.wait(rows.map((r) async {
      final map = Map<String, dynamic>.from(r);
      map['id_photo_path']      = await toAbsolute(map['id_photo_path']);
      map['id_photo_back_path'] = await toAbsolute(map['id_photo_back_path']);
      return Attendance.fromMap(map, map['id'] as String);
    }));
  }

  Future<void> insertAttendance(Attendance a) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(a.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    await db.insert('attendance', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAttendance(Attendance a) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(a.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    await db.update('attendance', map, where: 'id = ?', whereArgs: [a.id]);
  }

  Future<void> deleteAttendance(String id) async {
    final db = await database;
    await db.delete('attendance', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> settleAttendance(String id) async {
    final db = await database;
    await db.update('attendance', {'is_settled': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── DB 백업 (WAL 체크포인트 후 파일 복사) ─────────────────
  Future<String> get dbPath async {
    final base = await getApplicationDocumentsDirectory();
    return p.join(base.path, _dataFolder, _dbName);
  }

  Future<bool> backupDbTo(String destFolderPath,
      {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final accessible = await Directory(destFolderPath)
          .exists()
          .timeout(timeout, onTimeout: () => false);
      if (!accessible) return false;

      final destDataDir = Directory(p.join(destFolderPath, _dataFolder));
      if (!await destDataDir.exists()) {
        await destDataDir.create(recursive: true);
      }

      final srcPath  = await dbPath;
      final destPath = p.join(destDataDir.path, _dbName);

      final db = await database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      await File(srcPath).copy(destPath).timeout(timeout);
      return true;
    } catch (e) {
      print('DB 백업 실패 ($destFolderPath): $e');
      return false;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
