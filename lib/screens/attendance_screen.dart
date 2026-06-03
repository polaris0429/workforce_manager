import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/workforce_provider.dart';
import '../models/worker.dart';
import '../models/client.dart';
import '../models/attendance.dart';
import '../utils/image_helper.dart';
import '../utils/formatters.dart';
import '../utils/resident_number_formatter.dart';

// ─────────────────────────────────────────────────────────────
// 커스텀 자동완성 위젯 (IME 안전 + 마우스 클릭 수정 버전)
// ─────────────────────────────────────────────────────────────
class _KeyboardAutocomplete<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) displayString;
  final Widget Function(T item, bool isHighlighted, VoidCallback onTap) itemBuilder;
  final void Function(T) onSelected;
  final TextEditingController controller;
  final FocusNode focusNode;
  final InputDecoration decoration;
  final String? Function(String?)? validator;
  final VoidCallback? onTextChanged;

  const _KeyboardAutocomplete({
    required Key key, required this.items, required this.displayString,
    required this.itemBuilder, required this.onSelected, required this.controller,
    required this.focusNode, required this.decoration, this.validator, this.onTextChanged,
  }) : super(key: key);

  @override
  State<_KeyboardAutocomplete<T>> createState() => _KeyboardAutocompleteState<T>();
}

class _KeyboardAutocompleteState<T> extends State<_KeyboardAutocomplete<T>> {
  final LayerLink _layerLink       = LayerLink();
  OverlayEntry?   _overlay;
  List<T>         _filtered        = [];
  int             _highlightedIndex = -1;
  bool            _isHoveringDropdown = false;

  @override
  void initState() { super.initState(); widget.focusNode.addListener(_onFocusChange); }
  @override
  void dispose() { widget.focusNode.removeListener(_onFocusChange); _safeRemoveOverlay(); super.dispose(); }

  void _onFocusChange() { if (!widget.focusNode.hasFocus && !_isHoveringDropdown) _safeRemoveOverlay(); }
  void _safeRemoveOverlay() { if (_overlay != null) { try { _overlay!.remove(); } catch (_) {} _overlay = null; } }

  void _onTextChanged(String value) {
    widget.onTextChanged?.call();
    if (value.isEmpty) { _safeRemoveOverlay(); setState(() { _filtered = []; _highlightedIndex = -1; }); return; }
    final nf = widget.items.where((i) => widget.displayString(i).contains(value)).toList();
    setState(() { _filtered = nf; _highlightedIndex = nf.isEmpty ? -1 : 0; });
    nf.isEmpty ? _safeRemoveOverlay() : _showOrUpdateOverlay();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_overlay == null || _filtered.isEmpty) return KeyEventResult.ignored;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      setState(() { _highlightedIndex = isShift ? (_highlightedIndex <= 0 ? _filtered.length : _highlightedIndex) - 1 : (_highlightedIndex + 1) % _filtered.length; });
      _showOrUpdateOverlay(); return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_highlightedIndex >= 0 && _highlightedIndex < _filtered.length) { _selectItem(_filtered[_highlightedIndex]); return KeyEventResult.handled; }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) { _safeRemoveOverlay(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  void _selectItem(T item) {
    final text = widget.displayString(item);
    widget.controller.text = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.controller.text == text) widget.controller.selection = TextSelection.collapsed(offset: text.length);
    });
    _safeRemoveOverlay();
    setState(() { _filtered = []; _highlightedIndex = -1; });
    _isHoveringDropdown = false;
    widget.onSelected(item);
    WidgetsBinding.instance.addPostFrameCallback((_) { widget.focusNode.requestFocus(); });
  }

  void _showOrUpdateOverlay() {
    _safeRemoveOverlay();
    _overlay = _buildOverlayEntry();
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  OverlayEntry _buildOverlayEntry() {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return OverlayEntry(builder: (_) => const SizedBox());
    final size = rb.size; final ch = _highlightedIndex; final cf = List<T>.from(_filtered);
    return OverlayEntry(builder: (ctx) => Positioned(width: size.width,
      child: CompositedTransformFollower(link: _layerLink, showWhenUnlinked: false, offset: Offset(0, size.height + 2),
        child: MouseRegion(
          onEnter: (_) { _isHoveringDropdown = true; },
          onExit:  (_) { _isHoveringDropdown = false; if (!widget.focusNode.hasFocus) _safeRemoveOverlay(); },
          child: Material(elevation: 8, borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: cf.length,
                itemBuilder: (_, i) => widget.itemBuilder(cf[i], i == ch, () => _selectItem(cf[i])))))))));
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(link: _layerLink,
      child: Focus(onKeyEvent: _handleKey,
        child: TextFormField(controller: widget.controller, focusNode: widget.focusNode,
            decoration: widget.decoration, validator: widget.validator, onChanged: _onTextChanged)));
  }
}

