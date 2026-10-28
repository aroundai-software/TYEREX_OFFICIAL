// lib/screens/admin/reports_analytics_screen.dart
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import 'package:printing/printing.dart';

import '../../utils/app_constants.dart';
import '../../utils/haptic_utils.dart';
import '../../services/company_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/modern_loading.dart';
import '../../widgets/printable_job_card.dart';

/// Models for Structured Analytics
class BranchMetric {
  final dynamic branchId;
  final String branchName;
  final String branchFormat;
  final String? city;
  final int totalJobs;
  final int completedJobs;
  final int liveJobs;
  final int cancelledJobs;
  final double revenue;
  final double avgTicket;
  final int repeatCustomerCount;
  final double revenueSharePercent;
  final double jobsSharePercent;

  const BranchMetric({
    required this.branchId,
    required this.branchName,
    required this.branchFormat,
    this.city,
    required this.totalJobs,
    required this.completedJobs,
    required this.liveJobs,
    required this.cancelledJobs,
    required this.revenue,
    required this.avgTicket,
    required this.repeatCustomerCount,
    required this.revenueSharePercent,
    required this.jobsSharePercent,
  });
}

class CustomerMetric {
  final String customerKey;
  final String name;
  final String phone;
  final List<String> vehicles;
  final List<String> carBrandsModels;
  final List<Map<String, dynamic>> jobcards;
  final int visitCount;
  final bool isRepeat;
  final double totalSpend;
  final DateTime? firstVisit;
  final DateTime? lastVisit;
  final String primaryBranch;

  const CustomerMetric({
    required this.customerKey,
    required this.name,
    required this.phone,
    required this.vehicles,
    required this.carBrandsModels,
    required this.jobcards,
    required this.visitCount,
    required this.isRepeat,
    required this.totalSpend,
    this.firstVisit,
    this.lastVisit,
    required this.primaryBranch,
  });
}

class BrandMetric {
  final String brand;
  final int totalJobs;
  final int uniqueVehicles;
  final int repeatJobs;
  final int repeatVehiclesCount;
  final double repeatRatePercent;
  final double totalRevenue;
  final double brandSharePercent;
  final List<ModelMetric> models;

  const BrandMetric({
    required this.brand,
    required this.totalJobs,
    required this.uniqueVehicles,
    required this.repeatJobs,
    required this.repeatVehiclesCount,
    required this.repeatRatePercent,
    required this.totalRevenue,
    required this.brandSharePercent,
    required this.models,
  });
}

class ModelMetric {
  final String modelName;
  final String brand;
  final int totalJobs;
  final int uniqueVehicles;
  final int repeatJobs;
  final double repeatRatePercent;
  final double totalRevenue;

  const ModelMetric({
    required this.modelName,
    required this.brand,
    required this.totalJobs,
    required this.uniqueVehicles,
    required this.repeatJobs,
    required this.repeatRatePercent,
    required this.totalRevenue,
  });
}

class RepeatVehicleMetric {
  final String vehicleNumber;
  final String brand;
  final String model;
  final String ownerName;
  final String phone;
  final int visitCount;
  final double totalSpend;
  final DateTime? lastVisit;
  final String primaryBranch;

  const RepeatVehicleMetric({
    required this.vehicleNumber,
    required this.brand,
    required this.model,
    required this.ownerName,
    required this.phone,
    required this.visitCount,
    required this.totalSpend,
    this.lastVisit,
    required this.primaryBranch,
  });
}

class JobWorkItem {
  final String title;
  final double amount;
  final int qty;
  final double? unitPrice;
  final String category; // 'tyre', 'service', 'part', 'buyback'

  const JobWorkItem({
    required this.title,
    required this.amount,
    required this.qty,
    this.unitPrice,
    required this.category,
  });
}

class StockItemMetric {
  final String title;
  final String category; // 'tyre', 'valve', 'service', 'part'
  final int totalQty;
  final double totalRevenue;
  final int jobCount;
  final double avgUnitPrice;
  final double revenueSharePercent;

  const StockItemMetric({
    required this.title,
    required this.category,
    required this.totalQty,
    required this.totalRevenue,
    required this.jobCount,
    required this.avgUnitPrice,
    required this.revenueSharePercent,
  });
}

class _StockAccumulator {
  final String title;
  final String category;
  int totalQty = 0;
  double totalRevenue = 0.0;
  int jobCount = 0;

  _StockAccumulator({required this.title, required this.category});
}

class ReportsAnalyticsScreen extends StatefulWidget {
  final String? initialBranchId;
  const ReportsAnalyticsScreen({super.key, this.initialBranchId});

  @override
  State<ReportsAnalyticsScreen> createState() => _ReportsAnalyticsScreenState();
}

