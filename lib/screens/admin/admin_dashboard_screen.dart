import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'app_settings_screen.dart';
import 'vehicle_management_screen.dart';
import 'service_catalog_screen.dart';
import 'tyre_catalog_screen.dart';
import '../login_screen.dart';
import 'user_management_screen.dart';
import 'reports_analytics_screen.dart';
import '../../widgets/modern_page_route.dart';
import '../../widgets/modern_card.dart';
import '../../widgets/modern_loading.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/app_constants.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import 'dart:convert';
import '../profile_screen.dart';
import '../../services/company_service.dart';
import '../update_screen.dart';

class AdminBranchStat {
  final dynamic branchId;
  final String branchName;
  final String branchFormat;
  final String? city;
  final int todayJobs;
  final int liveJobs;
  final int completedJobs;
  final double todayRevenue;

  const AdminBranchStat({
    required this.branchId,
    required this.branchName,
    required this.branchFormat,
    this.city,
    required this.todayJobs,
    required this.liveJobs,
    required this.completedJobs,
    required this.todayRevenue,
  });
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final supabase = Supabase.instance.client;
  
  // Metrics across all allocated branches
  int _todayJobs = 0;
  int _totalLiveJobs = 0;
  int _totalCompletedToday = 0;
  double _amountReceived = 0.0;
  List<AdminBranchStat> _branchStats = [];
  List<Map<String, dynamic>> _allocatedBranches = [];
  bool _isLoadingMetrics = true;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

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

  bool _isCourierJob(Map<String, dynamic> r) {
    if (r['vehicle_id'] == null) return true;
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
    if (c.contains('courier')) return true;
    return false;
  }

