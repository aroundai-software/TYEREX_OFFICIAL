// lib/screens/super_admin/super_admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_constants.dart';
import '../../services/company_service.dart';
import '../../providers/user_provider.dart';
import '../../providers/report_provider.dart';
import '../../widgets/company_switcher_badge.dart';
import '../login_screen.dart';
import 'company_management_screen.dart';
import 'super_user_management_screen.dart';
import 'tally_company_modal_dialog.dart';
import 'branch_allocation_dialog.dart';
import '../admin/reports_analytics_screen.dart';
import '../update_screen.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _tallyCompanies = [];
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  // Search & Filter
  final TextEditingController _companySearchController = TextEditingController();
  final TextEditingController _tallySearchController = TextEditingController();
  final TextEditingController _userSearchController = TextEditingController();
  String _companySearch = '';
  String _tallySearch = '';
  String _userSearch = '';
  String _selectedRoleFilter = 'all';
  String _selectedBranchFilter = 'all';

  // Stats
  int _totalJobsAcrossBranches = 0;
  int _activeJobsAcrossBranches = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _companySearchController.dispose();
    _tallySearchController.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        CompanyService().getAllCompanies(),
        supabase.from('users').select('*').neq('role', AppConstants.roleSuperAdmin).order('username'),
        supabase.from('reports').select('id, status'),
        CompanyService().getAllTallyCompanyMasters(),
      ]);

      final companies = results[0] as List<Map<String, dynamic>>;
      final users = List<Map<String, dynamic>>.from(results[1] as List);
      final reports = List<Map<String, dynamic>>.from(results[2] as List);
      final tallyCompanies = results[3] as List<Map<String, dynamic>>;

      int activeJobs = reports.where((r) => 
        r['status'] == AppConstants.statusWorkInProgress || 
        r['status'] == AppConstants.statusOngoing
      ).length;

      if (mounted) {
        setState(() {
          _companies = companies;
          _users = users;
          _tallyCompanies = tallyCompanies;
          _totalJobsAcrossBranches = reports.length;
          _activeJobsAcrossBranches = activeJobs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ SuperAdmin: Error loading dashboard data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.cacheKeyCurrentUser);
    if (!mounted) return;
    Provider.of<UserProvider>(context, listen: false).setUser(null);
    Provider.of<ReportProvider>(context, listen: false).clearCache();
    CompanyService().clearCache();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openCompanyModal([Map<String, dynamic>? company]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompanyModalDialog(
        company: company,
        tallyMasters: _tallyCompanies,
      ),
    );

    if (result == true) {
      _loadDashboardData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(company == null ? 'Branch created successfully!' : 'Branch updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _openTallyCompanyModal([Map<String, dynamic>? tallyCompany]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TallyCompanyModalDialog(
        tallyCompany: tallyCompany,
        allBranches: _companies,
      ),
    );

    if (result == true) {
      _loadDashboardData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tallyCompany == null ? 'Tally Company Master created!' : 'Tally Company Master updated!'),
          backgroundColor: const Color(0xFF0D9488),
        ),
      );
    }
  }

  void _openBranchAllocationModal(Map<String, dynamic> tallyCompany) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BranchAllocationDialog(
        tallyCompany: tallyCompany,
        allBranches: _companies,
      ),
    );

    if (result == true) {
      _loadDashboardData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Branches allocated to ${tallyCompany['tally_company_name']}!'),
          backgroundColor: const Color(0xFF0D9488),
        ),
      );
    }
  }

  void _confirmDeleteTallyCompany(Map<String, dynamic> tallyCompany) {
    final tName = tallyCompany['tally_company_name'] ?? 'Tally Company';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Tally Master'),
          ],
        ),
        content: Text('Are you sure you want to delete Tally Master "$tName"? Allocated branches will be unlinked for syncing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final tId = tallyCompany['id'].toString();
                await CompanyService().deleteTallyCompanyMaster(tId);
                _loadDashboardData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tally Company Master deleted'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openUserModal([Map<String, dynamic>? user]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SuperUserModalDialog(
        user: user,
        allCompanies: _companies,
      ),
    );

    if (result == true) {
      _loadDashboardData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(user == null ? 'User created successfully!' : 'User updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _confirmDeleteCompany(Map<String, dynamic> company) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Company'),
          ],
        ),
        content: Text('Are you sure you want to delete "${company['company_name']}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await CompanyService().deleteCompany(company['id'].toString());
                _loadDashboardData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Company deleted successfully'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteUser(Map<String, dynamic> user) {
    final username = user['username'] ?? 'User';
    final role = user['role'] ?? '';

    if (role == AppConstants.roleSuperAdmin || username.toString().toLowerCase() == 'superadmin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete the primary owner account'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete User'),
          ],
        ),
        content: Text('Are you sure you want to permanently delete user "$username" ($role)? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final userId = user['id'] as int;
                final result = await CompanyService().deleteUser(userId);

                _loadDashboardData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['message'] ?? 'User processed successfully'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete user: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Image.asset('assets/images/logo2.png', height: 28, errorBuilder: (_, __, ___) => const Icon(Icons.shield_rounded, color: Color(0xFF6366F1))),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Super Admin',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(width: 8),
            CompanySwitcherBadge(isDark: true),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Data',
            onPressed: _loadDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
            tooltip: 'Log Out',
            onPressed: _logout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : Column(
              children: [
                // Top Hero Section / Stats Summary
                _buildHeroHeader(),

                // Tabs Navigation
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF4F46E5),
                    unselectedLabelColor: const Color(0xFF64748B),
                    indicatorColor: const Color(0xFF4F46E5),
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.business_rounded, size: 20),
                        text: 'Branches (${_companies.length})',
                      ),
                      Tab(
                        icon: const Icon(Icons.account_balance_rounded, size: 20),
                        text: 'Tally Masters (${_tallyCompanies.length})',
                      ),
                      Tab(
                        icon: const Icon(Icons.people_alt_rounded, size: 20),
                        text: 'Users (${_users.length})',
                      ),
                      const Tab(
                        icon: const Icon(Icons.dashboard_customize_rounded, size: 20),
                        text: 'Global Oversight',
                      ),
                    ],
                  ),
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCompaniesTab(),
                      _buildTallyCompaniesTab(),
                      _buildUsersTab(),
                      _buildOversightTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeroHeader() {
    final activeBranches = _companies.where((c) => c['is_active'] == true).length;
    final allocatedBranchesCount = _companies.where((c) => c['tally_company_id'] != null).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspace_premium_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'APP OWNER TIER',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Platform Overview',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Metric Cards Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Branches',
                  value: '${_companies.length}',
                  subtitle: '$activeBranches Active',
                  icon: Icons.apartment_rounded,
                  color: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'Tally Masters',
                  value: '${_tallyCompanies.length}',
                  subtitle: '$allocatedBranchesCount Linked',
                  icon: Icons.account_balance_rounded,
                  color: const Color(0xFF0D9488),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'Users',
                  value: '${_users.length}',
                  subtitle: 'Across roles',
                  icon: Icons.people_outline_rounded,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'Total Jobs',
                  value: '$_totalJobsAcrossBranches',
                  subtitle: '$_activeJobsAcrossBranches Ongoing',
                  icon: Icons.assignment_outlined,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildCompaniesTab() {
    final filtered = _companies.where((c) {
      if (_companySearch.trim().isEmpty) return true;
      final q = _companySearch.trim().toLowerCase();
      final name = (c['branch_name'] ?? c['company_name'] ?? '').toString().toLowerCase();
      final num = (c['branch_code'] ?? c['company_number'] ?? '').toString().toLowerCase();
      final guid = (c['Guid'] ?? c['guid'] ?? '').toString().toLowerCase();
      final format = (c['format'] ?? c['jobcard_prefix'] ?? c['company_alias'] ?? '').toString().toLowerCase();
      final city = (c['city'] ?? '').toString().toLowerCase();
      final state = (c['state'] ?? '').toString().toLowerCase();
      final address = (c['address_line1'] ?? '').toString().toLowerCase();
      final gst = (c['gst_number'] ?? '').toString().toLowerCase();
      final phone = (c['phone_number'] ?? c['phone'] ?? '').toString().toLowerCase();
      final email = (c['email'] ?? '').toString().toLowerCase();

      return name.contains(q) ||
          num.contains(q) ||
          guid.contains(q) ||
          format.contains(q) ||
          city.contains(q) ||
          state.contains(q) ||
          address.contains(q) ||
          gst.contains(q) ||
          phone.contains(q) ||
          email.contains(q);
    }).toList();

    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _companySearchController,
                  decoration: InputDecoration(
                    hintText: 'Search branches by name, code, prefix, city, GUID...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _companySearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _companySearchController.clear();
                              setState(() => _companySearch = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onChanged: (v) => setState(() => _companySearch = v),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openCompanyModal(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Branch'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),

        // List of branches
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('No branches found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _openCompanyModal(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add New Branch'),
                      ),
                    ],
                  ),
                )
              : AnimationLimiter(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final company = filtered[index];
                      final cId = company['id'].toString();
                      final cName = company['branch_name'] ?? company['company_name'] ?? 'Unknown Branch';
                      final cNum = company['branch_code'] ?? company['company_number'] ?? 'N/A';
                      final cGuid = company['Guid'] ?? company['guid'] ?? 'N/A';
                      final cGst = company['gst_number'] ?? '';
                      final isCurrentActive = CompanyService().companyId?.toString() == cId;
                      final isActive = company['is_active'] == true;

                      return AnimationConfiguration.staggeredList(
                        position: index,
                        duration: const Duration(milliseconds: 300),
                        child: SlideAnimation(
                          verticalOffset: 20.0,
                          child: FadeInAnimation(
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isCurrentActive ? const Color(0xFF4F46E5) : Colors.grey.shade200,
                                  width: isCurrentActive ? 2 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isActive ? const Color(0xFF4F46E5).withValues(alpha: 0.1) : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.apartment_rounded,
                                            color: isActive ? const Color(0xFF4F46E5) : Colors.grey,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      cName,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                  if (isCurrentActive)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF4F46E5),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: const Text(
                                                        'CURRENT CONTEXT',
                                                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'Format: ${(company['format'] ?? company['jobcard_prefix'] ?? company['branch_code'] ?? 'TYX').toString().toUpperCase()}${DateTime.now().year}xxx',
                                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4F46E5)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'Code: $cNum  •  GUID: $cGuid',
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Tally Company Master Link Status Badge
                                    Builder(builder: (_) {
                                      final tallyName = company['tally_company'] as String?;
                                      final hasTally = company['tally_company_id'] != null || (tallyName != null && tallyName.isNotEmpty);
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: hasTally 
                                              ? const Color(0xFF0D9488).withValues(alpha: 0.08) 
                                              : Colors.amber.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: hasTally 
                                                ? const Color(0xFF0D9488).withValues(alpha: 0.3) 
                                                : Colors.amber.shade300,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              hasTally ? Icons.check_circle_rounded : Icons.link_off_rounded,
                                              size: 14,
                                              color: hasTally ? const Color(0xFF0D9488) : Colors.amber.shade800,
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                hasTally ? 'Tally Master: $tallyName' : 'No Tally Master Linked (Unallocated)',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: hasTally ? const Color(0xFF0F766E) : Colors.amber.shade900,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    if (cGst.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('GST: $cGst', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                      ),
                                    ],
                                    const Divider(height: 20),
                                    Row(
                                      children: [
                                        // Active Switch
                                        Row(
                                          children: [
                                            Switch(
                                              value: isActive,
                                              activeColor: const Color(0xFF4F46E5),
                                              onChanged: (val) async {
                                                await CompanyService().toggleCompanyStatus(cId, val);
                                                _loadDashboardData();
                                              },
                                            ),
                                            Text(
                                              isActive ? 'Active' : 'Inactive',
                                              style: TextStyle(
                                                color: isActive ? Colors.green.shade700 : Colors.grey,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Spacer(),
                                        // Set as active context button
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            CompanyService().setActiveCompany(company);
                                            setState(() {});
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Switched context to $cName'), duration: const Duration(seconds: 1)),
                                            );
                                          },
                                          icon: const Icon(Icons.swap_horiz, size: 16),
                                          label: const Text('Select Context'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF4F46E5)),
                                          tooltip: 'Edit Branch',
                                          onPressed: () => _openCompanyModal(company),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                          tooltip: 'Delete Branch',
                                          onPressed: () => _confirmDeleteCompany(company),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTallyCompaniesTab() {
    final filtered = _tallyCompanies.where((t) {
      if (_tallySearch.trim().isEmpty) return true;
      final q = _tallySearch.trim().toLowerCase();
      final name = (t['tally_company_name'] ?? '').toString().toLowerCase();
      final guid = (t['tally_guid'] ?? '').toString().toLowerCase();
      final alias = (t['company_alias'] ?? '').toString().toLowerCase();
      final url = (t['tally_server_url'] ?? '').toString().toLowerCase();
      final gst = (t['gst_number'] ?? '').toString().toLowerCase();
      final pan = (t['pan_number'] ?? '').toString().toLowerCase();
      final city = (t['city'] ?? '').toString().toLowerCase();
      final state = (t['state'] ?? '').toString().toLowerCase();

      return name.contains(q) ||
          guid.contains(q) ||
          alias.contains(q) ||
          url.contains(q) ||
          gst.contains(q) ||
          pan.contains(q) ||
          city.contains(q) ||
          state.contains(q);
    }).toList();

    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tallySearchController,
                  decoration: InputDecoration(
                    hintText: 'Search Tally masters by company name, GUID, alias, server URL, GST...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _tallySearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _tallySearchController.clear();
                              setState(() => _tallySearch = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onChanged: (v) => setState(() => _tallySearch = v),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openTallyCompanyModal(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Tally Master'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),

        // List of Tally Company Masters
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('No Tally Company Masters found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        'Create a Tally company master to allocate branches for Tally synchronization.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _openTallyCompanyModal(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add New Tally Master'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : AnimationLimiter(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final tally = filtered[index];
                      final tId = tally['id'].toString();
                      final tName = tally['tally_company_name'] ?? 'Unnamed Tally Company';
                      final tGuid = tally['tally_guid'] ?? 'N/A';
                      final tAlias = tally['company_alias'] ?? '';
                      final tNum = tally['company_number'] ?? '';
                      final tServer = tally['tally_server_url'] ?? '';
                      final tPort = tally['tally_port'] ?? 9000;
                      final tGst = tally['gst_number'] ?? '';
                      final tPan = tally['pan_number'] ?? '';
                      final syncStatus = (tally['sync_status'] ?? 'pending').toString().toLowerCase();
                      final isActive = tally['is_active'] ?? true;

                      // Find all branches allocated to this tally company master
                      final allocatedBranches = _companies.where((b) => 
                        b['tally_company_id']?.toString() == tId || 
                        (b['tally_company_id'] == null && b['tally_company'] == tName)
                      ).toList();

                      return AnimationConfiguration.staggeredList(
                        position: index,
                        duration: const Duration(milliseconds: 300),
                        child: SlideAnimation(
                          verticalOffset: 20.0,
                          child: FadeInAnimation(
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                                  width: 1.2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header: Icon + Name + Sync Status Pill
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isActive 
                                                ? const Color(0xFF0D9488).withValues(alpha: 0.12) 
                                                : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.account_balance_rounded,
                                            color: isActive ? const Color(0xFF0D9488) : Colors.grey,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      tName,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: syncStatus == 'synced'
                                                          ? Colors.green.shade50
                                                          : syncStatus == 'error'
                                                              ? Colors.red.shade50
                                                              : Colors.amber.shade50,
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: syncStatus == 'synced'
                                                            ? Colors.green.shade300
                                                            : syncStatus == 'error'
                                                                ? Colors.red.shade300
                                                                : Colors.amber.shade300,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          syncStatus == 'synced'
                                                              ? Icons.cloud_done_rounded
                                                              : syncStatus == 'error'
                                                                  ? Icons.error_outline_rounded
                                                                  : Icons.sync_rounded,
                                                          size: 11,
                                                          color: syncStatus == 'synced'
                                                              ? Colors.green.shade700
                                                              : syncStatus == 'error'
                                                                  ? Colors.red.shade700
                                                                  : Colors.amber.shade800,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          syncStatus.toUpperCase(),
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w800,
                                                            color: syncStatus == 'synced'
                                                                ? Colors.green.shade700
                                                                : syncStatus == 'error'
                                                                    ? Colors.red.shade700
                                                                    : Colors.amber.shade800,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'GUID: $tGuid${tAlias.isNotEmpty ? "  •  Alias: $tAlias" : ""}${tNum.isNotEmpty ? "  •  Code: $tNum" : ""}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Server & Tax badges
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (tServer.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.blue.shade200),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.dns_rounded, size: 12, color: Colors.blue),
                                                const SizedBox(width: 4),
                                                Text('$tServer:$tPort', style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        if (tGst.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                                            child: Text('GST: $tGst', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                          ),
                                        if (tPan.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                                            child: Text('PAN: $tPan', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                          ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // Allocated Branches Container
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.account_tree_rounded, size: 16, color: Color(0xFF0F766E)),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Allocated Branches (${allocatedBranches.length})',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5,
                                                  color: Color(0xFF0F766E),
                                                ),
                                              ),
                                              const Spacer(),
                                              TextButton.icon(
                                                onPressed: () => _openBranchAllocationModal(tally),
                                                icon: const Icon(Icons.edit_note_rounded, size: 16),
                                                label: const Text('Manage Allocation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(0xFF0D9488),
                                                  visualDensity: VisualDensity.compact,
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          if (allocatedBranches.isEmpty)
                                            Row(
                                              children: [
                                                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'No branches linked to this Tally company yet.',
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                                ),
                                              ],
                                            )
                                          else
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: allocatedBranches.map((b) {
                                                final bName = b['branch_name'] ?? b['company_name'] ?? 'Branch';
                                                final format = b['format'] ?? b['branch_code'] ?? 'TYX';
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.02),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.domain_rounded, size: 13, color: Color(0xFF0D9488)),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        bName,
                                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          format,
                                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                        ],
                                      ),
                                    ),

                                    const Divider(height: 20),

                                    // Card Footer Actions
                                    Row(
                                      children: [
                                        // Active Switch
                                        Row(
                                          children: [
                                            Switch(
                                              value: isActive,
                                              activeColor: const Color(0xFF0D9488),
                                              onChanged: (val) async {
                                                await CompanyService().updateTallyCompanyMaster(tId, {'is_active': val});
                                                _loadDashboardData();
                                              },
                                            ),
                                            Text(
                                              isActive ? 'Sync Active' : 'Sync Paused',
                                              style: TextStyle(
                                                color: isActive ? Colors.teal.shade700 : Colors.grey,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Spacer(),
                                        ElevatedButton.icon(
                                          onPressed: () => _openBranchAllocationModal(tally),
                                          icon: const Icon(Icons.account_tree_rounded, size: 16),
                                          label: const Text('Allocate Branches'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0D9488),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            visualDensity: VisualDensity.compact,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 0,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF0D9488)),
                                          tooltip: 'Edit Tally Master',
                                          onPressed: () => _openTallyCompanyModal(tally),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                          tooltip: 'Delete Tally Master',
                                          onPressed: () => _confirmDeleteTallyCompany(tally),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildUsersTab() {
    final filtered = _users.where((u) {
      if (_selectedBranchFilter != 'all' && !_userMatchesBranchFilter(u, _selectedBranchFilter)) {
        return false;
      }
      if (_selectedRoleFilter != 'all' && u['role'] != _selectedRoleFilter) return false;
      if (_userSearch.trim().isEmpty) return true;
      final q = _userSearch.trim().toLowerCase();
      final username = (u['username'] ?? '').toString().toLowerCase();
      final role = (u['role'] ?? '').toString().toLowerCase();
      final branchName = (u['branch_name'] ?? u['company_name'] ?? '').toString().toLowerCase();
      final fullName = (u['full_name'] ?? u['name'] ?? '').toString().toLowerCase();
      final phone = (u['phone'] ?? u['phone_number'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();

      // Check if query matches allocated branch names or IDs
      bool matchAlloc = false;
      final rawAllocs = u['allocated_branches'] ?? u['allocated_companies'];
      if (rawAllocs != null) {
        if (rawAllocs is List) {
          for (var item in rawAllocs) {
            final str = item.toString().toLowerCase();
            if (str.contains(q)) matchAlloc = true;
            final matchedBranch = _companies.firstWhere(
              (c) => c['id']?.toString() == item.toString(),
              orElse: () => <String, dynamic>{},
            );
            if (matchedBranch.isNotEmpty) {
              final bName = (matchedBranch['branch_name'] ?? matchedBranch['company_name'] ?? '').toString().toLowerCase();
              if (bName.contains(q)) matchAlloc = true;
            }
          }
        } else if (rawAllocs is String) {
          if (rawAllocs.toLowerCase().contains(q)) matchAlloc = true;
        }
      }

      return username.contains(q) ||
          role.contains(q) ||
          branchName.contains(q) ||
          fullName.contains(q) ||
          phone.contains(q) ||
          email.contains(q) ||
          matchAlloc;
    }).toList();

    return Column(
      children: [
        // Action bar & Branch + Role Filters
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search users by username, role, branch, phone...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _userSearch.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _userSearchController.clear();
                                  setState(() => _userSearch = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onChanged: (v) => setState(() => _userSearch = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _openUserModal(),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Add User'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Branch Filter Chips Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.apartment_rounded, size: 14, color: Color(0xFF0D9488)),
                        SizedBox(width: 4),
                        Text(
                          'Branch:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildBranchFilterChip('all', 'All Branches', Icons.domain_rounded),
                          ..._companies.map((c) {
                            final bId = c['id'].toString();
                            final bName = (c['branch_name'] ?? c['company_name'] ?? 'Branch $bId').toString();
                            final bCode = (c['branch_code'] ?? c['format'] ?? '').toString().trim();
                            final label = bCode.isNotEmpty ? '$bName ($bCode)' : bName;
                            return _buildBranchFilterChip(bId, label, Icons.storefront_rounded);
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Role Filter Chips Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge_outlined, size: 14, color: Color(0xFF0F172A)),
                        SizedBox(width: 4),
                        Text(
                          'Role:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildRoleFilterChip('all', 'All Roles'),
                          _buildRoleFilterChip(AppConstants.roleAdmin, 'Admin'),
                          _buildRoleFilterChip(AppConstants.roleExecutive, 'Executive'),
                          _buildRoleFilterChip(AppConstants.roleAccountant, 'Accountant'),
                          _buildRoleFilterChip(AppConstants.roleWarranty, 'Warranty'),
                          _buildRoleFilterChip(AppConstants.roleSuperAdmin, 'Super Admin'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedBranchFilter != 'all' || _selectedRoleFilter != 'all' || _userSearch.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Text(
                        'Showing ${filtered.length} of ${_users.length} users',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _selectedBranchFilter = 'all';
                            _selectedRoleFilter = 'all';
                            _userSearch = '';
                            _userSearchController.clear();
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.refresh, size: 13, color: Color(0xFF6366F1)),
                              SizedBox(width: 3),
                              Text(
                                'Clear filters',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // List of users
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('No users found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      if (_selectedBranchFilter != 'all' || _selectedRoleFilter != 'all' || _userSearch.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedBranchFilter = 'all';
                              _selectedRoleFilter = 'all';
                              _userSearch = '';
                              _userSearchController.clear();
                            });
                          },
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text('Reset all filters'),
                        ),
                      ],
                    ],
                  ),
                )
              : AnimationLimiter(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      final username = user['username'] ?? 'User';
                      final role = user['role'] ?? 'executive';
                      final isActive = user['is_active'] == true;
                      final primaryCompany = user['branch_name'] ?? user['company_name'] ?? 'All / Dynamic';

                      // Determine allocated count
                      List<dynamic> allocs = [];
                      final rawAllocs = user['allocated_branches'] ?? user['allocated_companies'];
                      if (rawAllocs != null) {
                        if (rawAllocs is List) {
                          allocs = rawAllocs;
                        } else if (rawAllocs is String) {
                          try { allocs = jsonDecode(rawAllocs); } catch (_) {}
                        }
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: _getRoleColor(role).withValues(alpha: 0.15),
                                    foregroundColor: _getRoleColor(role),
                                    child: const Icon(Icons.person, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              username,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getRoleColor(role).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                role.toUpperCase(),
                                                style: TextStyle(
                                                  color: _getRoleColor(role),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Quick access / Switch to user
                                  IconButton(
                                    icon: const Icon(Icons.login_rounded, color: Color(0xFF6366F1)),
                                    tooltip: 'Impersonate / Quick Access',
                                    onPressed: () {
                                      Provider.of<UserProvider>(context, listen: false).setUser(user);
                                      CompanyService().loadCompaniesForUser(user);
                                      Navigator.pushReplacementNamed(context, '/');
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5)),
                                    tooltip: 'Edit User & Allocations',
                                    onPressed: () => _openUserModal(user),
                                  ),
                                  if (role != AppConstants.roleSuperAdmin && (user['username'] ?? '').toString().toLowerCase() != 'superadmin')
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      tooltip: 'Delete User',
                                      onPressed: () => _confirmDeleteUser(user),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Company / Branch allocation badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (allocs.isEmpty && user['branch_name'] == null && user['company_name'] == null && role != AppConstants.roleSuperAdmin)
                                      ? Colors.amber.shade50
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: (allocs.isEmpty && user['branch_name'] == null && user['company_name'] == null && role != AppConstants.roleSuperAdmin)
                                        ? Colors.amber.shade300
                                        : Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      (allocs.isEmpty && user['branch_name'] == null && user['company_name'] == null && role != AppConstants.roleSuperAdmin)
                                          ? Icons.warning_amber_rounded
                                          : Icons.account_tree_outlined,
                                      size: 16,
                                      color: (allocs.isEmpty && user['branch_name'] == null && user['company_name'] == null && role != AppConstants.roleSuperAdmin)
                                          ? Colors.amber.shade800
                                          : const Color(0xFF4F46E5),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        (allocs.isEmpty && user['branch_name'] == null && user['company_name'] == null && role != AppConstants.roleSuperAdmin)
                                            ? 'No Branches Allocated (Login Blocked)'
                                            : (allocs.isNotEmpty
                                                ? '${allocs.length} Branches Allocated (Primary: $primaryCompany)'
                                                : 'Branch: $primaryCompany'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: (allocs.isEmpty && user['branch_name'] == null && user['company_name'] == null && role != AppConstants.roleSuperAdmin)
                                              ? Colors.amber.shade900
                                              : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      isActive ? 'Active' : 'Disabled',
                                      style: TextStyle(
                                        color: isActive ? Colors.green : Colors.red,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  bool _userMatchesBranchFilter(Map<String, dynamic> u, String selectedBranchId) {
    if (selectedBranchId == 'all') return true;

    // Direct primary branch match by ID
    final bId = u['branch_id'] ?? u['company_id'];
    if (bId != null && bId.toString() == selectedBranchId) {
      return true;
    }

    // Selected branch info
    final selectedCompany = _companies.firstWhere(
      (c) => c['id']?.toString() == selectedBranchId,
      orElse: () => <String, dynamic>{},
    );
    final selBranchName = (selectedCompany['branch_name'] ?? selectedCompany['company_name'] ?? '').toString().trim().toLowerCase();

    // Direct primary branch match by Name
    final userBranchName = (u['branch_name'] ?? u['company_name'] ?? '').toString().trim().toLowerCase();
    if (selBranchName.isNotEmpty && userBranchName.isNotEmpty && userBranchName == selBranchName) {
      return true;
    }

    // Check allocated branches/companies
    final rawAllocs = u['allocated_branches'] ?? u['allocated_companies'];
    if (rawAllocs != null) {
      List<dynamic> list = [];
      if (rawAllocs is List) {
        list = rawAllocs;
      } else if (rawAllocs is String) {
        try {
          final decoded = jsonDecode(rawAllocs);
          if (decoded is List) list = decoded;
        } catch (_) {
          if (rawAllocs.toLowerCase().contains(selectedBranchId.toLowerCase()) ||
              (selBranchName.isNotEmpty && rawAllocs.toLowerCase().contains(selBranchName))) {
            return true;
          }
        }
      }

      for (var item in list) {
        final str = item.toString().trim();
        if (str == selectedBranchId) return true;
        if (selBranchName.isNotEmpty && str.toLowerCase() == selBranchName) return true;

        final matchedCompany = _companies.firstWhere(
          (c) => c['id']?.toString() == str,
          orElse: () => <String, dynamic>{},
        );
        if (matchedCompany.isNotEmpty && matchedCompany['id']?.toString() == selectedBranchId) {
          return true;
        }
      }
    }

    return false;
  }

  Widget _buildBranchFilterChip(String key, String label, IconData icon) {
    final isSelected = _selectedBranchFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(
          icon,
          size: 14,
          color: isSelected ? Colors.white : const Color(0xFF0D9488),
        ),
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF0D9488),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(
          color: isSelected ? const Color(0xFF0D9488) : Colors.grey.shade300,
        ),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade800,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
        onSelected: (_) => setState(() => _selectedBranchFilter = key),
      ),
    );
  }

  Widget _buildRoleFilterChip(String key, String label) {
    final isSelected = _selectedRoleFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(
          color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade300,
        ),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
        onSelected: (_) => setState(() => _selectedRoleFilter = key),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case AppConstants.roleSuperAdmin:
        return const Color(0xFF8B5CF6);
      case AppConstants.roleAdmin:
        return const Color(0xFF4F46E5);
      case AppConstants.roleExecutive:
        return const Color(0xFF0EA5E9);
      case AppConstants.roleAccountant:
        return const Color(0xFF10B981);
      case AppConstants.roleWarranty:
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _buildOversightTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Operations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 14),

          // Shortcut Cards
          Row(
            children: [
              Expanded(
                child: _buildOperationCard(
                  title: 'View All Job Cards',
                  description: 'Inspect jobs across active company context',
                  icon: Icons.assignment_turned_in_outlined,
                  color: const Color(0xFF4F46E5),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UpdateScreen(isAdminMode: true)),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildOperationCard(
                  title: 'Reports & Analytics',
                  description: 'Generate financial & operational reports',
                  icon: Icons.analytics_outlined,
                  color: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReportsAnalyticsScreen()),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Text(
            'Branch Sync & System Health',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 14),

          // Branch list overview
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _companies.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, i) {
                final c = _companies[i];
                final syncStatus = c['sync_status'] ?? 'Active';
                final isSynced = c['is_synced'] == true;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                    child: const Icon(Icons.domain, color: Color(0xFF4F46E5), size: 20),
                  ),
                  title: Text(c['company_name'] ?? 'Company', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('GUID: ${c['Guid'] ?? "N/A"}'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSynced ? Colors.green.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isSynced ? 'Synced' : 'Active',
                      style: TextStyle(
                        color: isSynced ? Colors.green.shade700 : Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
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

  Widget _buildOperationCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
