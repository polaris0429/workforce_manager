import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:workforce_manager/models/worker.dart';
import 'package:workforce_manager/services/database_service.dart';
import 'package:workforce_manager/services/backup_service.dart';
import 'package:workforce_manager/services/backup_file.dart';
import 'package:workforce_manager/services/storage_location.dart';
import 'package:workforce_manager/providers/workforce_provider.dart';

class TempPaths extends PathProviderPlatform {
  final String path;
  TempPaths(this.path);
  @override Future<String?> getApplicationDocumentsPath() async => path;
}

Future<WorkforceProvider> startProvider() async {
  final provider = WorkforceProvider();
  await provider.ready;
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform original;
  final db = DatabaseService();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('workforce_backup_audit_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TempPaths(temp.path);
    await db.insertWorker(Worker(id:'baseline',name:'테스트',phone:'',createdAt:DateTime(2026)));
  });
  tearDown(() async {
    await StorageLocation.withLock(() async {});
    await db.close();
    PathProviderPlatform.instance = original;
    await temp.delete(recursive:true);
  });
  Future<int> backupCount(String root) async {
    final path=p.join(root,'woosin_data','woosin_data.db');
    if(!await File(path).exists()) return -1;
    final copy=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(readOnly:true,singleInstance:false));
    try {return (await copy.query('workers')).length;} finally {await copy.close();}
  }

  test('baseline: registering accessible destination and normal delayed save work',() async {
    final dest=await Directory(p.join(temp.path,'backup')).create();
    final provider=await startProvider();
    addTearDown(provider.dispose);
    await provider.addBackupPath(dest.path);
    await StorageLocation.withLock(() async {});
    expect(await backupCount(dest.path),1);
    await provider.addWorker(name:'새 근로자',phone:'');
    await Future<void>.delayed(const Duration(milliseconds:700));
    await StorageLocation.withLock(() async {});
    expect(await backupCount(dest.path),2);
  });

  test('restart repairs a save made before debounce',() async {
    final dest=await Directory(p.join(temp.path,'backup')).create();
    final first=await startProvider();
    await first.addBackupPath(dest.path);
    await StorageLocation.withLock(() async {});
    await first.addWorker(name:'종료 직전 저장',phone:'');
    first.dispose(); // before 500 ms debounce fires
    await db.close();
    final restarted=await startProvider();
    addTearDown(restarted.dispose);
    expect(restarted.workers.length,2);
    expect(restarted.backupPaths,[dest.path]);
    expect(restarted.pendingPaths,isEmpty);
    await restarted.retryBackupNow();

    await StorageLocation.withLock(() async {});
    expect(await backupCount(dest.path),2);
  },timeout:const Timeout(Duration(seconds:50)));

  test('queued offline destination survives service restart and recovers',() async {
    final dest=p.join(temp.path,'offline');
    final first=BackupService();
    await first.backupAll(backupPaths:[dest]);
    expect(await first.getPendingPaths(),{dest});
    first.dispose();
    await Directory(dest).create();
    final second=BackupService(); addTearDown(second.dispose);
    await second.retryPending();
    expect(await backupCount(dest),1);
    expect(await second.getPendingPaths(),isEmpty);
  });

  test('photo copy failure stays pending',() async {
    final source=File(p.join(temp.path,'woosin_data','images','test.png'));
    await source.parent.create(recursive:true); await source.writeAsBytes([1,2,3]);
    final dest=await Directory(p.join(temp.path,'backup')).create();
    await Directory(p.join(dest.path,'woosin_data')).create();
    await File(p.join(dest.path,'woosin_data','images')).writeAsString('blocks image directory');
    final service=BackupService(); addTearDown(service.dispose);
    await service.backupAll(backupPaths:[dest.path]);
    expect(await backupCount(dest.path),-1);
    expect(service.statusMap[dest.path],BackupPathStatus.pending);
    expect(await service.getPendingPaths(),{dest.path});
    expect(await File(p.join(dest.path,'woosin_data','images','test.png')).exists(),isFalse);
  });

  test('checks pending paths when multiple destinations fail together',() async {
    final destinations=List.generate(5,(i)=>p.join(temp.path,'offline$i'));
    final service=BackupService(); addTearDown(service.dispose);
    await service.backupAll(backupPaths:destinations);
    final pending=await service.getPendingPaths();
    expect(service.statusMap.values.where((s)=>s==BackupPathStatus.pending).length,5);
    expect(pending, destinations.toSet());
  });

  test('manual sync refreshes all paths even with an empty queue and keeps previous DB', () async {
    final dest = await Directory(p.join(temp.path, 'backup')).create();
    final provider = await startProvider();
    addTearDown(provider.dispose);
    await provider.addBackupPath(dest.path);
    await db.insertWorker(Worker(id: 'extra', name: 'test', phone: '', createdAt: DateTime(2026)));
    expect(provider.pendingPaths, isEmpty);
    await provider.retryBackupNow();
    expect(await backupCount(dest.path), 2);
    final previous = await databaseFactoryFfi.openDatabase(
      p.join(dest.path, 'woosin_data', 'woosin_data.db.previous'),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try { expect((await previous.query('workers')).length, 1); }
    finally { await previous.close(); }
  });

  test('photo failure preserves existing DB and recovery replaces equal-size wrong image', () async {
    final dest = await Directory(p.join(temp.path, 'backup')).create();
    final service = BackupService(); addTearDown(service.dispose);
    await service.backupAll(backupPaths: [dest.path]);
    final source = File(p.join(temp.path, 'woosin_data', 'images', 'test.png'));
    await source.parent.create(recursive: true);
    await source.writeAsBytes([1, 2, 3]);
    final blocker = File(p.join(dest.path, 'woosin_data', 'images'));
    await blocker.writeAsString('blocked');
    await db.insertWorker(Worker(id: 'extra', name: 'test', phone: '', createdAt: DateTime(2026)));
    await service.backupAll(backupPaths: [dest.path]);
    expect(await backupCount(dest.path), 1);
    expect(await service.getPendingPaths(), {dest.path});
    await blocker.delete();
    final image = File(p.join(blocker.path, 'test.png'));
    await image.parent.create();
    await image.writeAsBytes([3, 2, 1]);
    await service.retryPending();
    expect(await image.readAsBytes(), [1, 2, 3]);
    expect(await backupCount(dest.path), 2);
    expect(await service.getPendingPaths(), isEmpty);
  });

  test('startup queues disconnected destination and removing it clears retries', () async {
    final offline = p.join(temp.path, 'offline');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('backupPaths', [offline]);
    final provider = await startProvider(); addTearDown(provider.dispose);
    expect(provider.pendingPaths, {offline});
    await provider.removeBackupPath(offline);
    expect(provider.pendingPaths, isEmpty);
    await Directory(offline).create();
    await provider.retryBackupNow();
    expect(await backupCount(offline), -1);
  });

  test('overlapping destinations are rejected', () async {
    final service = BackupService(); addTearDown(service.dispose);
    await expectLater(service.validateDestination(temp.path), throwsStateError);
    await expectLater(service.validateDestination(p.join(temp.path, 'woosin_data')), throwsStateError);
  });

  test('failed validation leaves the existing backup untouched', () async {
    final source = File(p.join(temp.path, 'new.db'));
    final destination = File(p.join(temp.path, 'existing.db'));
    await source.writeAsBytes([1, 2, 3]);
    await destination.writeAsBytes([4, 5, 6]);
    await expectLater(BackupFile.replace(source, destination,
        validate: (_) async { throw StateError('invalid snapshot'); }), throwsStateError);
    expect(await destination.readAsBytes(), [4, 5, 6]);
  });
}
