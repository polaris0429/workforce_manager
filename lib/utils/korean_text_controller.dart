import 'package:flutter/material.dart';

/// 한글 IME composing 범위를 항상 빈 범위로 유지하는 컨트롤러.
///
/// Windows 한글 IME는 글자 조합 중(ㅇ+ㅣ → '이') composing 범위를
/// [0, 1] 같이 설정해서 커서가 입력 중인 글자 앞에 표시된다.
/// 이 컨트롤러는 value 변경 시 composing을 항상 TextRange.empty로
/// 강제해서 커서가 항상 맨 끝(또는 사용자가 선택한 위치)에 있게 한다.
class KoreanTextEditingController extends TextEditingController {
  KoreanTextEditingController({super.text});

  @override
  set value(TextEditingValue newValue) {
    // composing 범위가 비어있지 않으면 비워서 커서를 텍스트 끝으로 고정
    if (!newValue.composing.isCollapsed) {
      super.value = newValue.copyWith(composing: TextRange.empty);
    } else {
      super.value = newValue;
    }
  }
}
