// lib/screens/super_admin/branch_allocation_dialog.dart
import 'package:flutter/material.dart';
import '../../services/company_service.dart';

class BranchAllocationDialog extends StatefulWidget {
  final Map<String, dynamic> tallyCompany;
  final List<Map<String, dynamic>> allBranches;

  const BranchAllocationDialog({
    super.key,
    required this.tallyCompany,
    required this.allBranches,
  });

  @override
  State<BranchAllocationDialog> createState() => _BranchAllocationDialogState();
}

class _BranchAllocationDialogState extends State<BranchAllocationDialog> {
  final Set<String> _selectedBranchIds = {};
  String _searchQuery = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final targetTallyId = widget.tallyCompany['id']?.toString();
    for (final b in widget.allBranches) {
      if (b['tally_company_id']?.toString() == targetTallyId) {
        _selectedBranchIds.add(b['id'].toString());
      }
    }
  }

  Future<void> _saveAllocations() async {
    setState(() => _isSaving = true);
    try {
      final tallyId = widget.tallyCompany['id'].toString();
      await CompanyService().allocateBranchesToTallyCompany(
        tallyCompanyMasterId: tallyId,
        branchIds: _selectedBranchIds.toList(),
        tallyCompanyData: widget.tallyCompany,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update branch allocations: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyName = widget.tallyCompany['tally_company_name'] ?? 'Tally Company';
    final guid = widget.tallyCompany['tally_guid'] ?? '-';
    final alias = widget.tallyCompany['company_alias'];

    final filteredBranches = widget.allBranches.where((b) {
      final name = (b['branch_name'] ?? b['company_name'] ?? '').toString().toLowerCase();
      final code = (b['branch_code'] ?? b['format'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 700),
        child: Column(
          children: [
            // Top Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF0284C7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.account_tree_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Allocate Branches to Tally',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Sync source branches to this Tally company master',
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
                  const SizedBox(height: 14),

                  // Tally Company Badge Info Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.business_center_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                companyName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'GUID: $guid${alias != null && alias.isNotEmpty ? " • Alias: $alias" : ""}',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_selectedBranchIds.length} Allocated',
                            style: const TextStyle(
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar & Bulk Selection Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search branches by name or code...',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filteredBranches.length} branch(es) found',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                for (final b in filteredBranches) {
                                  _selectedBranchIds.add(b['id'].toString());
                                }
                              });
                            },
                            child: const Text('Select All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                for (final b in filteredBranches) {
                                  _selectedBranchIds.remove(b['id'].toString());
                                }
                              });
                            },
                            child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Branch List with Status Indicators
            Expanded(
              child: filteredBranches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.domain_disabled_rounded, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            _searchQuery.isEmpty ? 'No branches found in database' : 'No branches match "$_searchQuery"',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filteredBranches.length,
                      itemBuilder: (context, index) {
                        final b = filteredBranches[index];
                        final bId = b['id'].toString();
                        final bName = b['branch_name'] ?? b['company_name'] ?? 'Branch';
                        final format = b['format'] ?? b['jobcard_prefix'] ?? b['branch_code'] ?? 'TYX';
                        final isSelected = _selectedBranchIds.contains(bId);

                        final otherTallyId = b['tally_company_id']?.toString();
                        final targetTallyId = widget.tallyCompany['id']?.toString();
                        final isLinkedToOther = otherTallyId != null && 
                            otherTallyId.isNotEmpty && 
                            otherTallyId != targetTallyId;
                        final otherTallyName = b['tally_company'] ?? 'Another Tally Master';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? const Color(0xFF0D9488).withValues(alpha: 0.06)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected 
                                  ? const Color(0xFF0D9488).withValues(alpha: 0.5)
                                  : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            value: isSelected,
                            activeColor: const Color(0xFF0D9488),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    bName,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 14,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    format,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0D9488),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                if (isLinkedToOther)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber.shade300),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded, size: 12, color: Colors.amber.shade800),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Will reassign from: $otherTallyName',
                                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (otherTallyId == targetTallyId)
                                  const Text(
                                    '✅ Currently synced to this Tally company',
                                    style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                                  )
                                else
                                  Text(
                                    'Unallocated (No Tally master assigned)',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedBranchIds.add(bId);
                                } else {
                                  _selectedBranchIds.remove(bId);
                                }
                              });
                            },
                          ),
                        );
                      },
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
                  Text(
                    '${_selectedBranchIds.length} branch(es) selected',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAllocations,
                    icon: _isSaving 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(_isSaving ? 'Saving...' : 'Save Allocation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
