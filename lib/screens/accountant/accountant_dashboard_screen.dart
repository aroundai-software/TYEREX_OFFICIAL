// lib/screens/accountant/accountant_dashboard_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_constants.dart';
import '../../utils/date_utils.dart';
import '../../providers/user_provider.dart';
import '../../services/company_service.dart';
import '../login_screen.dart';
import 'invoice_detail_screen.dart';
import '../../widgets/company_switcher_badge.dart';

class AccountantDashboardScreen extends StatefulWidget {
  const AccountantDashboardScreen({super.key});

  @override
  State<AccountantDashboardScreen> createState() => _AccountantDashboardScreenState();
}

class _AccountantDashboardScreenState extends State<AccountantDashboardScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;

  List<Map<String, dynamic>> _allCompletedJobs = [];
  List<Map<String, dynamic>> _pendingBills = [];
  List<Map<String, dynamic>> _billed = [];
  bool _isLoading = true;
  DateTime? _selectedSingleDate;
  DateTimeRange? _selectedCustomRange;
  String _selectedFilter = 'Today';
  final List<String> _filterOptions = ['Today', 'This Week', 'This Month', 'Custom Range', 'All Time'];
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Metrics
  int _pendingCount = 0;
  int _billedCount = 0;
  double _totalBilledAmount = 0;

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

  bool _isJobBilled(Map<String, dynamic> job) {
    final isConv = job['is_converted'];
    if (isConv == true || isConv == 'true' || isConv == 1 || isConv == '1') return true;
    final bStatus = (job['billing_status'] ?? '').toString().toLowerCase();
    if (bStatus == 'billed' || bStatus == 'paid' || bStatus == 'completed') return true;
    return job['billed_at'] != null && job['billed_at'].toString().isNotEmpty;
  }

  List<Map<String, dynamic>> _filterJobs(List<Map<String, dynamic>> jobs) {
    if (_searchQuery.isEmpty) return jobs;
    final q = _searchQuery.toLowerCase();
    return jobs.where((job) {
      final String jobId = (job['job_card_id'] ?? '#${job['id']}').toString().toLowerCase();
      final String customerName = _getCustomerName(job).toLowerCase();
      final String vehicleNo = _getVehicleNo(job).toLowerCase();
      final String clientPhone = (job['bookings']?['customer_phone'] ?? job['client_phone'] ?? '').toString().toLowerCase();

      return jobId.contains(q) || customerName.contains(q) || vehicleNo.contains(q) || clientPhone.contains(q);
    }).toList();
  }

  DateTime? _getStartDate() {
    if (_selectedSingleDate != null) {
      final d = _selectedSingleDate!;
      return DateTime(d.year, d.month, d.day, 0, 0, 0);
    }
    if (_selectedCustomRange != null) {
      final d = _selectedCustomRange!.start;
      return DateTime(d.year, d.month, d.day, 0, 0, 0);
    }

    final now = DateTime.now();
    switch (_selectedFilter) {
      case 'Today':
        return DateTime(now.year, now.month, now.day, 0, 0, 0);
      case 'This Week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day, 0, 0, 0);
      case 'This Month':
        return DateTime(now.year, now.month, 1, 0, 0, 0);
      case 'All Time':
      default:
        return null;
    }
  }

  DateTime? _getEndDate() {
    if (_selectedSingleDate != null) {
      final d = _selectedSingleDate!;
      return DateTime(d.year, d.month, d.day, 23, 59, 59);
    }
    if (_selectedCustomRange != null) {
      final d = _selectedCustomRange!.end;
      return DateTime(d.year, d.month, d.day, 23, 59, 59);
    }
    final now = DateTime.now();
    switch (_selectedFilter) {
      case 'Today':
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'This Week':
        final sunday = now.add(Duration(days: 7 - now.weekday));
        return DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);
      case 'This Month':
        final lastDay = DateTime(now.year, now.month + 1, 0);
        return DateTime(now.year, now.month, lastDay.day, 23, 59, 59);
      case 'All Time':
      default:
        return null;
    }
  }

  Future<void> _pickSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedSingleDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedSingleDate = picked;
        _selectedCustomRange = null;
        _selectedFilter = DateFormat('dd MMM yyyy').format(picked);
      });
      _loadData();
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedCustomRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedCustomRange = picked;
        _selectedSingleDate = null;
        _selectedFilter = 'Custom Range';
      });
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final startDate = _getStartDate();
      final startDateIso = startDate?.toIso8601String();
      final endDate = _getEndDate();
      final endDateIso = endDate?.toIso8601String();
      final branchId = CompanyService().branchId;
      final branchName = CompanyService().branchName;

      // Fetch all completed job cards
      var query = supabase
          .from('reports')
          .select('''
            id, job_card_id, status, billing_status, is_converted, odometer_reading,
            complaint, suggested, labour_cost, created_at, completed_at, marks,
            billed_at, paid_at, payment_method,
            gst_percent, discount_amount, discount_type, extra_charge_amount, extra_charge_label,
            "Owner name", client_phone, branch_id, branch_name, company_name, "Guid",
            vehicles!reports_vehicle_fk("Vehicle Number", odometer, vehicle_models(brand, "Model name")),
            bookings(customer_name, customer_phone),
            executive:executive_id(username),
            payments(id, method, amount, transaction_id, voucher_type, alter_id, notes, tally_sync_status, paid_at)
          ''')
          .eq('status', AppConstants.statusCompleted);

      if (branchId != null && branchId.isNotEmpty) {
        query = query.or('branch_id.eq.$branchId,company_name.eq.$branchName');
      } else if (branchName != null && branchName.isNotEmpty) {
        query = query.eq('company_name', branchName);
      }

      if (startDateIso != null && endDateIso != null) {
        query = query.or('and(completed_at.gte.$startDateIso,completed_at.lte.$endDateIso),and(completed_at.is.null,created_at.gte.$startDateIso,created_at.lte.$endDateIso)');
      } else if (startDateIso != null) {
        query = query.or('completed_at.gte.$startDateIso,and(completed_at.is.null,created_at.gte.$startDateIso)');
      }

      final res = await query.order('id', ascending: false);

      if (!mounted) return;

      final allCompleted = List<Map<String, dynamic>>.from(res);
      final billedList = allCompleted.where(_isJobBilled).toList();
      final pendingList = allCompleted.where((j) => !_isJobBilled(j)).toList();

      double billedTotal = 0;
      for (final inv in billedList) {
        billedTotal += _calcTotal(inv);
      }

      setState(() {
        _allCompletedJobs = allCompleted;
        _billed = billedList;
        _pendingBills = pendingList;
        _pendingCount = pendingList.length;
        _billedCount = billedList.length;
        _totalBilledAmount = billedTotal;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  double _calcTotal(Map<String, dynamic> job) {
    double total = 0;
    try {
      final labour = (job['labour_cost'] ?? 0).toDouble();
      total += labour;

      final marksObj = job['marks'];
      bool isCourier = false;
      Map<String, dynamic>? marksMap;
      if (marksObj != null) {
        if (marksObj is String) {
          try {
            final decoded = jsonDecode(marksObj);
            if (decoded is Map<String, dynamic>) marksMap = decoded;
          } catch (_) {}
        } else if (marksObj is Map) {
          marksMap = Map<String, dynamic>.from(marksObj);
        }
        if (marksMap != null && marksMap['is_courier'] == true) {
          isCourier = true;
        }
      }

      // Decode complaint list
      dynamic rawComplaints = job['complaint'];
      List<dynamic> complaints = [];
      if (rawComplaints is List) {
        complaints = rawComplaints;
      } else if (rawComplaints is String && rawComplaints.trim().startsWith('[')) {
        try { complaints = jsonDecode(rawComplaints); } catch (_) {}
      }

      // Decode suggested list
      dynamic rawSuggested = job['suggested'];
      List<dynamic> suggested = [];
      if (rawSuggested is List) {
        suggested = rawSuggested;
      } else if (rawSuggested is String && rawSuggested.trim().startsWith('[')) {
        try { suggested = jsonDecode(rawSuggested); } catch (_) {}
      }

      if (isCourier) {
        double complaintTotal = 0;
        for (final c in complaints) {
          if (c is Map) complaintTotal += ((c['amount'] ?? 0) as num).toDouble();
        }

        if (complaintTotal > 0) {
          total += complaintTotal;
        } else {
          final products = marksMap?['products'] as List<dynamic>?;
          if (products != null) {
            for (final p in products) {
              if (p is Map) {
                final qty = (p['qty'] ?? 1) as num;
                final unitPrice = ((p['price'] ?? p['amount'] ?? 0) as num).toDouble();
                total += unitPrice * qty;
              }
            }
          }
        }
      } else {
        for (final c in complaints) {
          if (c is Map) total += ((c['amount'] ?? 0) as num).toDouble();
        }
        for (final s in suggested) {
          if (s is Map && s['type'] != AppConstants.typeComplaint) {
            total += ((s['amount'] ?? 0) as num).toDouble();
          }
        }
      }

      // Apply discount
      if (job['discount_amount'] != null) {
        final dVal = (job['discount_amount'] as num).toDouble();
        final dType = job['discount_type'] ?? 'flat';
        if (dType == 'percent') {
          total -= total * (dVal / 100);
        } else {
          total -= dVal;
        }
      }

      // Apply extra charges
      if (job['extra_charge_amount'] != null) {
        total += (job['extra_charge_amount'] as num).toDouble();
      }

      // Apply GST
      if (job['gst_percent'] != null) {
        final gst = (job['gst_percent'] as num).toDouble();
        total += total * (gst / 100);
      }

    } catch (_) {}
    return total;
  }

  String _getCustomerName(Map<String, dynamic> job) {
    return job['bookings']?['customer_name'] ??
           job['Owner name'] ?? 
           'Walk-in Customer';
  }

  String _getVehicleNo(Map<String, dynamic> job) {
    return job['vehicles']?['Vehicle Number'] ?? 'No Reg.';
  }

  String _getBrandModel(Map<String, dynamic> job) {
    final brand = job['vehicles']?['vehicle_models']?['brand'] ?? '';
    final model = job['vehicles']?['vehicle_models']?['Model name'] ?? '';
    return '$brand $model'.trim();
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

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final parsed = AppDateUtils.parseUtcToLocal(dateStr);
      return DateFormat('dd MMM yyyy, hh:mm a').format(parsed);
    } catch (_) {
      return 'Invalid Date';
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.cacheKeyCurrentUser);
    if (!mounted) return;
    Provider.of<UserProvider>(context, listen: false).setUser(null);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showCancelledJobs() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          bool isLoading = true;
          List<Map<String, dynamic>> cancelledJobs = [];
          final searchController = TextEditingController();
          bool isSearching = false;
          bool initialLoadDone = false;
          
          return StatefulBuilder(
            builder: (context, setStateLocal) {
              void fetchCancelled() async {
                if (!mounted) return;
                setStateLocal(() => isLoading = true);
                try {
                  final companyName = CompanyService().companyName;
                  var q = supabase
                      .from('reports')
                      .select('''
                        id, job_card_id, status, billing_status, odometer_reading,
                        complaint, suggested, labour_cost, created_at, completed_at, marks,
                        billed_at, paid_at, payment_method,
                        gst_percent, discount_amount, discount_type, extra_charge_amount, extra_charge_label,
                        "Owner name", client_phone,
                        vehicles!reports_vehicle_fk("Vehicle Number", odometer, vehicle_models(brand, "Model name")),
                        bookings(customer_name, customer_phone),
                        executive:executive_id(username),
                        payments(method, amount, transaction_id)
                      ''')
                      .eq('status', AppConstants.statusCancelled);
                  if (companyName != null && companyName.isNotEmpty) {
                    q = q.eq('company_name', companyName);
                  }
                  final res = await q.order('id', ascending: false);
                  if (mounted) {
                    setStateLocal(() {
                      cancelledJobs = List<Map<String, dynamic>>.from(res);
                      isLoading = false;
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    setStateLocal(() => isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              }

              if (!initialLoadDone) {
                initialLoadDone = true;
                fetchCancelled();
              }

              final searchQuery = searchController.text.toLowerCase();
              final filtered = cancelledJobs.where((job) {
                if (searchQuery.isEmpty) return true;
                final jobId = (job['job_card_id'] ?? '#${job['id']}').toString().toLowerCase();
                final customer = _getCustomerName(job).toLowerCase();
                final vehicle = _getVehicleNo(job).toLowerCase();
                return jobId.contains(searchQuery) || customer.contains(searchQuery) || vehicle.contains(searchQuery);
              }).toList();

              return Scaffold(
                backgroundColor: const Color(0xFFF8FAFC),
                appBar: AppBar(
                  title: isSearching
                      ? TextField(
                          controller: searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Search cancelled jobs...',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setStateLocal(() {}),
                        )
                      : const Text('Cancelled Jobcards', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.textPrimary,
                  elevation: 1,
                  actions: [
                    if (isSearching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setStateLocal(() {
                            isSearching = false;
                            searchController.clear();
                          });
                        },
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          setStateLocal(() {
                            isSearching = true;
                          });
                        },
                      ),
                  ],
                ),
                body: isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cancel_outlined, size: 64, color: AppTheme.textSecondary),
                                SizedBox(height: 16),
                                Text('No cancelled jobs found', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              return _buildJobCard(filtered[index]);
                            },
                          ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Accountant Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
        actions: [
          CompanySwitcherBadge(onCompanyChanged: _loadData),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) { 
              if (v == 'logout') {
                _logout(); 
              } else if (v == 'cancelled') {
                _showCancelledJobs();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'cancelled',
                child: Row(children: [Icon(Icons.cancel, size: 18, color: Colors.red), SizedBox(width: 8), Text('Cancelled Jobcards')]),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 8), Text('Logout')]),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildFilterStrip(),
                        _buildMetricsStrip(),
                      ],
                    ),
                  ),
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    automaticallyImplyLeading: false,
                    backgroundColor: const Color(0xFFF8FAFC),
                    surfaceTintColor: Colors.transparent,
                    elevation: 2,
                    shadowColor: Colors.black12,
                    toolbarHeight: 68,
                    titleSpacing: 0,
                    title: _buildSearchBar(),
                    bottom: TabBar(
                      controller: _tabController,
                      labelColor: AppTheme.primaryColor,
                      unselectedLabelColor: AppTheme.textSecondary,
                      indicatorColor: AppTheme.primaryColor,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      tabs: [
                        Tab(text: 'All (${_allCompletedJobs.length})'),
                        Tab(text: 'Pending ($_pendingCount)'),
                        Tab(text: 'Billed ($_billedCount)'),
                      ],
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildJobList(_allCompletedJobs, 'No completed jobs found.'),
                  _buildJobList(_pendingBills, 'No pending billing.'),
                  _buildJobList(_billed, 'No billed jobs found.'),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search by Name, Vehicle, Phone, or ID...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterStrip() {
    final hasSingleDate = _selectedSingleDate != null;
    final hasCustomRange = _selectedCustomRange != null;
    final activeDateLabel = hasSingleDate
        ? DateFormat('dd MMM yyyy').format(_selectedSingleDate!)
        : hasCustomRange
            ? '${DateFormat('dd MMM').format(_selectedCustomRange!.start)} - ${DateFormat('dd MMM').format(_selectedCustomRange!.end)}'
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Date Filter:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(
                  Icons.calendar_month_rounded,
                  color: (hasSingleDate || hasCustomRange) ? AppTheme.primaryColor : Colors.grey.shade700,
                  size: 22,
                ),
                tooltip: 'Filter by Single Date',
                onPressed: _pickSingleDate,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              if (activeDateLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        activeDateLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSingleDate = null;
                            _selectedCustomRange = null;
                            _selectedFilter = 'Today';
                          });
                          _loadData();
                        },
                        child: const Icon(Icons.close, size: 14, color: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          DropdownButton<String>(
            value: _filterOptions.contains(_selectedFilter) ? _selectedFilter : null,
            hint: _filterOptions.contains(_selectedFilter) ? null : Text(_selectedFilter, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            underline: const SizedBox(),
            icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.primaryColor),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
            items: _filterOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (v) async {
              if (v == 'Custom Range') {
                await _pickCustomRange();
              } else if (v != null) {
                setState(() {
                  _selectedSingleDate = null;
                  _selectedCustomRange = null;
                  _selectedFilter = v;
                });
                _loadData();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsStrip() {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _metricChip(Icons.task_alt, 'Total Completed', '${_allCompletedJobs.length} jobs', const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          _metricChip(Icons.pending_actions, 'Pending', '$_pendingCount jobs', Colors.orange),
          const SizedBox(width: 10),
          _metricChip(Icons.receipt_long, 'Billed Amount', currency.format(_totalBilledAmount), const Color(0xFF059669)),
        ],
      ),
    );
  }

  Widget _metricChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label, 
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobList(List<Map<String, dynamic>> rawList, String emptyMessage) {
    final filtered = _filterJobs(rawList);
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(emptyMessage, style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
        itemCount: filtered.length,
        itemBuilder: (context, i) => _buildJobCard(filtered[i]),
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final total = _calcTotal(job);
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final isBilled = _isJobBilled(job);

    // Border color driven by status
    final Color borderColor = isBilled
        ? const Color(0xFF10B981).withValues(alpha: 0.3)
        : Colors.orange.withValues(alpha: 0.25);

    // Amount color
    final Color amountColor = isBilled
        ? const Color(0xFF059669)
        : Colors.orange.shade800;

    final marksObj = job['marks'];
    bool isCourier = false;
    String? courierSubtitle;
    String? courierDetails;
    
    if (marksObj != null) {
      Map<String, dynamic>? marksMap;
      if (marksObj is String) {
        try {
          final decoded = jsonDecode(marksObj);
          if (decoded is Map<String, dynamic>) marksMap = decoded;
        } catch (_) {}
      } else if (marksObj is Map) {
        marksMap = Map<String, dynamic>.from(marksObj);
      }
      
      if (marksMap != null && marksMap['is_courier'] == true) {
        isCourier = true;
        
        final products = marksMap['products'] as List<dynamic>?;
        if (products != null && products.isNotEmpty) {
           courierSubtitle = products[0]['name']?.toString() ?? 'Courier Package';
           courierDetails = '${products.length} Product(s)';
        } else {
           courierSubtitle = 'Courier Package';
           courierDetails = 'No Products';
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvoiceDetailScreen(job: job, isPending: !isBilled),
            ),
          );
          _loadData();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Job info + Amount & Pills
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                job['job_card_id'] ?? '#${job['id']}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCourier) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: const Text(
                                  'Courier',
                                  style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (isCourier) ...[
                          Row(
                            children: [
                              const Icon(Icons.inventory_2, size: 14, color: AppTheme.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  courierSubtitle ?? 'Courier Package',
                                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Text(
                              courierDetails ?? 'Details',
                              style: TextStyle(fontSize: 12, color: Colors.purple.shade700, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ] else ...[
                          Text(
                            _getBrandModel(job),
                            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _getVehicleNo(job),
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                                ),
                              ),
                              if (_getOdometer(job).isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.blue.shade100),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.speed, size: 12, color: Colors.blue.shade700),
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
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currency.format(total),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: amountColor),
                      ),
                      const SizedBox(height: 6),
                      // Status pill
                      if (isBilled)
                        _pill('Billed', const Color(0xFF059669), Icons.receipt_long)
                      else
                        _pill('Pending Billing', Colors.orange.shade800, Icons.pending_actions),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 15, color: AppTheme.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(child: Text(_getCustomerName(job), style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary))),
                  const Icon(Icons.arrow_forward_ios, size: 13, color: AppTheme.textSecondary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    job['completed_at'] != null 
                        ? _formatDate(job['completed_at']) 
                        : (job['billed_at'] != null ? _formatDate(job['billed_at']) : _formatDate(job['created_at'])), 
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)
                  ),
                  const Spacer(),
                  const Icon(Icons.engineering, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 5),
                  Text(job['executive']?['username'] ?? 'Staff', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
