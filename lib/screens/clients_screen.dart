import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/workforce_provider.dart';
import '../models/client.dart';
import '../utils/formatters.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 가나다순 정렬 + 검색 필터
  List<Client> _getList(List<Client> all) {
    final q = _searchQuery.trim();
    List<Client> list = q.isEmpty
        ? List<Client>.from(all)
        : all.where((c) =>
            c.name.contains(q) ||
            c.contactPerson.contains(q) ||
            PhoneInputFormatter.format(c.phone).contains(q) ||
            c.phone.contains(q)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkforceProvider>();
    final list     = _getList(provider.clients);

    return Scaffold(
      appBar: AppBar(
        title: const Text('거래처 관리'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF92D050), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.add), label: const Text('거래처 등록'),
              onPressed: () => _showClientDialog(context),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // 검색창
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '거래처명, 담당자, 전화번호로 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      })
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),

        // 건수 표시
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('검색 결과: ${list.length}개',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
          ),

        // 목록
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(
                  _searchQuery.isNotEmpty
                      ? '"$_searchQuery" 검색 결과가 없습니다.'
                      : '등록된 거래처가 없습니다.',
                  style: const TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = list[index];
                    return ListTile(
                      onTap: () => _showClientDialog(context, client: c),
                      tileColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (c.address.isNotEmpty)      Text('📍 ${c.address}'),
                        if (c.contactPerson.isNotEmpty) Text('👤 ${c.contactPerson}'),
                        if (c.phone.isNotEmpty)
                          Text('📞 ${PhoneInputFormatter.format(c.phone)}'),
                        if (c.officePhone.isNotEmpty)
                          Text('🏢 ${PhoneInputFormatter.format(c.officePhone)}'),
                        if (c.email.isNotEmpty)
                          Text('✉️ ${c.email}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.grey),
                        onPressed: () => _confirmDelete(context, c),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  void _confirmDelete(BuildContext context, Client client) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'),
      content: Text('거래처 "${client.name}"을 삭제하시겠습니까?\n삭제 후 복구할 수 없습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () {
            context.read<WorkforceProvider>().deleteClient(client.id);
            Navigator.pop(ctx);
          },
          child: const Text('삭제')),
      ],
    ));
  }

  void _showClientDialog(BuildContext context, {Client? client}) {
    showDialog(
      context: context,
      builder: (_) => _ClientDialog(client: client),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 거래처 등록/수정 다이얼로그 — StatefulWidget으로 분리
// TextField를 StatefulWidget 안에 두어야 IME 커서 버그 없음
// ─────────────────────────────────────────────────────────────
class _ClientDialog extends StatefulWidget {
  final Client? client;
  const _ClientDialog({this.client});
  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _officePhoneCtrl;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final c          = widget.client;
    _nameCtrl        = TextEditingController(text: c?.name ?? '');
    _addressCtrl     = TextEditingController(text: c?.address ?? '');
    _contactCtrl     = TextEditingController(text: c?.contactPerson ?? '');
    _emailCtrl       = TextEditingController(text: c?.email ?? '');
    _phoneCtrl       = TextEditingController(text: PhoneInputFormatter.format(c?.phone ?? ''));
    _officePhoneCtrl = TextEditingController(text: PhoneInputFormatter.format(c?.officePhone ?? ''));
    _notesCtrl       = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    for (final ctrl in [_nameCtrl, _addressCtrl, _contactCtrl, _emailCtrl,
        _phoneCtrl, _officePhoneCtrl, _notesCtrl]) ctrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final cleanPhone       = _phoneCtrl.text.replaceAll('-', '').trim();
    final cleanOfficePhone = _officePhoneCtrl.text.replaceAll('-', '').trim();
    final provider         = context.read<WorkforceProvider>();

    if (widget.client != null) {
      provider.updateClient(widget.client!.id, {
        'name':           _nameCtrl.text.trim(),
        'address':        _addressCtrl.text.trim(),
        'contact_person': _contactCtrl.text.trim(),
        'email':          _emailCtrl.text.trim(),
        'phone':          cleanPhone,
        'office_phone':   cleanOfficePhone,
        'notes':          _notesCtrl.text.trim(),
      });
    } else {
      provider.addClient(Client(
        name:          _nameCtrl.text.trim(),
        address:       _addressCtrl.text.trim(),
        contactPerson: _contactCtrl.text.trim(),
        email:         _emailCtrl.text.trim(),
        phone:         cleanPhone,
        officePhone:   cleanOfficePhone,
        notes:         _notesCtrl.text.trim(),
        createdAt:     DateTime.now(),
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.client != null ? '거래처 수정' : '거래처 추가'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [

          // 거래처명 *
          TextField(controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '거래처명 *')),

          // 주소
          TextField(controller: _addressCtrl,
              decoration: const InputDecoration(labelText: '주소')),

          // 담당자
          TextField(controller: _contactCtrl,
              decoration: const InputDecoration(labelText: '담당자')),

          // 이메일
          TextField(controller: _emailCtrl,
              decoration: const InputDecoration(labelText: '이메일')),

          // 연락처 / 회사번호 (한 줄)
          Row(children: [
            Expanded(child: TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: '연락처'),
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _officePhoneCtrl,
              decoration: const InputDecoration(labelText: '회사번호'),
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
            )),
          ]),

          // 비고
          TextField(controller: _notesCtrl,
              decoration: const InputDecoration(labelText: '비고')),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        ElevatedButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}
