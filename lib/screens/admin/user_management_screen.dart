// lib/screens/admin/user_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../utils/app_constants.dart';
import '../../services/company_service.dart';
import '../../widgets/company_switcher_badge.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;
  String _selectedRoleFilter = 'ALL';

  final List<Map<String, String>> _roleFilters = [
    {'key': 'ALL', 'label': 'All Staff'},
    {'key': AppConstants.roleExecutive, 'label': 'Executive'},
    {'key': AppConstants.roleWarranty, 'label': 'Warranty'},
    {'key': AppConstants.roleAccountant, 'label': 'Accountant'},
    {'key': 'TECHNICIAN', 'label': 'Technicians'},
    {'key': AppConstants.roleTeleCaller, 'label': 'Tele-Caller'},
    {'key': AppConstants.rolePickupDropoff, 'label': 'Pickup/Drop'},
  ];

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final currentBranchId = CompanyService().branchId;
      final currentBranchName = CompanyService().branchName;

      // 1. Fetch user branch allocations from user_branches junction table if available
      Set<int> branchUserIds = {};
      if (currentBranchId != null) {
        try {
          final junctionRes = await supabase
              .from('user_branches')
              .select('user_id')
              .eq('branch_id', currentBranchId);
          for (var row in junctionRes as List<dynamic>) {
            if (row['user_id'] != null) {
              final uid = int.tryParse(row['user_id'].toString());
              if (uid != null) branchUserIds.add(uid);
            }
          }
        } catch (_) {}

        if (branchUserIds.isEmpty) {
          try {
            final junctionRes = await supabase
                .from('user_companies')
                .select('user_id')
                .eq('company_id', currentBranchId);
            for (var row in junctionRes as List<dynamic>) {
              if (row['user_id'] != null) {
                final uid = int.tryParse(row['user_id'].toString());
                if (uid != null) branchUserIds.add(uid);
              }
            }
          } catch (_) {}
        }
      }

      // 2. Fetch all non-superadmin users
      final usersRes = await supabase
          .from('users')
          .select('*')
          .neq('role', AppConstants.roleSuperAdmin)
          .order('username');

      List<Map<String, dynamic>> branchUsers = [];

      for (var u in usersRes as List<dynamic>) {
        final uMap = Map<String, dynamic>.from(u);
        final uId = int.tryParse(uMap['id']?.toString() ?? '');

        // Check if user belongs to active branch
        bool belongsToBranch = false;

        if (uId != null && branchUserIds.contains(uId)) {
          belongsToBranch = true;
        } else if (currentBranchId != null &&
            (uMap['branch_id']?.toString() == currentBranchId.toString() ||
                uMap['company_id']?.toString() == currentBranchId.toString())) {
          belongsToBranch = true;
        } else if (currentBranchName != null &&
            (uMap['branch_name']?.toString().toLowerCase() == currentBranchName.toLowerCase() ||
                uMap['company_name']?.toString().toLowerCase() == currentBranchName.toLowerCase())) {
          belongsToBranch = true;
        } else if (uMap['allocated_branches'] != null || uMap['allocated_companies'] != null) {
          final raw = uMap['allocated_branches'] ?? uMap['allocated_companies'];
          List<dynamic> allocs = [];
          if (raw is String) {
            try { allocs = jsonDecode(raw); } catch (_) {}
          } else if (raw is List) {
            allocs = raw;
          }
          if (allocs.map((e) => e.toString()).contains(currentBranchId?.toString())) {
            belongsToBranch = true;
          }
        }

        // If no branch-specific filtering match was found, include if no branch is assigned yet
        if (belongsToBranch || (currentBranchId == null && branchUserIds.isEmpty)) {
          branchUsers.add(uMap);
        }
      }

      // If branch filter resulted in empty list (e.g., initial setup without allocations), show users list
      if (branchUsers.isEmpty && (usersRes as List).isNotEmpty) {
        branchUsers = (usersRes as List).map((u) => Map<String, dynamic>.from(u)).toList();
      }

      if (mounted) {
        setState(() {
          _allUsers = branchUsers;
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint('Error loading branch users: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load team: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredUsers = _allUsers.where((u) {
        // Role filter
        final role = u['role']?.toString().toLowerCase() ?? '';
        if (_selectedRoleFilter != 'ALL') {
          if (_selectedRoleFilter == 'TECHNICIAN') {
            final isTech = role.contains('tech') ||
                role == AppConstants.roleAlignmentTech ||
                role == AppConstants.roleInstallationTech ||
                role == 'washer' ||
                role == 'inspector';
            if (!isTech) return false;
          } else if (role != _selectedRoleFilter.toLowerCase()) {
            return false;
          }
        }

        // Search query filter
        if (query.isNotEmpty) {
          final username = u['username']?.toString().toLowerCase() ?? '';
          final phone = (u['phone_number'] ?? u['phone'] ?? '').toString().toLowerCase();
          final email = u['email']?.toString().toLowerCase() ?? '';
          final fullName = (u['full_name'] ?? u['name'] ?? '').toString().toLowerCase();
          final branchName = (u['branch_name'] ?? u['company_name'] ?? '').toString().toLowerCase();
          final id = u['id']?.toString() ?? '';
          final roleDisplay = role.replaceAll('_', ' ');
          if (!username.contains(query) &&
              !phone.contains(query) &&
              !email.contains(query) &&
              !fullName.contains(query) &&
              !branchName.contains(query) &&
              !id.contains(query) &&
              !roleDisplay.contains(query)) {
            return false;
          }
        }

        return true;
      }).toList();
    });
  }

  Color _getRoleColor(String? role) {
    final r = role?.toLowerCase() ?? '';
    if (r == AppConstants.roleExecutive) return const Color(0xFF2563EB); // Blue
    if (r == AppConstants.roleWarranty) return const Color(0xFF7C3AED); // Purple
    if (r == AppConstants.roleAccountant) return const Color(0xFF059669); // Emerald
    if (r.contains('tech') || r == 'washer' || r == 'inspector') return const Color(0xFFD97706); // Amber
    if (r == AppConstants.roleAdmin) return const Color(0xFF4F46E5); // Indigo
    if (r == AppConstants.roleTeleCaller || r == AppConstants.rolePickupDropoff) return const Color(0xFF0891B2); // Cyan
    return const Color(0xFF64748B); // Slate
  }

  IconData _getRoleIcon(String? role) {
    final r = role?.toLowerCase() ?? '';
    if (r == AppConstants.roleExecutive) return Icons.badge_outlined;
    if (r == AppConstants.roleWarranty) return Icons.verified_user_outlined;
    if (r == AppConstants.roleAccountant) return Icons.receipt_long_outlined;
    if (r.contains('align')) return Icons.tune_outlined;
    if (r.contains('install') || r.contains('tech')) return Icons.build_outlined;
    if (r == AppConstants.roleTeleCaller) return Icons.phone_in_talk_outlined;
    if (r == AppConstants.rolePickupDropoff) return Icons.directions_car_outlined;
    if (r == AppConstants.roleAdmin) return Icons.admin_panel_settings_outlined;
    return Icons.person_outline;
  }

  String _formatRoleName(String? role) {
    if (role == null || role.isEmpty) return 'Staff';
    final parts = role.split('_');
    return parts.map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final branchName = CompanyService().branchName ?? 'Branch';
    final branchPrefix = CompanyService().branchFormat;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Branch Team Directory'),
        centerTitle: false,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: CompanySwitcherBadge(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadUsers,
        child: Column(
          children: [
            // Top Header & Info Banner
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Branch info row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          '[$branchPrefix] $branchName',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_filteredUsers.length} Staff Member${_filteredUsers.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // View-only notice banner
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF64748B)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'View-Only: Staff accounts, passwords, and branch allocations are managed exclusively by Administration.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Search Bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search staff by name or role...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Role Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _roleFilters.map((f) {
                        final isSelected = _selectedRoleFilter == f['key'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(f['label']!),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() => _selectedRoleFilter = f['key']!);
                              _applyFilters();
                            },
                            backgroundColor: const Color(0xFFF1F5F9),
                            selectedColor: const Color(0xFF4F46E5),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.white : const Color(0xFF475569),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Staff List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 56, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                _searchController.text.isNotEmpty || _selectedRoleFilter != 'ALL'
                                    ? 'No team members matching your filter'
                                    : 'No staff members assigned to this branch',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Contact Administration to allocate users to $branchName.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredUsers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];
                            final role = user['role']?.toString() ?? 'staff';
                            final username = user['username']?.toString() ?? 'Unnamed User';
                            final isActive = user['is_active'] ?? true;
                            final roleColor = _getRoleColor(role);
                            final roleIcon = _getRoleIcon(role);
                            final roleTitle = _formatRoleName(role);

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: roleColor.withValues(alpha: 0.12),
                                      child: Icon(roleIcon, color: roleColor, size: 24),
                                    ),
                                    PositionIndicator(isActive: isActive),
                                  ],
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        username,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        roleTitle.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: roleColor,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isActive ? Icons.check_circle_outline : Icons.cancel_outlined,
                                        size: 13,
                                        color: isActive ? Colors.green : Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isActive ? 'Active Staff' : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isActive ? Colors.green.shade700 : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.tag, size: 12, color: Colors.grey),
                                      Text(
                                        'ID: ${user['id']}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.05, end: 0);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class PositionIndicator extends StatelessWidget {
  final bool isActive;
  const PositionIndicator({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      bottom: 0,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}