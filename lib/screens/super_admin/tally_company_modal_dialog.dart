// lib/screens/super_admin/tally_company_modal_dialog.dart
import 'package:flutter/material.dart';
import '../../services/company_service.dart';
import '../../widgets/modern_input.dart';

class TallyCompanyModalDialog extends StatefulWidget {
  final Map<String, dynamic>? tallyCompany; // Null for Create, non-null for Edit
  final List<Map<String, dynamic>> allBranches;

  const TallyCompanyModalDialog({
    super.key,
    this.tallyCompany,
    this.allBranches = const [],
  });

  @override
  State<TallyCompanyModalDialog> createState() => _TallyCompanyModalDialogState();
}

class _TallyCompanyModalDialogState extends State<TallyCompanyModalDialog> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _guidController = TextEditingController();
  final _numberController = TextEditingController();
  final _aliasController = TextEditingController();
  final _serverUrlController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _gstController = TextEditingController();
  final _panController = TextEditingController();
  final _tanController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _countryController = TextEditingController(text: 'India');

  bool _isActive = true;
  bool _isSubmitting = false;
  final Set<String> _selectedBranchIds = {};

  bool get isEditing => widget.tallyCompany != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final t = widget.tallyCompany!;
      _nameController.text = t['tally_company_name'] ?? '';
      _guidController.text = t['tally_guid'] ?? '';
      _numberController.text = t['company_number'] ?? '';
      _aliasController.text = t['company_alias'] ?? '';
      _serverUrlController.text = t['tally_server_url'] ?? '';
      _portController.text = t['tally_port'] != null ? t['tally_port'].toString() : '9000';
      _usernameController.text = t['tally_username'] ?? '';
      _passwordController.text = t['tally_password'] ?? '';
      _gstController.text = t['gst_number'] ?? '';
      _panController.text = t['pan_number'] ?? '';
      _tanController.text = t['tan_number'] ?? '';
      _phoneController.text = t['phone_number'] ?? '';
      _emailController.text = t['email'] ?? '';
      _cityController.text = t['city'] ?? '';
      _stateController.text = t['state'] ?? '';
      _pinController.text = t['pin_code'] ?? '';
      _address1Controller.text = t['address_line1'] ?? '';
      _address2Controller.text = t['address_line2'] ?? '';
      _countryController.text = t['country'] ?? 'India';
      _isActive = t['is_active'] ?? true;

      // Find branches currently allocated to this tally company
      final tId = t['id']?.toString();
      if (tId != null) {
        for (final b in widget.allBranches) {
          if (b['tally_company_id']?.toString() == tId) {
            _selectedBranchIds.add(b['id'].toString());
          }
        }
      }
    } else {
      _guidController.text = 'TALLY-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      _portController.text = '9000';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _guidController.dispose();
    _numberController.dispose();
    _aliasController.dispose();
    _serverUrlController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _gstController.dispose();
    _panController.dispose();
    _tanController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pinController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _saveTallyCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final portVal = int.tryParse(_portController.text.trim()) ?? 9000;

      final data = <String, dynamic>{
        'tally_company_name': _nameController.text.trim(),
        'tally_guid': _guidController.text.trim(),
        'company_number': _numberController.text.trim().isEmpty ? null : _numberController.text.trim(),
        'company_alias': _aliasController.text.trim().isEmpty ? null : _aliasController.text.trim(),
        'tally_server_url': _serverUrlController.text.trim().isEmpty ? null : _serverUrlController.text.trim(),
        'tally_port': portVal,
        'tally_username': _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        'tally_password': _passwordController.text.trim().isEmpty ? null : _passwordController.text.trim(),
        'gst_number': _gstController.text.trim().isEmpty ? null : _gstController.text.trim(),
        'pan_number': _panController.text.trim().isEmpty ? null : _panController.text.trim(),
        'tan_number': _tanController.text.trim().isEmpty ? null : _tanController.text.trim(),
        'phone_number': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'city': _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
        'pin_code': _pinController.text.trim().isEmpty ? null : _pinController.text.trim(),
        'address_line1': _address1Controller.text.trim().isEmpty ? null : _address1Controller.text.trim(),
        'address_line2': _address2Controller.text.trim().isEmpty ? null : _address2Controller.text.trim(),
        'country': _countryController.text.trim().isEmpty ? 'India' : _countryController.text.trim(),
        'is_active': _isActive,
      };

      String savedId;
      if (isEditing) {
        savedId = widget.tallyCompany!['id'].toString();
        await CompanyService().updateTallyCompanyMaster(savedId, data);
      } else {
        final res = await CompanyService().createTallyCompanyMaster(data);
        savedId = res['id'].toString();
      }

      // If branch allocations were chosen in this dialog, save them
      if (widget.allBranches.isNotEmpty) {
        await CompanyService().allocateBranchesToTallyCompany(
          tallyCompanyMasterId: savedId,
          branchIds: _selectedBranchIds.toList(),
          tallyCompanyData: {...data, 'id': savedId},
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save Tally Company: $e'), backgroundColor: Colors.red),
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
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Column(
          children: [
            // Gradient Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D9488), Color(0xFF0284C7)],
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
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit Tally Company Master' : 'Add Tally Company Master',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isEditing ? 'Update Tally sync parameters & server credentials' : 'Register a new Tally Company in tally_company_master',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
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
                      // Section 1: Core Tally Details
                      _sectionTitle('Company & Tally Identification', Icons.fingerprint),
                      const SizedBox(height: 10),

                      ModernTextField(
                        controller: _nameController,
                        label: 'Tally Company Name *',
                        hint: 'e.g. TYREX PRIVATE LIMITED (2026-27)',
                        prefixIcon: const Icon(Icons.business_rounded),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Tally company name is required' : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _guidController,
                              label: 'Tally GUID *',
                              hint: 'Unique GUID for Tally XML',
                              prefixIcon: const Icon(Icons.vpn_key_rounded),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Tally GUID is required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _aliasController,
                              label: 'Company Alias',
                              hint: 'e.g. TYX-HO',
                              prefixIcon: const Icon(Icons.short_text_rounded),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      ModernTextField(
                        controller: _numberController,
                        label: 'Company Number / Code',
                        hint: 'e.g. 10001',
                        prefixIcon: const Icon(Icons.tag),
                      ),
                      const SizedBox(height: 20),

                      // Section 2: Server & Integration
                      _sectionTitle('Tally Server & Sync Gateway', Icons.cloud_sync_rounded),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ModernTextField(
                              controller: _serverUrlController,
                              label: 'Tally Server URL',
                              hint: 'http://localhost or http://192.168.1.100',
                              prefixIcon: const Icon(Icons.dns_rounded),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: ModernTextField(
                              controller: _portController,
                              label: 'Port',
                              hint: '9000',
                              prefixIcon: const Icon(Icons.numbers),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _usernameController,
                              label: 'Tally Username',
                              hint: 'Optional Auth User',
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _passwordController,
                              label: 'Tally Password',
                              hint: 'Optional Auth Pass',
                              prefixIcon: const Icon(Icons.lock_outline),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Section 3: Tax & Registration
                      _sectionTitle('Tax & Legal Info', Icons.receipt_long_rounded),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _gstController,
                              label: 'GST Number',
                              hint: '32AAAAA0000A1Z5',
                              prefixIcon: const Icon(Icons.receipt),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _panController,
                              label: 'PAN Number',
                              hint: 'AAAAA0000A',
                              prefixIcon: const Icon(Icons.badge_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _phoneController,
                              label: 'Phone Number',
                              hint: 'Official phone',
                              prefixIcon: const Icon(Icons.phone),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _emailController,
                              label: 'Email',
                              hint: 'accounts@company.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      ModernTextField(
                        controller: _address1Controller,
                        label: 'Address Line 1',
                        hint: 'Registered office address',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _cityController,
                              label: 'City',
                              hint: 'City',
                              prefixIcon: const Icon(Icons.location_city),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _stateController,
                              label: 'State',
                              hint: 'State (e.g. Kerala)',
                              prefixIcon: const Icon(Icons.map_outlined),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _pinController,
                              label: 'Pin Code',
                              hint: '682001',
                              prefixIcon: const Icon(Icons.pin_drop_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Section 4: Branch Allocation (if branches available)
                      if (widget.allBranches.isNotEmpty) ...[
                        _sectionTitle('Allocate Branches to this Tally Company', Icons.account_tree_rounded),
                        const SizedBox(height: 6),
                        Text(
                          'Select all branches that should sync invoices & payments into this Tally company.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: widget.allBranches.map((b) {
                              final bId = b['id'].toString();
                              final bName = b['branch_name'] ?? b['company_name'] ?? 'Branch';
                              final isSelected = _selectedBranchIds.contains(bId);

                              // Check if currently allocated to another tally company
                              final otherTallyId = b['tally_company_id']?.toString();
                              final isOtherTally = otherTallyId != null && 
                                  otherTallyId.isNotEmpty && 
                                  (!isEditing || otherTallyId != widget.tallyCompany?['id']?.toString());
                              final otherTallyName = b['tally_company'] ?? 'Another Tally Company';

                              return CheckboxListTile(
                                dense: true,
                                value: isSelected,
                                activeColor: const Color(0xFF0D9488),
                                title: Text(bName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                subtitle: isOtherTally
                                    ? Text('Currently linked to: $otherTallyName', style: const TextStyle(fontSize: 11, color: Colors.orange))
                                    : Text('Format: ${b['format'] ?? b['branch_code'] ?? 'TYX'}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedBranchIds.add(bId);
                                    } else {
                                      _selectedBranchIds.remove(bId);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Active Switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active for Synchronization', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        subtitle: const Text('Enable or disable Tally integration for this master company', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        value: _isActive,
                        activeColor: const Color(0xFF0D9488),
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
                    onPressed: _isSubmitting ? null : _saveTallyCompany,
                    icon: _isSubmitting 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(isEditing ? 'Save Changes' : 'Create Tally Master'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
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

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0D9488)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
      ],
    );
  }
}