// ─────────────────────────────────────────────────────────────
// AttendanceScreen
// ─────────────────────────────────────────────────────────────
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  DateTime? _customStart;
  DateTime? _customEnd;
  static const _tabLabels = ['오늘', '이번주', '이번달', '기간 지정'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabLabels.length, vsync: this);
    _tabCtrl.addListener(() { if (mounted) setState(() {}); });
  }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  List<Attendance> _filtered(List<Attendance> all) {
    final now = DateTime.now();
    switch (_tabCtrl.index) {
      case 0: return all.where((a) => _sameDay(a.workDate, now)).toList();
      case 1: final s = DateTime(now.year, now.month, now.day-(now.weekday-1)); return all.where((a) => !a.workDate.isBefore(s)).toList();
      case 2: return all.where((a) => a.workDate.year == now.year && a.workDate.month == now.month).toList();
      case 3:
        if (_customStart == null && _customEnd == null) return all;
        final s = _customStart != null ? DateTime(_customStart!.year, _customStart!.month, _customStart!.day) : DateTime(2000);
        final e = _customEnd   != null ? DateTime(_customEnd!.year,   _customEnd!.month,   _customEnd!.day, 23, 59, 59) : DateTime(2100);
        return all.where((a) => !a.workDate.isBefore(s) && !a.workDate.isAfter(e)).toList();
      default: return all;
    }
  }
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickCustomRange() async {
    final start = await showDatePicker(context: context, initialDate: _customStart ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030), helpText: '시작 날짜 선택');
    if (start == null || !mounted) return;
    final end = await showDatePicker(context: context, initialDate: _customEnd ?? start, firstDate: start, lastDate: DateTime(2030), helpText: '종료 날짜 선택');
    if (end == null || !mounted) return;
    setState(() { _customStart = start; _customEnd = end; });
  }

  void _confirmDelete(BuildContext context, Attendance item) {
    final df = DateFormat('yyyy-MM-dd');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'),
      content: Text('${df.format(item.workDate)} - ${item.workerName}\n(${item.clientName}) 출근 기록을 삭제하시겠습니까?\n\n삭제 후 복구할 수 없습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () { context.read<WorkforceProvider>().deleteAttendance(item.id); Navigator.pop(ctx); },
          child: const Text('삭제')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkforceProvider>();
    final cf       = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final list     = _filtered(provider.attendanceList);

    return Scaffold(
      appBar: AppBar(
        title: const Text('출근 등록'),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF92D050), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.add), label: const Text('출근 등록'),
              onPressed: () => _showDialog(context))),
        ],
        bottom: TabBar(controller: _tabCtrl, tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
            indicatorColor: const Color(0xFF92D050), labelColor: const Color(0xFF4CAF50), unselectedLabelColor: Colors.grey),
      ),
      body: Column(children: [
        if (_tabCtrl.index == 3)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.grey.shade50,
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_customStart != null ? DateFormat('yyyy-MM-dd').format(_customStart!) : '시작 날짜'), onPressed: _pickCustomRange)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('~')),
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_customEnd != null ? DateFormat('yyyy-MM-dd').format(_customEnd!) : '종료 날짜'), onPressed: _pickCustomRange)),
              const SizedBox(width: 8),
              if (_customStart != null || _customEnd != null)
                IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: '초기화',
                    onPressed: () => setState(() { _customStart = null; _customEnd = null; })),
            ]),
          ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('${list.length}건', style: TextStyle(fontSize: 12, color: Colors.grey[600])))),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('기록이 없습니다.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final item = list[i];
                    return Card(margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(borderRadius: BorderRadius.circular(8), onTap: () => _showDialog(context, attendance: item),
                        child: Padding(padding: const EdgeInsets.all(12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(width: 52, padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                              child: Column(children: [
                                Text(DateFormat('MM/dd').format(item.workDate), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                Text(DateFormat('E', 'ko').format(item.workDate), style: TextStyle(fontSize: 11, color: Colors.blue.shade400)),
                              ])),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(item.workerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                if (item.workerGender.isNotEmpty) ...[const SizedBox(width: 6),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: item.workerGender == '남' ? Colors.blue.shade50 : Colors.pink.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: item.workerGender == '남' ? Colors.blue.shade200 : Colors.pink.shade200)),
                                    child: Text(item.workerGender, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: item.workerGender == '남' ? Colors.blue.shade700 : Colors.pink.shade700)))],
                                if (item.isPostpaid) ...[const SizedBox(width: 6),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
                                    child: Text('후불', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade700)))],
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [const Icon(Icons.business, size: 13, color: Colors.grey), const SizedBox(width: 4), Text(item.clientName, style: const TextStyle(fontSize: 13))]),
                              const SizedBox(height: 4),
                              Row(children: [_infoChip('일당', cf.format(item.dailyWage), Colors.lightBlue), const SizedBox(width: 8), _infoChip('수수료', cf.format(item.commission), Colors.green)]),
                              if (item.notes.isNotEmpty) ...[const SizedBox(height: 4),
                                Row(children: [const Icon(Icons.notes, size: 13, color: Colors.grey), const SizedBox(width: 4),
                                  Expanded(child: Text(item.notes, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis))])],
                            ])),
                            Column(mainAxisAlignment: MainAxisAlignment.start, children: [
                              if (item.idPhotoPath != null) const Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.image, color: Colors.blue, size: 18)),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _confirmDelete(context, item)),
                            ]),
                          ]))));
                  }),
        ),
      ]),
    );
  }

  Widget _infoChip(String label, String value, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: color.shade200)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 11, color: color.shade600)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade800)),
      ]));
  }

  void _showDialog(BuildContext context, {Attendance? attendance}) {
    showDialog(context: context, builder: (_) => AttendanceDialog(attendance: attendance));
  }
}

