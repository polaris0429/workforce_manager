// 이 파일은 더 이상 사용하지 않습니다.
// KoreanTextEditingController는 Windows 한글 IME와 충돌하여
// 글자가 중복 입력되는 문제를 유발합니다.
// 삭제하지 않고 비워두어 import 오류를 방지합니다.

import 'package:flutter/material.dart';

// 하위 호환을 위해 일반 TextEditingController를 그대로 re-export
typedef KoreanTextEditingController = TextEditingController;
