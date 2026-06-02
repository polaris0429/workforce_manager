import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/worker.dart';
import '../models/client.dart';
import '../models/attendance.dart';
import '../utils/image_helper.dart';
import '../services/database_service.dart';
import '../services/backup_service.dart';

export '../services/backup_service.dart' show BackupPathStatus;

enum ExcelPeriodType { today, week, month, all }

class WorkforceProvider with ChangeNotifier {
  final DatabaseService _dbSvc     = DatabaseService();
  final BackupService   _backupSvc = BackupService();

  List<Worker>     _workers        = [];
  List<Client>     _clients        = [];
  List<Attendance> _attendanceList = [];

  List<Worker>     get workers        => _workers;
  List<Client>     get clients        => _clients;
  List<Attendance> get attendanceList => _attendanceList;

  List<String> _backupPaths = [];
  List<String> get backupPaths => List.unmodifiable(_backupPaths);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Set<String> _pendingPaths = {};
  Set<String> get pendingPaths => Set.unmodifiable(_pendingPaths);

  // ── 등록 제안 설정 ────────────────────────────────────────
  bool _suggestWorkerRegistration  = true;
  bool _suggestClientRegistration  = true;
  bool get suggestWorkerRegistration => _suggestWorkerRegistration;
  bool get suggestClientRegistration => _suggestClientRegistration;

  static const String _keyWorkerSuggest = 'suggest_worker_registration';
  static const String _keyClientSuggest = 'suggest_client_registration';

  Map<String, BackupPathStatus> get backupStatusMap    => _backupSvc.statusMap;
  Stream<Map<String, BackupPathStatus>> get backupStatusStream => _backupSvc.statusStream;

  Timer? _debounceTimer;
  static const Duration _debounce      = Duration(milliseconds: 500);
  Timer? _retryTimer;
  static const Duration _retryInterval = Duration(seconds: 30);

