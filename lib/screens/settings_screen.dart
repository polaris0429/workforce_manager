import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/workforce_provider.dart';
import '../services/backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _localDataPath = '';
  bool   _isRetrying    = false;

  @override
  void initState() {
    super.initState();
    _loadLocalPath();
    // 백업 상태 변경 시 UI 자동 갱신
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WorkforceProvider>().backupStatusStream.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  Future<void> _loadLocalPath() async {
    final path = await BackupService().localDataPath;
    if (mounted) setState(() => _localDataPath = path);
  }

  Future<void> _addBackupPath() async {
    final selected = await FilePicker.platform.getDirectoryPath(dialogTitle: '백업 경로 선택');
    if (selected == null || !mounted) return;
    final provider = context.read<WorkforceProvider>();
    if (provider.backupPaths.contains(selected)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 등록된 경로입니다.')));
      return;
    }
    await provider.addBackupPath(selected);
    if (mounted) ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('백업 경로 추가됨:\n$selected')));
  }

  Future<void> _confirmRemovePath(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('백업 경로 삭제'),
        content: Text('아래 경로를 백업 목록에서 제거하시겠습니까?\n\n$path'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<WorkforceProvider>().removeBackupPath(path);
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('백업 경로가 제거되었습니다.')));
    }
  }

  Future<void> _retryNow() async {
    setState(() => _isRetrying = true);
    await context.read<WorkforceProvider>().retryBackupNow();
    if (mounted) setState(() => _isRetrying = false);
    if (mounted) {
      final pending = context.read<WorkforceProvider>().pendingPaths;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pending.isEmpty ? '✅ 모든 백업 경로 동기화 완료' : '⏳ ${pending.length}개 경로 아직 미완료'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider     = context.watch<WorkforceProvider>();
    final backupPaths  = provider.backupPaths;
    final pendingPaths = provider.pendingPaths;
    final statusMap    = provider.backupStatusMap;
    final hasPending   = pendingPaths.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ 설정')),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── 기본 저장 경로 ──────────────────────────────────
        _sectionHeader('기본 저장 경로'),
        Card(child: ListTile(
          leading: const Icon(Icons.folder, color: Colors.blue),
          title: const Text('데이터 저장 위치'),
          subtitle: Text(_localDataPath.isEmpty ? '불러오는 중...' : _localDataPath,
              style: const TextStyle(fontSize: 12)),
          trailing: const Tooltip(
            message: '기본 경로는 변경할 수 없습니다.',
            child: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
          ),
        )),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Text('앱 데이터는 항상 위 경로(woosin_data 폴더)에 자동 저장됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),

        // ── 추가 백업 경로 ──────────────────────────────────
        _sectionHeader('추가 백업 경로'),

        // 미완료 알림 배너
        if (hasPending)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(children: [
              const Icon(Icons.sync_problem, color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(
                '${pendingPaths.length}개 경로에 미완료 백업이 있습니다.\n'
                '30초마다 자동 재시도합니다.',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              )),
              if (_isRetrying)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
              else
                TextButton(
                  onPressed: _retryNow,
                  child: const Text('지금 시도', style: TextStyle(color: Colors.orange)),
                ),
            ]),
          ),

        Card(child: Column(children: [

          if (backupPaths.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline, color: Colors.grey),
              title: Text('등록된 백업 경로가 없습니다.', style: TextStyle(color: Colors.grey)),
            )
          else
            ...backupPaths.asMap().entries.map((entry) {
              final idx    = entry.key;
              final path   = entry.value;
              final isPend = pendingPaths.contains(path);
              final status = statusMap[path] ?? BackupPathStatus.unknown;

              return Column(children: [
                ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.blue.shade50,
                    child: Text('${idx + 1}',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold)),
                  ),
                  title: Text(path, style: const TextStyle(fontSize: 13)),
                  subtitle: Row(children: [
                    _statusDot(status, isPend),
                    const SizedBox(width: 6),
                    Text(_statusLabel(status, isPend),
                        style: TextStyle(fontSize: 11, color: _statusColor(status, isPend))),
                  ]),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: '이 경로 삭제',
                    onPressed: () => _confirmRemovePath(path),
                  ),
                ),
                if (idx < backupPaths.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ]);
            }),

          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.blue),
            title: const Text('백업 경로 추가', style: TextStyle(color: Colors.blue)),
            onTap: _addBackupPath,
          ),
        ])),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Text(
            '데이터 변경 시 기본 경로와 모든 추가 백업 경로에 동시에 저장됩니다.\n'
            '경로가 오프라인이거나 접근 불가 시 미완료 큐에 등록되며 30초마다 자동 재시도합니다.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),

        // 지금 백업 버튼 (항상 표시)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _isRetrying
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_sync),
              label: Text(_isRetrying ? '백업 중...' : '지금 백업 동기화'),
              onPressed: _isRetrying ? null : _retryNow,
            ),
          ),
        ),
      ]),
    );
  }

  // 상태 표시 점
  Widget _statusDot(BackupPathStatus status, bool isPending) {
    final color = _statusColor(status, isPending);
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Color _statusColor(BackupPathStatus status, bool isPending) {
    if (isPending) return Colors.orange;
    switch (status) {
      case BackupPathStatus.ok:      return Colors.green;
      case BackupPathStatus.pending: return Colors.orange;
      case BackupPathStatus.unknown: return Colors.grey;
    }
  }

  String _statusLabel(BackupPathStatus status, bool isPending) {
    if (isPending) return '미완료 (재시도 대기 중)';
    switch (status) {
      case BackupPathStatus.ok:      return '동기화 완료';
      case BackupPathStatus.pending: return '미완료 (재시도 대기 중)';
      case BackupPathStatus.unknown: return '상태 확인 중';
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
    );
  }
}
