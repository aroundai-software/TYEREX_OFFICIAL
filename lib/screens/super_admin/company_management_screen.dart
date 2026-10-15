// lib/screens/super_admin/company_management_screen.dart
import 'package:flutter/material.dart';
import '../../services/company_service.dart';
import '../../widgets/modern_input.dart';

class CompanyModalDialog extends StatefulWidget {
  final Map<String, dynamic>? company; // Null for Create, non-null for Edit
  final List<Map<String, dynamic>>? tallyMasters;

  const CompanyModalDialog({super.key, this.company, this.tallyMasters});

  @override
  State<CompanyModalDialog> createState() => _CompanyModalDialogState();
}

class _CompanyModalDialogState extends State<CompanyModalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _formatController = TextEditingController();
  final _numberController = TextEditingController();
  final _guidController = TextEditingController();
  final _aliasController = TextEditingController();
  final _gstController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinController = TextEditingController();
  final _address1Controller = TextEditingController();

  bool _isActive = true;
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _tallyMasters = [];
  String? _selectedTallyCompanyId;

  bool get isEditing => widget.company != null;

  @override
  void initState() {
    super.initState();
    if (widget.tallyMasters != null) {
      _tallyMasters = List<Map<String, dynamic>>.from(widget.tallyMasters!);
    } else {
      CompanyService().getAllTallyCompanyMasters().then((masters) {
        if (mounted) setState(() => _tallyMasters = masters);
      });
    }

    if (isEditing) {
      final c = widget.company!;
      _nameController.text = c['branch_name'] ?? c['company_name'] ?? '';
      final existingFormat = c['format'] ?? c['jobcard_prefix'];
      if (existingFormat != null && existingFormat.toString().trim().isNotEmpty) {
        _formatController.text = existingFormat.toString().trim().toUpperCase();
      } else {
        final bName = c['branch_name'] ?? c['company_name'] ?? '';
        final clean = bName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
        _formatController.text = clean.length >= 3 ? clean.substring(0, 3) : (clean.isNotEmpty ? clean : 'TYX');
      }
      _numberController.text = c['branch_code'] ?? c['company_number'] ?? '';
      _guidController.text = c['Guid'] ?? c['guid'] ?? '';
      _aliasController.text = c['company_alias'] ?? '';
      _gstController.text = c['gst_number'] ?? '';
      _phoneController.text = c['phone_number'] ?? '';
      _emailController.text = c['email'] ?? '';
      _cityController.text = c['city'] ?? '';
      _stateController.text = c['state'] ?? '';
      _pinController.text = c['pin_code'] ?? '';
      _address1Controller.text = c['address_line1'] ?? '';
      _isActive = c['is_active'] ?? true;
      _selectedTallyCompanyId = c['tally_company_id']?.toString();
    } else {
      _formatController.text = '';
      _guidController.text = 'BR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _formatController.dispose();
    _numberController.dispose();
    _guidController.dispose();
    _aliasController.dispose();
    _gstController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pinController.dispose();
    _address1Controller.dispose();
    super.dispose();
  }

  Future<void> _saveCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final formatVal = _formatController.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final nameClean = _nameController.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      final effectivePrefix = formatVal.isNotEmpty 
          ? formatVal 
          : (nameClean.length >= 3 ? nameClean.substring(0, 3) : (nameClean.isNotEmpty ? nameClean : 'TYX'));

      final data = <String, dynamic>{
        'branch_name': _nameController.text.trim(),
        'company_name': _nameController.text.trim(),
        'format': effectivePrefix,
        'jobcard_prefix': effectivePrefix,
        'branch_code': _numberController.text.trim().isEmpty 
            ? '01' 
            : _numberController.text.trim(),
        'company_number': _numberController.text.trim().isEmpty 
            ? '01' 
            : _numberController.text.trim(),
        'Guid': _guidController.text.trim(),
        'company_alias': _aliasController.text.trim().isEmpty ? effectivePrefix : _aliasController.text.trim(),
        'gst_number': _gstController.text.trim().isEmpty ? null : _gstController.text.trim(),
        'phone_number': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'city': _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
        'pin_code': _pinController.text.trim().isEmpty ? null : _pinController.text.trim(),
        'address_line1': _address1Controller.text.trim().isEmpty ? null : _address1Controller.text.trim(),
        'is_active': _isActive,
        'tally_company_id': _selectedTallyCompanyId,
      };

      if (_selectedTallyCompanyId != null && _selectedTallyCompanyId!.isNotEmpty) {
        final matchedTally = _tallyMasters.where((t) => t['id']?.toString() == _selectedTallyCompanyId).firstOrNull;
        if (matchedTally != null) {
          data['tally_company'] = matchedTally['tally_company_name'];
          data['tally_guid'] = matchedTally['tally_guid'];
          if (matchedTally['company_number'] != null) {
            data['company_number'] = matchedTally['company_number'];
          }
        }
      } else {
        data['tally_company'] = null;
        data['tally_guid'] = null;
      }

      if (isEditing) {
        final id = widget.company!['id'].toString();
        await CompanyService().updateCompany(id, data);
      } else {
        await CompanyService().createCompany(data);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save branch: $e'), backgroundColor: Colors.red),
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
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          children: [
            // Gradient Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
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
                    child: const Icon(Icons.business_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit Branch' : 'Add New Branch',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isEditing ? 'Update branch parameters & location' : 'Register a new branch in the branches table',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
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
                      ModernTextField(
                        controller: _nameController,
                        label: 'Branch Name *',
                        hint: 'e.g. KOCHI MAIN BRANCH or THRISSUR HUB',
                        prefixIcon: const Icon(Icons.domain),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Branch name is required' : null,
                        onChanged: (v) {
                          if (!isEditing && _formatController.text.isEmpty) {
                            final clean = v.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
                            if (clean.length >= 3) {
                              setState(() => _formatController.text = clean.substring(0, 3));
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      // Format / Prefix Field with Live Preview
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ModernTextField(
                              controller: _formatController,
                              label: 'Job Card & Courier Format Prefix *',
                              hint: 'e.g. TYX, TVR, KCH',
                              prefixIcon: const Icon(Icons.pin_outlined),
                              onChanged: (_) => setState(() {}),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Prefix format is required (e.g. TYX or TVR)' : null,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.info_outline, size: 14, color: Color(0xFF4F46E5)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Preview: ${_formatController.text.trim().toUpperCase().isEmpty ? "TYX" : _formatController.text.trim().toUpperCase()}${DateTime.now().year}001',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _numberController,
                              label: 'Branch Code',
                              hint: 'e.g. BR-01 or 10001',
                              prefixIcon: const Icon(Icons.tag),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _aliasController,
                              label: 'Alias',
                              hint: 'e.g. DTW or TVR',
                              prefixIcon: const Icon(Icons.short_text),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      ModernTextField(
                        controller: _guidController,
                        label: 'Branch GUID *',
                        hint: 'Unique GUID or UUID',
                        prefixIcon: const Icon(Icons.fingerprint),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'GUID is required' : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _gstController,
                              label: 'GST Number',
                              hint: '22AAAAA0000A1Z5',
                              prefixIcon: const Icon(Icons.receipt_long),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ModernTextField(
                              controller: _phoneController,
                              label: 'Phone Number',
                              hint: '10 digits phone',
                              prefixIcon: const Icon(Icons.phone),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      ModernTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'branch@tyrex.com',
                        prefixIcon: const Icon(Icons.email),
                      ),
                      const SizedBox(height: 14),

                      ModernTextField(
                        controller: _address1Controller,
                        label: 'Address',
                        hint: 'Street address',
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
                              hint: 'State',
                              prefixIcon: const Icon(Icons.map_outlined),
                            ),
                          ),
                        ],
                      ),
                      // Linked Tally Company Master (for Tally sync)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_rounded, size: 18, color: Color(0xFF0D9488)),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Linked Tally Company Master',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                                  ),
                                ),
                                if (_selectedTallyCompanyId != null)
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedTallyCompanyId = null),
                                    child: const Text('Unlink', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: _selectedTallyCompanyId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                hintText: _tallyMasters.isEmpty ? 'No Tally Companies created yet' : 'Select Tally Company Master for sync...',
                                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('None (Unallocated)', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ),
                                ..._tallyMasters.map((t) {
                                  final id = t['id']?.toString();
                                  final name = t['tally_company_name'] ?? 'Tally Company';
                                  final guid = t['tally_guid'] ?? '';
                                  return DropdownMenuItem<String?>(
                                    value: id,
                                    child: Text('$name ($guid)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (val) => setState(() => _selectedTallyCompanyId = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Active Switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active Branch', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        subtitle: const Text('Inactive branches cannot be assigned or create new job cards', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        value: _isActive,
                        activeColor: const Color(0xFF4F46E5),
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
                    onPressed: _isSubmitting ? null : _saveCompany,
                    icon: _isSubmitting 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(isEditing ? 'Save Changes' : 'Create Branch'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
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

