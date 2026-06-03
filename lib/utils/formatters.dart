import 'package:flutter/services.dart';

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {

    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    String formatted;
    if (digits.length <= 3) {
      formatted = digits;
    } else if (digits.startsWith('02')) {
      // 서울 지역번호: 02-XXXX-XXXX (2-4-4) 또는 02-XXX-XXXX (2-3-4)
      if (digits.length <= 5) {
        formatted = '${digits.substring(0, 2)}-${digits.substring(2)}';
      } else if (digits.length <= 9) {
        formatted = '${digits.substring(0, 2)}-${digits.substring(2, 5)}-${digits.substring(5)}';
      } else {
        formatted = '${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6, digits.length.clamp(0, 10))}';
      }
    } else if (digits.length <= 7) {
      formatted = '${digits.substring(0, 3)}-${digits.substring(3)}';
    } else if (digits.length <= 10) {
      // 3-3-4
      formatted = '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    } else {
      // 3-4-4 (휴대폰 010-XXXX-XXXX)
      formatted = '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, digits.length.clamp(0, 11))}';
    }

    return TextEditingValue(
      text:      formatted,
      // 커서 항상 맨 끝 + composing 초기화 → 한글 IME 커서 앞 깜빡임 방지
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }

  static String format(String text) {
    if (text.isEmpty) return '';
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('02')) {
      if (digits.length == 9)  return '${digits.substring(0, 2)}-${digits.substring(2, 5)}-${digits.substring(5)}';
      if (digits.length == 10) return '${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    if (digits.length == 10) return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    if (digits.length == 11) return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    return digits;
  }
}