// ─────────────────────────────────────────────────────────────
// AttendanceDialog
// ─────────────────────────────────────────────────────────────
class AttendanceDialog extends StatefulWidget {
  final Attendance? attendance;
  const AttendanceDialog({super.key, this.attendance});
  @override
  State<AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<AttendanceDialog> {
  final _formKey = GlobalKey<FormState>();
  static const _workerAutoKey = ValueKey('att_worker_auto');
  static const _clientAutoKey = ValueKey('att_client_auto');

  final _workerIdNotifier = ValueNotifier<String?>(null);
  final _clientIdNotifier = ValueNotifier<String?>(null);

  // 근로자 필드
  late TextEditingController _workerNameCtrl;
  String _workerGender = '';
  late TextEditingController _workerResidentCtrl;   // 주민번호 (숫자만 저장)
  late TextEditingController _workerPhoneCtrl;       // 휴대폰번호
  late TextEditingController _workerHomePhoneCtrl;   // 집전화번호 (선택)
  late TextEditingController _workerAddressCtrl;
  late TextEditingController _workerBankNameCtrl;
  late TextEditingController _workerBankAccountCtrl;
  late TextEditingController _workerCareerCtrl;

  // 거래처 필드
  late TextEditingController _clientNameCtrl;
  late TextEditingController _clientAddressCtrl;
  late TextEditingController _clientContactCtrl;
  late TextEditingController _clientEmailCtrl;
  late TextEditingController _clientPhoneCtrl;       // 연락처
  late TextEditingController _clientOfficePhoneCtrl; // 회사번호 (선택)
  late TextEditingController _clientNotesCtrl;

  // 근무 정보
  late TextEditingController _wageCtrl;
  late TextEditingController _commissionRateCtrl;
  late TextEditingController _notesCtrl;

  late DateTime _selectedDate;
  bool  _isPostpaid = false;
  File? _frontImage, _backImage;

  final FocusNode _workerNameFocus = FocusNode();
  final FocusNode _clientNameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final att     = widget.attendance;
    _selectedDate = att?.workDate ?? DateTime.now();
    _workerGender = att?.workerGender ?? '';

    _workerNameCtrl        = TextEditingController(text: att?.workerName ?? '');
    // 주민번호: 저장된 숫자열 → 화면 포맷 (자동 대시)
    _workerResidentCtrl    = TextEditingController(
        text: ResidentNumberFormatter.format(att?.workerResidentNumber ?? ''));
    _workerPhoneCtrl       = TextEditingController(text: PhoneInputFormatter.format(att?.workerPhone ?? ''));
    _workerHomePhoneCtrl   = TextEditingController(text: PhoneInputFormatter.format(att?.workerHomePhone ?? ''));
    _workerAddressCtrl     = TextEditingController(text: att?.workerAddress ?? '');
    _workerBankNameCtrl    = TextEditingController(text: att?.workerBankName ?? '');
    _workerBankAccountCtrl = TextEditingController(text: att?.workerBankAccount ?? '');
    _workerCareerCtrl      = TextEditingController(text: att?.workerCareer ?? '');

    _clientNameCtrl        = TextEditingController(text: att?.clientName ?? '');
    _clientAddressCtrl     = TextEditingController(text: att?.clientAddress ?? '');
    _clientContactCtrl     = TextEditingController(text: att?.clientContactPerson ?? '');
    _clientEmailCtrl       = TextEditingController(text: att?.clientEmail ?? '');
    _clientPhoneCtrl       = TextEditingController(text: PhoneInputFormatter.format(att?.clientPhone ?? ''));
    _clientOfficePhoneCtrl = TextEditingController(text: PhoneInputFormatter.format(att?.clientOfficePhone ?? ''));
    _clientNotesCtrl       = TextEditingController(text: att?.clientNotes ?? '');

    _wageCtrl           = TextEditingController(text: att?.dailyWage != null ? att!.dailyWage.toStringAsFixed(0) : '');
    _commissionRateCtrl = TextEditingController(text: att?.commissionRate != null ? att!.commissionRate.toStringAsFixed(0) : '10');
    _notesCtrl          = TextEditingController(text: att?.notes ?? '');

    _workerIdNotifier.value = att?.workerId;
    _clientIdNotifier.value = att?.clientId;
    _isPostpaid = att?.isPostpaid ?? false;

    if (att?.idPhotoPath != null)     _frontImage = ImageHelper.getFileFromPath(att!.idPhotoPath);
    if (att?.idPhotoBackPath != null) _backImage  = ImageHelper.getFileFromPath(att!.idPhotoBackPath);
  }

