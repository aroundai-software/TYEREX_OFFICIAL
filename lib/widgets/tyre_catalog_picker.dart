import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Helper class for cleaning, parsing, and normalizing raw tyre catalog records
class TyreCatalogHelper {
  static const List<String> primaryBrands = [
    'Apollo',
    'Bridgestone',
    'Ceat',
    'Continental',
    'Goodyear',
    'JK Tyre',
    'Kumho',
    'Michelin',
    'MRF',
    'Pirelli',
    'Yokohama',
    'Dunlop',
    'Falken',
    'Hankook',
    'Maxxis',
    'TVS',
    'Zeta',
    'Neo Wheels',
  ];

  /// Extract the true brand from brand, model, and tally_name
  static String extractBrand(Map<String, dynamic> raw) {
    final rawBrand = (raw['brand'] ?? '').toString().trim();
    final model = (raw['model'] ?? '').toString().trim();
    final tallyName = (raw['tally_name'] ?? '').toString().trim();
    final combined = '$rawBrand $model $tallyName'.toLowerCase();

    // Check for standard brands
    if (combined.contains('continental') || combined.contains('conti ')) {
      return 'Continental';
    }
    if (combined.contains('bridgestone') || combined.contains('bridgstone') || combined.contains('b/s ')) {
      return 'Bridgestone';
    }
    if (combined.contains('ceat')) {
      return 'Ceat';
    }
    if (combined.contains('goodyear') || combined.contains('good year')) {
      return 'Goodyear';
    }
    if (combined.contains('apollo')) {
      return 'Apollo';
    }
    if (combined.contains('michelin')) {
      return 'Michelin';
    }
    if (combined.contains('yokohama')) {
      return 'Yokohama';
    }
    if (combined.contains('pirelli')) {
      return 'Pirelli';
    }
    if (combined.contains('mrf')) {
      return 'MRF';
    }
    if (combined.contains('jk tyre') || combined.contains(' jk ') || combined.endsWith(' jk')) {
      return 'JK Tyre';
    }
    if (combined.contains('kumho')) {
      return 'Kumho';
    }
    if (combined.contains('zeta')) {
      return 'Zeta';
    }
    if (combined.contains('maxxis')) {
      return 'Maxxis';
    }
    if (combined.contains('falken')) {
      return 'Falken';
    }
    if (combined.contains('dunlop')) {
      return 'Dunlop';
    }
    if (combined.contains('hankook')) {
      return 'Hankook';
    }
    if (combined.contains('tvs')) {
      return 'TVS';
    }
    if (combined.contains('neo')) {
      return 'Neo Wheels';
    }

    // If raw brand is NOT a size or category, return rawBrand with clean casing
    if (rawBrand.isNotEmpty &&
        !RegExp(r'^\d').hasMatch(rawBrand) &&
        !rawBrand.toUpperCase().startsWith('R') &&
        !rawBrand.toLowerCase().contains('accessories') &&
        !rawBrand.toLowerCase().contains('valve') &&
        !rawBrand.toLowerCase().contains('cleaner') &&
        !rawBrand.toLowerCase().contains('primary')) {
      return _capitalize(rawBrand);
    }

    return 'Other';
  }

  /// Extract standard Tyre Size from size, model, brand, or tally_name
  static String extractSize(Map<String, dynamic> raw) {
    final rawSize = (raw['size'] ?? '').toString().trim();
    if (rawSize.isNotEmpty && rawSize != '-' && !rawSize.startsWith('?')) {
      return _formatSize(rawSize);
    }

    final brand = (raw['brand'] ?? '').toString().trim();
    final model = (raw['model'] ?? '').toString().trim();
    final tallyName = (raw['tally_name'] ?? '').toString().trim();
    final text = '$brand $model $tallyName';

    // Regex matching standard size formats: e.g. 195/65R15, 140/60-17, 145/70 R12, 155 R13, 2.75-17
    final sizeRegex = RegExp(
      r'(\d{3}\s*/\s*\d{2}\s*[/]?\s*R?\s*\d{2}|\d{3}\s*/\s*\d{2}[-\s]\d{2}|\d{3}\s*R\s*\d{2}|\d{3}\s*D\s*\d{2}|\d\.\d{2}\s*R?\s*\d{2})',
      caseSensitive: false,
    );

    final match = sizeRegex.firstMatch(text);
    if (match != null) {
      return _formatSize(match.group(1)!);
    }

    return rawSize.isNotEmpty && rawSize != '-' ? rawSize : '';
  }

