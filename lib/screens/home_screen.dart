import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'workers_screen.dart';
import 'clients_screen.dart';
import 'attendance_screen.dart';
import 'fees_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            groupAlignment: -1.0, // 상단 정렬
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('대시보드')),
              NavigationRailDestination(icon: Icon(Icons.people), label: Text('근로자')),
              NavigationRailDestination(icon: Icon(Icons.business), label: Text('거래처')),
              NavigationRailDestination(icon: Icon(Icons.calendar_today), label: Text('출근')),
              NavigationRailDestination(icon: Icon(Icons.attach_money), label: Text('수수료')),
              NavigationRailDestination(icon: Icon(Icons.settings), label: Text('설정')),
            ],
            // === 로고 추가 (왼쪽 최하단) ===
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 60, // 로고 크기 조절
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.image, color: Colors.grey); // 이미지 없을 때 대체 아이콘
                    },
                  ),
                ),
              ),
            ),
            // ===========================
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0: return const DashboardScreen();
      case 1: return const WorkersScreen();
      case 2: return const ClientsScreen();
      case 3: return const AttendanceScreen();
      case 4: return const FeesScreen();
      case 5: return const SettingsScreen();
      default: return const DashboardScreen();
    }
  }
}