  @override
  void dispose() {
    _workerIdNotifier.dispose(); _clientIdNotifier.dispose();
    _workerNameFocus.dispose();  _clientNameFocus.dispose();
    for (final c in [
      _workerNameCtrl, _workerResidentCtrl, _workerPhoneCtrl, _workerHomePhoneCtrl,
      _workerAddressCtrl, _workerBankNameCtrl, _workerBankAccountCtrl, _workerCareerCtrl,
      _clientNameCtrl, _clientAddressCtrl, _clientContactCtrl,
      _clientEmailCtrl, _clientPhoneCtrl, _clientOfficePhoneCtrl, _clientNotesCtrl,
      _wageCtrl, _commissionRateCtrl, _notesCtrl,
    ]) c.dispose();
    super.dispose();
  }

  // ── 근로자 선택 → 모든 필드 자동 채움 ────────────────────
  void _onWorkerSelected(Worker w) {
    _workerIdNotifier.value = w.id;
    setState(() { _workerGender = w.gender; });
    _workerResidentCtrl.text    = ResidentNumberFormatter.format(w.residentNumber);
    _workerPhoneCtrl.text       = PhoneInputFormatter.format(w.phone);
    _workerHomePhoneCtrl.text   = PhoneInputFormatter.format(w.homePhone);
    _workerAddressCtrl.text     = w.address;
    _workerBankNameCtrl.text    = w.bankName;
    _workerBankAccountCtrl.text = w.bankAccount;
    _workerCareerCtrl.text      = w.career;
    if (w.idPhotoPath != null)     _frontImage = ImageHelper.getFileFromPath(w.idPhotoPath);
    if (w.idPhotoBackPath != null) _backImage  = ImageHelper.getFileFromPath(w.idPhotoBackPath);
  }

