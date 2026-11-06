import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:intl/intl.dart';
import '../models/attendance.dart';
import '../utils/formatters.dart';
import '../utils/resident_number_formatter.dart';
import '../utils/attendance_photos.dart';
import '../models/worker.dart';
import 'storage_location.dart';

class AttendanceDocumentService {
  static String buildHtml(Attendance record,
      {Map<String, String> photos = const {}}) {
    String text(String value) =>
        htmlEscape.convert(value.trim().isEmpty ? '—' : value);
    String row(String label, String value) =>
        '<tr><th scope="row">$label</th><td>${text(value)}</td></tr>';
    final date = DateFormat('yyyy년 MM월 dd일').format(record.workDate);
    final wage =
        '${NumberFormat('#,##0.##', 'ko_KR').format(record.dailyWage)}원';
    String option(String group, String label, List<String> keys) {
      final available = keys.any(photos.containsKey);
      return '<label><input type="checkbox" data-group="$group" ${available ? '' : 'disabled'}> '
          '$label${available ? '' : ' (등록된 사진 없음)'}</label>';
    }

    String photo(String key, String group, String label) {
      final source = photos[key];
      if (source == null) return '';
      return '<figure data-photo-group="$group" hidden><figcaption>$label</figcaption>'
          '<img src="${htmlEscape.convert(source)}" alt="$label"></figure>';
    }

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
.options { max-width: 210mm; margin: 0 auto 16px; padding: 14px 16px; background: white; border: 1px solid #d2d8e0; }
.options legend { font-weight: bold; }
.options label { display: inline-flex; align-items: center; gap: 4px; margin: 4px 18px 4px 0; cursor: pointer; }
.options input { width: 16px; height: 16px; accent-color: #2456a6; }
.options p { font-size: 12px; color: #526071; margin: 6px 0 0; }
[hidden] { display: none !important; }
.signature { margin-top: 24px; border-top: 1px solid #d2d8e0; padding-top: 12px; break-inside: avoid; }
.signature p { margin: 0 0 14px; }
.signature-line { text-align: right; min-height: 38px; }
.sign-space { display: inline-block; width: 65mm; border-bottom: 1px solid #526071; margin: 0 8px; height: 32px; vertical-align: bottom; }
.attachment-page { margin-top: 32px; display: flex; flex-direction: column; gap: 12px; }
.attachment-page h2, .attachment-page p { margin: 0; }
.photo-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); grid-auto-rows: auto; align-items: start; gap: 12px; }
.photo-grid[data-count="1"] { grid-template-columns: 1fr; }
.photo-grid figure { margin: 0; min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 6px; break-inside: avoid; }
.photo-grid figcaption { font-weight: bold; text-align: center; }
.photo-grid img { display: block; width: auto; height: auto; max-width: 100%; max-height: 100mm; padding: 4px; border: 1px solid #d2d8e0; object-fit: contain; }
.photo-grid[data-count="1"] img, .photo-grid[data-count="2"] img { max-height: 210mm; }
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
  .toolbar, .options { display: none !important; }
  main { width: 100%; margin: 0; padding: 0; box-shadow: none; }
  header { margin-bottom: 16px; padding-bottom: 12px; }
  h1 { font-size: 22pt; }
  section { margin-top: 16px; }
  th, td { padding: 6px 10px; }
  .attachment-page { break-before: page; page-break-before: always; break-inside: avoid; margin: 0; padding: 0; }
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
  <button type="button" id="print-button">인쇄 / PDF로 저장</button>
</div>
<fieldset class="options">
<legend>사진 첨부 (선택)</legend>
${option('id', '신분증 앞·뒷면', ['front', 'back'])}
${option('safety', '안전교육 이수증', ['safety'])}
${option('health', '보건증', ['health'])}
<p>기본은 포함 안함입니다. 선택한 사진은 확인서 다음 한 페이지에 모아 인쇄됩니다.</p>
</fieldset>
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
<section class="signature" aria-label="담당자 서명란">
<p>위 근로 내역을 확인합니다.</p>
<div class="signature-line">담당자 성명 및 서명<span class="sign-space"></span>(서명 또는 인)</div>
</section>
<section id="attachments" class="attachment-page" hidden aria-labelledby="attachment-heading">
<h2 id="attachment-heading">첨부 사진</h2>
<p>${text(record.workerName)} · $date</p>
<div class="photo-grid" id="photo-grid" data-count="0">
${photo('front', 'id', '신분증 앞면')}
${photo('back', 'id', '신분증 뒷면')}
${photo('safety', 'safety', '안전교육 이수증')}
${photo('health', 'health', '보건증')}
</div>
</section>
</main>
<script>
const choices = [...document.querySelectorAll('input[data-group]')];
function updateAttachments() {
  const groups = new Set(choices.filter(input => input.checked && !input.disabled).map(input => input.dataset.group));
  let count = 0;
  document.querySelectorAll('figure[data-photo-group]').forEach(figure => {
    figure.hidden = !groups.has(figure.dataset.photoGroup);
    if (!figure.hidden) count++;
  });
  document.getElementById('attachments').hidden = count === 0;
  document.getElementById('photo-grid').dataset.count = String(count);
}
choices.forEach(input => { input.checked = false; input.addEventListener('change', updateAttachments); });
updateAttachments();
window.addEventListener('beforeprint', updateAttachments);
document.getElementById('print-button').addEventListener('click', async () => {
  updateAttachments();
  const images = [...document.querySelectorAll('figure:not([hidden]) img')];
  await Promise.all(images.map(img => img.decode().catch(() => {})));
  window.print();
});
</script>
</body>
</html>''';
  }

  static HttpServer? _server;
  static final Map<String, String> _previews = {};

  /// HTML과 사진은 메모리에서만 제공하고 데이터 폴더에 문서를 생성하지 않습니다.
  static Future<Uri> openPreview(Attendance record,
          {Iterable<Worker> workers = const []}) =>
      StorageLocation.withLock(() async {
        final resolved = AttendancePhotos.resolve(record, workers);
        final photos = <String, String>{};
        for (final entry in {
          'front': resolved.front,
          'back': resolved.back,
          'safety': resolved.safetyTraining,
          'health': resolved.healthCertificate
        }.entries) {
          final data = await _imageData(entry.value);
          if (data != null) photos[entry.key] = data;
        }
        if (_server == null) {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          _server = server;
          server.listen((request) async {
            request.response.headers
                .set(HttpHeaders.cacheControlHeader, 'no-store');
            request.response.headers.set('X-Content-Type-Options', 'nosniff');
            request.response.headers.set('Referrer-Policy', 'no-referrer');
            request.response.headers.contentType = ContentType.html;
            final html = _previews[request.uri.path];
            if (request.method != 'GET' || html == null) {
              request.response.statusCode = HttpStatus.notFound;
              request.response
                  .write('<meta charset="utf-8">프로그램에서 인쇄 버튼을 다시 눌러주세요.');
            } else {
              request.response.write(html);
            }
            await request.response.close();
          });
        }
        final token = base64Url.encode(
            List<int>.generate(24, (_) => Random.secure().nextInt(256)));
        final path = '/preview/$token';
        _previews[path] = buildHtml(record, photos: photos);
        while (_previews.length > 8) {
          _previews.remove(_previews.keys.first);
        }
        return Uri(
            scheme: 'http', host: '127.0.0.1', port: _server!.port, path: path);
      });

  static Future<String?> _imageData(File? file) async {
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < 12) return null;
      final String? type;
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47) {
        type = 'image/png';
      } else if (bytes[0] == 0xff && bytes[1] == 0xd8) {
        type = 'image/jpeg';
      } else if (ascii.decode(bytes.sublist(0, 3), allowInvalid: true) ==
          'GIF') {
        type = 'image/gif';
      } else if (ascii.decode(bytes.sublist(8, 12), allowInvalid: true) ==
          'WEBP') {
        type = 'image/webp';
      } else if (bytes[0] == 0x42 && bytes[1] == 0x4d) {
        type = 'image/bmp';
      } else {
        return null;
      }
      return 'data:$type;base64,${base64Encode(bytes)}';
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> closePreviews() async {
    await _server?.close(force: true);
    _server = null;
    _previews.clear();
  }
}
