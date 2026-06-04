import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/workforce_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _exportExcel(
    BuildContext context,
    ExcelPeriodType period,
    String label,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('엑셀 저장 중...'),
        ]),
      ),
    );

    final path = await context.read<WorkforceProvider>().exportToExcelByPeriod(period);

    if (context.mounted) Navigator.of(context).pop();

    if (path.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('[$label] 엑셀 저장 완료:\n$path'),
        duration: const Duration(seconds: 4),
      ));
    } else {
      messenger.showSnackBar(SnackBar(content: Text('[$label] 엑셀 저장 실패')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkforceProvider>();
    final cf       = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');

    return Scaffold(
      appBar: AppBar(
        title: const Text('대시보드'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: '전체 엑셀 다운로드',
            onPressed: () => _exportExcel(context, ExcelPeriodType.all, '전체'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 통계 카드 4개 (높이 동일하게 IntrinsicHeight로 묶음) ──
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatCard(
                    title: '오늘 출근',
                    value: '${provider.todayWorkersCount}명',
                    color: Colors.blue,
                    icon: Icons.people,
                    // 다운로드 없는 카드도 spacer로 높이를 맞춤
                    hasFooter: false,
                  ),
                  const SizedBox(width: 16),
                  _buildStatCard(
                    title: '오늘 수입',
                    value: cf.format(provider.todayIncome),
                    color: Colors.green,
                    icon: Icons.today,
                    downloadLabel: '일별 엑셀',
                    hasFooter: true,
                    onTap: () => _exportExcel(context, ExcelPeriodType.today, '오늘(일별)'),
                  ),
                  const SizedBox(width: 16),
                  _buildStatCard(
                    title: '이번주 수입',
                    value: cf.format(provider.weeklyIncome),
                    color: Colors.orange,
                    icon: Icons.date_range,
                    downloadLabel: '주별 엑셀',
                    hasFooter: true,
                    onTap: () => _exportExcel(context, ExcelPeriodType.week, '이번주(주별)'),
                  ),
                  const SizedBox(width: 16),
                  _buildStatCard(
                    title: '이번달 수입',
                    value: cf.format(provider.monthlyIncome),
                    color: Colors.purple,
                    icon: Icons.calendar_month,
                    downloadLabel: '월별 엑셀',
                    hasFooter: true,
                    onTap: () => _exportExcel(context, ExcelPeriodType.month, '이번달(월별)'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Text('최근 현황',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Card(
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('날짜')),
                    DataColumn(label: Text('근로자')),
                    DataColumn(label: Text('거래처')),
                    DataColumn(label: Text('수수료')),
                  ],
                  rows: provider.attendanceList.take(10).map((att) => DataRow(cells: [
                    DataCell(Text(DateFormat('yyyy-MM-dd').format(att.workDate))),
                    DataCell(Text(att.workerName)),
                    DataCell(Text(att.clientName)),
                    DataCell(Text(cf.format(att.commission))),
                  ])).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required bool hasFooter,       // 다운로드 영역 여부 — false여도 빈 공간으로 높이 확보
    String? downloadLabel,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Card(
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 10),
                Text(value,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color)),
                // 항상 같은 높이를 차지하는 footer 영역
                const SizedBox(height: 8),
                SizedBox(
                  height: 18, // 다운로드 행 높이 고정
                  child: hasFooter && downloadLabel != null
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.file_download,
                              size: 14, color: color.withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Text(downloadLabel,
                              style: TextStyle(
                                  fontSize: 11, color: color.withOpacity(0.8))),
                        ])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
