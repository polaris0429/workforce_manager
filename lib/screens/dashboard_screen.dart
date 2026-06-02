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
    // 4번 수정: ScaffoldMessenger를 다이얼로그 표시 전 미리 캡처
    // 비동기 작업 중 탭이 바뀌어 context가 unmount 되어도 snackbar는 정상 표시
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('엑셀 저장 중...'),
          ],
        ),
      ),
    );

    final path = await context.read<WorkforceProvider>().exportToExcelByPeriod(period);

    // context.mounted 체크 후 다이얼로그 닫기
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // messenger는 context와 무관하게 사용 가능 (미리 캡처했으므로)
    if (path.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('[$label] 엑셀 저장 완료:\n$path'),
        duration: const Duration(seconds: 4),
      ));
    } else {
      messenger.showSnackBar(
          SnackBar(content: Text('[$label] 엑셀 저장 실패')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider       = context.watch<WorkforceProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');

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
            Row(
              children: [
                _buildStatCard(
                  title: '오늘 출근',
                  value: '${provider.todayWorkersCount}명',
                  color: Colors.blue,
                  icon: Icons.people,
                  onTap: null,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  title: '오늘 수입',
                  value: currencyFormat.format(provider.todayIncome),
                  color: Colors.green,
                  icon: Icons.today,
                  downloadLabel: '일별 엑셀',
                  onTap: () => _exportExcel(context, ExcelPeriodType.today, '오늘(일별)'),
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  title: '이번주 수입',
                  value: currencyFormat.format(provider.weeklyIncome),
                  color: Colors.orange,
                  icon: Icons.date_range,
                  downloadLabel: '주별 엑셀',
                  onTap: () => _exportExcel(context, ExcelPeriodType.week, '이번주(주별)'),
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  title: '이번달 수입',
                  value: currencyFormat.format(provider.monthlyIncome),
                  color: Colors.purple,
                  icon: Icons.calendar_month,
                  downloadLabel: '월별 엑셀',
                  onTap: () => _exportExcel(context, ExcelPeriodType.month, '이번달(월별)'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              '최근 현황',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
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
                  rows: provider.attendanceList.take(10).map((att) {
                    return DataRow(cells: [
                      DataCell(Text(DateFormat('yyyy-MM-dd').format(att.workDate))),
                      DataCell(Text(att.workerName)),
                      DataCell(Text(att.clientName)),
                      DataCell(Text(currencyFormat.format(att.commission))),
                    ]);
                  }).toList(),
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
              children: [
                Text(title, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: color),
                ),
                if (onTap != null && downloadLabel != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.file_download,
                          size: 14, color: color.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Text(
                        downloadLabel,
                        style:
                            TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