  WorkforceProvider() { _init(); }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _backupSvc.dispose();
    super.dispose();
  }

  // ── 초기화 ────────────────────────────────────────────────
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _backupPaths = (prefs.getStringList('backupPaths') ?? [])
        .where((s) => s.isNotEmpty).toList();
    // 등록 제안 설정 로드 (기본값 true)
    _suggestWorkerRegistration = prefs.getBool(_keyWorkerSuggest) ?? true;
    _suggestClientRegistration = prefs.getBool(_keyClientSuggest) ?? true;
    await _loadData();
    _startRetryTimer();
    await _refreshPending();
  }

  // ── 등록 제안 설정 변경 ───────────────────────────────────
  Future<void> setSuggestWorkerRegistration(bool value) async {
    _suggestWorkerRegistration = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWorkerSuggest, value);
    notifyListeners();
  }

  Future<void> setSuggestClientRegistration(bool value) async {
    _suggestClientRegistration = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyClientSuggest, value);
    notifyListeners();
  }

  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();
    _workers        = await _dbSvc.getAllWorkers();
    _clients        = await _dbSvc.getAllClients();
    _attendanceList = await _dbSvc.getAllAttendance();
    _isLoading = false;
    notifyListeners();
  }

  // ── 디바운스 백업 ─────────────────────────────────────────
  void _scheduleBackup() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(_backupSvc.backupAll(backupPaths: _backupPaths).then((_) => _refreshPending()));
    });
  }

  Future<void> _refreshPending() async {
    _pendingPaths = await _backupSvc.getPendingPaths();
    notifyListeners();
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      unawaited(_backupSvc.retryPending().then((_) => _refreshPending()));
    });
  }

  Future<void> retryBackupNow() async {
    await _backupSvc.retryPending();
    await _refreshPending();
  }

  // ── 백업 경로 관리 ────────────────────────────────────────
  Future<void> addBackupPath(String path) async {
    if (path.isEmpty || _backupPaths.contains(path)) return;
    _backupPaths.add(path);
    await _persistPaths();
    notifyListeners();
    unawaited(_backupSvc.backupAll(backupPaths: [path]).then((_) => _refreshPending()));
  }

  Future<void> removeBackupPath(String path) async {
    _backupPaths.remove(path);
    final pending = await _backupSvc.getPendingPaths();
    if (pending.contains(path)) {
      pending.remove(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('backup_pending_paths', pending.toList());
      _pendingPaths = pending;
    }
    await _persistPaths();
    notifyListeners();
  }

  Future<void> _persistPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('backupPaths', _backupPaths);
  }

  Future<void> _backupImage(String localPath) async {
    if (_backupPaths.isEmpty) return;
    await _backupSvc.backupImage(localImagePath: localPath, backupPaths: _backupPaths);
  }

  String _generateId() {
    final now = DateTime.now();
    return '${now.millisecondsSinceEpoch}_${now.microsecond}';
  }

  // =========================================================
  // CRUD
  // =========================================================

  Future<void> addWorker({
    required String name, String gender = '', String residentNumber = '',
    required String phone, String address = '', String bankName = '',
    String bankAccount = '', String career = '', String notes = '',
    File? idPhotoFront, File? idPhotoBack,
  }) async {
    String? fp, bp;
    if (idPhotoFront != null) { fp = await ImageHelper.saveImageLocally(idPhotoFront, workerName: name); await _backupImage(fp); }
    if (idPhotoBack  != null) { bp = await ImageHelper.saveImageLocally(idPhotoBack,  workerName: name); await _backupImage(bp); }
    final w = Worker(id: _generateId(), name: name, gender: gender, residentNumber: residentNumber,
        phone: phone, address: address, bankName: bankName, bankAccount: bankAccount,
        career: career, notes: notes, idPhotoPath: fp, idPhotoBackPath: bp, createdAt: DateTime.now());
    await _dbSvc.insertWorker(w);
    _workers = await _dbSvc.getAllWorkers();
    notifyListeners(); _scheduleBackup();
  }

  Future<void> updateWorker({required String id, required Map<String, dynamic> data,
      File? newFrontImage, File? newBackImage}) async {
    final idx = _workers.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    final old   = _workers[idx];
    final wName = (data['name'] as String?)?.isNotEmpty == true ? data['name'] as String : old.name;
    if (newFrontImage != null) { final path = await ImageHelper.saveImageLocally(newFrontImage, workerName: wName); data['id_photo_path']      = path; await _backupImage(path); }
    if (newBackImage  != null) { final path = await ImageHelper.saveImageLocally(newBackImage,  workerName: wName); data['id_photo_back_path'] = path; await _backupImage(path); }
    final updated = Worker(id: old.id, name: data['name'] ?? old.name, gender: data['gender'] ?? old.gender,
        residentNumber: data['resident_number'] ?? old.residentNumber, phone: data['phone'] ?? old.phone,
        address: data['address'] ?? old.address, bankName: data['bank_name'] ?? old.bankName,
        bankAccount: data['bank_account'] ?? old.bankAccount, career: data['career'] ?? old.career,
        notes: data['notes'] ?? old.notes, idPhotoPath: data['id_photo_path'] ?? old.idPhotoPath,
        idPhotoBackPath: data['id_photo_back_path'] ?? old.idPhotoBackPath,
        isBlacklisted: old.isBlacklisted, blacklistReason: old.blacklistReason, createdAt: old.createdAt);
    await _dbSvc.updateWorker(updated);
    _workers = await _dbSvc.getAllWorkers();
    notifyListeners(); _scheduleBackup();
  }

  Future<void> deleteWorker(String id) async {
    await _dbSvc.deleteWorker(id);
    _workers.removeWhere((w) => w.id == id);
    notifyListeners(); _scheduleBackup();
  }

  Future<void> toggleBlacklist(String id, bool currentStatus, String? reason) async {
    final idx = _workers.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    final old = _workers[idx];
    final updated = Worker(id: old.id, name: old.name, gender: old.gender, residentNumber: old.residentNumber,
        phone: old.phone, address: old.address, bankName: old.bankName, bankAccount: old.bankAccount,
        career: old.career, notes: old.notes, idPhotoPath: old.idPhotoPath, idPhotoBackPath: old.idPhotoBackPath,
        isBlacklisted: !currentStatus, blacklistReason: !currentStatus ? reason : null, createdAt: old.createdAt);
    await _dbSvc.updateWorker(updated);
    _workers[idx] = updated;
    notifyListeners(); _scheduleBackup();
  }

  Future<void> addClient(Client client) async {
    client.id = _generateId();
    await _dbSvc.insertClient(client);
    _clients.insert(0, client);
    notifyListeners(); _scheduleBackup();
  }

  Future<void> updateClient(String id, Map<String, dynamic> data) async {
    final idx = _clients.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final old = _clients[idx];
    final updated = Client(id: old.id, name: data['name'] ?? old.name,
        address: data['address'] ?? old.address, contactPerson: data['contact_person'] ?? old.contactPerson,
        phone: data['phone'] ?? old.phone, email: data['email'] ?? old.email,
        notes: data['notes'] ?? old.notes, createdAt: old.createdAt);
    await _dbSvc.updateClient(updated);
    _clients[idx] = updated;
    notifyListeners(); _scheduleBackup();
  }

  Future<void> deleteClient(String id) async {
    await _dbSvc.deleteClient(id);
    _clients.removeWhere((c) => c.id == id);
    notifyListeners(); _scheduleBackup();
  }

  Future<void> addAttendance({
    String? workerId, required String workerName, String workerGender = '',
    String workerResidentNumber = '', required String workerPhone,
    String workerAddress = '', String workerBankName = '', String workerBankAccount = '',
    String workerCareer = '', String? clientId, required String clientName,
    required String clientAddress, required DateTime workDate,
    required double dailyWage, required double commissionRate, required bool isPostpaid,
    String notes = '', File? idPhotoFront, File? idPhotoBack,
  }) async {
    String? fp, bp;
    if (idPhotoFront != null) { fp = await ImageHelper.saveImageLocally(idPhotoFront, workerName: workerName); await _backupImage(fp); }
    if (idPhotoBack  != null) { bp = await ImageHelper.saveImageLocally(idPhotoBack,  workerName: workerName); await _backupImage(bp); }
    final comm = dailyWage * (commissionRate / 100);
    final att  = Attendance(id: _generateId(), workerId: workerId, workerName: workerName,
        workerGender: workerGender, workerResidentNumber: workerResidentNumber,
        workerPhone: workerPhone, workerAddress: workerAddress, workerBankName: workerBankName,
        workerBankAccount: workerBankAccount, workerCareer: workerCareer,
        clientId: clientId, clientName: clientName, clientAddress: clientAddress,
        workDate: workDate, dailyWage: dailyWage, commissionRate: commissionRate,
        commission: comm, netWage: isPostpaid ? dailyWage : (dailyWage - comm),
        notes: notes, idPhotoPath: fp, idPhotoBackPath: bp,
        isPostpaid: isPostpaid, isSettled: !isPostpaid, createdAt: DateTime.now());
    await _dbSvc.insertAttendance(att);
    _attendanceList.insert(0, att);
    notifyListeners(); _scheduleBackup();
  }

  Future<void> updateAttendance({required String id, required Map<String, dynamic> data,
      File? newFrontImage, File? newBackImage}) async {
    final idx = _attendanceList.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final old   = _attendanceList[idx];
    final wName = (data['worker_name'] as String?) ?? old.workerName;
    if (newFrontImage != null) { final path = await ImageHelper.saveImageLocally(newFrontImage, workerName: wName); data['id_photo_path']      = path; await _backupImage(path); }
    if (newBackImage  != null) { final path = await ImageHelper.saveImageLocally(newBackImage,  workerName: wName); data['id_photo_back_path'] = path; await _backupImage(path); }

    if (data.containsKey('daily_wage') && data.containsKey('commission_rate') && data.containsKey('is_postpaid')) {
      final double dw = (data['daily_wage'] as num).toDouble();
      final double rt = (data['commission_rate'] as num).toDouble();
      final bool   pp = data['is_postpaid'] as bool;
      final double cm = dw * (rt / 100);
      data['commission'] = cm; data['net_wage'] = pp ? dw : (dw - cm);
      if (!pp) data['is_settled'] = true;
    }
    final updated = Attendance(id: old.id,
        workerId:             data['worker_id']              ?? old.workerId,
        workerName:           data['worker_name']            ?? old.workerName,
        workerGender:         data['worker_gender']          ?? old.workerGender,
        workerResidentNumber: data['worker_resident_number'] ?? old.workerResidentNumber,
        workerPhone:          data['worker_phone']           ?? old.workerPhone,
        workerAddress:        data['worker_address']         ?? old.workerAddress,
        workerBankName:       data['worker_bank_name']       ?? old.workerBankName,
        workerBankAccount:    data['worker_bank_account']    ?? old.workerBankAccount,
        workerCareer:         data['worker_career']          ?? old.workerCareer,
        clientId:             data['client_id']              ?? old.clientId,
        clientName:           data['client_name']            ?? old.clientName,
        clientAddress:        data['client_address']         ?? old.clientAddress,
        workDate:             data['work_date']               ?? old.workDate,
        dailyWage:            _toDouble(data['daily_wage'])   ?? old.dailyWage,
        commissionRate:       _toDouble(data['commission_rate']) ?? old.commissionRate,
        commission:           _toDouble(data['commission'])   ?? old.commission,
        netWage:              _toDouble(data['net_wage'])     ?? old.netWage,
        notes:                data['notes']                   ?? old.notes,
        idPhotoPath:          data['id_photo_path']           ?? old.idPhotoPath,
        idPhotoBackPath:      data['id_photo_back_path']      ?? old.idPhotoBackPath,
        isPostpaid:           data['is_postpaid']             ?? old.isPostpaid,
        isSettled:            data['is_settled']              ?? old.isSettled,
        createdAt:            old.createdAt);
    await _dbSvc.updateAttendance(updated);
    _attendanceList[idx] = updated;
    notifyListeners(); _scheduleBackup();
  }

  double? _toDouble(dynamic v) {
    if (v == null)   return null;
    if (v is double) return v;
    if (v is int)    return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Future<void> settleCommission(String id) async {
    await _dbSvc.settleAttendance(id);
    final idx = _attendanceList.indexWhere((a) => a.id == id);
    if (idx != -1) { _attendanceList[idx].isSettled = true; notifyListeners(); _scheduleBackup(); }
  }

  Future<void> deleteAttendance(String id) async {
    await _dbSvc.deleteAttendance(id);
    _attendanceList.removeWhere((a) => a.id == id);
    notifyListeners(); _scheduleBackup();
  }

  // =========================================================
  // 통계
  // =========================================================
  List<Attendance> get unpaidCommissions => _attendanceList.where((a) => a.isPostpaid && !a.isSettled).toList();
  double get totalUnpaidAmount => unpaidCommissions.fold(0.0, (s, a) => s + a.commission);

  double get todayIncome { final t = DateTime.now(); return _attendanceList.where((a) => _isSameDay(a.workDate, t) && a.isSettled).fold(0.0, (s, a) => s + a.commission); }
  int    get todayWorkersCount { final t = DateTime.now(); return _attendanceList.where((a) => _isSameDay(a.workDate, t)).length; }
  double get weeklyIncome { final now = DateTime.now(); final s = DateTime(now.year, now.month, now.day - (now.weekday - 1)); return _attendanceList.where((a) => !a.workDate.isBefore(s) && a.isSettled).fold(0.0, (x, a) => x + a.commission); }
  double get monthlyIncome { final now = DateTime.now(); return _attendanceList.where((a) => a.workDate.year == now.year && a.workDate.month == now.month && a.isSettled).fold(0.0, (s, a) => s + a.commission); }
  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  // =========================================================
  // 엑셀 내보내기
  // =========================================================
  CellStyle _makeColorStyle(String hex) => CellStyle(backgroundColorHex: ExcelColor.fromHexString(hex), fontColorHex: ExcelColor.fromHexString('#000000'), bold: false);

  void _writeAttendanceSheet(Sheet sheet, List<Attendance> records) {
    final hStyle = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#4472C4'), fontColorHex: ExcelColor.fromHexString('#FFFFFF'), bold: true);
    final headers = ['날짜','근로자','거래처','일당','수수료','유형','정산여부','수수료 합계'];
    for (int c = 0; c < headers.length; c++) { final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)); cell.value = TextCellValue(headers[c]); cell.cellStyle = hStyle; }
    final ss = _makeColorStyle('#92D050'), us = _makeColorStyle('#FF0000'), ds = _makeColorStyle('#87CEEB'), cs = _makeColorStyle('#92D050');
    final ts = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#92D050'), fontColorHex: ExcelColor.fromHexString('#000000'), bold: true);
    final total = records.fold(0.0, (s, a) => s + a.commission);
    for (int i = 0; i < records.length; i++) {
      final att = records[i]; final row = i + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(att.workDate.toIso8601String().split('T')[0]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(att.workerName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(att.clientName);
      final dc = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)); dc.value = IntCellValue(att.dailyWage.toInt()); dc.cellStyle = ds;
      final cc = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)); cc.value = IntCellValue(att.commission.toInt()); cc.cellStyle = cs;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(att.isPostpaid ? '후불' : '선불');
      final sc = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)); sc.value = TextCellValue(att.isSettled ? '완료' : '미수'); sc.cellStyle = att.isSettled ? ss : us;
      if (i == 0) { final tc = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)); tc.value = IntCellValue(total.toInt()); tc.cellStyle = ts; }
    }
  }

  List<Attendance> _filterByPeriod(ExcelPeriodType period) {
    final now = DateTime.now();
    switch (period) {
      case ExcelPeriodType.today:  return _attendanceList.where((a) => _isSameDay(a.workDate, now)).toList();
      case ExcelPeriodType.week:   final s = DateTime(now.year, now.month, now.day - (now.weekday - 1)); return _attendanceList.where((a) => !a.workDate.isBefore(s)).toList();
      case ExcelPeriodType.month:  return _attendanceList.where((a) => a.workDate.year == now.year && a.workDate.month == now.month).toList();
      case ExcelPeriodType.all:    return List.from(_attendanceList);
    }
  }

  String _periodLabel(ExcelPeriodType period) {
    final now = DateTime.now(); String d(int n) => n.toString().padLeft(2, '0');
    switch (period) {
      case ExcelPeriodType.today:  return '일별_${now.year}${d(now.month)}${d(now.day)}';
      case ExcelPeriodType.week:   final mon = now.subtract(Duration(days: now.weekday - 1)); return '주별_${mon.year}${d(mon.month)}${d(mon.day)}';
      case ExcelPeriodType.month:  return '월별_${now.year}${d(now.month)}';
      case ExcelPeriodType.all:    return '전체_${now.year}${d(now.month)}${d(now.day)}';
    }
  }

  Future<String> exportToExcelByPeriod(ExcelPeriodType period) async {
    try {
      final records = _filterByPeriod(period);
      final excel   = Excel.createExcel();
      excel.rename('Sheet1', '출근기록');
      _writeAttendanceSheet(excel['출근기록'], records);
      final docDir    = await getApplicationDocumentsDirectory();
      final exportDir = Directory(p.join(docDir.path, '우신인력_엑셀'));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);
      final filePath = p.join(exportDir.path, '출근기록_${_periodLabel(period)}.xlsx');
      final bytes    = excel.save();
      if (bytes != null) { File(filePath)..createSync(recursive: true)..writeAsBytesSync(bytes); return filePath; }
      return '';
    } catch (e) { print('엑셀 저장 실패: $e'); return ''; }
  }

  Future<String> exportToExcel() async => exportToExcelByPeriod(ExcelPeriodType.all);
}
