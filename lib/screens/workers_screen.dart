import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../providers/workforce_provider.dart';
import '../models/worker.dart';
import '../utils/image_helper.dart';
import '../utils/formatters.dart';
import '../utils/resident_number_formatter.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  static const _tabs = ['전체', '남성', '여성', '블랙리스트'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() { _tabCtrl.dispose(); _searchCtrl.dispose(); super.dispose(); }

  List<Worker> _getList(List<Worker> all, int tabIndex) {
    final q = _searchQuery.trim();
    if (q.isNotEmpty) {
      return all.where((w) =>
          w.name.contains(q) ||
          PhoneInputFormatter.format(w.phone).contains(q) ||
          w.phone.contains(q))
          .toList()..sort((a, b) => a.name.compareTo(b.name));
    }
    late List<Worker> filtered;
    switch (tabIndex) {
      case 0: filtered = all.where((w) => !w.isBlacklisted).toList(); break;
      case 1: filtered = all.where((w) => !w.isBlacklisted && w.gender == '남').toList(); break;
      case 2: filtered = all.where((w) => !w.isBlacklisted && w.gender == '여').toList(); break;
      case 3: filtered = all.where((w) => w.isBlacklisted).toList(); break;
      default: filtered = List.from(all);
    }
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkforceProvider>();
    final all      = provider.workers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('근로자 관리'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF92D050), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.add), label: const Text('근로자 등록'),
              onPressed: () => _showWorkerDialog(context),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
          indicatorColor: const Color(0xFF92D050),
          labelColor: const Color(0xFF4CAF50),
          unselectedLabelColor: Colors.grey,
          onTap: (_) => setState(() {}),
        ),
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '이름 또는 전화번호로 검색 (블랙리스트 포함)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear),
                            onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              AnimatedBuilder(
                animation: _tabCtrl,
                builder: (_, __) {
                  final list = _getList(all, _tabCtrl.index);
                  if (_searchQuery.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      child: Align(alignment: Alignment.centerLeft,
                        child: Text('검색 결과: ${list.length}명 (블랙리스트 포함)',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _tabCtrl,
                  builder: (_, __) {
                    final list = _getList(all, _tabCtrl.index);
                    if (list.isEmpty) {
                      return Center(child: Text(
                        _searchQuery.isNotEmpty ? '"$_searchQuery" 검색 결과가 없습니다.'
                            : _tabCtrl.index == 3 ? '블랙리스트에 등록된 근로자가 없습니다.'
                            : '등록된 근로자가 없습니다.',
                        style: const TextStyle(color: Colors.grey)));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: list.length,
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => _showWorkerDialog(context, worker: list[i]),
                        child: _buildWorkerCard(context, list[i]),
                      ),
                    );
                  },
                ),
              ),
            ]),
    );
  }

  Widget _buildWorkerCard(BuildContext context, Worker w) {
    return Card(
      color: w.isBlacklisted ? Colors.red.shade50 : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildImagePreview(context, w.idPhotoPath, '앞면'),
          const SizedBox(width: 8),
          _buildImagePreview(context, w.idPhotoBackPath, '뒷면'),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (w.isBlacklisted)
                const Padding(padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.block, color: Colors.red, size: 18)),
              Expanded(child: Text(w.name,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                      color: w.isBlacklisted ? Colors.red : null))),
              if (w.gender.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: w.gender == '남' ? Colors.blue.shade50 : Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: w.gender == '남' ? Colors.blue.shade200 : Colors.pink.shade200)),
                  child: Text(w.gender, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: w.gender == '남' ? Colors.blue.shade700 : Colors.pink.shade700)),
                ),
              if (w.isBlacklisted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade300)),
                  child: const Text('블랙리스트',
                      style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 4),
            if (w.residentNumber.isNotEmpty)
              Text('🪪 ${ResidentNumberFormatter.format(w.residentNumber)}',
                  style: const TextStyle(fontSize: 12)),
            if (w.address.isNotEmpty)
              Text('📍 ${w.address}', style: const TextStyle(fontSize: 12)),
            Text('📱 ${PhoneInputFormatter.format(w.phone)}'),
            if (w.homePhone.isNotEmpty)
              Text('☎️ ${PhoneInputFormatter.format(w.homePhone)}',
                  style: const TextStyle(fontSize: 12)),
            if (w.bankName.isNotEmpty || w.bankAccount.isNotEmpty)
              Text('🏦 ${w.bankName} ${w.bankAccount}'),
            if (w.career.isNotEmpty)
              Text('💼 ${w.career}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
            if (w.notes.isNotEmpty)
              Text('📝 ${w.notes}', style: const TextStyle(color: Colors.grey)),
            if (w.isBlacklisted && (w.blacklistReason?.isNotEmpty ?? false))
              Padding(padding: const EdgeInsets.only(top: 4),
                child: Text('⚠️ 사유: ${w.blacklistReason}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
          ])),
          Column(children: [
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey),
                tooltip: '삭제', onPressed: () => _confirmDelete(context, w)),
            Tooltip(
              message: w.isBlacklisted ? '블랙리스트 해제' : '블랙리스트 등록',
              child: Switch(
                value: w.isBlacklisted, activeColor: Colors.red,
                onChanged: (val) => val
                    ? _showBlacklistDialog(context, w)
                    : context.read<WorkforceProvider>().toggleBlacklist(w.id, w.isBlacklisted, null),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showBlacklistDialog(BuildContext context, Worker worker) {
    final reasonCtrl  = TextEditingController();
    final messenger   = ScaffoldMessenger.of(context);
    final providerRef = context.read<WorkforceProvider>();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Row(children: [Icon(Icons.block, color: Colors.red, size: 22), SizedBox(width: 8), Text('블랙리스트 등록')]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${worker.name} 님을 블랙리스트에 등록합니다.', style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 14),
        TextField(controller: reasonCtrl, autofocus: true, maxLines: 3,
            decoration: const InputDecoration(labelText: '사유 *', hintText: '블랙리스트 등록 사유를 입력하세요', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          icon: const Icon(Icons.block, size: 16), label: const Text('등록'),
          onPressed: () {
            final reason = reasonCtrl.text.trim();
            if (reason.isEmpty) { messenger.showSnackBar(const SnackBar(content: Text('사유를 입력해주세요.'))); return; }
            providerRef.toggleBlacklist(worker.id, worker.isBlacklisted, reason);
            Navigator.pop(ctx);
          }),
      ],
    )).then((_) => reasonCtrl.dispose());
  }

  void _confirmDelete(BuildContext context, Worker worker) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'),
      content: Text('${worker.name} 님을 삭제하시겠습니까?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () { context.read<WorkforceProvider>().deleteWorker(worker.id); Navigator.pop(ctx); },
          child: const Text('삭제')),
      ],
    ));
  }

  Widget _buildImagePreview(BuildContext context, String? path, String label) {
    final file = ImageHelper.getFileFromPath(path);
    return Column(children: [
      InkWell(
        onTap: () { if (file != null) _showImageOptions(context, file); },
        child: Container(
          width: 90, height: 56,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
          child: file != null
              ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(file, fit: BoxFit.cover))
              : const Icon(Icons.image_not_supported, color: Colors.grey, size: 20),
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }

  void _showImageOptions(BuildContext context, File imageFile) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('이미지 옵션'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Image.file(imageFile, height: 200, fit: BoxFit.contain),
        const SizedBox(height: 16), const Text('이 이미지를 어떻게 하시겠습니까?'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        ElevatedButton.icon(icon: const Icon(Icons.save_alt), label: const Text('다른 위치에 저장'),
          onPressed: () async { Navigator.pop(ctx); await _saveImageToExternal(context, imageFile); }),
      ],
    ));
  }

  Future<void> _saveImageToExternal(BuildContext context, File sourceFile) async {
    final outputDir = await FilePicker.platform.getDirectoryPath();
    if (outputDir == null) return;
    try {
      final dest = p.join(outputDir, p.basename(sourceFile.path));
      await sourceFile.copy(dest);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 완료: $dest')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  void _showWorkerDialog(BuildContext context, {Worker? worker}) {
    showDialog(context: context, builder: (_) => WorkerInputDialog(worker: worker));
  }
}

// ─────────────────────────────────────────────────────────────
// WorkerInputDialog
// ─────────────────────────────────────────────────────────────
class WorkerInputDialog extends StatefulWidget {
  final Worker? worker;
  const WorkerInputDialog({super.key, this.worker});
  @override
  State<WorkerInputDialog> createState() => _WorkerInputDialogState();
}

class _WorkerInputDialogState extends State<WorkerInputDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _residentCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;       // 휴대폰번호
  late TextEditingController _homePhoneCtrl;   // 집전화번호
  late TextEditingController _bankNameCtrl;
  late TextEditingController _bankAccountCtrl;
  late TextEditingController _careerCtrl;
  late TextEditingController _notesCtrl;

  String _gender = '';
  File?  _frontImage;
  File?  _backImage;

  @override
  void initState() {
    super.initState();
    final w          = widget.worker;
    _gender          = w?.gender ?? '';
    _nameCtrl        = TextEditingController(text: w?.name ?? '');
    // 주민번호: 저장된 숫자열 → 화면 포맷
    _residentCtrl    = TextEditingController(
        text: ResidentNumberFormatter.format(w?.residentNumber ?? ''));
    _addressCtrl     = TextEditingController(text: w?.address ?? '');
    _phoneCtrl       = TextEditingController(text: PhoneInputFormatter.format(w?.phone ?? ''));
    _homePhoneCtrl   = TextEditingController(text: PhoneInputFormatter.format(w?.homePhone ?? ''));
    _bankNameCtrl    = TextEditingController(text: w?.bankName ?? '');
    _bankAccountCtrl = TextEditingController(text: w?.bankAccount ?? '');
    _careerCtrl      = TextEditingController(text: w?.career ?? '');
    _notesCtrl       = TextEditingController(text: w?.notes ?? '');
    if (w?.idPhotoPath != null)     _frontImage = ImageHelper.getFileFromPath(w!.idPhotoPath);
    if (w?.idPhotoBackPath != null) _backImage  = ImageHelper.getFileFromPath(w!.idPhotoBackPath);
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _residentCtrl, _addressCtrl, _phoneCtrl, _homePhoneCtrl,
        _bankNameCtrl, _bankAccountCtrl, _careerCtrl, _notesCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isFront) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        if (isFront) _frontImage = File(result.files.single.path!);
        else _backImage = File(result.files.single.path!);
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    // 주민번호: 대시 제거 후 숫자만 저장
    final cleanResident  = ResidentNumberFormatter.strip(_residentCtrl.text);
    final cleanPhone     = _phoneCtrl.text.replaceAll('-', '').trim();
    final cleanHomePhone = _homePhoneCtrl.text.replaceAll('-', '').trim();
    final provider       = context.read<WorkforceProvider>();

    if (widget.worker == null) {
      provider.addWorker(
        name: _nameCtrl.text.trim(), gender: _gender,
        residentNumber: cleanResident, address: _addressCtrl.text.trim(),
        phone: cleanPhone, homePhone: cleanHomePhone,
        bankName: _bankNameCtrl.text.trim(), bankAccount: _bankAccountCtrl.text.trim(),
        career: _careerCtrl.text.trim(), notes: _notesCtrl.text.trim(),
        idPhotoFront: _frontImage, idPhotoBack: _backImage,
      );
    } else {
      provider.updateWorker(id: widget.worker!.id, data: {
        'name': _nameCtrl.text.trim(), 'gender': _gender,
        'resident_number': cleanResident, 'address': _addressCtrl.text.trim(),
        'phone': cleanPhone, 'home_phone': cleanHomePhone,
        'bank_name': _bankNameCtrl.text.trim(), 'bank_account': _bankAccountCtrl.text.trim(),
        'career': _careerCtrl.text.trim(), 'notes': _notesCtrl.text.trim(),
      }, newFrontImage: _frontImage, newBackImage: _backImage);
    }
    Navigator.pop(context);
  }

  Widget _genderButton(String label, MaterialColor color) {
    final selected = _gender == label;
    return GestureDetector(
      onTap: () => setState(() => _gender = selected ? '' : label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color.shade400 : Colors.grey.shade300, width: 1.5)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
            color: selected ? color.shade700 : Colors.grey.shade500))),
    );
  }

  Widget _buildImagePicker(bool isFront) {
    final file = isFront ? _frontImage : _backImage;
    return Expanded(child: InkWell(
      onTap: () => _pickImage(isFront),
      child: Container(
        height: 100,
        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
        child: file == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [const Icon(Icons.add_a_photo), Text(isFront ? '앞면' : '뒷면')])
            : Image.file(file, fit: BoxFit.cover),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.worker != null ? '근로자 수정' : '근로자 등록'),
      content: SizedBox(width: 520, child: Form(key: _formKey,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [

          // 이름 + 성별
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: TextFormField(controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '이름 *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력하세요' : null)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('성별', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Row(children: [_genderButton('남', Colors.blue), const SizedBox(width: 6), _genderButton('여', Colors.pink)]),
            ]),
          ]),
          const SizedBox(height: 6),

          // 주민등록번호 (자동 대시)
          TextFormField(
            controller: _residentCtrl,
            decoration: const InputDecoration(labelText: '주민등록번호', hintText: '000000-0000000'),
            keyboardType: TextInputType.number,
            inputFormatters: [ResidentNumberFormatter()],
          ),

          // 주소
          TextFormField(controller: _addressCtrl, decoration: const InputDecoration(labelText: '주소')),

          // 휴대폰번호 *
          TextFormField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(labelText: '휴대폰번호 *', hintText: '010-0000-0000'),
            inputFormatters: [PhoneInputFormatter()],
            validator: (v) => (v == null || v.trim().isEmpty) ? '휴대폰번호를 입력하세요' : null,
          ),

          // 집전화번호 (선택)
          TextFormField(
            controller: _homePhoneCtrl,
            decoration: const InputDecoration(
                labelText: '집전화번호', hintText: '02-0000-0000 (선택)'),
            inputFormatters: [PhoneInputFormatter()],
          ),

          const SizedBox(height: 4),
          // 은행명 / 계좌번호
          Row(children: [
            Expanded(child: TextFormField(controller: _bankNameCtrl,
                decoration: const InputDecoration(labelText: '은행명'))),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _bankAccountCtrl,
                decoration: const InputDecoration(labelText: '계좌번호'))),
          ]),

          TextFormField(controller: _careerCtrl, decoration: const InputDecoration(labelText: '경력사항'), maxLines: 2),
          TextFormField(controller: _notesCtrl, decoration: const InputDecoration(labelText: '메모'), maxLines: 2),

          const SizedBox(height: 16),
          // 신분증 사진
          Row(children: [_buildImagePicker(true), const SizedBox(width: 10), _buildImagePicker(false)]),
        ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        ElevatedButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}
