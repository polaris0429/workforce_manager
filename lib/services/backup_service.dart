import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

// ─────────────────────────────────────────────────────────────
// 백업 경로 상태
// ─────────────────────────────────────────────────────────────
enum BackupPathStatus { ok, pending, unknown }

class BackupService {
  static const String _pendingQueueKey = 'backup_pending_paths';
  static const Duration _pathTimeout   = Duration(seconds: 3);

  final DatabaseService _db = DatabaseService();

  // 경로별 상태 캐시 (런타임 UI 표시용)
  final Map<String, BackupPathStatus> _statusMap = {};
  Map<String, BackupPathStatus> get statusMap => Map.unmodifiable(_statusMap);

  final _statusCtrl = StreamController<Map<String, BackupPathStatus>>.broadcast();
  Stream<Map<String, BackupPathStatus>> get statusStream => _statusCtrl.stream;

  void dispose() => _statusCtrl.close();

  // ── 경로 접근 가능 여부 ───────────────────────────────────
  Future<bool> _isAccessible(String path) async {
    try {
      return await Directory(path).exists().timeout(_pathTimeout, onTimeout: () => false);
    } catch (_) { return false; }
  }

  // ── 미완료 큐 ─────────────────────────────────────────────
  Future<Set<String>> getPendingPaths() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingQueueKey) ?? []).toSet();
  }

  Future<void> _addPending(String path) async {
    final set = await getPendingPaths();
    set.add(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingQueueKey, set.toList());
    _setStatus(path, BackupPathStatus.pending);
  }

  Future<void> _removePending(String path) async {
    final set = await getPendingPaths();
    set.remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingQueueKey, set.toList());
    _setStatus(path, BackupPathStatus.ok);
  }

  void _setStatus(String path, BackupPathStatus s) {
    _statusMap[path] = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(Map.unmodifiable(_statusMap));
  }

  // ── 전체 백업 (DB 파일 복사 + 이미지 동기화) ─────────────
  Future<void> backupAll({required List<String> backupPaths}) async {
    if (backupPaths.isEmpty) return;
    await Future.wait(backupPaths.map((path) async {
      if (path.isEmpty) return;
      final ok = await _db.backupDbTo(path);
      if (ok) {
        await _backupImages(path);
        await _removePending(path);
      } else {
        await _addPending(path);
      }
    }));
  }

  // ── 미완료 큐 재시도 ──────────────────────────────────────
  Future<void> retryPending() async {
    final pending = await getPendingPaths();
    if (pending.isEmpty) return;
    print('🔄 미완료 백업 재시도: ${pending.length}개');
    for (final path in pending.toList()) {
      final ok = await _db.backupDbTo(path);
      if (ok) {
        await _backupImages(path);
        await _removePending(path);
        print('✅ 재시도 성공: $path');
      } else {
        print('⏳ 재시도 실패 유지: $path');
      }
    }
  }

  // ── 이미지 폴더 동기화 ────────────────────────────────────
  // woosin_data/images/ → {dest}/woosin_data/images/ 로 증분 복사
  Future<void> _backupImages(String destRoot) async {
    try {
      if (!await _isAccessible(destRoot)) return;
      final dbService = DatabaseService();
      final srcBase   = p.dirname(await dbService.dbPath); // woosin_data/
      final srcImages = Directory(p.join(srcBase, 'images'));
      if (!await srcImages.exists()) return;

      final destImages = Directory(p.join(destRoot, 'woosin_data', 'images'));
      if (!await destImages.exists()) await destImages.create(recursive: true);

      await for (final entity in srcImages.list(recursive: true)) {
        if (entity is File) {
          final rel      = p.relative(entity.path, from: srcImages.path);
          final destFile = File(p.join(destImages.path, rel));
          if (!await destFile.parent.exists()) {
            await destFile.parent.create(recursive: true);
          }
          // 이미 같은 파일이면 스킵 (크기 비교)
          if (await destFile.exists() &&
              (await destFile.length()) == (await entity.length())) continue;
          await entity.copy(destFile.path).timeout(_pathTimeout);
        }
      }
    } catch (e) {
      print('이미지 백업 실패 ($destRoot): $e');
    }
  }

  // ── 이미지 단일 파일 백업 ─────────────────────────────────
  // 근로자 등록/수정 시 신분증 사진 즉시 백업
  Future<void> backupImage({
    required String localImagePath,
    required List<String> backupPaths,
  }) async {
    if (backupPaths.isEmpty) return;
    final srcFile = File(localImagePath);
    if (!await srcFile.exists()) return;

    final dbSvc  = DatabaseService();
    final base   = p.dirname(await dbSvc.dbPath); // woosin_data/
    final relPath = p.relative(localImagePath, from: base).replaceAll('\\', '/');

    await Future.wait(backupPaths.map((rootPath) async {
      if (rootPath.isEmpty) return;
      try {
        if (!await _isAccessible(rootPath)) return;
        final dest = File(p.join(rootPath, 'woosin_data', relPath.replaceAll('/', p.separator)));
        if (!await dest.parent.exists()) await dest.parent.create(recursive: true);
        await srcFile.copy(dest.path).timeout(_pathTimeout);
      } catch (e) {
        print('이미지 단일 백업 실패 ($rootPath): $e');
      }
    }));
  }
}
