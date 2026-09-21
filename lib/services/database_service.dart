import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_location.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/worker.dart';
import '../models/client.dart';
import '../models/attendance.dart';

class DatabaseService {
  static const String _dbName     = 'woosin_data.db';
  static const String _dataFolder = 'woosin_data';
  // 버전 2: worker.home_phone, client.office_phone,
  //         attendance 거래처 상세 컬럼 추가
  static const int    _dbVersion  = 3;

  static DatabaseService? _instance;
  static Database?        _db;

  DatabaseService._();
  factory DatabaseService() {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dir = Directory(await StorageLocation.dataDirectory);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(StorageLocation.preferenceKey) != null &&
        !await File(p.join(dir.path, _dbName)).exists()) {
      throw FileSystemException('설정한 저장 위치의 데이터베이스에 접근할 수 없습니다.', dir.path);
    }
    if (!await dir.exists()) await dir.create(recursive: true);

    final dbPath = p.join(dir.path, _dbName);
    return _openDb(dbPath);
  }

  Future<Database> _openDb(String dbPath) {
    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version:  _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          await db.execute('PRAGMA journal_mode=WAL;');
          await db.execute('PRAGMA foreign_keys=ON;');
        },
      ),
    );
  }

  // ── 최초 생성 (v3 스키마) ─────────────────────────────────
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE workers (
        id                 TEXT PRIMARY KEY,
        name               TEXT NOT NULL,
        gender             TEXT NOT NULL DEFAULT '',
        resident_number    TEXT NOT NULL DEFAULT '',
        address            TEXT NOT NULL DEFAULT '',
        phone              TEXT NOT NULL,
        home_phone         TEXT NOT NULL DEFAULT '',
        bank_name          TEXT NOT NULL DEFAULT '',
        bank_account       TEXT NOT NULL DEFAULT '',
        career             TEXT NOT NULL DEFAULT '',
        notes              TEXT NOT NULL DEFAULT '',
        id_photo_path      TEXT,
        id_photo_back_path TEXT,
        safety_training_photo_path TEXT,
        health_certificate_photo_path TEXT,
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
        office_phone    TEXT NOT NULL DEFAULT '',
        email           TEXT NOT NULL DEFAULT '',
        notes           TEXT NOT NULL DEFAULT '',
        created_at      TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance (
        id                       TEXT PRIMARY KEY,
        worker_id                TEXT,
        worker_name              TEXT NOT NULL,
        worker_gender            TEXT NOT NULL DEFAULT '',
        worker_resident_number   TEXT NOT NULL DEFAULT '',
        worker_phone             TEXT NOT NULL DEFAULT '',
        worker_home_phone        TEXT NOT NULL DEFAULT '',
        worker_address           TEXT NOT NULL DEFAULT '',
        worker_bank_name         TEXT NOT NULL DEFAULT '',
        worker_bank_account      TEXT NOT NULL DEFAULT '',
        worker_career            TEXT NOT NULL DEFAULT '',
        client_id                TEXT,
        client_name              TEXT NOT NULL,
        client_address           TEXT NOT NULL DEFAULT '',
        client_contact_person    TEXT NOT NULL DEFAULT '',
        client_phone             TEXT NOT NULL DEFAULT '',
        client_office_phone      TEXT NOT NULL DEFAULT '',
        client_email             TEXT NOT NULL DEFAULT '',
        client_notes             TEXT NOT NULL DEFAULT '',
        work_date                TEXT NOT NULL,
        daily_wage               REAL NOT NULL DEFAULT 0,
        commission_rate          REAL NOT NULL DEFAULT 0,
        commission               REAL NOT NULL DEFAULT 0,
        net_wage                 REAL NOT NULL DEFAULT 0,
        notes                    TEXT NOT NULL DEFAULT '',
        id_photo_path            TEXT,
        id_photo_back_path       TEXT,
        safety_training_photo_path       TEXT,
        health_certificate_photo_path       TEXT,
        is_postpaid              INTEGER NOT NULL DEFAULT 0,
        is_settled               INTEGER NOT NULL DEFAULT 1,
        created_at               TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_workers_name       ON workers(name)');
    await db.execute('CREATE INDEX idx_attendance_date    ON attendance(work_date)');
    await db.execute('CREATE INDEX idx_attendance_settled ON attendance(is_settled)');
  }

  // ── v1 → v2 마이그레이션 ─────────────────────────────────
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // workers: address 순서 변경은 ALTER로 불가 → 새 컬럼만 추가
      await db.execute("ALTER TABLE workers ADD COLUMN home_phone TEXT NOT NULL DEFAULT ''");

      // clients: 회사번호
      await db.execute("ALTER TABLE clients ADD COLUMN office_phone TEXT NOT NULL DEFAULT ''");

      // attendance: 새 컬럼들
      await db.execute("ALTER TABLE attendance ADD COLUMN worker_home_phone      TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE attendance ADD COLUMN client_contact_person  TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE attendance ADD COLUMN client_phone           TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE attendance ADD COLUMN client_office_phone    TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE attendance ADD COLUMN client_email           TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE attendance ADD COLUMN client_notes           TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 3) {
      for (final table in ['workers', 'attendance']) {
        await db.execute('ALTER TABLE $table ADD COLUMN safety_training_photo_path TEXT');
        await db.execute('ALTER TABLE $table ADD COLUMN health_certificate_photo_path TEXT');
      }
    }
  }

  // ── 이미지 경로 변환 ──────────────────────────────────────
  Future<String> get _dataFolderPath => StorageLocation.dataDirectory;

  Future<String?> toRelative(String? absPath) async {
    if (absPath == null || absPath.isEmpty) return null;
    if (!p.isAbsolute(absPath)) return absPath;
    final base = await _dataFolderPath;
    if (p.isWithin(base, absPath)) {
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
      map['safety_training_photo_path'] = await toAbsolute(map['safety_training_photo_path']);
      map['health_certificate_photo_path'] = await toAbsolute(map['health_certificate_photo_path']);
      return Worker.fromMap(map, map['id'] as String);
    }));
  }

  Future<void> insertWorker(Worker w) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(w.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    map['safety_training_photo_path'] = await toRelative(map['safety_training_photo_path'] as String?);
    map['health_certificate_photo_path'] = await toRelative(map['health_certificate_photo_path'] as String?);
    await db.insert('workers', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateWorker(Worker w) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(w.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    map['safety_training_photo_path'] = await toRelative(map['safety_training_photo_path'] as String?);
    map['health_certificate_photo_path'] = await toRelative(map['health_certificate_photo_path'] as String?);
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
    final rows = await db.query('attendance', orderBy: 'work_date DESC, created_at DESC');
    return Future.wait(rows.map((r) async {
      final map = Map<String, dynamic>.from(r);
      map['id_photo_path']      = await toAbsolute(map['id_photo_path']);
      map['id_photo_back_path'] = await toAbsolute(map['id_photo_back_path']);
      map['safety_training_photo_path'] = await toAbsolute(map['safety_training_photo_path']);
      map['health_certificate_photo_path'] = await toAbsolute(map['health_certificate_photo_path']);
      return Attendance.fromMap(map, map['id'] as String);
    }));
  }

  Future<void> insertAttendance(Attendance a) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(a.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    map['safety_training_photo_path'] = await toRelative(map['safety_training_photo_path'] as String?);
    map['health_certificate_photo_path'] = await toRelative(map['health_certificate_photo_path'] as String?);
    await db.insert('attendance', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAttendance(Attendance a) async {
    final db  = await database;
    final map = Map<String, dynamic>.from(a.toMap());
    map['id_photo_path']      = await toRelative(map['id_photo_path'] as String?);
    map['id_photo_back_path'] = await toRelative(map['id_photo_back_path'] as String?);
    map['safety_training_photo_path'] = await toRelative(map['safety_training_photo_path'] as String?);
    map['health_certificate_photo_path'] = await toRelative(map['health_certificate_photo_path'] as String?);
    await db.update('attendance', map, where: 'id = ?', whereArgs: [a.id]);
  }

  Future<void> deleteAttendance(String id) async {
    final db = await database;
    await db.delete('attendance', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> settleAttendance(String id) async {
    final db = await database;
    await db.update('attendance', {'is_settled': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ── DB 백업 ───────────────────────────────────────────────
  Future<String> get dbPath async => p.join(await StorageLocation.dataDirectory, _dbName);

  Future<bool> backupDbTo(String destFolderPath,
      {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final accessible = await Directory(destFolderPath)
          .exists()
          .timeout(timeout, onTimeout: () => false);
      if (!accessible) return false;

      final destDataDir = Directory(p.join(destFolderPath, _dataFolder));
      if (!await destDataDir.exists()) await destDataDir.create(recursive: true);

      final srcPath  = await dbPath;
      final destPath = p.join(destDataDir.path, _dbName);
      if (p.equals(p.normalize(srcPath), p.normalize(destPath))) return true;

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

  /// 호출자는 StorageLocation.withLock 안에서 실행해야 합니다.
  /// 복사 및 검증이 끝난 후에만 새 경로를 적용하며 원본은 보존합니다.
  Future<void> changeDataDirectory(String selectedFolder) async {
    final prefs = await SharedPreferences.getInstance();
    final previousSetting = prefs.getString(StorageLocation.preferenceKey);
    final selected = await Directory(selectedFolder).resolveSymbolicLinks();
    final source = Directory(await StorageLocation.dataDirectory);
    await database;
    final sourcePath = await source.resolveSymbolicLinks();
    var targetPath = p.basename(selected).toLowerCase() == _dataFolder
        ? selected : p.join(selected, _dataFolder);
    final target = Directory(targetPath);
    if (await target.exists()) targetPath = await target.resolveSymbolicLinks();
    if (p.equals(sourcePath, targetPath)) return;
    if (p.isWithin(sourcePath, targetPath) || p.isWithin(targetPath, sourcePath)) {
      throw StateError('현재 저장 폴더와 겹치지 않는 다른 폴더를 선택해주세요.');
    }
    if (await target.exists() && !await target.list().isEmpty) {
      throw StateError('선택한 위치의 woosin_data 폴더에 파일이 있습니다. 빈 폴더를 선택해주세요.');
    }
    final staging = await Directory(p.dirname(targetPath)).createTemp('.woosin_transfer_');
    Database? copiedDb;
    var switched = false;
    try {
      // close flushes the WAL, so the copied database is a complete snapshot.
      await close();
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: source.path);
        final destination = p.join(staging.path, relative);
        if (entity is Directory) {
          await Directory(destination).create(recursive: true);
        } else if (entity is File) {
          if (relative == '$_dbName-wal' || relative == '$_dbName-shm') continue;
          await Directory(p.dirname(destination)).create(recursive: true);
          final copy = await entity.copy(destination);
          if (await copy.length() != await entity.length()) {
            throw FileSystemException('파일 복사 확인에 실패했습니다.', entity.path);
          }
        } else {
          throw FileSystemException('연결된 폴더나 파일이 있어 저장 경로를 변경할 수 없습니다.', entity.path);
        }
      }
      copiedDb = await _openDb(p.join(staging.path, _dbName));
      final check = await copiedDb.rawQuery('PRAGMA quick_check');
      if (check.length != 1 || check.single.values.single != 'ok') {
        throw StateError('복사한 데이터베이스 검사에 실패했습니다.');
      }
      // 구버전에서 절대 경로로 저장된 사진도 새 폴더를 참조하게 합니다.
      await copiedDb.transaction((txn) async {
        for (final table in ['workers', 'attendance']) {
          for (final row in await txn.query(table)) {
            final changes = <String, Object?>{};
            for (final key in ['id_photo_path', 'id_photo_back_path',
              'safety_training_photo_path', 'health_certificate_photo_path']) {
              final value = row[key];
              if (value is String && p.isAbsolute(value)) {
                for (final base in [source.path, sourcePath]) {
                  if (p.isWithin(base, value)) {
                    changes[key] = p.relative(value, from: base).replaceAll('\\', '/');
                    break;
                  }
                }
              }
            }
            if (changes.isNotEmpty) {
              await txn.update(table, changes, where: 'id = ?', whereArgs: [row['id']]);
            }
          }
        }
      });
      await copiedDb.close();
      copiedDb = null;
      if (await target.exists()) await target.delete(); // 검증한 빈 폴더만 제거
      await staging.rename(targetPath);
      copiedDb = await _openDb(p.join(targetPath, _dbName));
      if (!await prefs.setString(StorageLocation.preferenceKey, targetPath)) {
        if (previousSetting == null) {
          await prefs.remove(StorageLocation.preferenceKey);
        } else {
          await prefs.setString(StorageLocation.preferenceKey, previousSetting);
        }
        throw StateError('새 저장 경로 설정을 저장하지 못했습니다.');
      }
      _db = copiedDb;
      copiedDb = null;
      switched = true;
    } finally {
      await copiedDb?.close();
      if (!switched) _db = await _initDb();
      // 이 작업에서 생성한 임시 폴더만 정리합니다. 기존/새 데이터 폴더는 보존합니다.
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
