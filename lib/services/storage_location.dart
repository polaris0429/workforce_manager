import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageLocation {
  static const preferenceKey = 'primary_data_directory';
  static Future<void> _pending = Future<void>.value();

  static Future<String> get dataDirectory async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(preferenceKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return p.join(
        (await getApplicationDocumentsDirectory()).path, 'woosin_data');
  }

  /// 저장 작업과 백업이 진행 중일 때 경로가 바뀌지 않도록 순서대로 실행합니다.
  static Future<T> withLock<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
