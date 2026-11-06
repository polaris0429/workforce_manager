import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce_manager/models/attendance.dart';
import 'package:workforce_manager/models/worker.dart';
import 'package:workforce_manager/services/attendance_document_service.dart';
import 'package:workforce_manager/services/storage_location.dart';

class _LocalHttpOverrides extends HttpOverrides {}

Attendance sampleAttendance() => Attendance(
    workerName: '홍길동',
    workerGender: '남',
    workerResidentNumber: '9001011234567',
    workerPhone: '01012345678',
    workerHomePhone: '0212345678',
    workerAddress: '서울시 테스트로 123',
    workerBankName: '테스트은행',
    workerBankAccount: '123-456-789',
    workerCareer: 'EXCLUDED_CAREER',
    notes: 'EXCLUDED_MEMO',
    idPhotoPath: 'EXCLUDED_FRONT',
    idPhotoBackPath: 'EXCLUDED_BACK',
    safetyTrainingPhotoPath: 'EXCLUDED_TRAINING',
    healthCertificatePhotoPath: 'EXCLUDED_HEALTH',
    clientName: '테스트 건설',
    clientAddress: '서울시 현장로 456',
    clientContactPerson: '김담당',
    clientPhone: '01098765432',
    clientOfficePhone: '0234567890',
    clientEmail: 'site@example.com',
    clientNotes: 'EXCLUDED_CLIENT_NOTES',
    workDate: DateTime(2026, 9, 21),
    dailyWage: 150000,
    commissionRate: 17.23,
    commission: 25845,
    netWage: 124155,
    createdAt: DateTime(2026, 9, 21));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HTML includes requested information and excludes internal fields', () {
    final html = AttendanceDocumentService.buildHtml(sampleAttendance());
    for (final expected in [
      '홍길동',
      '900101-1234567',
      '010-1234-5678',
      '02-1234-5678',
      '서울시 테스트로 123',
      '테스트은행',
      '123-456-789',
      '테스트 건설',
      '서울시 현장로 456',
      '김담당',
      '010-9876-5432',
      '02-3456-7890',
      'site@example.com',
      '2026년 09월 21일',
      '150,000원',
      'window.print()',
      '@media print',
      'size: A4'
    ]) {
      expect(html, contains(expected));
    }
    for (final forbidden in [
      'EXCLUDED_',
      '수수료',
      '실지급',
      '17.23',
      '25,845',
      '124,155',
      '25845',
      '124155',
      '<img',
      '경력',
      '메모',
      '비고'
    ]) {
      expect(html, isNot(contains(forbidden)));
    }
  });

  test('user values are escaped as text and missing fields remain readable',
      () {
    final record = sampleAttendance()
      ..workerName = '<script>alert("test")</script>'
      ..clientName = 'A & B <현장>'
      ..workerBankName = '';
    final html = AttendanceDocumentService.buildHtml(record);
    expect(html, isNot(contains('<script>alert(')));
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('A &amp; B &lt;현장&gt;'));
    expect(html, contains('<td>—</td>'));
  });

  test(
      'preview is served from memory without creating documents and resolves worker photos',
      () async {
    final temp = await Directory.systemTemp.createTemp('attendance_document_');
    addTearDown(() => temp.delete(recursive: true));
    SharedPreferences.setMockInitialValues(
        {StorageLocation.preferenceKey: temp.path});
    final record = sampleAttendance();
    final image = await File(p.join(temp.path, 'test.png')).writeAsBytes(
        base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII='));
    record.workerId = 'linked';
    final worker = Worker(
        id: 'linked',
        name: record.workerName,
        phone: '',
        idPhotoPath: image.path,
        idPhotoBackPath: image.path,
        safetyTrainingPhotoPath: image.path,
        healthCertificatePhotoPath: image.path,
        createdAt: DateTime.now());
    addTearDown(AttendanceDocumentService.closePreviews);
    final first =
        await AttendanceDocumentService.openPreview(record, workers: [worker]);
    final second = await AttendanceDocumentService.openPreview(record);
    expect(first.host, '127.0.0.1');
    expect(first.path, isNot(second.path));
    final client = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(), _LocalHttpOverrides());
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(first)).close();
    expect(response.headers.value('cache-control'), 'no-store');
    final html = await response.transform(utf8.decoder).join();
    expect(RegExp('<img ').allMatches(html).length, 4);
    expect(html, contains('담당자 성명 및 서명'));
    expect(html, contains('id="attachments" class="attachment-page" hidden'));
    expect(RegExp('<input[^>]+checked').hasMatch(html), isFalse);
    expect(RegExp('<input[^>]+disabled').hasMatch(html), isFalse);
    expect(html, isNot(contains(image.path)));
    expect(await temp.list().length, 1);
    final missing =
        await (await client.getUrl(first.replace(path: '/unknown'))).close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
  });
}