  /// Extract clean Model/Pattern name
  static String extractModel(Map<String, dynamic> raw) {
    final rawModel = (raw['model'] ?? '').toString().trim();
    final tallyName = (raw['tally_name'] ?? '').toString().trim();
    String model = rawModel.isNotEmpty ? rawModel : tallyName;

    // Remove leading size if model starts with size (e.g. "145/70/ R12 AMAZER" -> "AMAZER")
    final sizeRegex = RegExp(
      r'^\s*(\d{3}\s*/\s*\d{2}\s*[/]?\s*R?\s*\d{2}|\d{3}\s*/\s*\d{2}[-\s]\d{2}|\d{3}\s*R\s*\d{2}|\d{3}\s*D\s*\d{2})\s*',
      caseSensitive: false,
    );
    final sizeMatch = sizeRegex.firstMatch(model);
    if (sizeMatch != null) {
      final stripped = model.substring(sizeMatch.end).trim();
      if (stripped.isNotEmpty && stripped != '-') {
        model = stripped;
      }
    }

    return model;
  }

  /// Extract Rim Diameter (e.g. 17" or R17)
  static String? extractRimSize(String size) {
    final upper = size.toUpperCase();
    final rMatch = RegExp(r'R(\d{2})').firstMatch(upper);
    if (rMatch != null) {
      return '${rMatch.group(1)}"';
    }
    final numMatch = RegExp(r'[-/ ](\d{2})$').firstMatch(upper);
    if (numMatch != null) {
      return '${numMatch.group(1)}"';
    }
    return null;
  }

  static String _formatSize(String raw) {
    return raw
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('//', '/')
        .replaceAll('/R', 'R')
        .trim();
  }

  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

/// A modern, searchable tyre catalog picker modal and component
/// Allows searching and filtering tyres from the `tyre_catalog` table by
/// Brand, Model, Size, LI/SI, Tally Name, and Price.
class TyreCatalogPicker extends StatefulWidget {
  final List<Map<String, dynamic>> tyreCatalog;
  final Function(Map<String, dynamic> tyre) onTyreSelected;
  final Function(String brand, String model, String size, double? price)? onCustomTyre;
  final String? initialBrand;
  final String? initialSize;

  const TyreCatalogPicker({
    super.key,
    required this.tyreCatalog,
    required this.onTyreSelected,
    this.onCustomTyre,
    this.initialBrand,
    this.initialSize,
  });

  /// Helper static method to show the picker in a bottom sheet or dialog
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> tyreCatalog,
    Function(Map<String, dynamic> tyre)? onTyreSelected,
    Function(String brand, String model, String size, double? price)? onCustomTyre,
    String? initialBrand,
    String? initialSize,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TyreCatalogPicker(
        tyreCatalog: tyreCatalog,
        onTyreSelected: (selected) {
          if (onTyreSelected != null) {
            onTyreSelected(selected);
          }
          Navigator.of(ctx).pop(selected);
        },
        onCustomTyre: (brand, model, size, price) {
          if (onCustomTyre != null) {
            onCustomTyre(brand, model, size, price);
          }
          Navigator.of(ctx).pop({
            'brand': brand,
            'model': model,
            'size': size,
            'billing_price': price,
            'basic_price': price,
          });
        },
        initialBrand: initialBrand,
        initialSize: initialSize,
      ),
    );
  }

  @override
  State<TyreCatalogPicker> createState() => _TyreCatalogPickerState();
}

