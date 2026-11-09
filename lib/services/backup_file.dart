import 'dart:io';

/// 복사는 새 임시 파일에만 수행합니다. 시간 초과된 복사가 늦게 끝나더라도
/// 사용 중인 백업 파일을 덮어쓰지 않습니다.
class BackupFile {
  static int _sequence = 0;

  static Future<void> replace(File source, File destination, {
    Duration timeout = const Duration(seconds: 10),
    Future<void> Function(File)? validate,
    bool keepPrevious = false,
  }) async {
    await destination.parent.create(recursive: true).timeout(timeout);
    final staging = File('${destination.path}.${DateTime.now().microsecondsSinceEpoch}-${_sequence++}.tmp');
    Future<File>? copying;
    try {
      copying = source.copy(staging.path);
      await copying.timeout(timeout);
      final handle = await staging.open(mode: FileMode.append).timeout(timeout);
      try { await handle.flush().timeout(timeout); } finally { await handle.close(); }
      if (await source.length() != await staging.length().timeout(timeout)) {
        throw FileSystemException('백업 파일 크기 확인 실패', destination.path);
      }
      if (validate != null) await validate(staging).timeout(timeout);
      if (keepPrevious && await destination.exists().timeout(timeout)) {
        // 직전 정상 DB를 남겨 교체 중 중단에도 복구 가능한 사본을 유지합니다.
        var valid = true;
        if (validate != null) {
          try { await validate(destination).timeout(timeout); } catch (_) { valid = false; }
        }
        if (valid) {
          await replace(destination, File('${destination.path}.previous'),
              timeout: timeout, validate: validate);
        }
      }
      // 같은 디렉터리에서 완료된 파일을 교체합니다. 기존 파일을 먼저 삭제하지 않습니다.
      await staging.rename(destination.path);
    } finally {
      if (copying != null) {
        // Future.timeout은 원래 I/O를 취소하지 않으므로 완료 후 정리합니다.
        copying.then((_) => _removeTemporary(staging), onError: (Object _) async {
          await _removeTemporary(staging);
        });
      } else {
        await _removeTemporary(staging);
      }
    }
  }

  static Future<void> _removeTemporary(File file) async {
    try { if (await file.exists()) await file.delete(); } catch (_) {}
  }

  static Future<bool> sameContents(File source, File destination,
      {Duration timeout = const Duration(seconds: 3)}) async {
    if (!await destination.exists().timeout(timeout)) return false;
    if (await source.length() != await destination.length().timeout(timeout)) return false;
    final a = await source.open();
    RandomAccessFile? b;
    try {
      b = await destination.open().timeout(timeout);
      while (true) {
        final left = await a.read(65536);
        final right = await b.read(left.length).timeout(timeout);
        if (left.length != right.length) return false;
        for (var i = 0; i < left.length; i++) {
          if (left[i] != right[i]) return false;
        }
        if (left.isEmpty) return true;
      }
    } finally { await a.close(); await b?.close(); }
  }
}
