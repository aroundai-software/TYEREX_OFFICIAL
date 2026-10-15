// lib/screens/super_admin/super_user_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_constants.dart';
import '../../services/company_service.dart';
import '../../widgets/modern_input.dart';

class SuperUserModalDialog extends StatefulWidget {
  final Map<String, dynamic>? user; // Null for Create, non-null for Edit
  final List<Map<String, dynamic>> allCompanies;

  const SuperUserModalDialog({
    super.key,
    this.user,
    required this.allCompanies,
  });

  @override
  State<SuperUserModalDialog> createState() => _SuperUserModalDialogState();
}

class _SuperUserModalDialogState extends State<SuperUserModalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final supabase = Supabase.instance.client;

  String _selectedRole = AppConstants.roleExecutive;
  bool _isActive = true;
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  // Set of selected company IDs (as strings)
  final Set<String> _selectedCompanyIds = {};

  bool get isEditing => widget.user != null;

  late final List<String> _allRoles = [
    AppConstants.roleAdmin,
    AppConstants.roleExecutive,
    AppConstants.roleAccountant,
    AppConstants.roleWarranty,
    AppConstants.roleTeleCaller,
    AppConstants.rolePickupDropoff,
    AppConstants.roleAlignmentTech,
    AppConstants.roleInstallationTech,
    'washer',
    'inspector',
  ];

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final u = widget.user!;
      _usernameController.text = u['username'] ?? '';
      _passwordController.text = u['password'] ?? '';
      final userRole = u['role']?.toString() ?? AppConstants.roleExecutive;
      if (!_allRoles.contains(userRole)) {
        _allRoles.add(userRole);
      }
      _selectedRole = userRole;
      _isActive = u['is_active'] ?? true;
      _loadAllocatedCompaniesForUser(u['id']);
    } else {
      // By default for new user, select all active companies or first active company
      if (widget.allCompanies.isNotEmpty) {
        _selectedCompanyIds.add(widget.allCompanies.first['id'].toString());
      }
    }
  }

  Future<void> _loadAllocatedCompaniesForUser(dynamic userId) async {
    if (userId == null) return;
    try {
      final int uId = userId is int ? userId : int.parse(userId.toString());
      final ids = await CompanyService().getUserCompanyIds(uId);
      if (mounted) {
        setState(() {
          _selectedCompanyIds.addAll(ids);
          // If junction table was empty, check user's direct branch_id / allocated_branches / branch_name
          if (_selectedCompanyIds.isEmpty) {
            final u = widget.user!;
            final directBId = u['branch_id'] ?? u['company_id'];
            final directBName = u['branch_name'] ?? u['company_name'];
            final rawAlloc = u['allocated_branches'] ?? u['allocated_companies'];
            if (rawAlloc != null) {
              if (rawAlloc is List) {
                _selectedCompanyIds.addAll(rawAlloc.map((e) => e.toString()));
              } else if (rawAlloc is String) {
                try {
                  final list = jsonDecode(rawAlloc) as List;
                  _selectedCompanyIds.addAll(list.map((e) => e.toString()));
                } catch (_) {}
              }
            }
            if (_selectedCompanyIds.isEmpty) {
              for (var c in widget.allCompanies) {
                if ((directBId != null && c['id'].toString() == directBId.toString()) ||
                    (directBName != null && (c['branch_name'] == directBName || c['company_name'] == directBName))) {
                  _selectedCompanyIds.add(c['id'].toString());
                }
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading user company allocations: $e');
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      // Find primary branch / company if any are selected
      Map<String, dynamic>? primaryCompany;
      if (_selectedCompanyIds.isNotEmpty) {
        final firstId = _selectedCompanyIds.first;
        primaryCompany = widget.allCompanies.firstWhere(
          (c) => c['id'].toString() == firstId,
          orElse: () => widget.allCompanies.first,
        );
      }

      final branchName = primaryCompany?['branch_name'] ?? primaryCompany?['company_name'];

      // Only include valid database columns for the users table
      final userData = <String, dynamic>{
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
        'role': _selectedRole,
        'is_active': _isActive,
        'branch_id': primaryCompany?['id'],
        'branch_name': branchName,
        'company_name': branchName,
        'allocated_branches': _selectedCompanyIds.toList(),
      };

      int targetUserId;

      if (isEditing) {
        targetUserId = widget.user!['id'] as int;
        await supabase.from('users').update(userData).eq('id', targetUserId);
      } else {
        final res = await supabase.from('users').insert(userData).select('id').single();
        targetUserId = res['id'] as int;
      }

      // Sync branch allocations in junction table and user record
      await CompanyService().setUserCompanyAllocations(
        targetUserId,
        _selectedCompanyIds.toList(),
        primaryCompanyId: primaryCompany?['id'],
        primaryCompanyName: branchName,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save user: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteUser() async {
    final username = widget.user?['username'] ?? 'User';
    final confirmed = await showDialog<bool>(
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
        content: Text('Are you sure you want to permanently delete "$username"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final userId = widget.user!['id'] as int;
      final res = await CompanyService().deleteUser(userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'User deleted successfully'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete user: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF334155)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit User & Branch Allocation' : 'Create New User & Allocation',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isEditing ? 'Modify roles and assigned branches' : 'Set up credentials and allocate branches',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Username & Password
                      ModernTextField(
                        controller: _usernameController,
                        label: 'Username *',
                        hint: 'e.g. rahul_executive',
                        prefixIcon: const Icon(Icons.person_outline),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null,
                      ),
                      const SizedBox(height: 14),

                      ModernTextField(
                        controller: _passwordController,
                        label: 'Password *',
                        hint: 'Enter password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Password is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Role Dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: InputDecoration(
                          labelText: 'Role *',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        items: _allRoles.toSet().map((r) {
                          final label = r.replaceAll('_', ' ').toUpperCase();
                          return DropdownMenuItem(value: r, child: Text(label));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedRole = v);
                        },
                      ),
                      const SizedBox(height: 14),

                      // Branch Allocation Section
                      const Divider(height: 28),
                      Row(
                        children: [
                          const Icon(Icons.account_tree_outlined, color: Color(0xFF4F46E5), size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Branch Allocation',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: Icon(
                              _selectedCompanyIds.isNotEmpty ? Icons.deselect : Icons.select_all,
                              size: 16,
                            ),
                            label: Text(_selectedCompanyIds.isNotEmpty ? 'Deselect All' : 'Select All'),
                            onPressed: () {
                              setState(() {
                                if (_selectedCompanyIds.isNotEmpty) {
                                  _selectedCompanyIds.clear();
                                } else {
                                  _selectedCompanyIds.clear();
                                  _selectedCompanyIds.addAll(widget.allCompanies.map((c) => c['id'].toString()));
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const Text(
                        'Select which branches this user is allowed to access. When logged in, they can view and work on jobcards only for their assigned branches.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (_selectedCompanyIds.isEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '0 branches allocated. This user will NOT be permitted to log in until assigned a branch.',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),

                      // List of Branch Checkboxes
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFF8FAFC),
                        ),
                        child: widget.allCompanies.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No branches available. Please create a branch first in Branch Management.'),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: widget.allCompanies.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                                itemBuilder: (context, idx) {
                                  final branch = widget.allCompanies[idx];
                                  final bId = branch['id'].toString();
                                  final bName = branch['branch_name'] ?? branch['company_name'] ?? 'Unknown Branch';
                                  final bCode = branch['branch_code'] ?? branch['company_number'] ?? '';
                                  final isChecked = _selectedCompanyIds.contains(bId);

                                  return CheckboxListTile(
                                    value: isChecked,
                                    activeColor: const Color(0xFF4F46E5),
                                    title: Text(
                                      bName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isChecked ? FontWeight.w700 : FontWeight.w500,
                                        color: isChecked ? const Color(0xFF1E293B) : Colors.grey.shade700,
                                      ),
                                    ),
                                    subtitle: bCode.isNotEmpty ? Text('Branch Code: $bCode', style: const TextStyle(fontSize: 11)) : null,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedCompanyIds.add(bId);
                                        } else {
                                          _selectedCompanyIds.remove(bId);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),

                      const SizedBox(height: 16),

                      // Active Switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Account Active', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        subtitle: const Text('Disabled users cannot log into the app', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        value: _isActive,
                        activeColor: const Color(0xFF10B981),
                        onChanged: (val) => setState(() => _isActive = val),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  if (isEditing && _selectedRole != AppConstants.roleSuperAdmin && (widget.user?['username'] ?? '').toString().toLowerCase() != 'superadmin')
                    TextButton.icon(
                      onPressed: _isSubmitting ? null : _deleteUser,
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      label: const Text('Delete User', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _saveUser,
                    icon: _isSubmitting 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(isEditing ? 'Update User' : 'Create User'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
