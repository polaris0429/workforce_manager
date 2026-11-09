import 'dart:async';
import 'storage_location.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'backup_file.dart';

enum BackupPathStatus { ok, pending, unknown }

class BackupService {
  static const String _pendingQueueKey = 'backup_pending_paths';
  static const Duration _pathTimeout   = Duration(seconds: 3);

  final DatabaseService _db = DatabaseService();

  final Map<String, BackupPathStatus> _statusMap = {};
  Map<String, BackupPathStatus> get statusMap => Map.unmodifiable(_statusMap);

  final _statusCtrl = StreamController<Map<String, BackupPathStatus>>.broadcast();
  Stream<Map<String, BackupPathStatus>> get statusStream => _statusCtrl.stream;

  void dispose() {
    if (!_statusCtrl.isClosed) _statusCtrl.close();
  }

  // ── 기본 저장경로 반환 (settings_screen 표시용) ───────────
  Future<String> get localDataPath async {
    final dbSvc = DatabaseService();
    return p.dirname(await dbSvc.dbPath);
  }

  // ── 경로 접근 가능 여부 ───────────────────────────────────
  Future<bool> _isAccessible(String path) async {
    try {
      return await Directory(path)
          .exists()
          .timeout(_pathTimeout, onTimeout: () => false);
    } catch (_) { return false; }
  }

  // ── 미완료 큐 ─────────────────────────────────────────────
  Future<Set<String>> getPendingPaths() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingQueueKey) ?? []).toSet();
  }

  // Called under StorageLocation.withLock before local mutations.
  Future<void> markPending(Iterable<String> paths) async {
    final pending = await getPendingPaths();
    pending.addAll(paths.where((s) => s.isNotEmpty));
    await _savePending(pending);
    for (final path in paths) { _setStatus(path, BackupPathStatus.pending); }
  }
  Future<void> _savePending(Set<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_pendingQueueKey, paths.toList())) {
      throw StateError('Cannot persist backup queue');
    }
  }
  Future<void> retainPaths(Iterable<String> paths) async {
    await _savePending((await getPendingPaths()).intersection(paths.toSet()));
    _statusMap.removeWhere((key, _) => !paths.contains(key));
  }

  void _setStatus(String path, BackupPathStatus s) {
    _statusMap[path] = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(Map.unmodifiable(_statusMap));
  }

  Future<void> backupAll({required List<String> backupPaths}) =>
      StorageLocation.withLock(() => _backupPaths(backupPaths.toSet()));

  Future<void> retryPending({List<String>? backupPaths}) => StorageLocation.withLock(() async {
    var paths = await getPendingPaths();
    if (backupPaths != null) paths = paths.intersection(backupPaths.toSet());
    await _backupPaths(paths);
  });

  Future<void> _backupPaths(Set<String> paths) async {
    await markPending(paths);
    for (final path in paths.where((s) => s.isNotEmpty)) {
      try {
        await validateDestination(path);
        await _backupImages(path);
        if (!await _db.backupDbTo(path)) throw StateError('DB backup failed');
        final pending = await getPendingPaths();
        pending.remove(path);
        await _savePending(pending);
        _setStatus(path, BackupPathStatus.ok);
      } catch (_) { _setStatus(path, BackupPathStatus.pending); }
    }
  }

  Future<void> validateDestination(String root) async {
    if (!await _isAccessible(root)) throw FileSystemException('백업 경로에 접근할 수 없습니다.', root);
    final source = await Directory(await localDataPath).resolveSymbolicLinks();
    final canonicalRoot = await Directory(root).resolveSymbolicLinks().timeout(_pathTimeout);
    var destination = p.join(canonicalRoot, 'woosin_data');
    if (await Directory(destination).exists().timeout(_pathTimeout)) {
      destination = await Directory(destination).resolveSymbolicLinks().timeout(_pathTimeout);
    }
    if (p.equals(source, destination) || p.isWithin(source, destination) || p.isWithin(destination, source)) {
      throw StateError('기본 저장경로와 겹치는 폴더는 백업 경로로 사용할 수 없습니다.');
    }
  }

  Future<void> _backupImages(String root) async {
    final source = Directory(p.join(await localDataPath, 'images'));
    if (!await source.exists()) return;
    final target = Directory(p.join(root, 'woosin_data', 'images'));
    await target.create(recursive: true).timeout(_pathTimeout);
    await for (final entity in source.list(recursive: true, followLinks: false)) {
      if (entity is Link) throw FileSystemException('사진 폴더의 연결 파일은 백업할 수 없습니다.', entity.path);
      if (entity is! File) continue;
      final dest = File(p.join(target.path, p.relative(entity.path, from: source.path)));
      if (await BackupFile.sameContents(entity, dest)) continue;
      await BackupFile.replace(entity, dest);
    }
  }
}