  bool _isPaymentForBranch(Map<String, dynamic> payment, Map<String, dynamic> branch) {
    // 1. Check direct branch fields on payment
    if (_isReportForBranch(payment, branch)) {
      return true;
    }
    // 2. Check nested reports map
    final rep = payment['reports'];
    if (rep != null && rep is Map) {
      try {
        final repMap = Map<String, dynamic>.from(rep);
        if (_isReportForBranch(repMap, branch)) return true;
      } catch (_) {}
    }
    return false;
  }

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
        if (marksMap != null && marksMap['is_courier'] == true) {
          isCourier = true;
        }
      }

      dynamic rawComplaints = job['complaint'];
      List<dynamic> complaints = [];
      if (rawComplaints is List) {
        complaints = rawComplaints;
      } else if (rawComplaints is String && rawComplaints.trim().startsWith('[')) {
        try { complaints = jsonDecode(rawComplaints); } catch (_) {}
      }

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

      if (job['discount_amount'] != null) {
        final dVal = (job['discount_amount'] as num).toDouble();
        final dType = job['discount_type'] ?? 'flat';
        if (dType == 'percent') {
          total -= total * (dVal / 100);
        } else {
          total -= dVal;
        }
      }

      if (job['extra_charge_amount'] != null) {
        total += (job['extra_charge_amount'] as num).toDouble();
      }

      if (job['gst_percent'] != null) {
        final gst = (job['gst_percent'] as num).toDouble();
        total += total * (gst / 100);
      }
    } catch (_) {}
    return total;
  }

  Future<void> _loadMetrics() async {
    if (!mounted) return;
    setState(() => _isLoadingMetrics = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      var allocated = CompanyService().allocatedCompanies;

      // Ensure allocated branches are loaded for current admin
      if (allocated.isEmpty && userProvider.user != null) {
        allocated = await CompanyService().loadCompaniesForUser(userProvider.user!);
      }

      final now = DateTime.now();
      final startOfTodayLocal = DateTime(now.year, now.month, now.day);
      final startOfTodayUtcIso = startOfTodayLocal.toUtc().toIso8601String();
      final todayDateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final startFilter = startOfTodayUtcIso.compareTo(todayDateStr) < 0 ? startOfTodayUtcIso : todayDateStr;

      // If admin has no allocated branches, leave metrics as 0
      if (allocated.isEmpty) {
        if (mounted) {
          setState(() {
            _allocatedBranches = [];
            _branchStats = [];
            _todayJobs = 0;
            _totalLiveJobs = 0;
            _totalCompletedToday = 0;
            _amountReceived = 0.0;
            _isLoadingMetrics = false;
          });
        }
        return;
      }

      // Fetch today's reports, all live/ongoing reports, today's payments, and today's paid reports
      final results = await Future.wait([
        supabase
            .from('reports')
            .select('id, company_name, branch_id, branch_name, status, created_at, "Guid", marks, vehicle_id, complaint')
            .gte('created_at', startFilter),
        supabase
            .from('reports')
            .select('id, company_name, branch_id, branch_name, status, "Guid", marks, vehicle_id, complaint')
            .not('status', 'in', '(${AppConstants.statusCompleted},ready / completed,delivered,completed,${AppConstants.statusCancelled},cancelled,${AppConstants.statusDraft},draft,${AppConstants.statusNotStarted},not started)'),
        supabase
            .from('payments')
            .select('amount, paid_at, report_id, branch_id, branch_name, "Guid", reports(id, company_name, branch_id, branch_name, "Guid")')
            .gte('paid_at', startFilter),
        supabase
            .from('reports')
            .select('id, company_name, branch_id, branch_name, "Guid", billing_status, paid_at, billed_at, labour_cost, marks, complaint, suggested, discount_amount, discount_type, extra_charge_amount, gst_percent')
            .eq('billing_status', AppConstants.statusPaid)
            .or('paid_at.gte.$startFilter,billed_at.gte.$startFilter'),
      ]);

      final List<dynamic> todayReportsRaw = results[0] as List<dynamic>;
      final List<dynamic> liveReportsRaw = results[1] as List<dynamic>;
      final List<dynamic> paymentsRaw = results[2] as List<dynamic>;
      final List<dynamic> todayPaidReportsRaw = results[3] as List<dynamic>;

      final List<AdminBranchStat> branchStatsList = [];
      int grandTodayJobs = 0;
      int grandLiveJobs = 0;
      int grandCompletedJobs = 0;
      double grandRevenue = 0.0;

      // Compute statistics strictly per allocated branch
      for (final branch in allocated) {
        final bName = (branch['branch_name'] ?? branch['company_name'] ?? 'Branch').toString();
        final bFormat = (branch['format'] ?? branch['jobcard_prefix'] ?? branch['branch_code'] ?? 'TYX').toString();
        final bCity = branch['city'] as String?;

        // 1. Today's reports for this branch
        final branchTodayReports = todayReportsRaw.where((r) {
          final rep = r as Map<String, dynamic>;
          return _isReportForBranch(rep, branch) && !_isCourierJob(rep);
        }).toList();
        final todayCount = branchTodayReports.length;

        // 2. Live / In-Progress reports for this branch (matching Work in Progress tab in Job Cards)
        final branchLiveReports = liveReportsRaw.where((r) {
          final rep = r as Map<String, dynamic>;
          if (!_isReportForBranch(rep, branch)) return false;
          if (_isCourierJob(rep)) return false;
          final s = (rep['status'] ?? '').toString().trim().toLowerCase();
          if (s == AppConstants.statusDraft.toLowerCase() ||
              s == 'draft' ||
              s == 'not started' ||
              s == AppConstants.statusNotStarted.toLowerCase() ||
              s == AppConstants.statusCompleted.toLowerCase() ||
              s == 'ready / completed' ||
              s == 'delivered' ||
              s == 'completed' ||
              s == AppConstants.statusCancelled.toLowerCase() ||
              s == 'cancelled') {
            return false;
          }
          return true;
        }).toList();
        final liveCount = branchLiveReports.length;

        // 3. Completed today for this branch
        final completedCount = branchTodayReports.where((r) {
          final s = (r['status'] ?? '').toString().toLowerCase();
          return s == AppConstants.statusCompleted.toLowerCase() ||
                 s == 'ready / completed' ||
                 s == 'delivered' ||
                 s == 'completed';
        }).length;

        // 4. Revenue today for this branch (matching Accountant Dashboard)
        double branchRevenue = 0.0;
        final Set<int> coveredReportIds = {};
        for (final p in paymentsRaw) {
          if (_isPaymentForBranch(p as Map<String, dynamic>, branch)) {
            branchRevenue += ((p['amount'] ?? 0.0) as num).toDouble();
            final rId = p['report_id'];
            if (rId != null) {
              final parsedId = int.tryParse(rId.toString());
              if (parsedId != null) coveredReportIds.add(parsedId);
            }
          }
        }
        for (final r in todayPaidReportsRaw) {
          final rep = r as Map<String, dynamic>;
          if (_isReportForBranch(rep, branch)) {
            final repId = rep['id'] != null ? int.tryParse(rep['id'].toString()) : null;
            if (repId == null || !coveredReportIds.contains(repId)) {
              branchRevenue += _calcReportTotal(rep);
              if (repId != null) coveredReportIds.add(repId);
            }
          }
        }

        branchStatsList.add(
          AdminBranchStat(
            branchId: branch['id'],
            branchName: bName,
            branchFormat: bFormat,
            city: bCity,
            todayJobs: todayCount,
            liveJobs: liveCount,
            completedJobs: completedCount,
            todayRevenue: branchRevenue,
          ),
        );

        grandTodayJobs += todayCount;
        grandLiveJobs += liveCount;
        grandCompletedJobs += completedCount;
        grandRevenue += branchRevenue;
      }

      if (mounted) {
        setState(() {
          _allocatedBranches = allocated;
          _branchStats = branchStatsList;
          _todayJobs = grandTodayJobs;
          _totalLiveJobs = grandLiveJobs;
          _totalCompletedToday = grandCompletedJobs;
          _amountReceived = grandRevenue;
          _isLoadingMetrics = false;
        });
      }
    } catch (e) {
      debugPrint('❌ AdminDashboard: Error loading metrics: $e');
      if (mounted) {
        setState(() => _isLoadingMetrics = false);
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final originalAdminJson = prefs.getString('originalAdmin');

    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (originalAdminJson != null) {
      final originalAdmin = jsonDecode(originalAdminJson) as Map<String, dynamic>;
      userProvider.switchToUser(originalAdmin);

      await prefs.setString('currentUser', originalAdminJson);
      await prefs.remove('originalAdmin');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Returned to admin dashboard'),
          backgroundColor: Colors.green,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      );
      return;
    }

    await prefs.remove('currentUser');
    if (!mounted) return;
    userProvider.setUser(null);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    context.pushModern(
      screen,
      transition: RouteTransitionType.slideUp,
    );
  }

  @override
  Widget build(BuildContext context) {
    final int branchCount = _allocatedBranches.length;
    final String branchSubtitle = branchCount <= 1
        ? (_allocatedBranches.isNotEmpty
            ? (_allocatedBranches.first['branch_name'] ?? _allocatedBranches.first['company_name'] ?? 'Single Branch')
            : 'No Branch Assigned')
        : '$branchCount Branches Managed';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: const Color(0xFFE2E8F0),
            height: 1.0,
          ),
        ),
        title: Column(
          children: [
            const Text(
              'Admin Dashboard',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.business_rounded, size: 12, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 4),
                  Text(
                    branchSubtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isLoadingMetrics
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4F46E5),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF475569)),
            tooltip: 'Refresh Dashboard',
            onPressed: _isLoadingMetrics
                ? null
                : () {
                    HapticUtils.light();
                    _loadMetrics();
                  },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF475569)),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, size: 18),
                    SizedBox(width: 8),
                    Text('Profile'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMetrics,
          color: const Color(0xFF4F46E5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 750;
              final double horizontalPadding = isDesktop ? 24.0 : 12.0;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Consolidated Overview Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.insights_rounded, size: 18, color: Color(0xFF4F46E5)),
                              ),
                              const SizedBox(width: 8),
                              const Flexible(
                                child: Text(
                                  'Consolidated Overview',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!_isLoadingMetrics)
                          InkWell(
                            onTap: () {
                              HapticUtils.light();
                              _navigateTo(context, const ReportsAnalyticsScreen());
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.25)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.analytics_rounded, size: 14, color: Color(0xFF4F46E5)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Reports & Analytics',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF4F46E5)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Top 4 Real Metric Cards
                    _isLoadingMetrics
                        ? const ModernLoadingIndicator(message: 'Calculating metrics across branches...')
                        : AnimationLimiter(
                            child: LayoutBuilder(
                              builder: (context, boxConstraints) {
                                final isWide = boxConstraints.maxWidth > 650;
                                final double cardSpacing = 10.0;
                                final int cols = isWide ? 4 : 2;
                                final double cardWidth = (boxConstraints.maxWidth - (cardSpacing * (cols - 1))) / cols;

                                return Wrap(
                                  spacing: cardSpacing,
                                  runSpacing: cardSpacing,
                                  children: AnimationConfiguration.toStaggeredList(
                                    duration: const Duration(milliseconds: 350),
                                    childAnimationBuilder: (widget) => SlideAnimation(
                                      verticalOffset: 20.0,
                                      child: FadeInAnimation(child: widget),
                                    ),
                                    children: [
                                      _buildMetricCard(
                                        width: cardWidth,
                                        title: "Today's Job Cards",
                                        subtitle: branchCount > 1 ? 'All Branches' : 'Selected Branch',
                                        value: _todayJobs.toString(),
                                        icon: Icons.assignment_outlined,
                                        color: const Color(0xFF2563EB),
                                        bgColor: const Color(0xFFEFF6FF),
                                        onTap: () {
                                          HapticUtils.light();
                                          Navigator.push(
                                            context,
                                            ModernPageRoute(page: const UpdateScreen(isAdminMode: true)),
                                          ).then((_) => _loadMetrics());
                                        },
                                      ),
                                      _buildMetricCard(
                                        width: cardWidth,
                                        title: "Today's Revenue",
                                        subtitle: branchCount > 1 ? 'All Branches' : 'Selected Branch',
                                        value: NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(_amountReceived),
                                        icon: Icons.currency_rupee_rounded,
                                        color: const Color(0xFF059669),
                                        bgColor: const Color(0xFFECFDF5),
                                        onTap: () {
                                          HapticUtils.light();
                                          _navigateTo(context, const ReportsAnalyticsScreen());
                                        },
                                      ),
                                      _buildMetricCard(
                                        width: cardWidth,
                                        title: "Live Active Jobs",
                                        subtitle: 'In Progress / Ongoing',
                                        value: _totalLiveJobs.toString(),
                                        icon: Icons.pending_actions_rounded,
                                        color: const Color(0xFFD97706),
                                        bgColor: const Color(0xFFFFFBEB),
                                        onTap: () {
                                          HapticUtils.light();
                                          Navigator.push(
                                            context,
                                            ModernPageRoute(page: const UpdateScreen(isAdminMode: true)),
                                          ).then((_) => _loadMetrics());
                                        },
                                      ),
                                      _buildMetricCard(
                                        width: cardWidth,
                                        title: "Completed Today",
                                        subtitle: 'Ready & Delivered',
                                        value: _totalCompletedToday.toString(),
                                        icon: Icons.task_alt_rounded,
                                        color: const Color(0xFF0D9488),
                                        bgColor: const Color(0xFFF0FDFA),
                                        onTap: () {
                                          HapticUtils.light();
                                          _navigateTo(context, const ReportsAnalyticsScreen());
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                    const SizedBox(height: 24),

                    // Branch-Wise Performance / Analysis Section
                    if (!_isLoadingMetrics && _branchStats.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.domain_rounded, size: 18, color: Color(0xFF0284C7)),
                                ),
                                const SizedBox(width: 8),
                                const Flexible(
                                  child: Text(
                                    'Branch-Wise Analysis',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.3,
                                    ),
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
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_branchStats.length} ${_branchStats.length == 1 ? "Branch" : "Branches"}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      AnimationLimiter(
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _branchStats.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final stat = _branchStats[index];
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 300),
                              child: SlideAnimation(
                                verticalOffset: 20.0,
                                child: FadeInAnimation(
                                  child: _buildBranchAnalysisCard(context, stat),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Quick Actions Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.grid_view_rounded, size: 18, color: Color(0xFF8B5CF6)),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    AnimationLimiter(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth > 750;
                          final double gap = isDesktop ? 12.0 : 8.0;
                          final int crossAxisCount = isDesktop ? 3 : 2;
                          final double itemWidth = (constraints.maxWidth - (gap * (crossAxisCount - 1))) / crossAxisCount;

                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: AnimationConfiguration.toStaggeredList(
                              duration: const Duration(milliseconds: 375),
                              childAnimationBuilder: (widget) => SlideAnimation(
                                verticalOffset: 50.0,
                                child: FadeInAnimation(child: widget),
                              ),
                              children: [
                                _buildDashboardCard(
                                  context,
                                  width: itemWidth,
                                  title: 'Live Job Board',
                                  subtitle: 'Active Jobs & Status',
                                  icon: Icons.dashboard_customize_rounded,
                                  color: const Color(0xFF4F46E5),
                                  onTap: () {
                                    HapticUtils.light();
                                    Navigator.push(
                                      context,
                                      ModernPageRoute(page: const UpdateScreen(isAdminMode: true)),
                                    );
                                  },
                                ),
                                _buildDashboardCard(
                                  context,
                                  width: itemWidth,
                                  title: 'Reports & Analytics',
                                  subtitle: 'Job cards, branch-wise, revenue & customers',
                                  icon: Icons.analytics_rounded,
                                  color: const Color(0xFF0284C7),
                                  onTap: () {
                                    HapticUtils.light();
                                    _navigateTo(context, const ReportsAnalyticsScreen());
                                  },
                                ),
                                _buildDashboardCard(
                                  context,
                                  width: itemWidth,
                                  title: 'Vehicle Management',
                                  subtitle: 'Models, makes & types',
                                  icon: Icons.directions_car_rounded,
                                  color: const Color(0xFFD97706),
                                  onTap: () {
                                    HapticUtils.light();
                                    _navigateTo(context, const VehicleManagementScreen());
                                  },
                                ),
                                _buildDashboardCard(
                                  context,
                                  width: itemWidth,
                                  title: 'Service Catalog',
                                  subtitle: 'Services & labor rates',
                                  icon: Icons.design_services_rounded,
                                  color: const Color(0xFF0D9488),
                                  onTap: () {
                                    HapticUtils.light();
                                    _navigateTo(context, const ServiceCatalogScreen());
                                  },
                                ),
                                _buildDashboardCard(
                                  context,
                                  width: itemWidth,
                                  title: 'Tyre Catalog',
                                  subtitle: 'Tyre sizes & brands',
                                  icon: Icons.tire_repair_rounded,
                                  color: const Color(0xFF059669),
                                  onTap: () {
                                    HapticUtils.light();
                                    _navigateTo(context, const TyreCatalogScreen());
                                  },
                                ),
                                _buildDashboardCard(
                                  context,
                                  width: itemWidth,
                                  title: 'Team Members',
                                  subtitle: 'User accounts & roles',
                                  icon: Icons.badge_outlined,
                                  color: const Color(0xFF9333EA),
                                  onTap: () {
                                    HapticUtils.light();
                                    _navigateTo(context, const UserManagementScreen());
                                  },
                                ),
                                _buildDashboardCard(
                                  context,
                                  width: itemWidth,
                                  title: 'App Settings',
                                  subtitle: 'System configurations',
                                  icon: Icons.settings_rounded,
                                  color: const Color(0xFF475569),
                                  onTap: () {
                                    HapticUtils.light();
                                    _navigateTo(context, const AppSettingsScreen());
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required double width,
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
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
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        subtitle,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.grey.shade400),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchAnalysisCard(BuildContext context, AdminBranchStat stat) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticUtils.light();
          final branch = _allocatedBranches.firstWhere(
            (b) => (b['id'] ?? b['branch_id'])?.toString() == stat.branchId?.toString(),
            orElse: () => <String, dynamic>{},
          );
          if (branch.isNotEmpty) {
            CompanyService().setActiveCompany(branch);
          }
          Navigator.push(
            context,
            ModernPageRoute(page: const UpdateScreen(isAdminMode: true)),
          ).then((_) => _loadMetrics());
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Branch Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  stat.branchFormat,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4F46E5),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.branchName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (stat.city != null && stat.city!.isNotEmpty)
                      Text(
                        stat.city!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              // Live active indicator badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stat.liveJobs > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: stat.liveJobs > 0 ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: stat.liveJobs > 0 ? const Color(0xFFD97706) : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${stat.liveJobs} Live',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: stat.liveJobs > 0 ? const Color(0xFFB45309) : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // 3 Metric Pills: Today's Jobs, Completed, Today's Revenue
          Row(
            children: [
              Expanded(
                child: _buildBranchMiniStat(
                  label: "Today's Jobs",
                  value: stat.todayJobs.toString(),
                  icon: Icons.assignment_outlined,
                  color: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildBranchMiniStat(
                  label: 'Completed',
                  value: stat.completedJobs.toString(),
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF0D9488),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildBranchMiniStat(
                  label: "Today's Revenue",
                  value: NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(stat.todayRevenue),
                  icon: Icons.currency_rupee_rounded,
                  color: const Color(0xFF059669),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildBranchMiniStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required double width,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: ModernCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 24,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}