  // ── 거래처 선택 → 모든 필드 자동 채움 ────────────────────
  void _onClientSelected(Client c) {
    _clientIdNotifier.value        = c.id;
    _clientAddressCtrl.text        = c.address;
    _clientContactCtrl.text        = c.contactPerson;
    _clientEmailCtrl.text          = c.email;
    _clientPhoneCtrl.text          = PhoneInputFormatter.format(c.phone);
    _clientOfficePhoneCtrl.text    = PhoneInputFormatter.format(c.officePhone);
    _clientNotesCtrl.text          = c.notes;
  }

  Widget _genderButton(String label, MaterialColor color) {
    final selected = _workerGender == label;
    return GestureDetector(
      onTap: () => setState(() => _workerGender = selected ? '' : label),
      child: AnimatedContainer(duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color.shade400 : Colors.grey.shade300, width: 1.5)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
            color: selected ? color.shade700 : Colors.grey.shade500))));
  }

  Widget _buildImagePicker(bool isFront) {
    final file = isFront ? _frontImage : _backImage;
    return Expanded(child: InkWell(
      onTap: () async {
        final r = await FilePicker.platform.pickFiles(type: FileType.image);
        if (r != null) setState(() {
          if (isFront) _frontImage = File(r.files.single.path!);
          else         _backImage  = File(r.files.single.path!);
        });
      },
      child: Container(height: 80,
        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
        child: file == null ? const Center(child: Icon(Icons.camera_alt, color: Colors.grey)) : Image.file(file, fit: BoxFit.cover))));
  }

  String? _validateNumber(String? v, String fn) {
    if (v == null || v.trim().isEmpty) return '$fn을 입력하세요';
    final n = double.tryParse(v.trim());
    if (n == null) return '숫자만 입력 가능합니다';
    if (n < 0)     return '0 이상의 값을 입력하세요';
    return null;
  }

  // ── 저장 ─────────────────────────────────────────────────
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final provider   = context.read<WorkforceProvider>();
    // 주민번호: 대시 제거 후 숫자만
    final cleanResident    = ResidentNumberFormatter.strip(_workerResidentCtrl.text);
    final cleanPhone       = _workerPhoneCtrl.text.replaceAll('-', '').trim();
    final cleanHomePhone   = _workerHomePhoneCtrl.text.replaceAll('-', '').trim();
    final cleanClientPhone = _clientPhoneCtrl.text.replaceAll('-', '').trim();
    final cleanOfficePhone = _clientOfficePhoneCtrl.text.replaceAll('-', '').trim();
    final wId  = _workerIdNotifier.value;
    final cId  = _clientIdNotifier.value;
    final wage = double.parse(_wageCtrl.text.trim());
    final rate = double.parse(_commissionRateCtrl.text.trim());

    Worker? existing;
    try { existing = provider.workers.firstWhere((w) => w.phone.replaceAll('-','').trim() == cleanPhone); }
    catch (_) { existing = null; }

    void doSave() {
      if (widget.attendance == null) {
        provider.addAttendance(
          workerId: wId, workerName: _workerNameCtrl.text.trim(), workerGender: _workerGender,
          workerResidentNumber: cleanResident, workerPhone: cleanPhone,
          workerHomePhone: cleanHomePhone, workerAddress: _workerAddressCtrl.text.trim(),
          workerBankName: _workerBankNameCtrl.text.trim(), workerBankAccount: _workerBankAccountCtrl.text.trim(),
          workerCareer: _workerCareerCtrl.text.trim(),
          clientId: cId, clientName: _clientNameCtrl.text.trim(),
          clientAddress: _clientAddressCtrl.text.trim(),
          clientContactPerson: _clientContactCtrl.text.trim(),
          clientPhone: cleanClientPhone, clientOfficePhone: cleanOfficePhone,
          clientEmail: _clientEmailCtrl.text.trim(), clientNotes: _clientNotesCtrl.text.trim(),
          workDate: _selectedDate, dailyWage: wage, commissionRate: rate,
          isPostpaid: _isPostpaid, notes: _notesCtrl.text.trim(),
          idPhotoFront: _frontImage, idPhotoBack: _backImage,
        );
      } else {
        provider.updateAttendance(id: widget.attendance!.id, data: {
          'worker_id': wId, 'worker_name': _workerNameCtrl.text.trim(),
          'worker_gender': _workerGender, 'worker_resident_number': cleanResident,
          'worker_phone': cleanPhone, 'worker_home_phone': cleanHomePhone,
          'worker_address': _workerAddressCtrl.text.trim(),
          'worker_bank_name': _workerBankNameCtrl.text.trim(), 'worker_bank_account': _workerBankAccountCtrl.text.trim(),
          'worker_career': _workerCareerCtrl.text.trim(),
          'client_id': cId, 'client_name': _clientNameCtrl.text.trim(),
          'client_address': _clientAddressCtrl.text.trim(),
          'client_contact_person': _clientContactCtrl.text.trim(),
          'client_phone': cleanClientPhone, 'client_office_phone': cleanOfficePhone,
          'client_email': _clientEmailCtrl.text.trim(), 'client_notes': _clientNotesCtrl.text.trim(),
          'work_date': _selectedDate, 'daily_wage': wage, 'commission_rate': rate,
          'is_postpaid': _isPostpaid, 'notes': _notesCtrl.text.trim(),
        }, newFrontImage: _frontImage, newBackImage: _backImage);
      }
      Navigator.pop(context);

      if (widget.attendance == null) {
        final needWorker = wId == null && provider.suggestWorkerRegistration;
        final needClient = cId == null && provider.suggestClientRegistration;
        if (needWorker) {
          _askRegisterWorker(onDone: needClient ? _askRegisterClient : null);
        } else if (needClient) {
          _askRegisterClient();
        }
      }
    }

    if (existing != null && existing.id != wId) {
      var msg = '입력한 전화번호(${PhoneInputFormatter.format(existing.phone)})를 가진\n기존 근로자 \'${existing.name}\'가 있습니다.';
      if (existing.isBlacklisted) msg += '\n\n⚠️ 블랙리스트 대상입니다! (${existing.blacklistReason})';
      msg += '\n\n계속 진행하시겠습니까?';
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('중복/경고 알림'), content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); doSave(); }, child: const Text('진행')),
        ],
      ));
    } else { doSave(); }
  }

  // ── 근로자 등록 제안 ──────────────────────────────────────
  void _askRegisterWorker({VoidCallback? onDone}) {
    final provider   = context.read<WorkforceProvider>();
    final cleanPhone = _workerPhoneCtrl.text.replaceAll('-', '').trim();
    if (provider.workers.any((w) => w.phone.replaceAll('-','').trim() == cleanPhone)) {
      onDone?.call(); return;
    }
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Row(children: [Icon(Icons.person_add, color: Colors.blue), SizedBox(width: 8), Text('근로자 등록')]),
      content: Text('${_workerNameCtrl.text.trim()} 님을 근로자 목록에 등록하시겠습니까?\n\n등록하면 다음 출근 등록 시 자동완성에서 바로 선택할 수 있습니다.'),
      actions: [
        TextButton(onPressed: () { Navigator.pop(ctx); onDone?.call(); }, child: const Text('나중에')),
        ElevatedButton.icon(icon: const Icon(Icons.person_add, size: 16), label: const Text('등록'),
          onPressed: () {
            final cleanResident  = ResidentNumberFormatter.strip(_workerResidentCtrl.text);
            final cleanPhone     = _workerPhoneCtrl.text.replaceAll('-','').trim();
            final cleanHomePhone = _workerHomePhoneCtrl.text.replaceAll('-','').trim();
            provider.addWorker(
              name: _workerNameCtrl.text.trim(), gender: _workerGender,
              residentNumber: cleanResident, address: _workerAddressCtrl.text.trim(),
              phone: cleanPhone, homePhone: cleanHomePhone,
              bankName: _workerBankNameCtrl.text.trim(), bankAccount: _workerBankAccountCtrl.text.trim(),
              career: _workerCareerCtrl.text.trim(), notes: _notesCtrl.text.trim(),
              idPhotoFront: _frontImage, idPhotoBack: _backImage,
            );
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${_workerNameCtrl.text.trim()} 님이 근로자 목록에 등록되었습니다.')));
            onDone?.call();
          }),
      ],
    ));
  }

  // ── 거래처 등록 제안 ──────────────────────────────────────
  void _askRegisterClient() {
    final provider   = context.read<WorkforceProvider>();
    final clientName = _clientNameCtrl.text.trim();
    if (clientName.isEmpty) return;
    if (provider.clients.any((c) => c.name == clientName)) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Row(children: [Icon(Icons.business, color: Colors.blue), SizedBox(width: 8), Text('거래처 등록')]),
      content: Text('"$clientName"을 거래처 목록에 등록하시겠습니까?\n\n등록하면 다음 출근 등록 시 자동완성에서 바로 선택할 수 있습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('나중에')),
        ElevatedButton.icon(icon: const Icon(Icons.business, size: 16), label: const Text('등록'),
          onPressed: () {
            provider.addClient(Client(
              name: clientName, address: _clientAddressCtrl.text.trim(),
              contactPerson: _clientContactCtrl.text.trim(),
              email: _clientEmailCtrl.text.trim(),
              phone: _clientPhoneCtrl.text.replaceAll('-','').trim(),
              officePhone: _clientOfficePhoneCtrl.text.replaceAll('-','').trim(),
              notes: _clientNotesCtrl.text.trim(), createdAt: DateTime.now(),
            ));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$clientName"이 거래처 목록에 등록되었습니다.')));
          }),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final workers = context.read<WorkforceProvider>().workers;
    final clients = context.read<WorkforceProvider>().clients;

    return AlertDialog(
      title: Text(widget.attendance != null ? '출근 수정' : '출근 등록'),
      content: SizedBox(width: 560, child: Form(key: _formKey,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [

          // 날짜
          ListTile(
            title: Text('날짜: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final p = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (p != null) setState(() => _selectedDate = p);
            }),
          const Divider(),

          // ── 근로자 정보 ────────────────────────────────────
          const Align(alignment: Alignment.centerLeft,
            child: Text('근로자 정보', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
          const SizedBox(height: 8),

          // 이름 + 성별
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _KeyboardAutocomplete<Worker>(
              key: _workerAutoKey, items: workers, displayString: (w) => w.name,
              controller: _workerNameCtrl, focusNode: _workerNameFocus,
              decoration: const InputDecoration(labelText: '이름 (직접 입력 가능) *', suffixIcon: Icon(Icons.search)),
              validator: (v) => (v == null || v.trim().isEmpty) ? '근로자 이름을 입력하세요' : null,
              onTextChanged: () => _workerIdNotifier.value = null,
              onSelected: _onWorkerSelected,
              itemBuilder: (Worker w, bool hl, VoidCallback onTap) => InkWell(onTap: onTap,
                child: Container(color: hl ? Colors.blue.shade50 : null,
                  child: ListTile(dense: true,
                    leading: w.isBlacklisted ? const Icon(Icons.warning, color: Colors.red, size: 20) : const Icon(Icons.person, size: 20),
                    title: Text(w.name, style: TextStyle(fontWeight: hl ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text('${PhoneInputFormatter.format(w.phone)}${w.isBlacklisted ? '  ⚠️ ${w.blacklistReason}' : ''}',
                        style: TextStyle(color: w.isBlacklisted ? Colors.red : Colors.grey, fontSize: 12))))),
            )),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('성별', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Row(children: [_genderButton('남', Colors.blue), const SizedBox(width: 6), _genderButton('여', Colors.pink)]),
            ]),
          ]),
          const SizedBox(height: 6),

          // 주민등록번호 (자동 대시)
          TextFormField(controller: _workerResidentCtrl,
              decoration: const InputDecoration(labelText: '주민등록번호', hintText: '000000-0000000'),
              keyboardType: TextInputType.number,
              inputFormatters: [ResidentNumberFormatter()]),

          // 주소
          TextFormField(controller: _workerAddressCtrl, decoration: const InputDecoration(labelText: '주소')),

          // 휴대폰번호 *
          TextFormField(controller: _workerPhoneCtrl,
              decoration: const InputDecoration(labelText: '휴대폰번호', hintText: '010-0000-0000'),
              inputFormatters: [PhoneInputFormatter()]),

          // 집전화번호 (선택)
          TextFormField(controller: _workerHomePhoneCtrl,
              decoration: const InputDecoration(labelText: '집전화번호', hintText: '02-0000-0000 (선택)'),
              inputFormatters: [PhoneInputFormatter()]),

          Row(children: [
            Expanded(child: TextFormField(controller: _workerBankNameCtrl, decoration: const InputDecoration(labelText: '은행명'))),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _workerBankAccountCtrl, decoration: const InputDecoration(labelText: '계좌번호'))),
          ]),
          TextFormField(controller: _workerCareerCtrl, decoration: const InputDecoration(labelText: '경력사항'), maxLines: 2),
          const SizedBox(height: 12), const Divider(),

          // ── 거래처 정보 ────────────────────────────────────
          const Align(alignment: Alignment.centerLeft,
            child: Text('거래처 정보', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
          const SizedBox(height: 8),

          _KeyboardAutocomplete<Client>(
            key: _clientAutoKey, items: clients, displayString: (c) => c.name,
            controller: _clientNameCtrl, focusNode: _clientNameFocus,
            decoration: const InputDecoration(labelText: '거래처명 (직접 입력 가능) *', suffixIcon: Icon(Icons.search)),
            validator: (v) => (v == null || v.trim().isEmpty) ? '거래처를 입력하세요' : null,
            onTextChanged: () {
              _clientIdNotifier.value = null;
              _clientAddressCtrl.clear(); _clientContactCtrl.clear();
              _clientEmailCtrl.clear(); _clientPhoneCtrl.clear();
              _clientOfficePhoneCtrl.clear(); _clientNotesCtrl.clear();
            },
            onSelected: _onClientSelected,
            itemBuilder: (Client c, bool hl, VoidCallback onTap) => InkWell(onTap: onTap,
              child: Container(color: hl ? Colors.blue.shade50 : null,
                child: ListTile(dense: true, leading: const Icon(Icons.business, size: 20),
                  title: Text(c.name, style: TextStyle(fontWeight: hl ? FontWeight.bold : FontWeight.normal)),
                  subtitle: c.address.isNotEmpty ? Text(c.address, style: const TextStyle(fontSize: 12, color: Colors.grey)) : null))),
          ),
          const SizedBox(height: 6),
          TextFormField(controller: _clientAddressCtrl, decoration: const InputDecoration(labelText: '현장 주소')),
          // 담당자 + 이메일
          Row(children: [
            Expanded(child: TextFormField(controller: _clientContactCtrl, decoration: const InputDecoration(labelText: '담당자'))),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _clientEmailCtrl, decoration: const InputDecoration(labelText: '이메일'))),
          ]),
          // 연락처 + 회사번호
          Row(children: [
            Expanded(child: TextFormField(controller: _clientPhoneCtrl,
                decoration: const InputDecoration(labelText: '연락처', hintText: '010-0000-0000'),
                inputFormatters: [PhoneInputFormatter()])),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _clientOfficePhoneCtrl,
                decoration: const InputDecoration(labelText: '회사번호', hintText: '02-0000-0000 (선택)'),
                inputFormatters: [PhoneInputFormatter()])),
          ]),
          TextFormField(controller: _clientNotesCtrl, decoration: const InputDecoration(labelText: '비고'), maxLines: 2),
          const SizedBox(height: 12), const Divider(),

          // ── 근무 정보 ──────────────────────────────────────
          const Align(alignment: Alignment.centerLeft,
            child: Text('근무 정보', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextFormField(controller: _wageCtrl, decoration: const InputDecoration(labelText: '일당 *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                validator: (v) => _validateNumber(v, '일당'))),
            const SizedBox(width: 16),
            Expanded(child: TextFormField(controller: _commissionRateCtrl, decoration: const InputDecoration(labelText: '수수료율(%) *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                validator: (v) => _validateNumber(v, '수수료율'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('지급 방식:', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 12),
            ChoiceChip(label: const Text('선불'), selected: !_isPostpaid, onSelected: (v) { if (v) setState(() => _isPostpaid = false); }),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('후불'), selected: _isPostpaid, onSelected: (v) { if (v) setState(() => _isPostpaid = true); }),
          ]),
          TextFormField(controller: _notesCtrl, decoration: const InputDecoration(labelText: '메모')),
          const SizedBox(height: 12),
          Row(children: [_buildImagePicker(true), const SizedBox(width: 10), _buildImagePicker(false)]),
        ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        ElevatedButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}
