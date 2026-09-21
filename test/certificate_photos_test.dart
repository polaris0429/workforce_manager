import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce_manager/models/attendance.dart';
import 'package:workforce_manager/models/worker.dart';
import 'package:workforce_manager/models/client.dart';
import 'package:workforce_manager/services/database_service.dart';
import 'package:workforce_manager/widgets/certificate_photos.dart';
import 'package:workforce_manager/providers/workforce_provider.dart';
import 'package:workforce_manager/utils/image_helper.dart';
import 'package:workforce_manager/screens/attendance_screen.dart';
import 'package:workforce_manager/utils/attendance_photos.dart';
import 'package:workforce_manager/services/storage_location.dart';
import 'package:workforce_manager/services/backup_service.dart';

class _TempPaths extends PathProviderPlatform {
  final String path;
  _TempPaths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform original;
  final service = DatabaseService();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('workforce_certificates_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TempPaths(temp.path);
  });
  tearDown(() async {
    await service.close();
    PathProviderPlatform.instance = original;
    await temp.delete(recursive: true);
  });

  test('optional photos persist for workers and attendance across reopening',
      () async {
    final safety =
        '${temp.path}${Platform.pathSeparator}woosin_data${Platform.pathSeparator}images${Platform.pathSeparator}safety.png';
    final health =
        '${temp.path}${Platform.pathSeparator}woosin_data${Platform.pathSeparator}images${Platform.pathSeparator}health.png';
    final worker = Worker(
        id: 'worker',
        name: '테스트',
        phone: '',
        safetyTrainingPhotoPath: safety,
        healthCertificatePhotoPath: health,
        createdAt: DateTime(2026));
    await service.insertWorker(worker);
    await service.insertWorker(Worker(
        id: 'optional', name: '미등록', phone: '', createdAt: DateTime(2026)));
    await service.insertAttendance(Attendance(
        id: 'attendance',
        workerId: worker.id,
        workerName: worker.name,
        clientName: '현장',
        workDate: DateTime(2026),
        dailyWage: 100000,
        commissionRate: 10,
        commission: 10000,
        netWage: 90000,
        safetyTrainingPhotoPath: safety,
        healthCertificatePhotoPath: health,
        createdAt: DateTime(2026)));
    final db = await service.database;
    final raw =
        (await db.query('workers', where: 'id = ?', whereArgs: ['worker']))
            .single;
    expect(raw['safety_training_photo_path'], 'images/safety.png');
    expect(raw['health_certificate_photo_path'], 'images/health.png');
    await service.close();
    final workers = await service.getAllWorkers();
    expect(workers.firstWhere((w) => w.id == 'worker').safetyTrainingPhotoPath,
        safety);
    expect(
        workers
            .firstWhere((w) => w.id == 'optional')
            .healthCertificatePhotoPath,
        isNull);
    final attendance = (await service.getAllAttendance()).single;
    expect(attendance.healthCertificatePhotoPath, health);
    attendance.safetyTrainingPhotoPath = null;
    await service.updateAttendance(attendance);
    expect((await service.getAllAttendance()).single.safetyTrainingPhotoPath,
        isNull);
  });

  test('version 2 database upgrades without losing existing records', () async {
    final db = await service.database;
    await service.insertWorker(Worker(
        id: 'old', name: '기존 근로자', phone: '010', createdAt: DateTime(2025)));
    for (final table in ['workers', 'attendance']) {
      await db
          .execute('ALTER TABLE $table DROP COLUMN safety_training_photo_path');
      await db.execute(
          'ALTER TABLE $table DROP COLUMN health_certificate_photo_path');
    }
    await db.setVersion(2);
    await service.close();
    final worker = (await service.getAllWorkers()).single;
    expect(worker.name, '기존 근로자');
    expect(worker.safetyTrainingPhotoPath, isNull);
    worker.healthCertificatePhotoPath =
        '${temp.path}${Platform.pathSeparator}woosin_data${Platform.pathSeparator}images${Platform.pathSeparator}health.png';
    await service.updateWorker(worker);
    expect((await service.getAllWorkers()).single.healthCertificatePhotoPath,
        worker.healthCertificatePhotoPath);
    expect(await (await service.database).getVersion(), 3);
  });

  test('attendance registration and edits reuse all four worker image files',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = WorkforceProvider();
    addTearDown(provider.dispose);
    final ready = Completer<void>();
    provider.addListener(() {
      if (!provider.isLoading && !ready.isCompleted) ready.complete();
    });
    await ready.future.timeout(const Duration(seconds: 10));
    // Allow the asynchronous initialization to finish setting up its timers.
    await Future<void>.delayed(Duration.zero);
    final sourceFiles = <File>[];
    for (var i = 0; i < 4; i++) {
      sourceFiles
          .add(await File(p.join(temp.path, 'source$i.png')).writeAsBytes([i]));
    }
    await provider.addWorker(
        name: '사진 테스트',
        phone: '01012345678',
        idPhotoFront: sourceFiles[0],
        idPhotoBack: sourceFiles[1],
        safetyTrainingPhoto: sourceFiles[2],
        healthCertificatePhoto: sourceFiles[3]);
    final worker = provider.workers.single;
    final paths = [
      worker.idPhotoPath!,
      worker.idPhotoBackPath!,
      worker.safetyTrainingPhotoPath!,
      worker.healthCertificatePhotoPath!
    ];
    final imageRoot = Directory(p.join(temp.path, 'woosin_data', 'images'));
    Future<int> imageCount() => imageRoot
        .list(recursive: true)
        .where((entity) => entity is File)
        .length;
    expect(await imageCount(), 4);

    for (var i = 0; i < 3; i++) {
      await provider.addAttendance(
          workerId: worker.id,
          workerName: worker.name,
          workerPhone: worker.phone,
          clientName: '현장',
          workDate: DateTime(2026, 9, 21 + i),
          dailyWage: 100000,
          commissionRate: 10,
          isPostpaid: true,
          idPhotoFront: File(paths[0]),
          idPhotoBack: File(paths[1]),
          safetyTrainingPhoto: File(paths[2]),
          healthCertificatePhoto: File(paths[3]));
    }
    final attendanceId = provider.attendanceList.first.id;
    await provider.updateAttendance(
        id: attendanceId,
        data: {'notes': '메모 수정'},
        newFrontImage: File(paths[0]),
        newBackImage: File(paths[1]),
        newSafetyTrainingImage: File(paths[2]),
        newHealthCertificateImage: File(paths[3]));
    await provider.updateWorker(
        id: worker.id,
        data: {'name': '이름 수정'},
        newFrontImage: File(paths[0]),
        newBackImage: File(paths[1]),
        newSafetyTrainingImage: File(paths[2]),
        newHealthCertificateImage: File(paths[3]));
    expect(await imageCount(), 4);
    await service.close();
    for (final record in await service.getAllAttendance()) {
      expect([
        record.idPhotoPath,
        record.idPhotoBackPath,
        record.safetyTrainingPhotoPath,
        record.healthCertificatePhotoPath
      ], paths);
    }

    final replacement =
        await File(p.join(temp.path, 'replacement.png')).writeAsBytes([9]);
    await provider.updateAttendance(
        id: attendanceId, data: {}, newFrontImage: replacement);
    expect(await imageCount(), 5);
    final updated = (await service.getAllAttendance())
        .firstWhere((a) => a.id == attendanceId);
    expect(updated.idPhotoPath, isNot(paths[0]));
    expect(await File(updated.idPhotoPath!).readAsBytes(), [9]);
    expect((await service.getAllWorkers()).single.idPhotoPath, paths[0]);
    expect(await File(paths[0]).readAsBytes(), [0]);
  });

  test('only files inside the managed images directory are reused', () async {
    final outside =
        File(p.join(temp.path, 'woosin_data', 'images-other', 'photo.png'));
    await outside.parent.create(recursive: true);
    await outside.writeAsBytes([7]);
    final saved =
        await ImageHelper.saveImageLocally(outside, workerName: '테스트');
    expect(saved, isNot(outside.path));
    expect(await File(saved).readAsBytes(), [7]);
    expect(await ImageHelper.saveImageLocally(File(saved), workerName: '이름 수정'),
        saved);
    await expectLater(
        ImageHelper.saveImageLocally(
            File(p.join(temp.path, 'woosin_data', 'images', 'missing.png'))),
        throwsA(isA<FileSystemException>()));
  });

  testWidgets(
      'missing attendance copies use worker photos in list and edit dialog',
      (tester) async {
    late Worker worker;
    late Attendance attendance;
    late List<String> paths;
    final provider = await tester.runAsync(() async {
      await initializeDateFormatting('ko');
      paths = [];
      for (var i = 0; i < 4; i++) {
        final file = File(
            p.join(temp.path, 'woosin_data', 'images', 'worker', '$i.png'));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII='));
        paths.add(file.path);
      }
      worker = Worker(
          id: 'linked',
          name: '사진참조',
          phone: '',
          createdAt: DateTime.now(),
          idPhotoPath: paths[0],
          idPhotoBackPath: paths[1],
          safetyTrainingPhotoPath: paths[2],
          healthCertificatePhotoPath: paths[3]);
      attendance = Attendance(
          id: 'missing-copies',
          workerId: worker.id,
          workerName: worker.name,
          clientName: '현장',
          workDate: DateTime.now(),
          dailyWage: 100000,
          commissionRate: 10,
          commission: 10000,
          netWage: 90000,
          createdAt: DateTime.now(),
          idPhotoPath: '${paths[0]}.missing',
          idPhotoBackPath: '${paths[1]}.missing',
          safetyTrainingPhotoPath: '${paths[2]}.missing',
          healthCertificatePhotoPath: '${paths[3]}.missing');
      await service.insertWorker(worker);
      await service.insertAttendance(attendance);
      SharedPreferences.setMockInitialValues({});
      final provider = WorkforceProvider();
      final ready = Completer<void>();
      provider.addListener(() {
        if (!provider.isLoading && !ready.isCompleted) ready.complete();
      });
      await ready.future.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(Duration.zero);
      return provider;
    });
    addTearDown(provider!.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<WorkforceProvider>.value(
        value: provider, child: const MaterialApp(home: AttendanceScreen())));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => (image.image as FileImage).file.path),
        unorderedEquals(paths));
    expect(find.text('미등록'), findsNothing);
    await tester.tap(find.text('사진참조'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<DocumentPhotoPicker>(find.byType(DocumentPhotoPicker))
            .map((picker) => picker.file?.path),
        unorderedEquals(paths));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // A valid attendance-specific image takes precedence; unrelated workers are never matched by name.
    attendance.idPhotoPath = paths[1];
    expect(
        AttendancePhotos.resolve(attendance, [worker]).front?.path, paths[1]);
    attendance.idPhotoPath = null;
    attendance.workerId = 'unrelated';
    final unmatched = AttendancePhotos.resolve(attendance, [worker]);
    expect([
      unmatched.front,
      unmatched.back,
      unmatched.safetyTraining,
      unmatched.healthCertificate
    ], everyElement(isNull));
  });

  for (final keyboard in [false, true]) {
    testWidgets(
        'worker and client selections advance focus (keyboard: $keyboard)',
        (tester) async {
      final provider = await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final provider = WorkforceProvider();
        final ready = Completer<void>();
        provider.addListener(() {
          if (!provider.isLoading && !ready.isCompleted) ready.complete();
        });
        await ready.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(Duration.zero);
        await provider.addWorker(
            name: '포커스테스트',
            phone: '01012345678',
            address: '테스트 주소',
            bankName: '테스트 은행');
        await provider.addClient(Client(
            name: '거래처포커스테스트',
            address: '테스트 현장 주소',
            contactPerson: '테스트 담당자',
            createdAt: DateTime.now()));
        return provider;
      });
      addTearDown(provider!.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<WorkforceProvider>.value(
          value: provider, child: const MaterialApp(home: AttendanceScreen())));
      await tester.tap(find.widgetWithText(ElevatedButton, '출근 등록'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
          of: find.byType(AttendanceDialog),
          matching: find.byType(TextFormField));
      await tester.enterText(fields.first, '포커스');
      await tester.pumpAndSettle();
      if (keyboard) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(find.text('포커스테스트'));
      }
      await tester.pumpAndSettle();
      final inputs = tester.widgetList<EditableText>(find.byType(EditableText));
      expect(inputs.where((field) => field.focusNode.hasFocus), hasLength(1));
      final focused = inputs.singleWhere((field) => field.focusNode.hasFocus);
      final clientField = tester.widget<TextFormField>(fields.at(8));
      expect(focused.controller, same(clientField.controller));
      expect(inputs.any((field) => field.controller.text == '테스트 주소'), isTrue);
      expect(inputs.any((field) => field.controller.text == '테스트 은행'), isTrue);
      await tester.enterText(fields.at(8), '거래처포커스');
      await tester.pumpAndSettle();
      if (keyboard) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(find.text('거래처포커스테스트'));
      }
      await tester.pumpAndSettle();
      final wageField = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == '일당 *');
      expect(tester.widget<TextField>(wageField).focusNode!.hasFocus, isTrue);
      expect(
          inputs.any((field) => field.controller.text == '테스트 현장 주소'), isTrue);
      expect(inputs.any((field) => field.controller.text == '테스트 담당자'), isTrue);
      await tester.enterText(wageField, '150000');
      expect(tester.widget<TextField>(wageField).controller!.text, '150000');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  test(
      'storage change preserves records, remaps photos, persists and backs up from new location',
      () async {
    final source = File(p.join(temp.path, 'source.png'));
    await source.writeAsBytes([1, 2, 3]);
    final photos = <String>[];
    for (var i = 0; i < 4; i++) {
      photos
          .add(await ImageHelper.saveImageLocally(source, workerName: '경로테스트'));
    }
    await service.insertWorker(Worker(
        id: 'worker',
        name: '경로테스트',
        phone: '',
        idPhotoPath: photos[0],
        idPhotoBackPath: photos[1],
        safetyTrainingPhotoPath: photos[2],
        healthCertificatePhotoPath: photos[3],
        createdAt: DateTime.now()));
    await service.insertClient(
        Client(id: 'client', name: '현장', createdAt: DateTime.now()));
    await service.insertAttendance(Attendance(
        id: 'attendance',
        workerId: 'worker',
        workerName: '경로테스트',
        clientName: '현장',
        workDate: DateTime.now(),
        dailyWage: 100000,
        commissionRate: 10,
        commission: 10000,
        netWage: 90000,
        idPhotoPath: photos[0],
        idPhotoBackPath: photos[1],
        safetyTrainingPhotoPath: photos[2],
        healthCertificatePhotoPath: photos[3],
        createdAt: DateTime.now()));
    // Also cover older databases storing absolute paths.
    await (await service.database)
        .update('workers', {'id_photo_path': photos[0]});
    final oldDb = await service.dbPath;
    final destination =
        await Directory(p.join(temp.path, 'new-location')).create();
    final provider = WorkforceProvider();
    addTearDown(provider.dispose);
    final ready = Completer<void>();
    provider.addListener(() {
      if (!provider.isLoading && !ready.isCompleted) ready.complete();
    });
    await ready.future.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    final pendingWrite = provider.updateClient('client', {'notes': '변경 직전 저장'});
    final relocation = provider.changeDataDirectory(destination.path);
    await Future.wait([pendingWrite, relocation]);
    final newRoot = p.join(destination.path, 'woosin_data');
    expect(provider.clients.single.notes, '변경 직전 저장');
    expect(p.isWithin(newRoot, provider.workers.single.idPhotoPath!), isTrue);
    expect(
        p.isWithin(newRoot,
            provider.attendanceList.single.healthCertificatePhotoPath!),
        isTrue);
    expect(await StorageLocation.dataDirectory, newRoot);
    expect(await File(oldDb).exists(), isTrue);
    for (final oldPhoto in photos) {
      expect(await File(oldPhoto).readAsBytes(), [1, 2, 3]);
    }
    await service.close();
    await (await SharedPreferences.getInstance()).reload();
    expect(await service.dbPath, p.join(newRoot, 'woosin_data.db'));
    final worker = (await service.getAllWorkers()).single;
    final attendance = (await service.getAllAttendance()).single;
    expect((await service.getAllClients()).single.name, '현장');
    for (final path in [
      worker.idPhotoPath,
      worker.idPhotoBackPath,
      worker.safetyTrainingPhotoPath,
      worker.healthCertificatePhotoPath,
      attendance.idPhotoPath,
      attendance.idPhotoBackPath,
      attendance.safetyTrainingPhotoPath,
      attendance.healthCertificatePhotoPath
    ]) {
      expect(p.isWithin(newRoot, path!), isTrue);
      expect(await File(path).readAsBytes(), [1, 2, 3]);
    }
    expect(
        await ImageHelper.saveImageLocally(File(worker.idPhotoPath!),
            workerName: worker.name),
        worker.idPhotoPath);
    final newPhoto =
        await ImageHelper.saveImageLocally(source, workerName: worker.name);
    expect(p.isWithin(newRoot, newPhoto), isTrue);
    final backup = await Directory(p.join(temp.path, 'backup')).create();
    final backupService = BackupService();
    addTearDown(backupService.dispose);
    await backupService.backupAll(backupPaths: [backup.path, destination.path]);
    expect(
        await File(p.join(backup.path, 'woosin_data', 'woosin_data.db'))
            .exists(),
        isTrue);
    expect(
        await File(p.join(backup.path, 'woosin_data',
                p.relative(newPhoto, from: newRoot)))
            .readAsBytes(),
        [1, 2, 3]);
    // Selecting the current data directory is a safe no-op.
    await StorageLocation.withLock(() => service.changeDataDirectory(newRoot));
    expect((await service.getAllWorkers()).single.id, worker.id);
    await provider.addBackupPath(backup.path);
    await expectLater(
        provider.changeDataDirectory(backup.path), throwsStateError);
    expect(await StorageLocation.dataDirectory, newRoot);
  });

  test('invalid destinations preserve the original database and setting',
      () async {
    await service.insertWorker(
        Worker(id: 'safe', name: '원본', phone: '', createdAt: DateTime.now()));
    final oldDb = await service.dbPath;
    final sourceRoot = await StorageLocation.dataDirectory;
    await expectLater(
        StorageLocation.withLock(
            () => service.changeDataDirectory(p.join(sourceRoot))),
        completes);
    final nested = await Directory(p.join(sourceRoot, 'nested')).create();
    await expectLater(
        StorageLocation.withLock(
            () => service.changeDataDirectory(nested.path)),
        throwsStateError);
    final occupied =
        await Directory(p.join(temp.path, 'occupied', 'woosin_data'))
            .create(recursive: true);
    final sentinel =
        await File(p.join(occupied.path, 'existing.txt')).writeAsString('keep');
    await expectLater(
        StorageLocation.withLock(
            () => service.changeDataDirectory(p.dirname(occupied.path))),
        throwsStateError);
    expect(await sentinel.readAsString(), 'keep');
    // Force a failure after copying, when publishing the staging directory.
    final blocked = await Directory(p.join(temp.path, 'blocked')).create();
    await File(p.join(blocked.path, 'woosin_data')).writeAsString('keep');
    await expectLater(
        StorageLocation.withLock(
            () => service.changeDataDirectory(blocked.path)),
        throwsA(isA<FileSystemException>()));
    expect(await service.dbPath, oldDb);
    expect((await service.getAllWorkers()).single.id, 'safe');
    expect(
        (await SharedPreferences.getInstance())
            .getString(StorageLocation.preferenceKey),
        isNull);
    expect(await blocked.list().length, 1);
  });

  testWidgets('optional certificate fields and compact previews fit',
      (tester) async {
    for (final compact in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
            width: compact ? 188 : 320,
            child: CertificatePhotos(
                compact: compact,
                onSafetyChanged: compact ? null : (_) {},
                onHealthChanged: compact ? null : (_) {})),
      ))));
      expect(find.text('안전교육 이수증'), findsOneWidget);
      expect(find.text('보건증'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
