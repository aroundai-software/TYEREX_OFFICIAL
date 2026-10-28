import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ServiceCatalogPicker extends StatefulWidget {
  final List<Map<String, dynamic>> serviceCatalog;
  final Function(String serviceName, double? defaultPrice) onServiceSelected;

  const ServiceCatalogPicker({
    super.key,
    required this.serviceCatalog,
    required this.onServiceSelected,
  });

  @override
  State<ServiceCatalogPicker> createState() => _ServiceCatalogPickerState();
}

class _ServiceCatalogPickerState extends State<ServiceCatalogPicker> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allServices = [];
  List<Map<String, dynamic>> _filteredServices = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initServices();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
        _filterServices();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initServices() {
    _allServices = widget.serviceCatalog.where((service) {
      final category = (service['category'] ?? '').toString().toLowerCase();
      // Hide Sales Accounts
      if (category == 'sales accounts' || category.contains('sales account')) {
        return false;
      }
      return true;
    }).toList();
    _filteredServices = List.from(_allServices);
  }

  void _filterServices() {
    if (_searchQuery.isEmpty) {
      _filteredServices = List.from(_allServices);
      return;
    }
    _filteredServices = _allServices.where((service) {
      final name = (service['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle pill
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select Service',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search services...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Color(0xFF9CA3AF)),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Expanded(
            child: _filteredServices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        const Text(
                          'No matching services found',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filteredServices.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 68,
                      endIndent: 16,
                      color: Color(0xFFF3F4F6),
                    ),
                    itemBuilder: (context, index) {
                      final service = _filteredServices[index];
                      final name = (service['name'] ?? '').toString();
                      final price = service['default_price'] != null
                          ? double.tryParse(service['default_price'].toString())
                          : null;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.handyman_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        trailing: price != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  '₹${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)}',
                                  style: const TextStyle(
                                    color: Color(0xFF059669),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF9CA3AF),
                                size: 22,
                              ),
                        onTap: () {
                          widget.onServiceSelected(name, price);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
