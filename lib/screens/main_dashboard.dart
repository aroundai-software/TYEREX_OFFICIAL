// lib/screens/main_dashboard.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../providers/report_provider.dart';
import '../theme/app_theme.dart';
import 'job_card_screen.dart';
import 'update_screen.dart'; // ✅ CHANGE THIS - use the complete one
import 'report_screen.dart';
import 'profile_screen.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 1;
  final Map<int, Widget> _cachedScreens = {};

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const JobCardScreen();
      case 1:
        return const UpdateScreen();
      case 2:
        return const ReportScreen();
      case 3:
        return const ProfileScreen();
      default:
        return const UpdateScreen();
    }
  }

  @override
  void initState() {
    super.initState();
    // Pre-cache only the initial screen (Job Cards / UpdateScreen)
    _cachedScreens[_currentIndex] = _buildScreen(_currentIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user != null) {
        final userId = user['id'] as int;
        Provider.of<ReportProvider>(context, listen: false).fetchReports(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(4, (index) {
          return _cachedScreens[index] ?? const SizedBox.shrink();
        }),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
                _cachedScreens.putIfAbsent(index, () => _buildScreen(index));
              });
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppTheme.primaryColor,
            unselectedItemColor: const Color(0xFF9CA3AF),
            selectedFontSize: 12,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            items: const [
              BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.description_outlined, size: 24),
                ),
                activeIcon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.description_rounded, size: 24),
                ),
                label: 'Create',
              ),
              BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.update_outlined, size: 24),
                ),
                activeIcon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.update_rounded, size: 24),
                ),
                label: 'Job Cards',
              ),
              BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.analytics_outlined, size: 24),
                ),
                activeIcon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.analytics_rounded, size: 24),
                ),
                label: 'Report',
              ),
              BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.person_outline_rounded, size: 24),
                ),
                activeIcon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.person_rounded, size: 24),
                ),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}