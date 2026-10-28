// lib/widgets/company_switcher_badge.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/company_service.dart';
import '../providers/report_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_constants.dart';

class CompanySwitcherBadge extends StatefulWidget {
  final bool isDark;
  final VoidCallback? onCompanyChanged;

  const CompanySwitcherBadge({
    super.key,
    this.isDark = false,
    this.onCompanyChanged,
  });

  @override
  State<CompanySwitcherBadge> createState() => _CompanySwitcherBadgeState();
}

class _CompanySwitcherBadgeState extends State<CompanySwitcherBadge> {
  void _openCompanyPicker() {
    final companyService = CompanyService();
    final allocated = companyService.allocatedCompanies;
    final current = companyService.activeCompany;

    if (allocated.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Active Branch: ${companyService.companyName ?? "Default"} (Single branch allocated)'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.business_rounded, color: Color(0xFF4F46E5), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Switch Branch',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Select which branch context to view and work on',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: allocated.length,
                    itemBuilder: (context, index) {
                      final comp = allocated[index];
                      final isSelected = current != null &&
                          comp['id'].toString() == current['id'].toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4F46E5).withValues(alpha: 0.08)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF4F46E5)
                                : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? const Color(0xFF4F46E5)
                                : Colors.grey.shade300,
                            foregroundColor: isSelected ? Colors.white : Colors.grey.shade700,
                            child: const Icon(Icons.apartment, size: 20),
                          ),
                          title: Text(
                            comp['branch_name'] ?? comp['company_name'] ?? 'Unknown',
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? const Color(0xFF4F46E5) : AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Prefix: ${comp['format'] ?? comp['jobcard_prefix'] ?? comp['branch_code'] ?? "TYX"} • ${comp['city'] ?? "Branch"}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: Color(0xFF4F46E5))
                              : null,
                          onTap: () async {
                            Navigator.pop(ctx);
                            companyService.setActiveCompany(comp);
                            
                            // Refresh reports for user with new company context
                            final user = Provider.of<UserProvider>(context, listen: false).user;
                            final reportProvider = Provider.of<ReportProvider>(context, listen: false);
                            reportProvider.clearCache();
                            if (user != null) {
                              await reportProvider.refresh(user['id'] as int, isAdminMode: user['role'] == AppConstants.roleAdmin);
                            }

                            if (mounted) {
                              setState(() {});
                            }
                            widget.onCompanyChanged?.call();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyService = CompanyService();
    final companyName = companyService.companyName ?? 'Branch';
    final format = companyService.branchFormat;
    final hasMultiple = companyService.hasMultipleCompanies;

    final bgColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.15)
        : const Color(0xFF4F46E5).withValues(alpha: 0.08);

    final textColor = widget.isDark ? Colors.white : const Color(0xFF4F46E5);
    final borderColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.25)
        : const Color(0xFF4F46E5).withValues(alpha: 0.25);

    return InkWell(
      onTap: hasMultiple ? _openCompanyPicker : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                format,
                style: TextStyle(
                  color: textColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 75),
              child: Text(
                companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (hasMultiple) ...[
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: textColor),
            ],
          ],
        ),
      ),
    );
  }
}
