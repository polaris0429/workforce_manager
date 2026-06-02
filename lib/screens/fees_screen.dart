import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/workforce_provider.dart';
import '../utils/formatters.dart';

class FeesScreen extends StatelessWidget {
  const FeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkforceProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final dateFormat = DateFormat('yyyy-MM-dd');
    final unpaidList = provider.unpaidCommissions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('미수금 관리'),
      ),
      body: Column(
        children: [
          // 상단 요약 카드
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 40),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("총 받아야 할 수수료", style: TextStyle(fontSize: 16, color: Colors.grey)),
                    Text(
                      currencyFormat.format(provider.totalUnpaidAmount),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: unpaidList.isEmpty
                ? const Center(child: Text("미수금이 없습니다."))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: unpaidList.length,
                    itemBuilder: (context, index) {
                      final item = unpaidList[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: const Text("미수", style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
                          ),
                          title: Text("${item.workerName} (${PhoneInputFormatter.format(item.workerPhone)})"),
                          subtitle: Text("${dateFormat.format(item.workDate)} @ ${item.clientName}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currencyFormat.format(item.commission),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onPressed: () {
                                  // 정산 완료 처리
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text("수수료 정산"),
                                      content: Text("${item.workerName}님의 수수료\n${currencyFormat.format(item.commission)}을 받으셨습니까?"),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
                                        ElevatedButton(
                                          onPressed: () {
                                            context.read<WorkforceProvider>().settleCommission(item.id);
                                            Navigator.pop(ctx);
                                          },
                                          child: const Text("확인"),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Text("받음"),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}