class _TyreCatalogPickerState extends State<TyreCatalogPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedBrand;
  String? _selectedRimSize;

  List<String> _availableBrands = [];
  List<String> _availableRimSizes = [];
  List<Map<String, dynamic>> _normalizedCatalog = [];
  List<Map<String, dynamic>> _filteredTyres = [];

  @override
  void initState() {
    super.initState();
    _selectedBrand = widget.initialBrand;
    _initCatalog();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _filterCatalog();
    });
  }

  String _normalizeString(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _initCatalog() {
    final brandsSet = <String>{};
    final rimSet = <String>{};
    final List<Map<String, dynamic>> normalized = [];

    for (final item in widget.tyreCatalog) {
      final cleanBrand = TyreCatalogHelper.extractBrand(item);
      final cleanSize = TyreCatalogHelper.extractSize(item);
      final cleanModel = TyreCatalogHelper.extractModel(item);

      if (cleanBrand.isNotEmpty && cleanBrand != 'Other') {
        brandsSet.add(cleanBrand);
      }

      if (cleanSize.isNotEmpty) {
        final rim = TyreCatalogHelper.extractRimSize(cleanSize);
        if (rim != null) {
          rimSet.add(rim);
        }
      }

      final billingPrice = item['billing_price'] != null
          ? double.tryParse(item['billing_price'].toString())
          : null;
      final basicPrice = item['basic_price'] != null
          ? double.tryParse(item['basic_price'].toString())
          : null;

      normalized.add({
        'id': item['id'],
        'brand': cleanBrand,
        'model': cleanModel,
        'size': cleanSize,
        'li_si': item['li_si'],
        'billing_price': billingPrice ?? basicPrice,
        'basic_price': basicPrice ?? billingPrice,
        'tally_name': item['tally_name'],
        'raw': item,
      });
    }

    // Sort brands with primary brands first
    final sortedBrands = brandsSet.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _availableBrands = sortedBrands;

    final sortedRims = rimSet.toList()..sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return numA.compareTo(numB);
    });
    _availableRimSizes = sortedRims;

    _normalizedCatalog = normalized;
    _filterCatalog();
  }

  void _filterCatalog() {
    final normalizedQuery = _normalizeString(_searchQuery);

    _filteredTyres = _normalizedCatalog.where((item) {
      final brand = (item['brand'] ?? '').toString().trim();
      final model = (item['model'] ?? '').toString().trim();
      final size = (item['size'] ?? '').toString().trim();
      final tallyName = (item['tally_name'] ?? '').toString().trim();
      final liSi = (item['li_si'] ?? '').toString().trim();

      // Brand filter
      if (_selectedBrand != null && _selectedBrand!.isNotEmpty) {
        if (brand.toLowerCase() != _selectedBrand!.toLowerCase()) {
          return false;
        }
      }

      // Rim size filter
      if (_selectedRimSize != null && _selectedRimSize!.isNotEmpty) {
        final itemRim = TyreCatalogHelper.extractRimSize(size);
        if (itemRim != _selectedRimSize) {
          return false;
        }
      }

      // Query filter
      if (normalizedQuery.isNotEmpty) {
        final normBrand = _normalizeString(brand);
        final normModel = _normalizeString(model);
        final normSize = _normalizeString(size);
        final normTally = _normalizeString(tallyName);
        final normLiSi = _normalizeString(liSi);

        final combined = '$normBrand $normSize $normModel $normTally $normLiSi';

        final words = _searchQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map(_normalizeString);
        for (final word in words) {
          if (!combined.contains(word)) {
            return false;
          }
        }
      }

      return true;
    }).toList();
  }

  void _showAddCustomDialog() {
    final brandCtrl = TextEditingController(text: _selectedBrand ?? '');
    final modelCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    if (_searchQuery.isNotEmpty) {
      final parts = _searchQuery.split(' ');
      if (parts.length >= 2) {
        sizeCtrl.text = parts.last.toUpperCase();
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('Add Custom Tyre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: brandCtrl,
                decoration: const InputDecoration(
                  labelText: 'Brand *',
                  hintText: 'e.g. Ceat, Continental',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Model / Pattern *',
                  hintText: 'e.g. Zoom Rad X3, CC6',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sizeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Size *',
                  hintText: 'e.g. 140/60R17, 195/65R15',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Billing Price (₹)',
                  hintText: 'e.g. 2159.68',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final b = brandCtrl.text.trim();
              final m = modelCtrl.text.trim();
              final s = sizeCtrl.text.trim();
              final p = double.tryParse(priceCtrl.text.trim());

              if (b.isEmpty || m.isEmpty || s.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill Brand, Model, and Size')),
                );
                return;
              }

              Navigator.of(ctx).pop();
              if (widget.onCustomTyre != null) {
                widget.onCustomTyre!(b, m, s, p);
              } else {
                widget.onTyreSelected({
                  'brand': b,
                  'model': m,
                  'size': s,
                  'billing_price': p,
                  'basic_price': p,
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Select & Use'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return Container(
      height: mediaQuery.size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tire_repair, color: AppTheme.primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Tyre from Catalog',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '${widget.tyreCatalog.length} tyres available in database',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search by Size (140/60, 195/65), Brand, Model...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor, size: 22),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),

          // Brand Filter Chips
          if (_availableBrands.isNotEmpty)
            Container(
              height: 38,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildFilterChip(
                    label: 'All Brands',
                    isSelected: _selectedBrand == null,
                    onTap: () {
                      setState(() {
                        _selectedBrand = null;
                        _filterCatalog();
                      });
                    },
                  ),
                  ..._availableBrands.map((brand) {
                    final isSelected = _selectedBrand?.toLowerCase() == brand.toLowerCase();
                    return _buildFilterChip(
                      label: brand,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedBrand = isSelected ? null : brand;
                          _filterCatalog();
                        });
                      },
                    );
                  }),
                ],
              ),
            ),

          // Rim Filter Chips
          if (_availableRimSizes.isNotEmpty)
            Container(
              height: 34,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildRimChip(
                    label: 'All Rims',
                    isSelected: _selectedRimSize == null,
                    onTap: () {
                      setState(() {
                        _selectedRimSize = null;
                        _filterCatalog();
                      });
                    },
                  ),
                  ..._availableRimSizes.map((rim) {
                    final isSelected = _selectedRimSize == rim;
                    return _buildRimChip(
                      label: rim,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedRimSize = isSelected ? null : rim;
                          _filterCatalog();
                        });
                      },
                    );
                  }),
                ],
              ),
            ),

          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_filteredTyres.length} tyres',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                InkWell(
                  onTap: _showAddCustomDialog,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 16, color: AppTheme.primaryColor),
                        SizedBox(width: 4),
                        Text(
                          'Custom Tyre',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // Tyres List
          Expanded(
            child: _filteredTyres.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, isKeyboardOpen ? 120 : 24),
                    itemCount: _filteredTyres.length,
                    itemBuilder: (context, index) {
                      final tyre = _filteredTyres[index];
                      return _buildTyreCard(tyre);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRimChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade300,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTyreCard(Map<String, dynamic> tyre) {
    final brand = (tyre['brand'] ?? 'Unknown').toString().trim();
    final model = (tyre['model'] ?? '').toString().trim();
    final size = (tyre['size'] ?? '').toString().trim();
    final liSi = (tyre['li_si'] ?? '').toString().trim();
    final tallyName = (tyre['tally_name'] ?? '').toString().trim();

    final billingPrice = tyre['billing_price'] != null
        ? double.tryParse(tyre['billing_price'].toString())
        : null;
    final basicPrice = tyre['basic_price'] != null
        ? double.tryParse(tyre['basic_price'].toString())
        : null;
    final displayPrice = billingPrice ?? basicPrice;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onTyreSelected(tyre),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getBrandColor(brand).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _getBrandColor(brand).withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        brand.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getBrandColor(brand),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Size Badge
                    if (size.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(
                          size,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),

                    if (liSi.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          liSi,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Price Badge
                    if (displayPrice != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          '₹${displayPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // Model name
                Text(
                  model.isNotEmpty ? model : '$brand $size',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),

                // Tally name subtitle
                if (tallyName.isNotEmpty && tallyName != model) ...[
                  const SizedBox(height: 3),
                  Text(
                    tallyName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tire_repair_outlined, size: 54, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No matching tyres found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No tyre found for "$_searchQuery".'
                  : 'Try changing your filter criteria.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showAddCustomDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add as Custom Tyre'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBrandColor(String brand) {
    final lower = brand.toLowerCase();
    if (lower.contains('ceat')) return const Color(0xFF0284C7);
    if (lower.contains('continental') || lower.contains('conti')) return const Color(0xFFEA580C);
    if (lower.contains('apollo')) return const Color(0xFF7C3AED);
    if (lower.contains('mrf')) return const Color(0xFFDC2626);
    if (lower.contains('bridgestone')) return const Color(0xFFB91C1C);
    if (lower.contains('michelin')) return const Color(0xFF1D4ED8);
    if (lower.contains('yokohama')) return const Color(0xFFBE123C);
    if (lower.contains('goodyear')) return const Color(0xFFD97706);
    if (lower.contains('jk')) return const Color(0xFF059669);
    if (lower.contains('pirelli')) return const Color(0xFF4338CA);
    return const Color(0xFF475569);
  }
}

/// Helper for cleaning, normalizing, and extracting alloy wheel catalog data
class AlloyCatalogHelper {
  static const List<String> primaryBrands = [
    'Momo',
    'Neo Wheels',
    'Plati',
    'Lenso',
    'Enkei',
    'HR',
    'OZ Racing',
    'BBS',
    'Sparco',
    'Fuel',
    'Black Rhino',
    'Yokohama',
    'Velocity',
    'Inforged',
    'SSW',
    'TSW',
    'Advanti',
    'Konig',
    'RM',
  ];

  static String extractSize(Map<String, dynamic> raw) {
    final rawSize = (raw['size'] ?? '').toString().trim();
    if (rawSize.isNotEmpty && rawSize != '-') {
      return rawSize.endsWith('"') ? rawSize : '$rawSize"';
    }
    final stockGroup = (raw['stock_group'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();

    final match = RegExp(r'(?:R|\b)(1[2-9]|2[0-4])\s*(?:\"|inch|in|-|\b)', caseSensitive: false)
        .firstMatch('$stockGroup $name');
    if (match != null) {
      return '${match.group(1)}"';
    }
    return '';
  }

  static String extractBrand(Map<String, dynamic> raw) {
    final rawBrand = (raw['brand'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    final combined = '$rawBrand $name'.toLowerCase();

    for (final b in primaryBrands) {
      if (combined.contains(b.toLowerCase())) {
        return b;
      }
    }
    if (rawBrand.isNotEmpty && rawBrand != '-' && !rawBrand.toLowerCase().contains('custom')) {
      return rawBrand;
    }
    if (name.toUpperCase().endsWith('-RM') || name.toUpperCase().contains(' RM')) {
      return 'RM';
    }
    return 'Alloy Wheels';
  }

  static String extractModel(Map<String, dynamic> raw) {
    final rawModel = (raw['model'] ?? '').toString().trim();
    if (rawModel.isNotEmpty && rawModel != '-') return rawModel;
    final name = (raw['name'] ?? '').toString().trim();
    return name;
  }

  static double? extractPrice(Map<String, dynamic> raw) {
    final val = raw['selling_price'] ??
        raw['billing_price'] ??
        raw['closing_rate'] ??
        raw['cost_price'] ??
        raw['basic_price'];
    if (val == null) return null;
    return double.tryParse(val.toString());
  }
}

/// Visual Alloy Catalog modal bottom sheet
class AlloyCatalogPicker extends StatefulWidget {
  final List<Map<String, dynamic>> alloyCatalog;
  final String? initialBrand;
  final String? initialSize;

  const AlloyCatalogPicker({
    super.key,
    required this.alloyCatalog,
    this.initialBrand,
    this.initialSize,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> alloyCatalog,
    String? initialBrand,
    String? initialSize,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AlloyCatalogPicker(
        alloyCatalog: alloyCatalog,
        initialBrand: initialBrand,
        initialSize: initialSize,
      ),
    );
  }

  @override
  State<AlloyCatalogPicker> createState() => _AlloyCatalogPickerState();
}

class _AlloyCatalogPickerState extends State<AlloyCatalogPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedBrand;
  String? _selectedSize;

  @override
  void initState() {
    super.initState();
    _selectedBrand = widget.initialBrand;
    _selectedSize = widget.initialSize;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredAlloys {
    return widget.alloyCatalog.where((item) {
      final brand = AlloyCatalogHelper.extractBrand(item);
      final size = AlloyCatalogHelper.extractSize(item);
      final model = AlloyCatalogHelper.extractModel(item);
      final name = (item['name'] ?? '').toString();
      final stockGroup = (item['stock_group'] ?? '').toString();

      if (_selectedBrand != null &&
          _selectedBrand!.isNotEmpty &&
          brand.toLowerCase() != _selectedBrand!.toLowerCase()) {
        return false;
      }
      if (_selectedSize != null &&
          _selectedSize!.isNotEmpty &&
          size.toLowerCase() != _selectedSize!.toLowerCase()) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final searchTarget = '$brand $size $model $name $stockGroup'.toLowerCase();
        final terms = q.split(' ').where((t) => t.isNotEmpty);
        for (final term in terms) {
          if (!searchTarget.contains(term)) return false;
        }
      }
      return true;
    }).toList();
  }

  List<String> get _availableBrands {
    final list = widget.alloyCatalog
        .map((t) => AlloyCatalogHelper.extractBrand(t))
        .where((b) => b.isNotEmpty && b != 'Alloy Wheels')
        .toSet()
        .toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> get _availableSizes {
    final list = widget.alloyCatalog
        .map((t) => AlloyCatalogHelper.extractSize(t))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    list.sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return numA.compareTo(numB);
    });
    return list;
  }

  Widget _buildSizeChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? Colors.black.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0D9488) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFCBD5E1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? const Color(0xFF0D9488).withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAlloys;
    final availableSizes = _availableSizes;
    final availableBrands = _availableBrands;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // Title Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.album_outlined, color: Color(0xFF0D9488), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Alloy Wheel Catalog',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      Text(
                        '${widget.alloyCatalog.length} wheels synced from Tally',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                if (_selectedBrand != null || _selectedSize != null || _searchQuery.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedBrand = null;
                        _selectedSize = null;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                    icon: const Icon(Icons.filter_alt_off, size: 15, color: Colors.red),
                    label: const Text('Reset', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'Search by wheel size, pattern, PCD (e.g. 17", 18", 5*114)...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF0D9488), size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                ),
              ),
            ),
          ),
          // Inches / Sizes Filter Chips Row
          if (availableSizes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Row(
                children: [
                  const Icon(Icons.straighten, size: 14, color: Color(0xFF475569)),
                  const SizedBox(width: 4),
                  const Text(
                    'RIM SIZE (INCHES)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 36,
              margin: const EdgeInsets.only(bottom: 4),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSizeChip(
                    label: 'All Sizes',
                    isSelected: _selectedSize == null,
                    onTap: () {
                      setState(() => _selectedSize = null);
                    },
                  ),
                  ...availableSizes.map((s) {
                    final isSelected = _selectedSize == s;
                    return _buildSizeChip(
                      label: s,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() => _selectedSize = isSelected ? null : s);
                      },
                    );
                  }),
                ],
              ),
            ),
          ],
          // Brands Filter Chips Row
          if (availableBrands.isNotEmpty)
            Container(
              height: 34,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildBrandChip(
                    label: 'All Brands',
                    isSelected: _selectedBrand == null,
                    onTap: () {
                      setState(() => _selectedBrand = null);
                    },
                  ),
                  ...availableBrands.map((b) {
                    final isSelected = _selectedBrand == b;
                    return _buildBrandChip(
                      label: b,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() => _selectedBrand = isSelected ? null : b);
                      },
                    );
                  }),
                ],
              ),
            ),
          // Result summary count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              'Showing ${filtered.length} wheels',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          const Divider(height: 8, color: Color(0xFFE2E8F0)),
          // Results List
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No matching alloy wheels found in catalog.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final brand = AlloyCatalogHelper.extractBrand(item);
                      final size = AlloyCatalogHelper.extractSize(item);
                      final model = AlloyCatalogHelper.extractModel(item);
                      final price = AlloyCatalogHelper.extractPrice(item);
                      final stockGroup = (item['stock_group'] ?? '').toString();

                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.05),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pop(context, {
                              'brand': brand,
                              'model': model,
                              'size': size,
                              'selling_price': price,
                              'billing_price': price,
                              'raw': item,
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                // High-Contrast Inch/Size Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 3,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    size.isNotEmpty ? size : 'Alloy',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        model,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      if (brand.isNotEmpty && brand != 'Alloy Wheels')
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            brand,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0D9488),
                                            ),
                                          ),
                                        )
                                      else if (stockGroup.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            stockGroup,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (price != null && price > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF86EFAC)),
                                    ),
                                    child: Text(
                                      '₹${price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  ),
                              ],
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
}
