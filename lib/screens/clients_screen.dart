import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/workforce_provider.dart';
import '../models/client.dart';
import '../utils/formatters.dart';

class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkforceProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('거래처 관리'),
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
              label: const Text('거래처 등록'),
              onPressed: () => _showClientDialog(context),
            ),
          ),
        ],
      ),
      body: provider.clients.isEmpty
          ? const Center(child: Text('등록된 거래처가 없습니다.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: provider.clients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final client = provider.clients[index];
                return ListTile(
                  onTap: () => _showClientDialog(context, client: client),
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  title: Text(client.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (client.address.isNotEmpty) Text('📍 ${client.address}'),
                      if (client.contactPerson.isNotEmpty || client.phone.isNotEmpty)
                        Text('👤 ${client.contactPerson} | 📞 ${PhoneInputFormatter.format(client.phone)}'),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    onPressed: () => _confirmDelete(context, client),
                  ),
                );
              },
            ),
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
          onPressed: () { context.read<WorkforceProvider>().deleteClient(client.id); Navigator.pop(ctx); },
          child: const Text('삭제'),
        ),
      ],
    ));
  }

  void _showClientDialog(BuildContext context, {Client? client}) {
    final isEdit        = client != null;
    final nameCtrl      = TextEditingController(text: client?.name ?? '');
    final addressCtrl   = TextEditingController(text: client?.address ?? '');
    final contactCtrl   = TextEditingController(text: client?.contactPerson ?? '');
    final phoneCtrl     = TextEditingController(text: PhoneInputFormatter.format(client?.phone ?? ''));
    final emailCtrl     = TextEditingController(text: client?.email ?? '');
    final notesCtrl     = TextEditingController(text: client?.notes ?? '');

    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(isEdit ? '거래처 수정' : '거래처 추가'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl,    decoration: const InputDecoration(labelText: '거래처명 *')),
        TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: '주소')),
        TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: '담당자')),
        TextField(controller: phoneCtrl,   decoration: const InputDecoration(labelText: '연락처'),
            inputFormatters: [PhoneInputFormatter()]),
        TextField(controller: emailCtrl,   decoration: const InputDecoration(labelText: '이메일')),
        TextField(controller: notesCtrl,   decoration: const InputDecoration(labelText: '비고')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        ElevatedButton(
          onPressed: () {
            if (nameCtrl.text.trim().isEmpty) return;
            final cleanPhone = phoneCtrl.text.replaceAll('-', '').trim();
            if (isEdit) {
              context.read<WorkforceProvider>().updateClient(client.id, {
                'name': nameCtrl.text.trim(), 'address': addressCtrl.text.trim(),
                'contact_person': contactCtrl.text.trim(), 'phone': cleanPhone,
                'email': emailCtrl.text.trim(), 'notes': notesCtrl.text.trim(),
              });
            } else {
              context.read<WorkforceProvider>().addClient(Client(
                name: nameCtrl.text.trim(), address: addressCtrl.text.trim(),
                contactPerson: contactCtrl.text.trim(), phone: cleanPhone,
                email: emailCtrl.text.trim(), notes: notesCtrl.text.trim(),
                createdAt: DateTime.now(),
              ));
            }
            Navigator.pop(context);
          },
          child: const Text('저장'),
        ),
      ],
    ));
  }
}
