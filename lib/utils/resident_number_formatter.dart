import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────
// 주민등록번호 자동 대시 포맷터
// 앞 6자리 입력 후 자동으로 '-' 삽입: 900101-1234567
// composing: TextRange.empty → 한글 IME 커서 앞 깜빡임 방지
// ─────────────────────────────────────────────────────────────
class ResidentNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final len    = digits.length.clamp(0, 13);
    final d      = digits.substring(0, len);

    final formatted = d.length <= 6 ? d : '${d.substring(0, 6)}-${d.substring(6)}';

    return TextEditingValue(
      text:      formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty, // IME composing 범위 초기화 → 커서 위치 안정화
    );
  }

  static String format(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length <= 6) return d;
    return '${d.substring(0, 6)}-${d.substring(6)}';
  }

  static String strip(String formatted) =>
      formatted.replaceAll(RegExp(r'\D'), '');
}
