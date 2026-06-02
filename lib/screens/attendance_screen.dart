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

// ─────────────────────────────────────────────────────────────
// 커스텀 자동완성 위젯
//
// 버그 수정:
//   1. 마우스 클릭 시 포커스 소실로 overlay가 먼저 닫히는 문제
//      → MouseRegion으로 hover 상태 추적, hover 중에는 포커스 소실 무시
//   2. 커서가 앞에서 깜빡이는 문제
//      → _selectItem 후 addPostFrameCallback으로 다음 프레임에 selection 재설정
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
    required Key key,
    required this.items,
    required this.displayString,
    required this.itemBuilder,
    required this.onSelected,
    required this.controller,
    required this.focusNode,
    required this.decoration,
    this.validator,
    this.onTextChanged,
  }) : super(key: key);

  @override
  State<_KeyboardAutocomplete<T>> createState() => _KeyboardAutocompleteState<T>();
}

class _KeyboardAutocompleteState<T> extends State<_KeyboardAutocomplete<T>> {
  final LayerLink _layerLink        = LayerLink();
  OverlayEntry?   _overlay;
  List<T>         _filtered         = [];
  int             _highlightedIndex = -1;

  // 드롭다운 위에 마우스가 올라가 있는지 추적
  // → hover 중에는 포커스 소실로 overlay를 닫지 않음 (클릭 씹힘 방지)
  bool _isHoveringDropdown = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _safeRemoveOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    // hover 중이면 닫지 않음 → 마우스 클릭이 완료될 때까지 overlay 유지
    if (!widget.focusNode.hasFocus && !_isHoveringDropdown) {
      _safeRemoveOverlay();
    }
  }

  void _safeRemoveOverlay() {
    if (_overlay != null) {
      try { _overlay!.remove(); } catch (_) {}
      _overlay = null;
    }
  }

  void _onTextChanged(String value) {
    widget.onTextChanged?.call();
    if (value.isEmpty) {
      _safeRemoveOverlay();
      setState(() { _filtered = []; _highlightedIndex = -1; });
      return;
    }
    final nf = widget.items
        .where((i) => widget.displayString(i).contains(value))
        .toList();
    setState(() { _filtered = nf; _highlightedIndex = nf.isEmpty ? -1 : 0; });
    nf.isEmpty ? _safeRemoveOverlay() : _showOrUpdateOverlay();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_overlay == null || _filtered.isEmpty) return KeyEventResult.ignored;

    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      setState(() {
        _highlightedIndex = isShift
            ? (_highlightedIndex <= 0 ? _filtered.length : _highlightedIndex) - 1
            : (_highlightedIndex + 1) % _filtered.length;
      });
      _showOrUpdateOverlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_highlightedIndex >= 0 && _highlightedIndex < _filtered.length) {
        _selectItem(_filtered[_highlightedIndex]);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _safeRemoveOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectItem(T item) {
    final text = widget.displayString(item);

    // 텍스트 먼저 설정
    widget.controller.text = text;

    // 커서를 맨 끝으로 — 다음 프레임에 설정해야 Flutter가 덮어쓰지 않음
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.controller.text == text) {
        widget.controller.selection =
            TextSelection.collapsed(offset: widget.controller.text.length);
      }
    });

    _safeRemoveOverlay();
    setState(() { _filtered = []; _highlightedIndex = -1; });
    _isHoveringDropdown = false;

    // onSelected 콜백 (다른 필드 채우기 등) 실행
    widget.onSelected(item);

    // 포커스 복원 — 다른 필드 채우는 과정에서 포커스가 이동했을 수 있음
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode.requestFocus();
    });
  }

  void _showOrUpdateOverlay() {
    _safeRemoveOverlay();
    _overlay = _buildOverlayEntry();
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  OverlayEntry _buildOverlayEntry() {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return OverlayEntry(builder: (_) => const SizedBox());
    final size = rb.size;
    final ch   = _highlightedIndex;
    final cf   = List<T>.from(_filtered);

    return OverlayEntry(
      builder: (ctx) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 2),
          child: MouseRegion(
            // hover 진입: overlay 닫힘 억제 시작
            onEnter: (_) { _isHoveringDropdown = true; },
            // hover 이탈: 억제 해제. 포커스도 없으면 즉시 닫기
            onExit:  (_) {
              _isHoveringDropdown = false;
              if (!widget.focusNode.hasFocus) _safeRemoveOverlay();
            },
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  padding:     EdgeInsets.zero,
                  shrinkWrap:  true,
                  itemCount:   cf.length,
                  itemBuilder: (_, i) => widget.itemBuilder(
                    cf[i],
                    i == ch,
                    () => _selectItem(cf[i]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        onKeyEvent: _handleKey,
        child: TextFormField(
          controller: widget.controller,
          focusNode:  widget.focusNode,
          decoration: widget.decoration,
          validator:  widget.validator,
          onChanged:  _onTextChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AttendanceScreen
// ─────────────────────────────────────────────────────────────
class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  void _confirmDelete(BuildContext context, Attendance item) {
    final df = DateFormat('yyyy-MM-dd');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'),
      content: Text('${df.format(item.workDate)} - ${item.workerName}\n'
          '(${item.clientName}) 출근 기록을 삭제하시겠습니까?\n\n삭제 후 복구할 수 없습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () { context.read<WorkforceProvider>().deleteAttendance(item.id); Navigator.pop(ctx); },
          child: const Text('삭제'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkforceProvider>();
    final cf = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('출근 등록'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF92D050),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('출근 등록'),
              onPressed: () => _showDialog(context),
            ),
          ),
        ],
      ),
      body: provider.attendanceList.isEmpty
          ? const Center(child: Text('기록이 없습니다.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.attendanceList.length,
              itemBuilder: (context, i) {
                final item = provider.attendanceList[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    onTap: () => _showDialog(context, attendance: item),
                    title: Text('${df.format(item.workDate)} - ${item.workerName}'
                        '${item.workerGender.isNotEmpty ? ' (${item.workerGender})' : ''}'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('🏢 ${item.clientName}'),
                      Row(children: [
                        Text('💰 수수료: ${cf.format(item.commission)} '),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.isPostpaid ? Colors.orange.shade100 : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4)),
                          child: Text(item.isPostpaid ? '후불' : '선불',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                                  color: item.isPostpaid ? Colors.deepOrange : Colors.green[800])),
                        ),
                      ]),
                      Text('💵 지급액: ${cf.format(item.netWage)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (item.idPhotoPath != null) const Icon(Icons.image, color: Colors.blue),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.grey),
                        onPressed: () => _confirmDelete(context, item),
                      ),
                    ]),
                  ),
                );
              }),
    );
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

  late TextEditingController _workerNameCtrl;
  String _workerGender = '';
  late TextEditingController _workerResidentCtrl;
  late TextEditingController _workerPhoneCtrl;
  late TextEditingController _workerAddressCtrl;
  late TextEditingController _workerBankNameCtrl;
  late TextEditingController _workerBankAccountCtrl;
  late TextEditingController _workerCareerCtrl;

  late TextEditingController _clientNameCtrl;
  late TextEditingController _clientAddressCtrl;

  late DateTime              _selectedDate;
  late TextEditingController _wageCtrl;
  late TextEditingController _commissionRateCtrl;
  late TextEditingController _notesCtrl;

  bool  _isPostpaid = false;
  File? _frontImage;
  File? _backImage;

  final FocusNode _workerNameFocus = FocusNode();
  final FocusNode _clientNameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final att     = widget.attendance;
    _selectedDate = att?.workDate ?? DateTime.now();
    _workerGender = att?.workerGender ?? '';

    _workerNameCtrl        = TextEditingController(text: att?.workerName ?? '');
    _workerResidentCtrl    = TextEditingController(text: att?.workerResidentNumber ?? '');
    _workerPhoneCtrl       = TextEditingController(text: PhoneInputFormatter.format(att?.workerPhone ?? ''));
    _workerAddressCtrl     = TextEditingController(text: att?.workerAddress ?? '');
    _workerBankNameCtrl    = TextEditingController(text: att?.workerBankName ?? '');
    _workerBankAccountCtrl = TextEditingController(text: att?.workerBankAccount ?? '');
    _workerCareerCtrl      = TextEditingController(text: att?.workerCareer ?? '');
    _clientNameCtrl        = TextEditingController(text: att?.clientName ?? '');
    _clientAddressCtrl     = TextEditingController(text: att?.clientAddress ?? '');
    _wageCtrl              = TextEditingController(
        text: att?.dailyWage != null ? att!.dailyWage.toStringAsFixed(0) : '');
    _commissionRateCtrl    = TextEditingController(
        text: att?.commissionRate != null ? att!.commissionRate.toStringAsFixed(0) : '10');
    _notesCtrl             = TextEditingController(text: att?.notes ?? '');

    _workerIdNotifier.value = att?.workerId;
    _clientIdNotifier.value = att?.clientId;
    _isPostpaid             = att?.isPostpaid ?? false;

    if (att?.idPhotoPath != null)     _frontImage = ImageHelper.getFileFromPath(att!.idPhotoPath);
    if (att?.idPhotoBackPath != null) _backImage  = ImageHelper.getFileFromPath(att!.idPhotoBackPath);
  }

  @override
  void dispose() {
    _workerIdNotifier.dispose();
    _clientIdNotifier.dispose();
    _workerNameFocus.dispose();
    _clientNameFocus.dispose();
    for (final c in [
      _workerNameCtrl, _workerResidentCtrl, _workerPhoneCtrl,
      _workerAddressCtrl, _workerBankNameCtrl, _workerBankAccountCtrl,
      _workerCareerCtrl, _clientNameCtrl, _clientAddressCtrl,
      _wageCtrl, _commissionRateCtrl, _notesCtrl,
    ]) c.dispose();
    super.dispose();
  }

  // 근로자 선택 시 다른 필드 자동 채우기
  // setState는 성별처럼 UI가 바뀌는 것만 — 나머지는 controller.text 직접 설정
  void _onWorkerSelected(Worker w) {
    _workerIdNotifier.value = w.id;
    // 성별만 setState (버튼 UI 갱신 필요)
    setState(() { _workerGender = w.gender; });
    // 나머지 컨트롤러: text 직접 할당 (rebuild 없음 → IME/포커스 안전)
    _workerResidentCtrl.text    = w.residentNumber;
    _workerPhoneCtrl.text       = PhoneInputFormatter.format(w.phone);
    _workerAddressCtrl.text     = w.address;
    _workerBankNameCtrl.text    = w.bankName;
    _workerBankAccountCtrl.text = w.bankAccount;
    _workerCareerCtrl.text      = w.career;
    if (w.idPhotoPath != null)     _frontImage = ImageHelper.getFileFromPath(w.idPhotoPath);
    if (w.idPhotoBackPath != null) _backImage  = ImageHelper.getFileFromPath(w.idPhotoBackPath);
  }

  Widget _genderButton(String label, MaterialColor color) {
    final selected = _workerGender == label;
    return GestureDetector(
      onTap: () => setState(() => _workerGender = selected ? '' : label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:  selected ? color.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color.shade400 : Colors.grey.shade300, width: 1.5),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
            color: selected ? color.shade700 : Colors.grey.shade500)),
      ),
    );
  }

  Widget _buildImagePicker(bool isFront) {
    final file = isFront ? _frontImage : _backImage;
    return Expanded(child: InkWell(
      onTap: () async {
        final r = await FilePicker.platform.pickFiles(type: FileType.image);
        if (r != null) setState(() {
          if (isFront) _frontImage = File(r.files.single.path!);
          else _backImage = File(r.files.single.path!);
        });
      },
      child: Container(
        height: 80,
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4)),
        child: file == null
            ? const Center(child: Icon(Icons.camera_alt, color: Colors.grey))
            : Image.file(file, fit: BoxFit.cover),
      ),
    ));
  }

  String? _validateNumber(String? v, String fn) {
    if (v == null || v.trim().isEmpty) return '$fn을 입력하세요';
    final n = double.tryParse(v.trim());
    if (n == null) return '숫자만 입력 가능합니다';
    if (n < 0)     return '0 이상의 값을 입력하세요';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final provider   = context.read<WorkforceProvider>();
    final cleanPhone = _workerPhoneCtrl.text.replaceAll('-', '').trim();
    final wId        = _workerIdNotifier.value;
    final cId        = _clientIdNotifier.value;
    final wage       = double.parse(_wageCtrl.text.trim());
    final rate       = double.parse(_commissionRateCtrl.text.trim());

    Worker? existing;
    try {
      existing = provider.workers.firstWhere(
          (w) => w.phone.replaceAll('-', '').trim() == cleanPhone);
    } catch (_) { existing = null; }

    void doSave() {
      if (widget.attendance == null) {
        provider.addAttendance(
          workerId: wId,
          workerName: _workerNameCtrl.text.trim(),
          workerGender: _workerGender,
          workerResidentNumber: _workerResidentCtrl.text.trim(),
          workerPhone: cleanPhone,
          workerAddress: _workerAddressCtrl.text.trim(),
          workerBankName: _workerBankNameCtrl.text.trim(),
          workerBankAccount: _workerBankAccountCtrl.text.trim(),
          workerCareer: _workerCareerCtrl.text.trim(),
          clientId: cId,
          clientName: _clientNameCtrl.text.trim(),
          clientAddress: _clientAddressCtrl.text.trim(),
          workDate: _selectedDate,
          dailyWage: wage, commissionRate: rate,
          isPostpaid: _isPostpaid,
          notes: _notesCtrl.text.trim(),
          idPhotoFront: _frontImage, idPhotoBack: _backImage,
        );
      } else {
        provider.updateAttendance(id: widget.attendance!.id, data: {
          'worker_id': wId, 'worker_name': _workerNameCtrl.text.trim(),
          'worker_gender': _workerGender,
          'worker_resident_number': _workerResidentCtrl.text.trim(),
          'worker_phone': cleanPhone, 'worker_address': _workerAddressCtrl.text.trim(),
          'worker_bank_name': _workerBankNameCtrl.text.trim(),
          'worker_bank_account': _workerBankAccountCtrl.text.trim(),
          'worker_career': _workerCareerCtrl.text.trim(),
          'client_id': cId, 'client_name': _clientNameCtrl.text.trim(),
          'client_address': _clientAddressCtrl.text.trim(),
          'work_date': _selectedDate, 'daily_wage': wage, 'commission_rate': rate,
          'is_postpaid': _isPostpaid, 'notes': _notesCtrl.text.trim(),
        }, newFrontImage: _frontImage, newBackImage: _backImage);
      }
      Navigator.pop(context);
      if (widget.attendance == null && wId == null) _askRegisterWorker();
    }

    if (existing != null && existing.id != wId) {
      var msg = '입력한 전화번호(${PhoneInputFormatter.format(existing.phone)})를 가진\n'
          '기존 근로자 \'${existing.name}\'가 있습니다.';
      if (existing.isBlacklisted)
        msg += '\n\n⚠️ 블랙리스트 대상입니다! (${existing.blacklistReason})';
      msg += '\n\n계속 진행하시겠습니까?';
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('중복/경고 알림'), content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
              onPressed: () { Navigator.pop(ctx); doSave(); },
              child: const Text('진행')),
        ],
      ));
    } else {
      doSave();
    }
  }

  void _askRegisterWorker() {
    final provider   = context.read<WorkforceProvider>();
    final cleanPhone = _workerPhoneCtrl.text.replaceAll('-', '').trim();
    if (provider.workers.any((w) => w.phone.replaceAll('-', '').trim() == cleanPhone)) return;

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.person_add, color: Colors.blue), SizedBox(width: 8), Text('근로자 등록'),
      ]),
      content: Text('${_workerNameCtrl.text.trim()} 님을 근로자 목록에 등록하시겠습니까?\n\n'
          '등록하면 다음 출근 등록 시 자동완성에서 바로 선택할 수 있습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('나중에')),
        ElevatedButton.icon(
          icon: const Icon(Icons.person_add, size: 16), label: const Text('등록'),
          onPressed: () {
            provider.addWorker(
              name: _workerNameCtrl.text.trim(), gender: _workerGender,
              residentNumber: _workerResidentCtrl.text.trim(),
              phone: cleanPhone,
              address: _workerAddressCtrl.text.trim(),
              bankName: _workerBankNameCtrl.text.trim(),
              bankAccount: _workerBankAccountCtrl.text.trim(),
              career: _workerCareerCtrl.text.trim(),
              notes: _notesCtrl.text.trim(),
              idPhotoFront: _frontImage, idPhotoBack: _backImage,
            );
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${_workerNameCtrl.text.trim()} 님이 근로자 목록에 등록되었습니다.')));
          },
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final workers = context.read<WorkforceProvider>().workers;
    final clients = context.read<WorkforceProvider>().clients;

    return AlertDialog(
      title: Text(widget.attendance != null ? '출근 수정' : '출근 등록'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [

            // 날짜
            ListTile(
              title: Text('날짜: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
            const Divider(),

            // ── 근로자 섹션 ──────────────────────────────
            const Align(alignment: Alignment.centerLeft,
              child: Text('근로자 정보',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            const SizedBox(height: 8),

            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _KeyboardAutocomplete<Worker>(
                key: _workerAutoKey,
                items: workers,
                displayString: (w) => w.name,
                controller: _workerNameCtrl,
                focusNode:  _workerNameFocus,
                decoration: const InputDecoration(
                    labelText: '이름 (직접 입력 가능) *', suffixIcon: Icon(Icons.search)),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '근로자 이름을 입력하세요' : null,
                onTextChanged: () => _workerIdNotifier.value = null,
                onSelected: _onWorkerSelected,
                itemBuilder: (Worker w, bool hl, VoidCallback onTap) =>
                    InkWell(onTap: onTap,
                      child: Container(
                        color: hl ? Colors.blue.shade50 : null,
                        child: ListTile(dense: true,
                          leading: w.isBlacklisted
                              ? const Icon(Icons.warning, color: Colors.red, size: 20)
                              : const Icon(Icons.person, size: 20),
                          title: Text(w.name, style: TextStyle(
                              fontWeight: hl ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(
                            '${PhoneInputFormatter.format(w.phone)}'
                            '${w.isBlacklisted ? '  ⚠️ ${w.blacklistReason}' : ''}',
                            style: TextStyle(
                                color: w.isBlacklisted ? Colors.red : Colors.grey,
                                fontSize: 12)),
                        ),
                      )),
              )),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('성별', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Row(children: [
                  _genderButton('남', Colors.blue),
                  const SizedBox(width: 6),
                  _genderButton('여', Colors.pink),
                ]),
              ]),
            ]),
            const SizedBox(height: 6),

            TextFormField(controller: _workerResidentCtrl,
                decoration: const InputDecoration(
                    labelText: '주민등록번호', hintText: '000000-0000000')),
            TextFormField(controller: _workerPhoneCtrl,
                decoration: const InputDecoration(
                    labelText: '전화번호', hintText: '010-0000-0000'),
                inputFormatters: [PhoneInputFormatter()]),
            TextFormField(controller: _workerAddressCtrl,
                decoration: const InputDecoration(labelText: '주소')),
            Row(children: [
              Expanded(child: TextFormField(controller: _workerBankNameCtrl,
                  decoration: const InputDecoration(labelText: '은행명'))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _workerBankAccountCtrl,
                  decoration: const InputDecoration(labelText: '계좌번호'))),
            ]),
            TextFormField(controller: _workerCareerCtrl,
                decoration: const InputDecoration(labelText: '경력사항'), maxLines: 2),

            const SizedBox(height: 12),
            const Divider(),

            // ── 거래처 섹션 ──────────────────────────────
            const Align(alignment: Alignment.centerLeft,
              child: Text('거래처 정보',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            const SizedBox(height: 8),

            _KeyboardAutocomplete<Client>(
              key: _clientAutoKey,
              items: clients,
              displayString: (c) => c.name,
              controller: _clientNameCtrl,
              focusNode:  _clientNameFocus,
              decoration: const InputDecoration(
                  labelText: '거래처명 (직접 입력 가능) *', suffixIcon: Icon(Icons.search)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '거래처를 입력하세요' : null,
              onTextChanged: () => _clientIdNotifier.value = null,
              onSelected: (Client c) {
                _clientIdNotifier.value = c.id;
                _clientAddressCtrl.text = c.address;
              },
              itemBuilder: (Client c, bool hl, VoidCallback onTap) =>
                  InkWell(onTap: onTap,
                    child: Container(
                      color: hl ? Colors.blue.shade50 : null,
                      child: ListTile(dense: true,
                        leading: const Icon(Icons.business, size: 20),
                        title: Text(c.name, style: TextStyle(
                            fontWeight: hl ? FontWeight.bold : FontWeight.normal)),
                        subtitle: c.address.isNotEmpty
                            ? Text(c.address, style: const TextStyle(fontSize: 12, color: Colors.grey))
                            : null,
                      ),
                    )),
            ),
            const SizedBox(height: 6),
            TextFormField(controller: _clientAddressCtrl,
                decoration: const InputDecoration(labelText: '현장 주소')),

            const SizedBox(height: 12),
            const Divider(),

            // ── 근무 정보 ────────────────────────────────
            const Align(alignment: Alignment.centerLeft,
              child: Text('근무 정보',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            const SizedBox(height: 8),

            Row(children: [
              Expanded(child: TextFormField(controller: _wageCtrl,
                decoration: const InputDecoration(labelText: '일당 *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                validator: (v) => _validateNumber(v, '일당'))),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(controller: _commissionRateCtrl,
                decoration: const InputDecoration(labelText: '수수료율(%) *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                validator: (v) => _validateNumber(v, '수수료율'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Text('지급 방식:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              ChoiceChip(label: const Text('선불'), selected: !_isPostpaid,
                  onSelected: (v) { if (v) setState(() => _isPostpaid = false); }),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('후불'), selected: _isPostpaid,
                  onSelected: (v) { if (v) setState(() => _isPostpaid = true); }),
            ]),
            TextFormField(controller: _notesCtrl,
                decoration: const InputDecoration(labelText: '메모')),
            const SizedBox(height: 12),

            Row(children: [
              _buildImagePicker(true), const SizedBox(width: 10), _buildImagePicker(false),
            ]),
          ])),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        ElevatedButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}
