import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ImageHelper {
  // 기본 저장 루트: Documents/woosin_data/images/
  static const String _dataFolder  = 'woosin_data';
  static const String _imageFolder = 'images';

  /// Documents/woosin_data/images/{workerName}/ 폴더 반환 (없으면 생성)
  /// [workerName] 이 비어있으면 images/ 바로 아래에 저장 (폴백)
  static Future<String> _getWorkerImageDir(String workerName) async {
    final docDir = await getApplicationDocumentsDirectory();

    // 폴더명으로 사용할 수 없는 문자 제거 (\/:*?"<>|)
    final safeName = workerName.trim().isEmpty
        ? '_unknown'
        : workerName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    final dirPath = p.join(docDir.path, _dataFolder, _imageFolder, safeName);
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dirPath;
  }

  /// 이미지를 근로자 폴더로 복사하고 저장된 경로 반환
  /// [workerName] : 근로자 이름 (폴더명으로 사용)
  static Future<String> saveImageLocally(
    File sourceFile, {
    String workerName = '',
  }) async {
    final saveDir = await _getWorkerImageDir(workerName);
    final ts       = DateTime.now().millisecondsSinceEpoch;
    final ext      = p.extension(sourceFile.path);
    final fileName = '${ts}$ext';
    final newPath  = p.join(saveDir, fileName);
    await sourceFile.copy(newPath);
    return newPath;
  }

  /// 저장된 경로의 File 반환 (없으면 null)
  static File? getFileFromPath(String? path) {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// 구버전 경로(workforce_images/) 에 있는 파일을
  /// 새 경로(woosin_data/images/{workerName}/)로 마이그레이션
  /// provider 초기화 후 근로자 목록이 확보된 시점에 호출하면 됨
  static Future<void> migrateOldImages({
    required List<Map<String, String>> workers, // [{id, name, front, back}, ...]
  }) async {
    final docDir    = await getApplicationDocumentsDirectory();
    final oldRoot   = p.join(docDir.path, 'workforce_images');

    for (final w in workers) {
      final name  = w['name'] ?? '';
      final front = w['front'];
      final back  = w['back'];

      for (final oldPath in [front, back]) {
        if (oldPath == null || oldPath.isEmpty) continue;
        // 이미 새 경로(woosin_data/images/...)에 있으면 스킵
        if (oldPath.contains(p.join(_dataFolder, _imageFolder))) continue;
        // 구 경로(workforce_images/)에 있으면 이동
        if (!oldPath.contains(oldRoot)) continue;

        final oldFile = File(oldPath);
        if (!await oldFile.exists()) continue;

        final newPath = await saveImageLocally(oldFile, workerName: name);
        print('📦 이미지 마이그레이션: $oldPath → $newPath');
        // 이동 완료 후 구 파일 삭제 (선택 — 안전하게 일단 남겨둠)
        // await oldFile.delete();
      }
    }
  }
}
