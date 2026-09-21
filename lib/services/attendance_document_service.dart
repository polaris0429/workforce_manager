import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/attendance.dart';
import '../utils/formatters.dart';
import '../utils/resident_number_formatter.dart';
import 'storage_location.dart';

class AttendanceDocumentService {
  static String buildHtml(Attendance record) {
    String text(String value) =>
        htmlEscape.convert(value.trim().isEmpty ? '—' : value);
    String row(String label, String value) =>
        '<tr><th scope="row">$label</th><td>${text(value)}</td></tr>';
    final date = DateFormat('yyyy년 MM월 dd일').format(record.workDate);
    final wage =
        '${NumberFormat('#,##0.##', 'ko_KR').format(record.dailyWage)}원';
    // 문서에 허용된 항목만 명시적으로 출력합니다. 수수료 및 차감액은 출력하지 않습니다.
    return '''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>근로내역 확인서 · ${text(record.workerName)} · $date</title>
<style>
* { box-sizing: border-box; }
body { margin: 0; background: #eef1f5; color: #182230; font-family: "Malgun Gothic", "Apple SD Gothic Neo", sans-serif; font-size: 14px; line-height: 1.6; }
.toolbar { max-width: 210mm; margin: 24px auto 16px; display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 0 16px; }
.toolbar p { margin: 0; color: #526071; font-size: 13px; }
button { padding: 11px 20px; border: 0; border-radius: 6px; background: #2456a6; color: white; font: inherit; font-weight: bold; cursor: pointer; white-space: nowrap; }
button:focus-visible { outline: 3px solid #7297d1; outline-offset: 3px; }
main { width: min(210mm, 100%); margin: 0 auto 32px; padding: 16mm; background: white; box-shadow: 0 4px 20px #18223012; }
header { border-bottom: 2px solid #243b55; padding-bottom: 20px; margin-bottom: 24px; }
h1 { margin: 0 0 6px; font-size: 28px; letter-spacing: 2px; }
header p { margin: 0; color: #526071; }
section { margin-top: 22px; }
h2 { margin: 0 0 8px; font-size: 16px; }
table { width: 100%; border-collapse: collapse; table-layout: fixed; }
th, td { border: 1px solid #d2d8e0; padding: 8px 12px; vertical-align: top; overflow-wrap: anywhere; white-space: pre-wrap; }
th { width: 25%; text-align: left; background: #f3f5f8; color: #3d4c60; font-weight: 600; }
.work th { width: auto; text-align: center; }
.work td { text-align: center; }
.work td:last-child { font-weight: bold; }
tr { break-inside: avoid; }
h2 { break-after: avoid; }
@page { size: A4; margin: 15mm; }
@media print {
  body { background: white; font-size: 10pt; color: black; }
  .toolbar { display: none !important; }
  main { width: 100%; margin: 0; padding: 0; box-shadow: none; }
  header { margin-bottom: 16px; padding-bottom: 12px; }
  h1 { font-size: 22pt; }
  section { margin-top: 16px; }
  th, td { padding: 6px 10px; }
}
@media screen and (max-width: 600px) {
  main { padding: 20px; }
  .toolbar { align-items: flex-start; flex-direction: column; }
}
</style>
</head>
<body>
<div class="toolbar">
  <p>인쇄 창에서 프린터 또는 ‘PDF로 저장’을 선택하세요.<br>주소·파일 경로가 필요 없으면 인쇄 설정의 ‘머리글과 바닥글’을 꺼주세요.</p>
  <button type="button" onclick="window.print()">인쇄 / PDF로 저장</button>
</div>
<main>
<header><h1>근로내역 확인서</h1><p>$date</p></header>
<section aria-labelledby="worker-heading">
<h2 id="worker-heading">근로자 정보</h2>
<table><tbody>
${row('성명', record.workerName)}
${row('성별', record.workerGender)}
${row('주민등록번호', ResidentNumberFormatter.format(record.workerResidentNumber))}
${row('휴대폰번호', PhoneInputFormatter.format(record.workerPhone))}
${row('집전화번호', PhoneInputFormatter.format(record.workerHomePhone))}
${row('주소', record.workerAddress)}
${row('은행명', record.workerBankName)}
${row('계좌번호', record.workerBankAccount)}
</tbody></table>
</section>
<section aria-labelledby="client-heading">
<h2 id="client-heading">근무지 정보</h2>
<table><tbody>
${row('거래처명', record.clientName)}
${row('현장 주소', record.clientAddress)}
${row('담당자', record.clientContactPerson)}
${row('연락처', PhoneInputFormatter.format(record.clientPhone))}
${row('회사번호', PhoneInputFormatter.format(record.clientOfficePhone))}
${row('이메일', record.clientEmail)}
</tbody></table>
</section>
<section aria-labelledby="work-heading">
<h2 id="work-heading">근로 내역</h2>
<table class="work">
<thead><tr><th scope="col">근무일</th><th scope="col">급여</th></tr></thead>
<tbody><tr><td>$date</td><td>$wage</td></tr></tbody>
</table>
</section>
</main>
</body>
</html>''';
  }

  static Future<File> saveHtml(Attendance record) =>
      StorageLocation.withLock(() async {
        final directory = Directory(p.join(
            await StorageLocation.dataDirectory, 'documents', 'attendance'));
        await directory.create(recursive: true);
        final date = DateFormat('yyyyMMdd').format(record.workDate);
        final file = File(p.join(directory.path,
            '근로내역서_${date}_${DateTime.now().microsecondsSinceEpoch}.html'));
        await file.writeAsString(buildHtml(record),
            encoding: utf8, flush: true);
        return file;
      });
}
