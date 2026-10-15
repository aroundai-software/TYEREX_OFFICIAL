// lib/screens/warranty/warranty_dashboard_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_constants.dart';
import '../../utils/date_utils.dart';
import '../../services/company_service.dart';
import '../login_screen.dart';
import 'warranty_details_screen.dart';
import '../../widgets/brand_model_search_dropdown.dart';
import '../../widgets/company_switcher_badge.dart';

class WarrantyDashboardScreen extends StatefulWidget {
  const WarrantyDashboardScreen({super.key});

  @override
  State<WarrantyDashboardScreen> createState() => _WarrantyDashboardScreenState();
}

class _WarrantyDashboardScreenState extends State<WarrantyDashboardScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;

  List<Map<String, dynamic>> _liveJobs = [];
  List<Map<String, dynamic>> _completedJobs = [];
  List<Map<String, dynamic>> _cancelledJobs = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime? _selectedDate;
  String? _selectedBrand;
  String? _selectedModel;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _getOdometer(Map<String, dynamic> job) {
    final odo = job['odometer_reading'] ?? 
                job['vehicles']?['odometer'] ?? 
                job['vehicles']?['km_driven'];
    if (odo == null || odo.toString().trim().isEmpty || odo == 0 || odo == '0') return '';
    final odoStr = odo.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (odoStr.isEmpty) return '$odo';
    try {
      final numVal = int.parse(odoStr);
      return '${NumberFormat('#,##,###').format(numVal)} KM';
    } catch (_) {
      return '$odo KM';
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final branchId = CompanyService().branchId;
      final branchName = CompanyService().branchName;

      var query = supabase.from('reports').select('''
        id, job_card_id, created_at, status, vehicle_id, barcode, photo_urls, company_name, branch_id, branch_name, "Owner name", client_phone, marks, odometer_reading,
        executive:executive_id(username),
        vehicles!reports_vehicle_fk("Guid", "Vehicle Number", odometer, vehicle_models(brand, "Model name"))
      ''');

      if (branchId != null && branchId.isNotEmpty) {
        query = query.or('branch_id.eq.$branchId,company_name.eq.$branchName');
      } else if (branchName != null && branchName.isNotEmpty) {
        query = query.eq('company_name', branchName);
      }

      final response = await query.order('created_at', ascending: false);
      
      final List<Map<String, dynamic>> allJobs = List<Map<String, dynamic>>.from(response);

      _liveJobs.clear();
      _completedJobs.clear();
      _cancelledJobs.clear();

      for (var job in allJobs) {
        final status = job['status'] as String?;
        if (status == AppConstants.statusDraft) continue;
        if (!_hasQrCaptured(job)) continue;

        if (status == AppConstants.statusCompleted) {
          _completedJobs.add(job);
        } else if (status == AppConstants.statusCancelled) {
          _cancelledJobs.add(job);
        } else {
          _liveJobs.add(job);
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading warranty data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load job cards: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.cacheKeyCurrentUser);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  List<Map<String, dynamic>> _filterJobs(List<Map<String, dynamic>> jobs) {
    return jobs.where((job) {
      // 1. Search Query
      if (_searchQuery.isNotEmpty) {
        final vehicleId = job['vehicle_id']?.toString().toLowerCase() ?? '';
        final vehicleNo = job['vehicles']?['Vehicle Number']?.toString().toLowerCase() ?? '';
        final brand = job['vehicles']?['vehicle_models']?['brand']?.toString().toLowerCase() ?? '';
        final model = job['vehicles']?['vehicle_models']?['Model name']?.toString().toLowerCase() ?? '';
        final id = job['id']?.toString().toLowerCase() ?? '';
        final q = _searchQuery.toLowerCase();
        
        final matchesQuery = vehicleId.contains(q) || vehicleNo.contains(q) || brand.contains(q) || model.contains(q) || id.contains(q);
        if (!matchesQuery) return false;
      }

      // 2. Date Filter
      if (_selectedDate != null) {
        final jobDateStr = job['created_at'] as String?;
        if (jobDateStr == null) return false;
        final jobDate = DateTime.tryParse(jobDateStr)?.toLocal();
        if (jobDate == null) return false;
        if (jobDate.year != _selectedDate!.year || jobDate.month != _selectedDate!.month || jobDate.day != _selectedDate!.day) {
          return false;
        }
      }

      // 3. Brand Filter
      if (_selectedBrand != null) {
        final brand = job['vehicles']?['vehicle_models']?['brand']?.toString();
        if (brand != _selectedBrand) return false;
      }

      // 4. Model Filter
      if (_selectedModel != null) {
        final model = job['vehicles']?['vehicle_models']?['Model name']?.toString();
        if (model != _selectedModel) return false;
      }

      return true;
    }).toList();
  }

  bool _hasQrCaptured(Map<String, dynamic> job) {
    final rawUrls = job['photo_urls'];
    List<String> photoUrls = [];
    if (rawUrls is String) {
      try { photoUrls = List<String>.from(jsonDecode(rawUrls)); } catch (_) {}
    } else if (rawUrls is List) {
      photoUrls = List<String>.from(rawUrls.map((e) => e.toString()));
    }
    final capturedQrImages = photoUrls.where((url) => url.contains('_tyreqr_') || url.contains('_barcode_')).toList();
    return ((job['barcode'] as String?)?.isNotEmpty == true && job['barcode'] != '{}') || capturedQrImages.isNotEmpty;
  }

  Future<void> _showJobDetails(Map<String, dynamic> job) async {
    final barcodeRaw = job['barcode'];
    Map<String, dynamic> barcodeData = {};
    if (barcodeRaw is String) {
      try { barcodeData = jsonDecode(barcodeRaw); } catch (_) {}
    } else if (barcodeRaw is Map) {
      barcodeData = Map<String, dynamic>.from(barcodeRaw);
    }

    final rawUrls = job['photo_urls'];
    List<String> capturedQrImages = [];
    if (rawUrls is String) {
      try { capturedQrImages = List<String>.from(jsonDecode(rawUrls)); } catch (_) {}
    } else if (rawUrls is List) {
      capturedQrImages = List<String>.from(rawUrls.map((e) => e.toString()));
    }
    
    // Only keep images that are explicitly QR codes or barcodes
    capturedQrImages = capturedQrImages.where((url) => url.contains('_tyreqr_') || url.contains('_barcode_')).toList();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WarrantyDetailsScreen(
          job: job,
          barcodeData: barcodeData,
          capturedQrImages: capturedQrImages,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _markAsCompleted(Map<String, dynamic> job) async {
    final currentMarks = job['marks'];
    Map<String, dynamic> marksData = {};
    if (currentMarks is String) {
      try { marksData = jsonDecode(currentMarks); } catch (_) {}
    } else if (currentMarks is Map) {
      marksData = Map<String, dynamic>.from(currentMarks);
    }
    
    // Optimistic UI update
    setState(() {
      marksData['is_warranty_registered'] = true;
      job['marks'] = marksData;
    });

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('reports').update({
        'marks': marksData,
      }).eq('id', job['id']);
    } catch (e) {
      if (mounted) {
        setState(() {
          marksData['is_warranty_registered'] = false;
          job['marks'] = marksData;
        });
      }
    }
  }

  Widget _buildJobList(List<Map<String, dynamic>> jobs) {
    final filtered = _filterJobs(jobs);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filtered.isEmpty) {
      return const Center(child: Text('No job cards found.', style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final job = filtered[index];
          final dateStr = job['created_at'] != null 
              ? DateFormat('dd MMM yyyy, hh:mm a').format(AppDateUtils.parseUtcToLocal(job['created_at']))
              : 'Unknown Date';
          
          final execName = job['executive'] != null ? job['executive']['username'] : 'Unassigned';
          
          final rawUrls = job['photo_urls'];
          List<String> photoUrls = [];
          if (rawUrls is String) {
            try { photoUrls = List<String>.from(jsonDecode(rawUrls)); } catch (_) {}
          } else if (rawUrls is List) {
            photoUrls = List<String>.from(rawUrls.map((e) => e.toString()));
          }
          final capturedQrImages = photoUrls.where((url) => url.contains('_tyreqr_') || url.contains('_barcode_')).toList();
          
          final hasBarcode = ((job['barcode'] as String?)?.isNotEmpty == true && job['barcode'] != '{}') || capturedQrImages.isNotEmpty;
          
          final jobIdStr = job['job_card_id']?.toString() ?? 'Job #${job['id']}';
          final brand = job['vehicles']?['vehicle_models']?['brand'] ?? 'Unknown';
          final model = job['vehicles']?['vehicle_models']?['Model name'] ?? 'Unknown';
          final vehicleNo = job['vehicles']?['Vehicle Number']?.toString() ?? job['vehicle_id']?.toString() ?? 'Unknown No.';
          
          final clientName = job['Owner name']?.toString() ?? 'Unknown Client';
          final clientPhone = job['client_phone']?.toString() ?? 'Unknown Phone';
          
          final currentMarks = job['marks'];
          Map<String, dynamic> marksData = {};
          if (currentMarks is String) {
            try { marksData = jsonDecode(currentMarks); } catch (_) {}
          } else if (currentMarks is Map) {
            marksData = Map<String, dynamic>.from(currentMarks);
          }
          final bool isWarrantyRegistered = marksData['is_warranty_registered'] == true;

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            color: isWarrantyRegistered ? const Color(0xFFF0FDF4) : Colors.white, // Light green for warranty registered
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isWarrantyRegistered ? const BorderSide(color: Colors.green, width: 2) : BorderSide.none,
            ),
            child: InkWell(
              onTap: () => _showJobDetails(job),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '$jobIdStr - $vehicleNo',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$brand $model',
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                        if (_getOdometer(job).isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.speed, size: 11, color: Colors.blue.shade700),
                                const SizedBox(width: 3),
                                Text(
                                  _getOdometer(job),
                                  style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.account_circle, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$clientName • $clientPhone',
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(child: Text('Executive: $execName', style: const TextStyle(color: Colors.grey), overflow: TextOverflow.ellipsis)),
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(dateStr, style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              hasBarcode ? Icons.qr_code_2 : Icons.qr_code_2_outlined,
                              color: hasBarcode ? Colors.green : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasBarcode ? 'QRs Available' : 'No QRs scanned',
                              style: TextStyle(
                                color: hasBarcode ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (!isWarrantyRegistered)
                          TextButton.icon(
                            onPressed: () => _markAsCompleted(job),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.green.withOpacity(0.1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                            label: const Text('Complete', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                        if (isWarrantyRegistered)
                           const Padding(
                             padding: EdgeInsets.only(right: 8.0),
                             child: Row(
                               children: [
                                 Icon(Icons.verified, color: Colors.green, size: 18),
                                 SizedBox(width: 4),
                                 Text('Completed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                               ],
                             ),
                           ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warranty Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          CompanySwitcherBadge(onCompanyChanged: _loadData),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by Vehicle No, Brand, Model, Job ID...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
                      color: _showFilters || _selectedDate != null || _selectedBrand != null ? AppTheme.primaryColor : Colors.grey,
                      onPressed: () => setState(() => _showFilters = !_showFilters),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppTheme.primaryColor,
                tabs: const [
                  Tab(text: 'Live'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Cancelled'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_showFilters)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setState(() => _selectedDate = date);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(_selectedDate != null 
                              ? DateFormat('dd MMM yyyy').format(_selectedDate!) 
                              : 'Select Date'),
                        ),
                      ),
                      if (_selectedDate != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.red),
                          onPressed: () => setState(() => _selectedDate = null),
                          tooltip: 'Clear Date',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  BrandModelSearchDropdown(
                    initialBrand: _selectedBrand,
                    initialModelName: _selectedModel,
                    onSelectionChanged: (brand, modelId, modelName) {
                      setState(() {
                        _selectedBrand = brand;
                        _selectedModel = modelName;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildJobList(_liveJobs),
                _buildJobList(_completedJobs),
                _buildJobList(_cancelledJobs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
