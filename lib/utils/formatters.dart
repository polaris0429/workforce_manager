import 'package:flutter/services.dart';

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    
    // 1. 숫자만 추출
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    
    // 2. 길이에 따라 포맷팅 적용
    // 01012341234 -> 010-1234-1234 (11자)
    // 0311231234 -> 031-123-1234 (10자)
    // 0212341234 -> 02-1234-1234 (10자, 서울)
    
    String formattedText = '';
    if (text.length <= 3) {
      formattedText = text;
    } else if (text.length <= 6) {
      formattedText = '${text.substring(0, 3)}-${text.substring(3)}';
      // 서울(02) 예외 처리 등은 필요 시 추가 가능하나, 
      // 일반적인 모바일/지역번호 로직(3자리 시작) 기준으로 작성
      if (text.startsWith('02') && text.length > 2) {
         // 02-xxxx 형식 대응은 로직이 복잡해지므로 
         // 여기서는 요청하신 3-3-4 / 3-4-4 위주로 처리
      }
    } else if (text.length <= 10) {
      // 10자리 이하일 때 (031-123-1234 등)
      // 보통 3-3-4 포맷
       formattedText = '${text.substring(0, 3)}-${text.substring(3, 6)}-${text.substring(6)}';
    } else {
      // 11자리 (010-1234-1234)
      formattedText = '${text.substring(0, 3)}-${text.substring(3, 7)}-${text.substring(7, text.length > 11 ? 11 : text.length)}';
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
  
  // DB에서 가져온 숫자 문자열을 화면 표시용으로 변환하는 정적 메서드
  static String format(String text) {
    if (text.isEmpty) return '';
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
       return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else if (digits.length == 10) {
       // 02로 시작하는지 체크하여 02-1234-5678 or 031-123-4567 구분 가능
       if (digits.startsWith('02')) {
         return '${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6)}';
       }
       return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return digits;
  }
}