class _ReportsAnalyticsScreenState extends State<ReportsAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;
  bool _isLoading = true;

  // Filter state
  String _selectedTimeFilter = 'This Month';
  final List<String> _timeFilterOptions = [
    'Today',
    'Yesterday',
    'This Week',
    'This Month',
    'Last Month',
    'This Year',
    'Custom Range',
    'All Time',
  ];

  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _selectedBranchId = 'all'; // 'all' or specific branch id
  List<Map<String, dynamic>> _allocatedBranches = [];

  // Raw and processed data
  List<Map<String, dynamic>> _allFetchedReports = [];
  List<Map<String, dynamic>> _filteredReports = [];

  // Summary KPIs
  int _totalJobcards = 0;
  int _completedJobcards = 0;
  int _liveJobcards = 0;
  int _draftJobcards = 0;
  int _cancelledJobcards = 0;
  double _completionRate = 0.0;

  double _totalRevenue = 0.0;
  double _avgJobcardValue = 0.0;

  Map<String, double> _paymentMethodDistribution = {};

  // Branch-wise Analytics
  List<BranchMetric> _branchMetrics = [];

  // Customer Loyalty & Retention Analytics
  int _totalUniqueCustomers = 0;
  int _repeatCustomerCount = 0;
  double _repeatCustomerRate = 0.0;
  List<CustomerMetric> _allCustomersList = [];
  List<CustomerMetric> _repeatCustomersList = [];
  String _customerViewMode = 'repeat'; // 'repeat' or 'all'

  // Frequency buckets
  int _freq2Visits = 0;
  int _freq3to5Visits = 0;
  int _freq6PlusVisits = 0;

  // Car Brands & Models Analytics
  List<BrandMetric> _brandMetrics = [];
  List<ModelMetric> _allModelMetrics = [];
  List<RepeatVehicleMetric> _repeatVehiclesList = [];
  String _brandViewMode = 'brands'; // 'brands', 'models', 'repeating_cars'
  String _brandSearchQuery = '';

  // Stock & Top Selling Items Analytics
  List<StockItemMetric> _allStockItems = [];
  int _totalTyresSoldQty = 0;
  int _totalValvesSoldQty = 0;
  int _totalServicesRenderedQty = 0;
  int _totalPartsSoldQty = 0;
  int _totalStockUnitsSold = 0;
  double _totalStockRevenue = 0.0;
  String _stockCategoryFilter = 'all'; // 'all', 'tyre', 'valve', 'service', 'part'
  String _stockSortBy = 'qty'; // 'qty', 'revenue', 'jobs'
  final TextEditingController _stockSearchController = TextEditingController();
  String _stockSearchQuery = '';
  int _stockDisplayLimit = 30;

  // Search & sorting
  final TextEditingController _recordsSearchController = TextEditingController();
  final TextEditingController _customerSearchController = TextEditingController();
  final TextEditingController _brandSearchController = TextEditingController();
  String _recordsSearchQuery = '';
  String _customerSearchQuery = '';
  String _recordsStatusFilter = 'all';

  // Records table pagination
  int _currentPage = 1;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    // 6 Tabs: Overview, Stock & Items, Car Brands & Models, Customers & Loyalty, Branch Wise, Job Details Record
    _tabController = TabController(length: 6, vsync: this);
    if (widget.initialBranchId != null) {
      _selectedBranchId = widget.initialBranchId!;
    }
    _initializeAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recordsSearchController.dispose();
    _customerSearchController.dispose();
    _brandSearchController.dispose();
    _stockSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      var allocated = CompanyService().allocatedCompanies;
      if (allocated.isEmpty && userProvider.user != null) {
        allocated = await CompanyService().loadCompaniesForUser(userProvider.user!);
      }

      // If still empty (e.g. Super Admin or unrestricted), fetch all active branches from DB
      if (allocated.isEmpty) {
        try {
          final branchesRes = await supabase
              .from('branches')
              .select('id, branch_name, format, jobcard_prefix, branch_code, city, Guid')
              .order('branch_name');
          allocated = List<Map<String, dynamic>>.from(branchesRes);
        } catch (_) {}
      }

      _allocatedBranches = allocated;
      await _fetchReportsData();
    } catch (e) {
      debugPrint('Error initializing reports & analytics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Branch matching helper matching admin_dashboard_screen
  bool _isReportForBranch(Map<String, dynamic> report, Map<String, dynamic> branch) {
    final bId = (branch['id'] ?? branch['branch_id'] ?? branch['company_id'])?.toString().trim().toLowerCase();
    final bGuid = (branch['Guid'] ?? branch['guid'] ?? branch['tally_guid'])?.toString().trim().toLowerCase();
    final bName = (branch['branch_name'] ?? branch['company_name'] ?? branch['name'])?.toString().trim().toLowerCase();

    final rBranchId = (report['branch_id'] ?? report['company_id'])?.toString().trim().toLowerCase();
    final rGuid = (report['Guid'] ?? report['guid'])?.toString().trim().toLowerCase();
    final rBranchName = (report['branch_name'] ?? report['company_name'])?.toString().trim().toLowerCase();

    if (bId != null && bId.isNotEmpty && rBranchId != null && rBranchId.isNotEmpty && bId == rBranchId) {
      return true;
    }
    if (bGuid != null && bGuid.isNotEmpty && rGuid != null && rGuid.isNotEmpty && bGuid == rGuid) {
      return true;
    }
    if (bName != null && bName.isNotEmpty && rBranchName != null && rBranchName.isNotEmpty && bName == rBranchName) {
      return true;
    }
    return false;
  }

  /// Check if job is a courier-specific parcel (does not drop regular jobs)
  bool _isCourierJob(Map<String, dynamic> r) {
    final veh = r['vehicles'];
    if (veh is Map && veh['Vehicle Number'] == 'Courier Package') {
      return true;
    }
    final marks = r['marks'];
    if (marks != null) {
      if (marks is String) {
        if (marks.contains('"is_courier":true') ||
            marks.contains('"is_courier": true') ||
            marks.contains('"is_courier":1')) {
          return true;
        }
        try {
          final map = jsonDecode(marks);
          if (map is Map && (map['is_courier'] == true || map['is_courier'] == 1)) return true;
        } catch (_) {}
      } else if (marks is Map) {
        if (marks['is_courier'] == true || marks['is_courier'] == 1) return true;
      }
    }
    final c = (r['complaint'] ?? '').toString().toLowerCase();
    if (c.contains('courier package') || c.startsWith('courier:')) return true;
    return false;
  }

  /// Accurate report total calculation matching Accountant Dashboard & Admin Dashboard
  double _calcReportTotal(Map<String, dynamic> job) {
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
        if (marksMap != null && (marksMap['is_courier'] == true || marksMap['is_courier'] == 1)) {
          isCourier = true;
        }
      }

      // Complaints
      dynamic rawComplaints = job['complaint'];
      List<dynamic> complaints = [];
      if (rawComplaints is List) {
        complaints = rawComplaints;
      } else if (rawComplaints is String && rawComplaints.trim().startsWith('[')) {
        try {
          complaints = jsonDecode(rawComplaints);
        } catch (_) {}
      }

      // Suggested
      dynamic rawSuggested = job['suggested'];
      List<dynamic> suggested = [];
      if (rawSuggested is List) {
        suggested = rawSuggested;
      } else if (rawSuggested is String && rawSuggested.trim().startsWith('[')) {
        try {
          suggested = jsonDecode(rawSuggested);
        } catch (_) {}
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

      // Discount
      if (job['discount_amount'] != null) {
        final dVal = (job['discount_amount'] as num).toDouble();
        final dType = job['discount_type'] ?? 'flat';
        if (dType == 'percent') {
          total -= total * (dVal / 100);
        } else {
          total -= dVal;
        }
      }

      // Extra charges
      if (job['extra_charge_amount'] != null) {
        total += (job['extra_charge_amount'] as num).toDouble();
      }

      // GST
      if (job['gst_percent'] != null) {
        final gst = (job['gst_percent'] as num).toDouble();
        total += total * (gst / 100);
      }
    } catch (_) {}
    return total < 0 ? 0 : total;
  }

  /// Consistently returns effective revenue for a report (prioritizing settled payments if present)
  double _getEffectiveJobTotal(Map<String, dynamic> r) {
    final paymentsList = r['payments'] as List<dynamic>?;
    if (paymentsList != null && paymentsList.isNotEmpty) {
      double paySum = 0;
      for (final p in paymentsList) {
        if (p is Map) {
          paySum += ((p['amount'] ?? 0) as num).toDouble();
        }
      }
      if (paySum > 0) return paySum;
    }
    return _calcReportTotal(r);
  }

  /// Extract brand and model cleanly from a report
  Map<String, String> _extractBrandAndModel(Map<String, dynamic> r) {
    String brand = '';
    String model = '';

    final veh = r['vehicles'];
    if (veh is Map) {
      final vm = veh['vehicle_models'];
      if (vm is Map) {
        brand = (vm['brand'] ?? '').toString().trim().toUpperCase();
        model = (vm['Model name'] ?? vm['model_name'] ?? '').toString().trim().toUpperCase();
      }

      // Fallback: Check vehicle_name if model or brand is blank
      if (brand.isEmpty || model.isEmpty) {
        final vName = (veh['vehicle_name'] ?? '').toString().trim();
        if (vName.isNotEmpty) {
          final parts = vName.split(' ');
          if (brand.isEmpty && parts.isNotEmpty) brand = parts.first.toUpperCase();
          if (model.isEmpty && parts.length > 1) model = parts.sublist(1).join(' ').toUpperCase();
        }
      }
    }

    if (brand.isEmpty) brand = 'OTHER / UNRECORDED';
    if (model.isEmpty) model = 'STANDARD MODEL';

    return {'brand': brand, 'model': model};
  }

  /// Extracts pitch-perfect accurate works, services, tyres, parts, and buybacks from a job card
  List<JobWorkItem> _extractJobWorksAndTyres(Map<String, dynamic> job) {
    final List<JobWorkItem> items = [];

    // Parse complaints/services/tyres
    dynamic rawComplaints = job['complaint'];
    List<dynamic> list = [];
    if (rawComplaints is List) {
      list = rawComplaints;
    } else if (rawComplaints is String && rawComplaints.trim().startsWith('[')) {
      try {
        list = jsonDecode(rawComplaints);
      } catch (_) {}
    }

    // If complaint list was empty, fallback to suggested
    if (list.isEmpty) {
      dynamic rawSuggested = job['suggested'];
      if (rawSuggested is List) {
        list = rawSuggested;
      } else if (rawSuggested is String && rawSuggested.trim().startsWith('[')) {
        try {
          list = jsonDecode(rawSuggested);
        } catch (_) {}
      }
    }

    for (final item in list) {
      if (item is Map) {
        final String text = (item['text'] ?? item['name'] ?? item['title'] ?? item['service'] ?? '').toString().trim();
        if (text.isEmpty) continue;

        final double amt = ((item['amount'] ?? 0) as num).toDouble();
        final int qty = ((item['qty'] ?? item['count'] ?? 1) as num).toInt();
        final double? unitPrice = item['unit_price'] != null ? ((item['unit_price'] as num).toDouble()) : null;

        // Categorize accurately
        final lower = text.toLowerCase();
        String cat = 'service';
        if (lower.contains('tyre') ||
            lower.contains('michelin') ||
            lower.contains('apollo') ||
            lower.contains('bridgestone') ||
            lower.contains('goodyear') ||
            lower.contains('continental') ||
            lower.contains('yokohama') ||
            lower.contains('pirelli') ||
            lower.contains('ceat') ||
            lower.contains('mrf') ||
            lower.contains('jk tyre') ||
            lower.contains('falken') ||
            lower.contains('hankook') ||
            lower.contains('kumho')) {
          cat = 'tyre';
        } else if (lower.contains('buyback')) {
          cat = 'buyback';
        } else if (lower.contains('alloy') ||
            lower.contains('valve') ||
            lower.contains('nut') ||
            lower.contains('weight') ||
            lower.contains('paint') ||
            lower.contains('oil') ||
            lower.contains('filter') ||
            lower.contains('pad') ||
            lower.contains('disc') ||
            lower.contains('coolant') ||
            lower.contains('battery')) {
          cat = 'part';
        } else {
          cat = 'service';
        }

        items.add(JobWorkItem(
          title: text,
          amount: amt,
          qty: qty <= 0 ? 1 : qty,
          unitPrice: unitPrice,
          category: cat,
        ));
      } else if (item is String && item.trim().isNotEmpty) {
        items.add(JobWorkItem(
          title: item.trim(),
          amount: 0,
          qty: 1,
          category: 'service',
        ));
      }
    }

    // Check marks for products (courier or retail items)
    final marks = job['marks'];
    if (marks != null) {
      Map<String, dynamic>? marksMap;
      if (marks is Map) {
        marksMap = Map<String, dynamic>.from(marks);
      } else if (marks is String) {
        try {
          final decoded = jsonDecode(marks);
          if (decoded is Map<String, dynamic>) marksMap = decoded;
        } catch (_) {}
      }

      if (marksMap != null) {
        final products = marksMap['products'] as List<dynamic>?;
        if (products != null && items.isEmpty) {
          for (final p in products) {
            if (p is Map) {
              final name = (p['name'] ?? p['item'] ?? p['product'] ?? 'Product').toString();
              final amt = ((p['price'] ?? p['amount'] ?? 0) as num).toDouble();
              final q = ((p['qty'] ?? 1) as num).toInt();
              items.add(JobWorkItem(
                title: name,
                amount: amt * q,
                qty: q,
                unitPrice: amt,
                category: 'tyre',
              ));
            }
          }
        }
      }
    }

    return items;
  }

  /// Determine time bounds based on selected filter
  DateTimeRange? _getDateRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedTimeFilter) {
      case 'Today':
        return DateTimeRange(start: todayStart, end: todayEnd);
      case 'Yesterday':
        final yest = now.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(yest.year, yest.month, yest.day, 0, 0, 0),
          end: DateTime(yest.year, yest.month, yest.day, 23, 59, 59),
        );
      case 'This Week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: DateTime(monday.year, monday.month, monday.day, 0, 0, 0),
          end: todayEnd,
        );
      case 'This Month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1, 0, 0, 0),
          end: todayEnd,
        );
      case 'Last Month':
        final firstOfThisMonth = DateTime(now.year, now.month, 1);
        final lastDayPrevMonth = firstOfThisMonth.subtract(const Duration(days: 1));
        final firstDayPrevMonth = DateTime(lastDayPrevMonth.year, lastDayPrevMonth.month, 1);
        return DateTimeRange(
          start: DateTime(firstDayPrevMonth.year, firstDayPrevMonth.month, 1, 0, 0, 0),
          end: DateTime(lastDayPrevMonth.year, lastDayPrevMonth.month, lastDayPrevMonth.day, 23, 59, 59),
        );
      case 'This Year':
        return DateTimeRange(
          start: DateTime(now.year, 1, 1, 0, 0, 0),
          end: todayEnd,
        );
      case 'Custom Range':
        if (_customStartDate != null && _customEndDate != null) {
          return DateTimeRange(
            start: DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day, 0, 0, 0),
            end: DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59),
          );
        }
        return null;
      case 'All Time':
      default:
        return null;
    }
  }

  /// Main data fetcher
  Future<void> _fetchReportsData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final range = _getDateRange();

      // Query reports with explicit FK constraint vehicles!reports_vehicle_fk to prevent HTTP 300 Multiple Choices
      var query = supabase.from('reports').select('''
            id, job_card_id, jobcard_number, started_at, completed_at, created_at, status, billing_status,
            labour_cost, marks, complaint, suggested, approved,
            "Owner name", client_phone, odometer_reading, vehicle_id,
            branch_id, branch_name, company_name, "Guid",
            discount_amount, discount_type, extra_charge_amount, gst_percent,
            billed_at, paid_at, payment_method, transaction_id,
            vehicles!reports_vehicle_fk(
              id, "Guid", "Vehicle Number", vehicle_name, "Color", "Engine Number", "Chasis Number", MobileNumber, "Owner name",
              vehicle_models(brand, "Model name")
            ),
            executive:executive_id(username),
            payments(id, method, amount, paid_at, transaction_id)
          ''');

      if (range != null) {
        final startIso = range.start.toUtc().toIso8601String();
        final endIso = range.end.toUtc().toIso8601String();
        query = query.gte('created_at', startIso).lte('created_at', endIso);
      }

      final response = await query.order('created_at', ascending: false).limit(4000);

      _allFetchedReports = List<Map<String, dynamic>>.from(response);

      _processAnalyticsData();
    } catch (e) {
      debugPrint('Error fetching reports data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load reports: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Filters and aggregates all metrics accurately
  void _processAnalyticsData() {
    // 1. Filter reports for allocated branches and selected branch filter
    List<Map<String, dynamic>> scopedReports = [];

    for (final report in _allFetchedReports) {
      // Exclude courier parcel jobs
      if (_isCourierJob(report)) continue;

      // Check if report belongs to any of admin's allocated branches
      bool belongsToAdmin = false;
      if (_allocatedBranches.isEmpty) {
        belongsToAdmin = true; // Unrestricted admin / Super Admin
      } else {
        for (final branch in _allocatedBranches) {
          if (_isReportForBranch(report, branch)) {
            belongsToAdmin = true;
            break;
          }
        }
      }

      if (!belongsToAdmin) continue;

      // If specific branch filter is selected
      if (_selectedBranchId != 'all') {
        final selectedBranchMap = _allocatedBranches.firstWhere(
          (b) => (b['id'] ?? b['branch_id'] ?? '').toString() == _selectedBranchId,
          orElse: () => <String, dynamic>{},
        );
        if (selectedBranchMap.isNotEmpty && !_isReportForBranch(report, selectedBranchMap)) {
          continue;
        }
      }

      scopedReports.add(report);
    }

    _filteredReports = scopedReports;

    // 2. Compute KPI counts
    int total = _filteredReports.length;
    int completed = 0;
    int live = 0;
    int draft = 0;
    int cancelled = 0;

    double rev = 0.0;
    Map<String, double> payMethods = {};

    for (final r in _filteredReports) {
      final s = (r['status'] ?? '').toString().trim().toLowerCase();
      if (s == 'completed' || s == 'ready / completed' || s == 'delivered') {
        completed++;
      } else if (s == 'ongoing' ||
          s == 'work in progress' ||
          s == 'sent to wash' ||
          s == 'wash completed' ||
          s == 'inspection_approved' ||
          s == 'pending_inspection') {
        live++;
      } else if (s == 'cancelled' || s == 'rejected') {
        cancelled++;
      } else {
        draft++;
      }

      // Calculate revenue
      double jobTotal = _getEffectiveJobTotal(r);
      final paymentsList = r['payments'] as List<dynamic>?;
      if (paymentsList != null && paymentsList.isNotEmpty) {
        for (final p in paymentsList) {
          if (p is Map) {
            final amt = ((p['amount'] ?? 0) as num).toDouble();
            final m = (p['method'] ?? 'Other').toString();
            payMethods[m] = (payMethods[m] ?? 0.0) + amt;
          }
        }
      } else if (jobTotal > 0) {
        final m = (r['payment_method'] ?? 'Direct Bill').toString();
        payMethods[m] = (payMethods[m] ?? 0.0) + jobTotal;
      }

      rev += jobTotal;
    }

    _totalJobcards = total;
    _completedJobcards = completed;
    _liveJobcards = live;
    _draftJobcards = draft;
    _cancelledJobcards = cancelled;
    _completionRate = total > 0 ? (completed / total * 100) : 0.0;

    _totalRevenue = rev;
    _avgJobcardValue = completed > 0 ? (rev / completed) : (total > 0 ? (rev / total) : 0.0);
    _paymentMethodDistribution = payMethods;

    // 3. Customer Intelligence & Repeated Customers Analysis
    final Map<String, List<Map<String, dynamic>>> customerGroups = {};

    for (final r in _filteredReports) {
      String key = _extractCustomerKey(r);
      if (key.isEmpty) continue;
      customerGroups.putIfAbsent(key, () => []).add(r);
    }

    List<CustomerMetric> customers = [];
    int repeatCount = 0;
    int f2 = 0;
    int f3to5 = 0;
    int f6Plus = 0;

    customerGroups.forEach((key, jobs) {
      final visitCount = jobs.length;
      final isRepeat = visitCount >= 2;

      // Extract details
      String name = '';
      String phone = '';
      final Set<String> vehicleSet = {};
      final Set<String> carBrandModelSet = {};
      final Set<String> branchSet = {};
      double spend = 0.0;
      DateTime? firstVisit;
      DateTime? lastVisit;

      for (final j in jobs) {
        final ownerName = (j['Owner name'] ?? '').toString().trim();
        if (ownerName.isNotEmpty && name.isEmpty) name = ownerName;

        final rawPhone = (j['client_phone'] ?? '').toString().trim();
        if (rawPhone.isNotEmpty && phone.isEmpty) phone = rawPhone;

        final veh = j['vehicles'];
        if (veh is Map) {
          final vNo = (veh['Vehicle Number'] ?? '').toString().trim();
          if (vNo.isNotEmpty) vehicleSet.add(vNo);
        }

        final bm = _extractBrandAndModel(j);
        final brand = bm['brand']!;
        final model = bm['model']!;
        if (brand != 'OTHER / UNRECORDED') {
          carBrandModelSet.add('$brand $model');
        }

        final bName = (j['branch_name'] ?? j['company_name'] ?? '').toString().trim();
        if (bName.isNotEmpty) branchSet.add(bName);

        spend += _getEffectiveJobTotal(j);

        final dt = DateTime.tryParse((j['created_at'] ?? '').toString());
        if (dt != null) {
          if (firstVisit == null || dt.isBefore(firstVisit)) firstVisit = dt;
          if (lastVisit == null || dt.isAfter(lastVisit)) lastVisit = dt;
        }
      }

      if (name.isEmpty) {
        name = vehicleSet.isNotEmpty ? 'Customer (${vehicleSet.first})' : 'Customer $key';
      }

      final cMetric = CustomerMetric(
        customerKey: key,
        name: name,
        phone: phone,
        vehicles: vehicleSet.toList(),
        carBrandsModels: carBrandModelSet.toList(),
        jobcards: jobs,
        visitCount: visitCount,
        isRepeat: isRepeat,
        totalSpend: spend,
        firstVisit: firstVisit,
        lastVisit: lastVisit,
        primaryBranch: branchSet.isNotEmpty ? branchSet.first : 'Main Branch',
      );

      customers.add(cMetric);

      if (isRepeat) {
        repeatCount++;
        if (visitCount == 2) {
          f2++;
        } else if (visitCount >= 3 && visitCount <= 5) {
          f3to5++;
        } else {
          f6Plus++;
        }
      }
    });

    // Sort customers by visit count descending, then spend
    customers.sort((a, b) {
      final vCmp = b.visitCount.compareTo(a.visitCount);
      if (vCmp != 0) return vCmp;
      return b.totalSpend.compareTo(a.totalSpend);
    });

    _allCustomersList = customers;
    _repeatCustomersList = customers.where((c) => c.isRepeat).toList();
    _totalUniqueCustomers = customers.length;
    _repeatCustomerCount = repeatCount;
    _repeatCustomerRate = customers.isNotEmpty ? (repeatCount / customers.length * 100) : 0.0;
    _freq2Visits = f2;
    _freq3to5Visits = f3to5;
    _freq6PlusVisits = f6Plus;

    // 4. Car Brand & Model Analytics + Repeating Vehicles
    _computeCarBrandModelAnalytics();

    // 5. Stock & Item Sales Analytics (Tyres, Valves, Services, Parts)
    _computeStockSalesAnalytics();

    // 5. Branch-Wise Analysis
    final List<BranchMetric> bMetrics = [];
    final branchesToAnalyze = _allocatedBranches.isNotEmpty
        ? _allocatedBranches
        : [
            {'branch_name': 'All Branches', 'id': 'all', 'format': 'TYX', 'city': null}
          ];

    for (final branch in branchesToAnalyze) {
      final bName = (branch['branch_name'] ?? branch['company_name'] ?? 'Branch').toString();
      final bFormat = (branch['format'] ?? branch['jobcard_prefix'] ?? branch['branch_code'] ?? 'TYX').toString();
      final bCity = branch['city'] as String?;

      // Filter reports for this branch
      final bReports = _allFetchedReports.where((r) {
        if (_isCourierJob(r)) return false;
        return _isReportForBranch(r, branch);
      }).toList();

      int bTotal = bReports.length;
      int bCompleted = 0;
      int bLive = 0;
      int bCancelled = 0;
      double bRev = 0.0;
      final Set<String> bCustomerKeys = {};
      final Map<String, int> bCustomerVisits = {};

      for (final r in bReports) {
        final s = (r['status'] ?? '').toString().trim().toLowerCase();
        if (s == 'completed' || s == 'ready / completed' || s == 'delivered') {
          bCompleted++;
        } else if (s == 'ongoing' ||
            s == 'work in progress' ||
            s == 'sent to wash' ||
            s == 'wash completed' ||
            s == 'inspection_approved' ||
            s == 'pending_inspection') {
          bLive++;
        } else if (s == 'cancelled' || s == 'rejected') {
          bCancelled++;
        }

        bRev += _getEffectiveJobTotal(r);

        final key = _extractCustomerKey(r);
        if (key.isNotEmpty) {
          bCustomerKeys.add(key);
          bCustomerVisits[key] = (bCustomerVisits[key] ?? 0) + 1;
        }
      }

      int bRepeatCount = bCustomerVisits.values.where((v) => v >= 2).length;
      double bAvg = bCompleted > 0 ? (bRev / bCompleted) : 0.0;
      double revShare = rev > 0 ? (bRev / rev * 100) : 0.0;
      double jobShare = total > 0 ? (bTotal / total * 100) : 0.0;

      bMetrics.add(
        BranchMetric(
          branchId: branch['id'] ?? branch['branch_id'],
          branchName: bName,
          branchFormat: bFormat,
          city: bCity,
          totalJobs: bTotal,
          completedJobs: bCompleted,
          liveJobs: bLive,
          cancelledJobs: bCancelled,
          revenue: bRev,
          avgTicket: bAvg,
          repeatCustomerCount: bRepeatCount,
          revenueSharePercent: revShare,
          jobsSharePercent: jobShare,
        ),
      );
    }

    // Sort branches by revenue descending
    bMetrics.sort((a, b) => b.revenue.compareTo(a.revenue));
    _branchMetrics = bMetrics;
  }

  /// Computes granular Brand, Model, and Repeat Vehicle metrics
  void _computeCarBrandModelAnalytics() {
    // 1. Group by Brand
    final Map<String, List<Map<String, dynamic>>> brandJobs = {};
    // 2. Track individual vehicles and their visit counts
    final Map<String, List<Map<String, dynamic>>> vehicleJobs = {};

    for (final r in _filteredReports) {
      final bm = _extractBrandAndModel(r);
      final brand = bm['brand']!;
      brandJobs.putIfAbsent(brand, () => []).add(r);

      final veh = r['vehicles'];
      if (veh is Map) {
        final vNo = (veh['Vehicle Number'] ?? '').toString().trim().toUpperCase();
        if (vNo.isNotEmpty && vNo != 'COURIER PACKAGE') {
          vehicleJobs.putIfAbsent(vNo, () => []).add(r);
        }
      }
    }

    // Process Brands
    final List<BrandMetric> computedBrands = [];
    final List<ModelMetric> computedAllModels = [];

    brandJobs.forEach((brand, jobs) {
      final int totalJobs = jobs.length;
      final Set<String> uniqueVehs = {};
      final Map<String, int> vehVisitCounts = {};
      double brandRevenue = 0.0;

      // Group by model within brand
      final Map<String, List<Map<String, dynamic>>> modelJobs = {};

      for (final j in jobs) {
        brandRevenue += _getEffectiveJobTotal(j);
        final veh = j['vehicles'];
        if (veh is Map) {
          final vNo = (veh['Vehicle Number'] ?? '').toString().trim().toUpperCase();
          if (vNo.isNotEmpty) {
            uniqueVehs.add(vNo);
            vehVisitCounts[vNo] = (vehVisitCounts[vNo] ?? 0) + 1;
          }
        }
        final bm = _extractBrandAndModel(j);
        final mName = bm['model']!;
        modelJobs.putIfAbsent(mName, () => []).add(j);
      }

      int repeatVehCount = vehVisitCounts.values.where((cnt) => cnt >= 2).length;
      int repeatJobCount = vehVisitCounts.values.where((cnt) => cnt >= 2).fold(0, (sum, cnt) => sum + cnt);
      double repeatRate = uniqueVehs.isNotEmpty ? (repeatVehCount / uniqueVehs.length * 100) : 0.0;
      double brandShare = _totalJobcards > 0 ? (totalJobs / _totalJobcards * 100) : 0.0;

      // Process models under this brand
      final List<ModelMetric> brandModels = [];
      modelJobs.forEach((mName, mJobs) {
        final int mTotalJobs = mJobs.length;
        final Set<String> mUniqueVehs = {};
        final Map<String, int> mVehVisits = {};
        double mRevenue = 0.0;

        for (final mj in mJobs) {
          mRevenue += _getEffectiveJobTotal(mj);
          final veh = mj['vehicles'];
          if (veh is Map) {
            final vNo = (veh['Vehicle Number'] ?? '').toString().trim().toUpperCase();
            if (vNo.isNotEmpty) {
              mUniqueVehs.add(vNo);
              mVehVisits[vNo] = (mVehVisits[vNo] ?? 0) + 1;
            }
          }
        }

        int mRepeatVehCount = mVehVisits.values.where((cnt) => cnt >= 2).length;
        double mRepeatRate = mUniqueVehs.isNotEmpty ? (mRepeatVehCount / mUniqueVehs.length * 100) : 0.0;

        final mMetric = ModelMetric(
          modelName: mName,
          brand: brand,
          totalJobs: mTotalJobs,
          uniqueVehicles: mUniqueVehs.length,
          repeatJobs: mRepeatVehCount,
          repeatRatePercent: mRepeatRate,
          totalRevenue: mRevenue,
        );

        brandModels.add(mMetric);
        computedAllModels.add(mMetric);
      });

      // Sort models under brand by total jobs descending
      brandModels.sort((a, b) => b.totalJobs.compareTo(a.totalJobs));

      computedBrands.add(
        BrandMetric(
          brand: brand,
          totalJobs: totalJobs,
          uniqueVehicles: uniqueVehs.length,
          repeatJobs: repeatJobCount,
          repeatVehiclesCount: repeatVehCount,
          repeatRatePercent: repeatRate,
          totalRevenue: brandRevenue,
          brandSharePercent: brandShare,
          models: brandModels,
        ),
      );
    });

    // Sort brands by total jobs descending
    computedBrands.sort((a, b) => b.totalJobs.compareTo(a.totalJobs));
    _brandMetrics = computedBrands;

    // Sort all models overall by total jobs descending
    computedAllModels.sort((a, b) => b.totalJobs.compareTo(a.totalJobs));
    _allModelMetrics = computedAllModels;

    // Process Repeat Vehicles
    final List<RepeatVehicleMetric> repeatVehs = [];
    vehicleJobs.forEach((vNo, jobs) {
      if (jobs.length >= 2) {
        final firstJob = jobs.first;
        final bm = _extractBrandAndModel(firstJob);
        String owner = (firstJob['Owner name'] ?? '').toString().trim();
        String phone = (firstJob['client_phone'] ?? '').toString().trim();
        String branch = (firstJob['branch_name'] ?? firstJob['company_name'] ?? 'Main').toString();
        double spend = 0.0;
        DateTime? lastDt;

        for (final j in jobs) {
          spend += _getEffectiveJobTotal(j);
          final o = (j['Owner name'] ?? '').toString().trim();
          if (o.isNotEmpty && owner.isEmpty) owner = o;
          final p = (j['client_phone'] ?? '').toString().trim();
          if (p.isNotEmpty && phone.isEmpty) phone = p;
          final dt = DateTime.tryParse((j['created_at'] ?? '').toString());
          if (dt != null && (lastDt == null || dt.isAfter(lastDt))) lastDt = dt;
        }

        repeatVehs.add(
          RepeatVehicleMetric(
            vehicleNumber: vNo,
            brand: bm['brand']!,
            model: bm['model']!,
            ownerName: owner.isNotEmpty ? owner : 'Customer ($vNo)',
            phone: phone,
            visitCount: jobs.length,
            totalSpend: spend,
            lastVisit: lastDt,
            primaryBranch: branch,
          ),
        );
      }
    });

    // Sort repeat vehicles by visit count descending, then spend
    repeatVehs.sort((a, b) {
      final c = b.visitCount.compareTo(a.visitCount);
      if (c != 0) return c;
      return b.totalSpend.compareTo(a.totalSpend);
    });
    _repeatVehiclesList = repeatVehs;
  }

  /// Categorizes an item title into 'valve', 'service', 'tyre', or 'part'
  String _categorizeStockItem(String title) {
    final lower = title.toLowerCase().trim();

    // 1. Valves & Hardware (valves, nuts, wheel weights, bolts, flaps, tubes)
    if (lower.contains('valve') ||
        lower.contains('nut') ||
        lower.contains('weight') ||
        lower.contains('stud') ||
        lower.contains('spacer') ||
        lower.contains('ring') ||
        lower.contains('bolt') ||
        lower.contains('pin') ||
        lower.contains('flap') ||
        lower.contains('tube') ||
        lower.contains('cap')) {
      return 'valve';
    }

    // 2. Services & Labour
    if (lower.contains('alignment') ||
        lower.contains('balancing') ||
        lower.contains('fitting') ||
        lower.contains('puncture') ||
        lower.contains('punture') ||
        lower.contains('rotation') ||
        lower.contains('nitrogen') ||
        lower.contains('patch') ||
        lower.contains('wash') ||
        lower.contains('labour') ||
        lower.contains('inspection') ||
        lower.contains('service')) {
      return 'service';
    }

    // 3. Tyres (brands, models, sizes)
    if (lower.contains('tyre') ||
        lower.contains('tyrex') ||
        lower.contains('continental') ||
        lower.contains('michelin') ||
        lower.contains('pirelli') ||
        lower.contains('bridgestone') ||
        lower.contains('goodyear') ||
        lower.contains('yokohama') ||
        lower.contains('apollo') ||
        lower.contains('ceat') ||
        lower.contains('mrf') ||
        lower.contains('falken') ||
        lower.contains('hankook') ||
        lower.contains('kumho') ||
        lower.contains('jk tyre') ||
        lower.contains('maxxis') ||
        RegExp(r'\d{2,3}/\d{2}\s*r\d{2}', caseSensitive: false).hasMatch(lower)) {
      return 'tyre';
    }

    // 4. Other Parts (Alloys, accessories, etc.)
    return 'part';
  }

  /// Computes comprehensive stock & sales analytics across tyres, valves, services, and parts
  void _computeStockSalesAnalytics() {
    final Map<String, _StockAccumulator> map = {};
    int tyresQty = 0;
    int valvesQty = 0;
    int servicesQty = 0;
    int partsQty = 0;
    int totalUnits = 0;
    double totalRev = 0.0;

    for (final r in _filteredReports) {
      final items = _extractJobWorksAndTyres(r);
      final Set<String> seenInJob = {};

      for (final it in items) {
        final title = it.title.trim();
        if (title.isEmpty) continue;

        final cat = _categorizeStockItem(title);
        final qty = it.qty > 0 ? it.qty : 1;
        final amt = it.amount;

        totalUnits += qty;
        totalRev += amt;

        if (cat == 'tyre') {
          tyresQty += qty;
        } else if (cat == 'valve') {
          valvesQty += qty;
        } else if (cat == 'service') {
          servicesQty += qty;
        } else {
          partsQty += qty;
        }

        final key = title.toUpperCase();
        if (!map.containsKey(key)) {
          map[key] = _StockAccumulator(title: title, category: cat);
        }
        final acc = map[key]!;
        acc.totalQty += qty;
        acc.totalRevenue += amt;
        if (!seenInJob.contains(key)) {
          acc.jobCount++;
          seenInJob.add(key);
        }
      }
    }

    final List<StockItemMetric> list = [];
    map.forEach((_, acc) {
      final avgPrice = acc.totalQty > 0 ? (acc.totalRevenue / acc.totalQty) : 0.0;
      final revShare = totalRev > 0 ? (acc.totalRevenue / totalRev * 100) : 0.0;
      list.add(
        StockItemMetric(
          title: acc.title,
          category: acc.category,
          totalQty: acc.totalQty,
          totalRevenue: acc.totalRevenue,
          jobCount: acc.jobCount,
          avgUnitPrice: avgPrice,
          revenueSharePercent: revShare,
        ),
      );
    });

    list.sort((a, b) {
      final qCmp = b.totalQty.compareTo(a.totalQty);
      if (qCmp != 0) return qCmp;
      return b.totalRevenue.compareTo(a.totalRevenue);
    });

    _allStockItems = list;
    _totalTyresSoldQty = tyresQty;
    _totalValvesSoldQty = valvesQty;
    _totalServicesRenderedQty = servicesQty;
    _totalPartsSoldQty = partsQty;
    _totalStockUnitsSold = totalUnits;
    _totalStockRevenue = totalRev;
    _stockDisplayLimit = 30;
  }

  /// Extracts a normalized, reliable key for a customer
  String _extractCustomerKey(Map<String, dynamic> r) {
    // 1. Phone number is primary
    String phone = (r['client_phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length >= 10) {
      return 'P_${phone.substring(phone.length - 10)}';
    }

    // 2. Mobile number from vehicles table
    final veh = r['vehicles'];
    if (veh is Map) {
      String mPhone = (veh['MobileNumber'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (mPhone.length >= 10) {
        return 'P_${mPhone.substring(mPhone.length - 10)}';
      }
      // 3. Vehicle number
      String vNo = (veh['Vehicle Number'] ?? '').toString().trim().toUpperCase().replaceAll(' ', '');
      if (vNo.isNotEmpty) {
        return 'V_$vNo';
      }
    }

    // 4. Owner name fallback
    final name = (r['Owner name'] ?? '').toString().trim().toLowerCase();
    if (name.isNotEmpty && name != 'null') {
      return 'N_$name';
    }

    return '';
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now(),
            ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4F46E5),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedTimeFilter = 'Custom Range';
      });
      _fetchReportsData();
    }
  }

  Future<void> _exportCsv({required String mode}) async {
    try {
      HapticUtils.light();
      final List<List<dynamic>> rows = [];
      String filename = '';

      if (mode == 'brands') {
        filename = 'car_brands_models_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
        rows.add([
          'Brand',
          'Total Jobcards',
          'Unique Vehicles',
          'Repeat Visits',
          'Repeat Rate (%)',
          'Total Revenue (Rs)',
          'Fleet Share (%)',
          'Top Models',
        ]);
        for (final b in _brandMetrics) {
          final topModelsStr = b.models.take(4).map((m) => '${m.modelName} (${m.totalJobs})').join('; ');
          rows.add([
            b.brand,
            b.totalJobs,
            b.uniqueVehicles,
            b.repeatJobs,
            b.repeatRatePercent.toStringAsFixed(1),
            b.totalRevenue.toStringAsFixed(2),
            b.brandSharePercent.toStringAsFixed(1),
            topModelsStr,
          ]);
        }
      } else if (mode == 'repeat_customers') {
        filename = 'repeat_customers_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
        rows.add([
          'Customer Name',
          'Phone',
          'Vehicles',
          'Car Brands & Models',
          'Total Visits / Jobcards',
          'Total Amount Spent (Rs)',
          'Average per Visit (Rs)',
          'First Visit',
          'Last Visit',
          'Primary Branch',
        ]);

        for (final c in _repeatCustomersList) {
          rows.add([
            c.name,
            c.phone,
            c.vehicles.join(', '),
            c.carBrandsModels.join(', '),
            c.visitCount,
            c.totalSpend.toStringAsFixed(2),
            (c.visitCount > 0 ? c.totalSpend / c.visitCount : 0).toStringAsFixed(2),
            c.firstVisit != null ? DateFormat('dd/MM/yyyy').format(c.firstVisit!) : '',
            c.lastVisit != null ? DateFormat('dd/MM/yyyy').format(c.lastVisit!) : '',
            c.primaryBranch,
          ]);
        }
      } else if (mode == 'stock') {
        filename = 'stock_items_sold_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
        rows.add([
          'Rank',
          'Item / Tyre / Part Name',
          'Category',
          'Total Quantity Sold',
          'Total Revenue (Rs)',
          'Jobcards Count',
          'Avg Unit Price (Rs)',
          'Revenue Share (%)',
        ]);
        int rank = 1;
        for (final item in _allStockItems) {
          rows.add([
            rank++,
            item.title,
            item.category.toUpperCase(),
            item.totalQty,
            item.totalRevenue.toStringAsFixed(2),
            item.jobCount,
            item.avgUnitPrice.toStringAsFixed(2),
            item.revenueSharePercent.toStringAsFixed(2),
          ]);
        }
      } else {
        filename = 'reports_analytics_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
        rows.add([
          'Job Card ID',
          'Date',
          'Branch',
          'Vehicle Number',
          'Car Brand',
          'Car Model',
          'Customer Name',
          'Phone',
          'Status',
          'Billing Status',
          'Labour Cost',
          'Total Amount',
          'Payment Method',
        ]);

        for (final r in _filteredReports) {
          final veh = r['vehicles'] is Map ? r['vehicles'] : {};
          final bm = _extractBrandAndModel(r);
          rows.add([
            r['job_card_id'] ?? r['jobcard_number'] ?? '#${r['id']}',
            r['created_at'] != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(r['created_at'].toString())) : '',
            r['branch_name'] ?? r['company_name'] ?? '',
            veh['Vehicle Number'] ?? '',
            bm['brand'] ?? '',
            bm['model'] ?? '',
            r['Owner name'] ?? '',
            r['client_phone'] ?? '',
            r['status'] ?? '',
            r['billing_status'] ?? '',
            r['labour_cost'] ?? 0,
            _getEffectiveJobTotal(r).toStringAsFixed(2),
            r['payment_method'] ?? '',
          ]);
        }
      }

      final String csv = const ListToCsvConverter().convert(rows);

      if (kIsWeb) {
        final blob = html.Blob([csv], 'text/csv');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final dir = await getTemporaryDirectory();
        final file = io.File('${dir.path}/$filename');
        await file.writeAsString(csv, flush: true);
        await Share.shareXFiles([XFile(file.path, name: filename, mimeType: 'text/csv')]);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported successfully: $filename'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCustomerDetailSheet(CustomerMetric customer) {
    HapticUtils.selection();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Sheet Header Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 12),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Customer Overview Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      child: const Icon(Icons.person_rounded, size: 28, color: Color(0xFF4F46E5)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  customer.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (customer.visitCount >= 2) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: customer.visitCount >= 5
                                        ? const Color(0xFFF1F5F9)
                                        : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: customer.visitCount >= 5
                                          ? const Color(0xFFCBD5E1)
                                          : const Color(0xFF93C5FD),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        customer.visitCount >= 5 ? Icons.verified_rounded : Icons.repeat_rounded,
                                        size: 12,
                                        color: customer.visitCount >= 5
                                            ? const Color(0xFF334155)
                                            : const Color(0xFF1D4ED8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        customer.visitCount >= 5 ? 'Frequent Client' : 'Returning Client',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: customer.visitCount >= 5
                                              ? const Color(0xFF334155)
                                              : const Color(0xFF1D4ED8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            customer.phone.isNotEmpty ? customer.phone : 'No phone recorded',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // KPI Quick Strip
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSheetMiniKpi(
                      'Total Visits',
                      '${customer.visitCount}',
                      Icons.event_repeat_rounded,
                      const Color(0xFF2563EB),
                    ),
                    Container(height: 30, width: 1, color: const Color(0xFFE2E8F0)),
                    _buildSheetMiniKpi(
                      'Total Spent',
                      NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(customer.totalSpend),
                      Icons.currency_rupee_rounded,
                      const Color(0xFF059669),
                    ),
                    Container(height: 30, width: 1, color: const Color(0xFFE2E8F0)),
                    _buildSheetMiniKpi(
                      'Avg / Visit',
                      NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(
                        customer.visitCount > 0 ? customer.totalSpend / customer.visitCount : 0,
                      ),
                      Icons.receipt_long_rounded,
                      const Color(0xFF8B5CF6),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Vehicles & Car Models
              if (customer.vehicles.isNotEmpty || customer.carBrandsModels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car_rounded, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          customer.carBrandsModels.isNotEmpty
                              ? customer.carBrandsModels.join(' • ')
                              : customer.vehicles.join(' • '),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Visit History (${customer.jobcards.length} Job Cards)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const Text(
                      'Most recent first',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),

              // List of customer's job cards with itemized works, tyres, and services
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: customer.jobcards.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final j = customer.jobcards[i];
                    final String jId = j['job_card_id'] ?? j['jobcard_number'] ?? '#${j['id']}';
                    final date = DateTime.tryParse(j['created_at'].toString());
                    final status = (j['status'] ?? 'Completed').toString();
                    final bName = j['branch_name'] ?? j['company_name'] ?? 'Branch';
                    final amt = _getEffectiveJobTotal(j);
                    final bm = _extractBrandAndModel(j);
                    final veh = j['vehicles'] is Map ? j['vehicles'] : {};
                    final vNo = (veh['Vehicle Number'] ?? '').toString();
                    final odo = j['odometer_reading'];
                    final works = _extractJobWorksAndTyres(j);
                    final labour = (j['labour_cost'] ?? 0) as num;
                    final discount = (j['discount_amount'] ?? 0) as num;
                    final gst = (j['gst_percent'] ?? 0) as num;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Job Card Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.assignment_rounded, size: 18, color: Color(0xFF4F46E5)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      jId,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildStatusBadge(status),
                                  ],
                                ),
                                Text(
                                  NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(amt),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Vehicle & Visit Meta
                            Row(
                              children: [
                                const Icon(Icons.directions_car_rounded, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 4),
                                Text(
                                  vNo.isNotEmpty ? '$vNo • ' : '',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                ),
                                Text(
                                  '${bm['brand']} ${bm['model']}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                ),
                                if (odo != null && odo != 0) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '•  ${NumberFormat('#,##,###').format(odo)} km',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 4),

                            Row(
                              children: [
                                const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Text(
                                  date != null ? DateFormat('dd MMM yyyy, hh:mm a').format(date) : '',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '•  $bName',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Works, Tyres & Services Breakdown Box
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.build_circle_outlined, size: 15, color: Color(0xFF4F46E5)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Works, Tyres & Services (${works.length})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (works.isNotEmpty)
                                        Text(
                                          'Itemized Details',
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  if (works.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 4),
                                      child: Text(
                                        'No specific work items recorded for this job card.',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                                      ),
                                    )
                                  else
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: works.length,
                                      separatorBuilder: (context, idx) => const Divider(height: 12, color: Color(0xFFE2E8F0)),
                                      itemBuilder: (context, idx) {
                                        final item = works[idx];

                                        // Category color and badge
                                        Color catBg = const Color(0xFFEFF6FF);
                                        Color catFg = const Color(0xFF1D4ED8);
                                        IconData catIcon = Icons.handyman_rounded;
                                        String catName = 'SERVICE';

                                        if (item.category == 'tyre') {
                                          catBg = const Color(0xFFECFDF5);
                                          catFg = const Color(0xFF059669);
                                          catIcon = Icons.adjust_rounded;
                                          catName = 'TYRE';
                                        } else if (item.category == 'part') {
                                          catBg = const Color(0xFFFEF3C7);
                                          catFg = const Color(0xFFB45309);
                                          catIcon = Icons.settings_suggest_rounded;
                                          catName = 'PART';
                                        } else if (item.category == 'buyback') {
                                          catBg = const Color(0xFFF3E8FF);
                                          catFg = const Color(0xFF7E22CE);
                                          catIcon = Icons.swap_horizontal_circle_rounded;
                                          catName = 'BUYBACK';
                                        }

                                        return Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Category Pill
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: catBg,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(catIcon, size: 10, color: catFg),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    catName,
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: catFg,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            const SizedBox(width: 8),

                                            // Item Title + Quantity & Rate
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.title,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  if (item.qty > 1 || item.unitPrice != null)
                                                    Text(
                                                      '${item.qty} pcs @ ₹${item.unitPrice?.toStringAsFixed(0) ?? (item.qty > 0 ? (item.amount / item.qty).toStringAsFixed(0) : "0")} each',
                                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                                    ),
                                                ],
                                              ),
                                            ),

                                            const SizedBox(width: 8),

                                            // Amount
                                            Text(
                                              item.amount < 0
                                                  ? '-₹${(-item.amount).toStringAsFixed(0)}'
                                                  : NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(item.amount),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: item.amount < 0 ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),

                                  // Financial adjustments strip (Labour, Discounts, GST)
                                  if (labour > 0 || discount > 0 || gst > 0) ...[
                                    const Divider(height: 16, color: Color(0xFFCBD5E1)),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        if (labour > 0)
                                          Text(
                                            'Labour: ₹${labour.toStringAsFixed(0)}',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                                          ),
                                        if (discount > 0)
                                          Text(
                                            'Discount: -₹${discount.toStringAsFixed(0)}',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                                          ),
                                        if (gst > 0)
                                          Text(
                                            'GST: ${gst.toStringAsFixed(0)}%',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF8B5CF6)),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetMiniKpi(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final s = status.toLowerCase();
    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF475569);

    if (s.contains('completed') || s.contains('delivered')) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF15803D);
    } else if (s.contains('ongoing') || s.contains('progress') || s.contains('wash')) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
    } else if (s.contains('cancel') || s.contains('reject')) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFB91C1C);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          children: [
            Text(
              'Reports & Analytics',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Jobcards, Car Brands & Customer Insights',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF475569)),
            tooltip: 'Refresh Analytics',
            onPressed: _isLoading
                ? null
                : () {
                    HapticUtils.light();
                    _fetchReportsData();
                  },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF475569)),
            tooltip: 'Export & Options',
            onSelected: (val) {
              if (val == 'csv_all') {
                _exportCsv(mode: 'all');
              } else if (val == 'csv_repeat') {
                _exportCsv(mode: 'repeat_customers');
              } else if (val == 'csv_brands') {
                _exportCsv(mode: 'brands');
              } else if (val == 'csv_stock') {
                _exportCsv(mode: 'stock');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'csv_all',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_rounded, size: 18, color: Color(0xFF2563EB)),
                    SizedBox(width: 8),
                    Text('Export Jobcards CSV'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv_stock',
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_rounded, size: 18, color: Color(0xFF4F46E5)),
                    SizedBox(width: 8),
                    Text('Export Stock & Items CSV'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv_brands',
                child: Row(
                  children: [
                    Icon(Icons.directions_car_rounded, size: 18, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Text('Export Car Brands CSV'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv_repeat',
                child: Row(
                  children: [
                    Icon(Icons.people_alt_rounded, size: 18, color: Color(0xFF059669)),
                    SizedBox(width: 8),
                    Text('Export Repeat Customers CSV'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF4F46E5),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF4F46E5),
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: [
                const Tab(
                  child: Row(
                    children: [
                      Icon(Icons.dashboard_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Overview'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Stock & Items Sold (${_allStockItems.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Car Brands & Models (${_brandMetrics.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Customers & Loyalty (${_allCustomersList.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.business_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Branch Wise (${_branchMetrics.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.view_list_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Job Details (${_filteredReports.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter Controls Ribbon
          _buildFilterBar(),

          // Main Tabs Content
          Expanded(
            child: _isLoading
                ? const ModernLoadingIndicator(message: 'Loading comprehensive reports & analytics...')
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildStockAnalyticsTab(),
                      _buildCarBrandsAndModelsTab(),
                      _buildCustomersAndLoyaltyTab(),
                      _buildBranchWiseTab(),
                      _buildJobcardsRecordTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Top sticky filter bar
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          // Branch selector + Date Range picker
          Row(
            children: [
              // Branch Filter
              Expanded(
                flex: 5,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBranchId,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF475569)),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedBranchId = val);
                          _processAnalyticsData();
                        }
                      },
                      items: [
                        DropdownMenuItem<String>(
                          value: 'all',
                          child: Row(
                            children: [
                              const Icon(Icons.apartment_rounded, size: 15, color: Color(0xFF4F46E5)),
                              const SizedBox(width: 6),
                              Text('All Branches (${_allocatedBranches.length})'),
                            ],
                          ),
                        ),
                        ..._allocatedBranches.map((b) {
                          final id = (b['id'] ?? b['branch_id'] ?? '').toString();
                          final name = (b['branch_name'] ?? b['company_name'] ?? 'Branch').toString();
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Row(
                              children: [
                                const Icon(Icons.storefront_rounded, size: 15, color: Color(0xFF0284C7)),
                                const SizedBox(width: 6),
                                Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Time preset dropdown
              Expanded(
                flex: 4,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTimeFilter,
                      isExpanded: true,
                      icon: const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF475569)),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          if (val == 'Custom Range') {
                            _pickCustomDateRange();
                          } else {
                            setState(() => _selectedTimeFilter = val);
                            _fetchReportsData();
                          }
                        }
                      },
                      items: _timeFilterOptions.map((opt) {
                        return DropdownMenuItem<String>(
                          value: opt,
                          child: Text(opt),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Custom range active indicator
          if (_selectedTimeFilter == 'Custom Range' && _customStartDate != null && _customEndDate != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickCustomDateRange,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.date_range_rounded, size: 13, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 4),
                  Text(
                    '${DateFormat('dd MMM yy').format(_customStartDate!)} - ${DateFormat('dd MMM yy').format(_customEndDate!)} (Tap to change)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: OVERVIEW & FINANCIALS
  // ==========================================
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 4 Main Master KPI Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 650;
              final double cardSpacing = 10.0;
              final int cols = isWide ? 4 : 2;
              final double cardWidth = (constraints.maxWidth - (cardSpacing * (cols - 1))) / cols;

              return Wrap(
                spacing: cardSpacing,
                runSpacing: cardSpacing,
                children: [
                  _buildPrimaryKpiCard(
                    width: cardWidth,
                    title: 'Total Job Cards',
                    value: '$_totalJobcards',
                    subtitle: '$_completedJobcards completed (${_completionRate.toStringAsFixed(0)}%)',
                    icon: Icons.assignment_outlined,
                    color: const Color(0xFF2563EB),
                    bgColor: const Color(0xFFEFF6FF),
                  ),
                  _buildPrimaryKpiCard(
                    width: cardWidth,
                    title: 'Total Revenue',
                    value: NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(_totalRevenue),
                    subtitle: 'Avg Ticket: ₹${_avgJobcardValue.toStringAsFixed(0)}',
                    icon: Icons.currency_rupee_rounded,
                    color: const Color(0xFF059669),
                    bgColor: const Color(0xFFECFDF5),
                  ),
                  _buildPrimaryKpiCard(
                    width: cardWidth,
                    title: 'Repeat Customers',
                    value: '$_repeatCustomerCount',
                    subtitle: '${_repeatCustomerRate.toStringAsFixed(1)}% Retention Rate',
                    icon: Icons.repeat_rounded,
                    color: const Color(0xFF8B5CF6),
                    bgColor: const Color(0xFFF5F3FF),
                  ),
                  _buildPrimaryKpiCard(
                    width: cardWidth,
                    title: 'Active / Live Jobs',
                    value: '$_liveJobcards',
                    subtitle: '$_draftJobcards in draft / pending',
                    icon: Icons.pending_actions_rounded,
                    color: const Color(0xFFD97706),
                    bgColor: const Color(0xFFFFFBEB),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 18),

          // Jobcards Status Breakdown Card
          _buildStatusBreakdownSection(),

          const SizedBox(height: 18),

          // Top Car Brands & Models Quick Snapshot
          _buildBrandsSnapshotSection(),

          const SizedBox(height: 18),

          // Top Selling Tyres & Stock Items Quick Snapshot
          _buildTopSellingStockSnapshotSection(),

          const SizedBox(height: 18),

          // Payment Methods Strip
          if (_paymentMethodDistribution.isNotEmpty) ...[
            _buildPaymentMethodsSection(),
            const SizedBox(height: 18),
          ],

          // Quick Branch Leaderboard Snippet
          _buildBranchSnapshotSection(),
        ],
      ).animate().fadeIn(duration: 350.ms),
    );
  }

  Widget _buildPrimaryKpiCard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    String? badge,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdownSection() {
    final double compPct = _totalJobcards > 0 ? (_completedJobcards / _totalJobcards) : 0;
    final double livePct = _totalJobcards > 0 ? (_liveJobcards / _totalJobcards) : 0;
    final double draftPct = _totalJobcards > 0 ? (_draftJobcards / _totalJobcards) : 0;
    final double cancelPct = _totalJobcards > 0 ? (_cancelledJobcards / _totalJobcards) : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.pie_chart_outline_rounded, size: 18, color: Color(0xFF4F46E5)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Job Card Status Distribution',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$_totalJobcards Total',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Stacked Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (compPct > 0)
                    Flexible(
                      flex: (_completedJobcards * 100).toInt(),
                      child: Container(color: const Color(0xFF10B981)),
                    ),
                  if (livePct > 0)
                    Flexible(
                      flex: (_liveJobcards * 100).toInt(),
                      child: Container(color: const Color(0xFFF59E0B)),
                    ),
                  if (draftPct > 0)
                    Flexible(
                      flex: (_draftJobcards * 100).toInt(),
                      child: Container(color: const Color(0xFF3B82F6)),
                    ),
                  if (cancelPct > 0)
                    Flexible(
                      flex: (_cancelledJobcards * 100).toInt(),
                      child: Container(color: const Color(0xFFEF4444)),
                    ),
                  if (_totalJobcards == 0)
                    Expanded(child: Container(color: Colors.grey.shade200)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Legend
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _buildLegendItem('Completed', '$_completedJobcards', const Color(0xFF10B981)),
              _buildLegendItem('Ongoing / Live', '$_liveJobcards', const Color(0xFFF59E0B)),
              _buildLegendItem('Draft / Pending', '$_draftJobcards', const Color(0xFF3B82F6)),
              _buildLegendItem('Cancelled', '$_cancelledJobcards', const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
      ],
    );
  }

  Widget _buildBrandsSnapshotSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.directions_car_rounded, size: 18, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Top Car Brands Serviced',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _tabController.animateTo(2),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF4F46E5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_brandMetrics.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No car brand data found for selected period.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _brandMetrics.take(4).length,
              separatorBuilder: (context, i) => const Divider(height: 16),
              itemBuilder: (context, i) {
                final b = _brandMetrics[i];
                final topModelStr = b.models.isNotEmpty ? b.models.first.modelName : '';
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFD97706).withValues(alpha: 0.1),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                b.brand,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              if (b.repeatVehiclesCount > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${b.repeatVehiclesCount} repeat',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${b.totalJobs} jobs (${b.uniqueVehicles} vehicles)${topModelStr.isNotEmpty ? " • Top: $topModelStr" : ""}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(b.totalRevenue),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                        ),
                        Text(
                          '${b.brandSharePercent.toStringAsFixed(1)}% Fleet',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_rounded, size: 18, color: Color(0xFF4F46E5)),
              SizedBox(width: 8),
              Text(
                'Payment Channels Recorded',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _paymentMethodDistribution.entries.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.key.toUpperCase(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(e.value),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchSnapshotSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF0284C7)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Branch Contribution Overview',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _tabController.animateTo(4),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF4F46E5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _branchMetrics.take(4).length,
            separatorBuilder: (context, i) => const Divider(height: 16),
            itemBuilder: (context, i) {
              final b = _branchMetrics[i];
              return Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.branchName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          '${b.totalJobs} jobs (${b.completedJobs} done) • ${b.repeatCustomerCount} repeat clients',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(b.revenue),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TOP SELLING STOCK & ITEMS SNAPSHOT (OVERVIEW)
  // ==========================================
  Widget _buildTopSellingStockSnapshotSection() {
    final topTyres = _allStockItems.where((i) => i.category == 'tyre').take(3).toList();
    final topValves = _allStockItems.where((i) => i.category == 'valve').take(3).toList();
    final topServices = _allStockItems.where((i) => i.category == 'service').take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_rounded, size: 18, color: Color(0xFF4F46E5)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Top Selling Tyres & Stock Items',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _tabController.animateTo(1),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF4F46E5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Quick pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickStatChip(
                  label: 'Tyres Sold',
                  value: '$_totalTyresSoldQty',
                  color: const Color(0xFF4338CA),
                  bgColor: const Color(0xFFEEF2FF),
                  icon: Icons.tire_repair_rounded,
                ),
                const SizedBox(width: 8),
                _buildQuickStatChip(
                  label: 'Valves & Hardware',
                  value: '$_totalValvesSoldQty',
                  color: const Color(0xFFB45309),
                  bgColor: const Color(0xFFFFFBEB),
                  icon: Icons.settings_rounded,
                ),
                const SizedBox(width: 8),
                _buildQuickStatChip(
                  label: 'Services Done',
                  value: '$_totalServicesRenderedQty',
                  color: const Color(0xFF047857),
                  bgColor: const Color(0xFFECFDF5),
                  icon: Icons.build_rounded,
                ),
                if (_totalPartsSoldQty > 0) ...[
                  const SizedBox(width: 8),
                  _buildQuickStatChip(
                    label: 'Alloys & Parts',
                    value: '$_totalPartsSoldQty',
                    color: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFFF5F3FF),
                    icon: Icons.inventory_2_rounded,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Top Tyres mini-list
          if (topTyres.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.tire_repair_rounded, size: 13, color: Color(0xFF4338CA)),
                SizedBox(width: 4),
                Text(
                  'TOP SELLING TYRES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA), letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...topTyres.map((item) => _buildMiniStockRow(item)),
            const SizedBox(height: 10),
          ],

          // Top Valves mini-list
          if (topValves.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.settings_rounded, size: 13, color: Color(0xFFB45309)),
                SizedBox(width: 4),
                Text(
                  'TOP VALVES & HARDWARE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB45309), letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...topValves.map((item) => _buildMiniStockRow(item)),
            const SizedBox(height: 10),
          ],

          // Top Services mini-list
          if (topServices.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.build_rounded, size: 13, color: Color(0xFF047857)),
                SizedBox(width: 4),
                Text(
                  'TOP SERVICES & LABOUR',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857), letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...topServices.map((item) => _buildMiniStockRow(item)),
          ],

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text('Explore All ${_allStockItems.length} Stock & Items Sold'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F46E5),
                side: const BorderSide(color: Color(0xFFC7D2FE)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatChip({
    required String label,
    required String value,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStockRow(StockItemMetric item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${item.totalQty} sold',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
          if (item.totalRevenue > 0) ...[
            const SizedBox(width: 8),
            Text(
              NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(item.totalRevenue),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: STOCK & ITEMS SOLD ANALYTICS
  // ==========================================
  Widget _buildStockAnalyticsTab() {
    // Filter by category
    List<StockItemMetric> filtered = _allStockItems;
    if (_stockCategoryFilter != 'all') {
      filtered = filtered.where((i) => i.category == _stockCategoryFilter).toList();
    }

    // Filter by search query
    if (_stockSearchQuery.isNotEmpty) {
      final q = _stockSearchQuery.toLowerCase();
      filtered = filtered.where((i) => i.title.toLowerCase().contains(q)).toList();
    }

    // Sort
    if (_stockSortBy == 'revenue') {
      filtered.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    } else if (_stockSortBy == 'jobs') {
      filtered.sort((a, b) => b.jobCount.compareTo(a.jobCount));
    } else {
      filtered.sort((a, b) {
        final qCmp = b.totalQty.compareTo(a.totalQty);
        if (qCmp != 0) return qCmp;
        return b.totalRevenue.compareTo(a.totalRevenue);
      });
    }

    final tyresCount = _allStockItems.where((i) => i.category == 'tyre').length;
    final valvesCount = _allStockItems.where((i) => i.category == 'valve').length;
    final servicesCount = _allStockItems.where((i) => i.category == 'service').length;
    final partsCount = _allStockItems.where((i) => i.category == 'part').length;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 4 Top Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 650;
              final cardWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStockKpiCard(
                    width: cardWidth,
                    title: 'Tyres Sold',
                    value: '$_totalTyresSoldQty',
                    subtitle: '$tyresCount distinct tyres',
                    icon: Icons.tire_repair_rounded,
                    color: const Color(0xFF4338CA),
                    bgColor: const Color(0xFFEEF2FF),
                  ),
                  _buildStockKpiCard(
                    width: cardWidth,
                    title: 'Valves & Hardware',
                    value: '$_totalValvesSoldQty',
                    subtitle: '$valvesCount distinct items',
                    icon: Icons.settings_rounded,
                    color: const Color(0xFFB45309),
                    bgColor: const Color(0xFFFFFBEB),
                  ),
                  _buildStockKpiCard(
                    width: cardWidth,
                    title: 'Services Done',
                    value: '$_totalServicesRenderedQty',
                    subtitle: '$servicesCount distinct services',
                    icon: Icons.build_rounded,
                    color: const Color(0xFF047857),
                    bgColor: const Color(0xFFECFDF5),
                  ),
                  _buildStockKpiCard(
                    width: cardWidth,
                    title: 'Parts & Alloys',
                    value: '$_totalPartsSoldQty',
                    subtitle: '$partsCount distinct parts',
                    icon: Icons.inventory_2_rounded,
                    color: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFFF5F3FF),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 18),

          // Search Box
          TextField(
            controller: _stockSearchController,
            decoration: InputDecoration(
              hintText: 'Search tyres, valves, services, brands...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _stockSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        setState(() {
                          _stockSearchController.clear();
                          _stockSearchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _stockSearchQuery = val.trim();
                _stockDisplayLimit = 30;
              });
            },
          ),

          const SizedBox(height: 12),

          // Category Pills Filter Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStockFilterPill('all', 'All (${_allStockItems.length})', Icons.apps_rounded),
                const SizedBox(width: 8),
                _buildStockFilterPill('tyre', 'Tyres ($tyresCount)', Icons.tire_repair_rounded),
                const SizedBox(width: 8),
                _buildStockFilterPill('valve', 'Valves & Hardware ($valvesCount)', Icons.settings_rounded),
                const SizedBox(width: 8),
                _buildStockFilterPill('service', 'Services ($servicesCount)', Icons.build_rounded),
                const SizedBox(width: 8),
                _buildStockFilterPill('part', 'Parts & Alloys ($partsCount)', Icons.inventory_2_rounded),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Sorting & Results Summary Bar (Responsive to prevent overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${filtered.length} items found • $_totalStockUnitsSold units sold',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Total: ${NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(_totalStockRevenue)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Sort: ', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _stockSortBy,
                        isDense: true,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        items: const [
                          DropdownMenuItem(value: 'qty', child: Text('Qty Sold')),
                          DropdownMenuItem(value: 'revenue', child: Text('Revenue')),
                          DropdownMenuItem(value: 'jobs', child: Text('Jobs/Cars')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _stockSortBy = val;
                              _stockDisplayLimit = 30;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Items List with Lazy Limit Rendering to eliminate tab navigation lag
          if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 12),
                  const Text(
                    'No items match the current filters',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Try changing the category or clearing the search box.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _stockSearchController.clear();
                        _stockSearchQuery = '';
                        _stockCategoryFilter = 'all';
                        _stockDisplayLimit = 30;
                      });
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
                    child: const Text('Reset Filters', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            )
          else ...[
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.take(_stockDisplayLimit).length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                return _buildStockItemCard(item, index + 1);
              },
            ),
            if (filtered.length > _stockDisplayLimit)
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Showing ${_stockDisplayLimit < filtered.length ? _stockDisplayLimit : filtered.length} of ${filtered.length} items',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _stockDisplayLimit += 30;
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Color(0xFF4F46E5)),
                      label: const Text('Load More (+30)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _stockDisplayLimit = filtered.length;
                        });
                      },
                      child: const Text('Show All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockKpiCard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStockFilterPill(String catKey, String label, IconData icon) {
    final isSelected = _stockCategoryFilter == catKey;
    return InkWell(
      onTap: () => setState(() {
        _stockCategoryFilter = catKey;
        _stockDisplayLimit = 30;
      }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockItemCard(StockItemMetric item, int rank) {
    Color catColor;
    Color catBg;
    String catLabel;
    IconData catIcon;

    if (item.category == 'tyre') {
      catColor = const Color(0xFF4338CA);
      catBg = const Color(0xFFEEF2FF);
      catLabel = 'TYRE';
      catIcon = Icons.tire_repair_rounded;
    } else if (item.category == 'valve') {
      catColor = const Color(0xFFB45309);
      catBg = const Color(0xFFFFFBEB);
      catLabel = 'VALVE & HARDWARE';
      catIcon = Icons.settings_rounded;
    } else if (item.category == 'service') {
      catColor = const Color(0xFF047857);
      catBg = const Color(0xFFECFDF5);
      catLabel = 'SERVICE';
      catIcon = Icons.build_rounded;
    } else {
      catColor = const Color(0xFF7C3AED);
      catBg = const Color(0xFFF5F3FF);
      catLabel = 'ALLOY / PART';
      catIcon = Icons.inventory_2_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rank indicator
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank <= 3 ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: rank <= 3 ? const Color(0xFFB45309) : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Category badge & item title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(catIcon, size: 10, color: catColor),
                          const SizedBox(width: 4),
                          Text(
                            catLabel,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: catColor, letterSpacing: 0.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Quantity sold badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${item.totalQty} Sold',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          // Metrics breakdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStockMetricCol('Revenue', NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(item.totalRevenue), const Color(0xFF059669)),
              _buildStockMetricCol('Jobcards', '${item.jobCount} jobs', const Color(0xFF2563EB)),
              _buildStockMetricCol('Avg Unit Price', item.avgUnitPrice > 0 ? NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(item.avgUnitPrice) : '-', const Color(0xFF64748B)),
              _buildStockMetricCol('Rev Share', '${item.revenueSharePercent.toStringAsFixed(1)}%', const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockMetricCol(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: CAR BRANDS & MODELS ANALYTICS
  // ==========================================
  Widget _buildCarBrandsAndModelsTab() {
    // Filtered lists based on brand search query
    final q = _brandSearchQuery.toLowerCase();
    final filteredBrands = _brandMetrics.where((b) {
      if (q.isEmpty) return true;
      return b.brand.toLowerCase().contains(q) ||
          b.models.any((m) => m.modelName.toLowerCase().contains(q));
    }).toList();

    final filteredModels = _allModelMetrics.where((m) {
      if (q.isEmpty) return true;
      return m.brand.toLowerCase().contains(q) || m.modelName.toLowerCase().contains(q);
    }).toList();

    final filteredRepeatVehicles = _repeatVehiclesList.where((v) {
      if (q.isEmpty) return true;
      return v.vehicleNumber.toLowerCase().contains(q) ||
          v.brand.toLowerCase().contains(q) ||
          v.model.toLowerCase().contains(q) ||
          v.ownerName.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Summary Strip for Brands
        Container(
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBrandSummaryTile('Brands', '${_brandMetrics.length}', Icons.directions_car_rounded, const Color(0xFF4F46E5)),
              Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
              _buildBrandSummaryTile('Models', '${_allModelMetrics.length}', Icons.category_rounded, const Color(0xFF0284C7)),
              Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
              _buildBrandSummaryTile('Repeat Cars', '${_repeatVehiclesList.length}', Icons.replay_rounded, const Color(0xFF059669)),
            ],
          ),
        ),

        // Sub-segment Toggle: Brands vs Models vs Repeating Cars
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              _buildSubToggleOption('brands', 'Car Brands (${_brandMetrics.length})'),
              const SizedBox(width: 6),
              _buildSubToggleOption('models', 'Top Models (${_allModelMetrics.length})'),
              const SizedBox(width: 6),
              _buildSubToggleOption('repeating_cars', 'Repeat Cars (${_repeatVehiclesList.length})'),
            ],
          ),
        ),

        // Search Bar for Brands/Models
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: TextField(
            controller: _brandSearchController,
            decoration: InputDecoration(
              hintText: _brandViewMode == 'repeating_cars'
                  ? 'Search repeat vehicle number, model, owner...'
                  : 'Search car brand or model (e.g. Toyota, Seltos, City)...',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
              suffixIcon: _brandSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _brandSearchController.clear();
                        setState(() => _brandSearchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            onChanged: (val) => setState(() => _brandSearchQuery = val.trim()),
          ),
        ),

        // Dynamic View
        Expanded(
          child: _brandViewMode == 'brands'
              ? _buildBrandsListView(filteredBrands)
              : _brandViewMode == 'models'
                  ? _buildModelsListView(filteredModels)
                  : _buildRepeatCarsListView(filteredRepeatVehicles),
        ),
      ],
    );
  }

  Widget _buildBrandSummaryTile(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildSubToggleOption(String mode, String label) {
    final bool isSelected = _brandViewMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticUtils.selection();
          setState(() => _brandViewMode = mode);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildBrandsListView(List<BrandMetric> brands) {
    if (brands.isEmpty) {
      return const Center(child: Text('No car brands match your search.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: brands.length,
      separatorBuilder: (context, i) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final b = brands[i];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
              child: Text(
                '${i + 1}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    b.brand,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
                Text(
                  NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(b.totalRevenue),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                ),
              ],
            ),
            subtitle: Row(
              children: [
                Text(
                  '${b.totalJobs} jobs (${b.uniqueVehicles} vehicles)',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                if (b.repeatVehiclesCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${b.repeatVehiclesCount} repeat (${b.repeatRatePercent.toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                    ),
                  ),
                ],
              ],
            ),
            children: [
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Models Breakdown',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                  Text(
                    '${b.models.length} registered models',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...b.models.map((m) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 6),
                          Text(
                            m.modelName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                          ),
                          if (m.repeatJobs > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${m.repeatJobs} repeats',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            '${m.totalJobs} jobs',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(m.totalRevenue),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModelsListView(List<ModelMetric> models) {
    if (models.isEmpty) {
      return const Center(child: Text('No car models match your search.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: models.length,
      separatorBuilder: (context, i) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = models[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.1),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          m.modelName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            m.brand,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${m.totalJobs} jobs • ${m.uniqueVehicles} distinct vehicles',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(m.totalRevenue),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                  if (m.repeatJobs > 0)
                    Text(
                      '${m.repeatJobs} repeats (${m.repeatRatePercent.toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRepeatCarsListView(List<RepeatVehicleMetric> repeatVehs) {
    if (repeatVehs.isEmpty) {
      return const Center(child: Text('No repeating vehicles found in this date range.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: repeatVehs.length,
      separatorBuilder: (context, i) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final v = repeatVehs[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF059669).withValues(alpha: 0.1),
                child: Text(
                  '${v.visitCount}x',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          v.vehicleNumber,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${v.brand} ${v.model}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Owner: ${v.ownerName}${v.phone.isNotEmpty ? " • ${v.phone}" : ""}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    if (v.lastVisit != null)
                      Text(
                        'Last service: ${DateFormat('dd MMM yy').format(v.lastVisit!)} • ${v.primaryBranch}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(v.totalSpend),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${v.visitCount} visits',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 3: CUSTOMERS & LOYALTY
  // ==========================================
  Widget _buildCustomersAndLoyaltyTab() {
    final displayList = _customerViewMode == 'repeat' ? _repeatCustomersList : _allCustomersList;
    final filtered = displayList.where((c) {
      if (_customerSearchQuery.isEmpty) return true;
      final q = _customerSearchQuery.toLowerCase();
      return c.name.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.vehicles.any((v) => v.toLowerCase().contains(q)) ||
          c.carBrandsModels.any((bm) => bm.toLowerCase().contains(q));
    }).toList();

    return Column(
      children: [
        // Top Loyalty KPI Card
        Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.loyalty_rounded, size: 20, color: Color(0xFF8B5CF6)),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Customer Retention & Loyalty',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_repeatCustomerRate.toStringAsFixed(1)}% Retention',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildRetentionTile('Total Clients', '$_totalUniqueCustomers', Icons.people_outline_rounded),
                  _buildRetentionTile('Repeat Clients', '$_repeatCustomerCount', Icons.repeat_rounded),
                ],
              ),
              const SizedBox(height: 12),
              // Frequency breakdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('2 Visits: $_freq2Visits', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    Text('3-5 Visits: $_freq3to5Visits', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2563EB))),
                    Text('6+ Visits (Frequent): $_freq6PlusVisits', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Toggle: Repeat Customers vs All Customers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _customerViewMode = 'repeat');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _customerViewMode == 'repeat' ? const Color(0xFF4F46E5) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _customerViewMode == 'repeat' ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'Repeat Customers (${_repeatCustomersList.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _customerViewMode == 'repeat' ? FontWeight.bold : FontWeight.w600,
                        color: _customerViewMode == 'repeat' ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _customerViewMode = 'all');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _customerViewMode == 'all' ? const Color(0xFF4F46E5) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _customerViewMode == 'all' ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'All Customers (${_allCustomersList.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _customerViewMode == 'all' ? FontWeight.bold : FontWeight.w600,
                        color: _customerViewMode == 'all' ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: _customerSearchController,
            decoration: InputDecoration(
              hintText: 'Search customers by name, phone, vehicle or car brand...',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
              suffixIcon: _customerSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _customerSearchController.clear();
                        setState(() => _customerSearchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            onChanged: (val) => setState(() => _customerSearchQuery = val.trim()),
          ),
        ),

        const SizedBox(height: 10),

        // Customers List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_search_rounded, size: 48, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 8),
                      Text(
                        _customerSearchQuery.isEmpty
                            ? 'No customers found in this date range.'
                            : 'No customers match "$_customerSearchQuery"',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  itemCount: filtered.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    return InkWell(
                      onTap: () => _showCustomerDetailSheet(c),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: c.isRepeat
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.1)
                                  : const Color(0xFF64748B).withValues(alpha: 0.1),
                              child: Text(
                                '${c.visitCount}x',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: c.isRepeat ? const Color(0xFF8B5CF6) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          c.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Highly Prominent Visits Pill
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFC7D2FE), width: 0.8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.event_repeat_rounded, size: 11, color: Color(0xFF4F46E5)),
                                            const SizedBox(width: 3),
                                            Text(
                                              '${c.visitCount} ${c.visitCount == 1 ? "Visit" : "Visits"}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF4F46E5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (c.visitCount >= 5) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFFCBD5E1), width: 0.6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.verified_rounded, size: 10, color: Color(0xFF475569)),
                                              SizedBox(width: 3),
                                              Text(
                                                'Frequent',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF334155),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    c.phone.isNotEmpty
                                        ? c.phone
                                        : (c.vehicles.isNotEmpty ? c.vehicles.join(', ') : 'Direct Client'),
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                  if (c.carBrandsModels.isNotEmpty)
                                    Text(
                                      c.carBrandsModels.join(' • '),
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (c.lastVisit != null)
                                    Text(
                                      'Last visit: ${DateFormat('dd MMM yyyy').format(c.lastVisit!)} • ${c.primaryBranch}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(c.totalSpend),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'History (${c.visitCount})',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF4F46E5)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRetentionTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF8B5CF6)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: BRANCH-WISE ANALYSIS
  // ==========================================
  Widget _buildBranchWiseTab() {
    if (_branchMetrics.isEmpty) {
      return const Center(
        child: Text('No branch metrics available for the selected filters.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _branchMetrics.length,
      separatorBuilder: (context, i) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final b = _branchMetrics[i];
        final bool isSelected = _selectedBranchId == (b.branchId ?? '').toString();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.business_rounded, size: 20, color: Color(0xFF0284C7)),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.branchName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Prefix: ${b.branchFormat}${b.city != null ? " • ${b.city}" : ""}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(b.revenue),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // KPI Matrix Grid
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildBranchMiniStat('Total Jobs', '${b.totalJobs}', const Color(0xFF2563EB)),
                    Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                    _buildBranchMiniStat('Completed', '${b.completedJobs}', const Color(0xFF10B981)),
                    Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                    _buildBranchMiniStat('Live Jobs', '${b.liveJobs}', const Color(0xFFD97706)),
                    Container(height: 26, width: 1, color: const Color(0xFFE2E8F0)),
                    _buildBranchMiniStat('Repeat Clients', '${b.repeatCustomerCount}', const Color(0xFF8B5CF6)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Action button to isolate this branch
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Avg Ticket: ₹${b.avgTicket.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.filter_alt_outlined,
                      size: 16,
                      color: const Color(0xFF4F46E5),
                    ),
                    label: Text(
                      isSelected ? 'Currently Selected' : 'Filter to this branch',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedBranchId = isSelected ? 'all' : (b.branchId ?? '').toString();
                      });
                      _processAnalyticsData();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBranchMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 5: DETAILED JOBCARDS RECORD
  // ==========================================
  Widget _buildJobcardsRecordTab() {
    final filtered = _filteredReports.where((r) {
      if (_recordsStatusFilter != 'all') {
        final s = (r['status'] ?? '').toString().toLowerCase();
        if (_recordsStatusFilter == 'completed' && !s.contains('completed') && !s.contains('delivered')) return false;
        if (_recordsStatusFilter == 'ongoing' && !s.contains('ongoing') && !s.contains('progress')) return false;
        if (_recordsStatusFilter == 'draft' && !s.contains('not started') && !s.contains('draft')) return false;
      }

      if (_recordsSearchQuery.isNotEmpty) {
        final q = _recordsSearchQuery.toLowerCase();
        final jId = (r['job_card_id'] ?? r['jobcard_number'] ?? '#${r['id']}').toString().toLowerCase();
        final name = (r['Owner name'] ?? '').toString().toLowerCase();
        final phone = (r['client_phone'] ?? '').toString().toLowerCase();
        final veh = r['vehicles'] is Map ? (r['vehicles']['Vehicle Number'] ?? '').toString().toLowerCase() : '';
        final bm = _extractBrandAndModel(r);
        final brand = bm['brand']!.toLowerCase();
        final model = bm['model']!.toLowerCase();
        return jId.contains(q) || name.contains(q) || phone.contains(q) || veh.contains(q) || brand.contains(q) || model.contains(q);
      }
      return true;
    }).toList();

    final totalPages = (filtered.length / _pageSize).ceil();
    final startIndex = (_currentPage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize > filtered.length) ? filtered.length : startIndex + _pageSize;
    final pageItems = (startIndex < filtered.length) ? filtered.sublist(startIndex, endIndex) : <Map<String, dynamic>>[];

    return Column(
      children: [
        // Search and Status Filters
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _recordsSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search jobcard ID, vehicle, client, brand...',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _recordsSearchQuery = val.trim();
                          _currentPage = 1;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _recordsStatusFilter,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _recordsStatusFilter = val;
                              _currentPage = 1;
                            });
                          }
                        },
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Status')),
                          DropdownMenuItem(value: 'completed', child: Text('Completed')),
                          DropdownMenuItem(value: 'ongoing', child: Text('Ongoing')),
                          DropdownMenuItem(value: 'draft', child: Text('Draft/New')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${pageItems.length} of ${filtered.length} Job Cards',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                  if (totalPages > 1)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                        ),
                        Text('$_currentPage / $totalPages', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: pageItems.isEmpty
              ? const Center(child: Text('No job cards match your search criteria.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: pageItems.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = pageItems[i];
                    final String jId = r['job_card_id'] ?? r['jobcard_number'] ?? '#${r['id']}';
                    final date = DateTime.tryParse(r['created_at'].toString());
                    final status = (r['status'] ?? 'Completed').toString();
                    final bName = r['branch_name'] ?? r['company_name'] ?? 'Branch';
                    final veh = r['vehicles'] is Map ? r['vehicles'] : {};
                    final vNo = (veh['Vehicle Number'] ?? 'Vehicle N/A').toString();
                    final owner = (r['Owner name'] ?? '').toString();
                    final phone = (r['client_phone'] ?? '').toString();
                    final amt = _getEffectiveJobTotal(r);
                    final bm = _extractBrandAndModel(r);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    jId,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildStatusBadge(status),
                                ],
                              ),
                              Text(
                                NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(amt),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF059669)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.directions_car_rounded, size: 14, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                vNo,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                              ),
                              if (bm['brand'] != 'OTHER / UNRECORDED') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${bm['brand']} ${bm['model']}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                  ),
                                ),
                              ],
                              if (owner.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '•  $owner',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              if (phone.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text('($phone)', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.storefront_rounded, size: 13, color: Color(0xFF94A3B8)),
                                  const SizedBox(width: 4),
                                  Text(
                                    bName,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 10),
                                  if (date != null)
                                    Text(
                                      DateFormat('dd MMM yy, hh:mm a').format(date),
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.print_rounded, size: 18, color: Color(0xFF4F46E5)),
                                tooltip: 'Print Job Card',
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  Printing.layoutPdf(
                                    onLayout: (format) => generateJobCardPdf(r),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
