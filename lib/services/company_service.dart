// lib/services/company_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_constants.dart';

class CompanyService {
  static final CompanyService _instance = CompanyService._internal();
  factory CompanyService() => _instance;
  CompanyService._internal();

  final supabase = Supabase.instance.client;

  // Cached active branch / company data
  Map<String, dynamic>? _activeCompany;
  List<Map<String, dynamic>> _allocatedCompanies = [];
  bool _isLoading = false;

  /// Get cached active branch / company data
  Map<String, dynamic>? get activeCompany => _activeCompany;
  Map<String, dynamic>? get activeBranch => _activeCompany;
  List<Map<String, dynamic>> get allocatedCompanies => _allocatedCompanies;
  List<Map<String, dynamic>> get allocatedBranches => _allocatedCompanies;
  bool get hasMultipleCompanies => _allocatedCompanies.length > 1;
  bool get hasMultipleBranches => _allocatedCompanies.length > 1;
  bool get isLoading => _isLoading;
  bool get hasActiveCompany => _activeCompany != null;
  bool get hasActiveBranch => _activeCompany != null;

  /// Get branch / company name from cached data
  String? get companyName => _activeCompany?['branch_name'] as String? ?? _activeCompany?['company_name'] as String?;
  String? get branchName => companyName;
  
  /// Get branch code or company alias/number
  String? get branchCode => _activeCompany?['branch_code'] as String? ?? _activeCompany?['company_number'] as String? ?? _activeCompany?['company_alias'] as String?;

  /// Returns true when the stored format/prefix value is ONLY the DB column default 'TYX'
  /// (i.e. the branch is NOT a Kochi/TyreX branch and the value was never explicitly changed).
  /// These branches should derive their prefix from the branch name instead.
  bool _isTyxDefault(String value, String branchNameLower) {
    if (value.toUpperCase() != 'TYX') return false;
    // If the branch is actually TyreX / Kochi, TYX is a real configured prefix
    return !branchNameLower.contains('kochi') &&
        !branchNameLower.contains('tyrex') &&
        !branchNameLower.contains('tyx');
  }

  /// Derive a short prefix from the branch name (e.g. "Mumbai Branch" → "MUM", "Trivandrum" → "TRI")
  String _derivePrefixFromName(String name) {
    if (name.isEmpty) return 'TYX';
    final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (clean.startsWith('MUMBAI') || clean.startsWith('MUM')) return 'MBX';
    if (clean.length >= 3) return clean.substring(0, 3);
    return clean.isNotEmpty ? clean : 'TYX';
  }

  /// Check if the active branch has an explicitly configured prefix/format
  /// (i.e. NOT just the DB default 'TYX' on a non-Kochi branch)
  bool get hasBranchPrefix {
    final name = (branchName ?? '').toLowerCase();
    final rawFormat = _activeCompany?['format'] ?? _activeCompany?['jobcard_prefix'];
    if (rawFormat != null && rawFormat.toString().trim().isNotEmpty) {
      final v = rawFormat.toString().trim().toUpperCase();
      // A non-default value (not TYX), or TYX on a real Kochi/TyreX branch
      if (!_isTyxDefault(v, name)) { return true; }
    }
    final rawAlias = _activeCompany?['company_alias'];
    if (rawAlias != null && rawAlias.toString().trim().isNotEmpty &&
        !_isTyxDefault(rawAlias.toString().trim().toUpperCase(), name)) { return true; }
    final rawCode = _activeCompany?['branch_code'];
    if (rawCode != null && rawCode.toString().trim().isNotEmpty &&
        !RegExp(r'^\d+$').hasMatch(rawCode.toString().trim())) { return true; }
    return false;
  }

  /// Get the explicitly configured prefix/format (null if not set or is just DB default)
  String? get configuredBranchPrefix {
    final rawFormat = _activeCompany?['format'] ?? _activeCompany?['jobcard_prefix'];
    final rawAlias = _activeCompany?['company_alias'];
    final rawCode = _activeCompany?['branch_code'];
    final name = (branchName ?? '').toLowerCase();

    // 1. Mumbai override
    if (name.contains('mumbai') || name.contains('mum')) {
      if (rawFormat != null && rawFormat.toString().trim().isNotEmpty) {
        final v = rawFormat.toString().trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (v.isNotEmpty && !_isTyxDefault(v, name)) return v;
      }
      return 'MBX';
    }

    // 2. Explicit format/jobcard_prefix — skip if it's just the DB default TYX
    if (rawFormat != null && rawFormat.toString().trim().isNotEmpty) {
      final clean = rawFormat.toString().trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      // Not TYX, or TYX on a real Kochi/TyreX branch
      if (clean.isNotEmpty && !_isTyxDefault(clean, name)) return clean;
    }

    // 3. company_alias
    if (rawAlias != null && rawAlias.toString().trim().isNotEmpty) {
      final clean = rawAlias.toString().trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (clean.isNotEmpty && !_isTyxDefault(clean, name)) return clean;
    }

    // 4. branch_code (only if letters, not a pure number)
    if (rawCode != null && rawCode.toString().trim().isNotEmpty) {
      final clean = rawCode.toString().trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (clean.isNotEmpty && !RegExp(r'^\d+$').hasMatch(clean) && !_isTyxDefault(clean, name)) return clean;
    }

    return null;
  }

  /// Get branch format / prefix (e.g. TYX, MBX, TVR)
  String get branchFormat {
    final configured = configuredBranchPrefix;
    if (configured != null && configured.isNotEmpty) return configured;
    // Fall back to deriving from branch name
    return _derivePrefixFromName(branchName ?? '');
  }


  /// Super Admin or Admin: Update prefix directly for a branch
  Future<void> setBranchPrefix(String branchId, String prefix) async {
    final clean = prefix.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    try {
      try {
        await supabase.from('branches').update({
          'format': clean,
          'jobcard_prefix': clean,
        }).eq('id', branchId);
      } catch (_) {
        try {
          await supabase.from('tally_companies').update({
            'company_alias': clean,
          }).eq('id', branchId);
        } catch (_) {}
      }

      if (_activeCompany != null && _activeCompany!['id'].toString() == branchId) {
        _activeCompany!['format'] = clean;
        _activeCompany!['jobcard_prefix'] = clean;
        _persistCompany(_activeCompany!);
      }
      debugPrint('✅ Updated branch prefix to "$clean" for branch $branchId');
    } catch (e) {
      debugPrint('❌ Failed to set branch prefix: $e');
      rethrow;
    }
  }

  /// Get GUID from cached data
  String? get guid => _activeCompany?['Guid'] as String? ?? _activeCompany?['guid'] as String? ?? _activeCompany?['tally_guid'] as String?;

  /// Get branch / company ID from cached data (UUID string or dynamic)
  dynamic get companyId => _activeCompany?['id'] ?? _activeCompany?['branch_id'] ?? _activeCompany?['company_id'];
  String? get branchId => companyId?.toString();

  /// Normalize record from either `branches` or `tally_companies` so all keys work uniformly
  static Map<String, dynamic> normalizeBranchRecord(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    final name = map['branch_name'] ?? map['company_name'] ?? 'Unnamed Branch';
    final code = map['branch_code'] ?? map['company_number'] ?? map['company_alias'];
    final format = map['format'] ?? map['jobcard_prefix'] ?? code;
    
    map['branch_name'] = name;
    map['company_name'] = name;
    if (code != null) {
      map['branch_code'] = code;
      map['company_number'] = code;
    }
    if (format != null) {
      map['format'] = format.toString().trim().toUpperCase();
      map['jobcard_prefix'] = format.toString().trim().toUpperCase();
    }
    return map;
  }

  /// Generate a unique sequential Job Card ID based on branch format and year
  /// Example: TYX2026001, MBX2026001, TVR2026001...
  Future<String> generateJobCardId({String? overrideBranchId}) async {
    String? bId = overrideBranchId ?? branchId;
    String prefix = 'TYX';

    // If branchId is null (no active company loaded), try to resolve it from persisted user
    if (bId == null) {
      debugPrint('⚠️ generateJobCardId: branchId is NULL, trying to resolve from persisted user...');
      try {
        // Try loading from SharedPreferences first
        if (!hasActiveCompany) {
          final restored = await loadPersistedCompany();
          if (restored) {
            bId = branchId;
            debugPrint('✅ generateJobCardId: Restored branch from prefs: $branchName (id=$bId)');
          }
        }

        // Still null? Query the current user's branch_id from the database
        if (bId == null) {
          final prefs = await SharedPreferences.getInstance();
          final userJson = prefs.getString('currentUser');
          if (userJson != null) {
            final user = jsonDecode(userJson) as Map<String, dynamic>;
            final userId = user['id'];
            if (userId != null) {
              final freshUser = await supabase
                  .from('users')
                  .select('branch_id')
                  .eq('id', userId)
                  .maybeSingle();
              if (freshUser != null && freshUser['branch_id'] != null) {
                bId = freshUser['branch_id'].toString();
                debugPrint('✅ generateJobCardId: Got branch_id from users table: $bId');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ generateJobCardId: Could not resolve branchId: $e');
      }
    }

    // Query the branch record directly from the database to get the configured prefix
    if (bId != null) {
      try {
        final bRow = await supabase
            .from('branches')
            .select('format, jobcard_prefix, branch_code, company_alias, branch_name')
            .eq('id', bId)
            .maybeSingle();
        if (bRow != null) {
          final bName = (bRow['branch_name'] ?? '').toString();
          // Priority: format → jobcard_prefix → company_alias → branch_code
          final bFmt = bRow['format'] ?? bRow['jobcard_prefix'] ?? bRow['company_alias'] ?? bRow['branch_code'];
          if (bFmt != null && bFmt.toString().trim().isNotEmpty) {
            final clean = bFmt.toString().trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
            if (clean.isNotEmpty) {
              // If clean is 'TYX' but the branch is NOT a real TyreX/Kochi branch,
              // it's just the DB column default — derive from branch name instead
              if (clean == 'TYX' && _isTyxDefault('TYX', bName.toLowerCase())) {
                prefix = _derivePrefixFromName(bName);
              } else {
                prefix = clean;
              }
            }
          } else {
            // No format at all — derive from branch name
            prefix = _derivePrefixFromName(bName);
          }
          debugPrint('🔍 Fresh DB prefix for branch "$bName": $prefix (format=$bFmt)');
        } else {
          // Fallback to tally_companies
          try {
            final cRow = await supabase
                .from('tally_companies')
                .select('company_name, company_alias, company_number')
                .eq('id', bId)
                .maybeSingle();
            if (cRow != null) {
              final cName = (cRow['company_name'] ?? '').toString();
              final cAlias = cRow['company_alias'] ?? cRow['company_number'];
              if (cAlias != null && cAlias.toString().trim().isNotEmpty) {
                prefix = cAlias.toString().trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
              } else {
                prefix = _derivePrefixFromName(cName);
              }
            }
          } catch (_) {}
          debugPrint('⚠️ generateJobCardId: No branch found in branches table for id=$bId, using prefix: $prefix');
        }
      } catch (e) {
        debugPrint('⚠️ Fresh prefix check notice: $e');
      }
    } else {
      debugPrint('⚠️ generateJobCardId: branchId is STILL null after all fallbacks, using TYX');
    }

    final year = DateTime.now().year;
    final searchPattern = '$prefix$year%';

    int nextSeq = 1;
    try {
      final res = await supabase
          .from('reports')
          .select('job_card_id')
          .ilike('job_card_id', searchPattern)
          .order('job_card_id', ascending: false)
          .limit(1);

      if (res.isNotEmpty && res[0]['job_card_id'] != null) {
        final lastId = res[0]['job_card_id'].toString();
        final digitsPart = lastId.replaceFirst(RegExp('^$prefix$year', caseSensitive: false), '');
        final lastSeq = int.tryParse(digitsPart);
        if (lastSeq != null) {
          nextSeq = lastSeq + 1;
        }
      } else {
        if (bId != null) {
          final countRes = await supabase
              .from('reports')
              .select('id')
              .eq('branch_id', bId)
              .count();
          nextSeq = countRes.count + 1;
        }
      }
    } catch (e) {
      debugPrint('ℹ️ Sequence check notice: $e');
      nextSeq = (DateTime.now().millisecondsSinceEpoch % 900) + 100;
    }

    final seqStr = nextSeq.toString().padLeft(3, '0');
    final formattedId = '$prefix$year$seqStr';
    debugPrint('🎫 Generated Job Card ID: $formattedId (branch=$bId, prefix=$prefix)');
    return formattedId;
  }

  /// Fetch and cache the single active branch/company
  Future<void> loadActiveCompany() async {
    if (_isLoading) return;
    
    try {
      _isLoading = true;
      
      // 1. Try from branches table first
      try {
        final response = await supabase
            .from('branches')
            .select('*')
            .eq('is_active', true)
            .limit(1)
            .maybeSingle();
        
        if (response != null) {
          _activeCompany = normalizeBranchRecord(response);
          if (_allocatedCompanies.isEmpty) {
            _allocatedCompanies = [_activeCompany!];
          }
          debugPrint('✅ Active branch loaded: $branchName (ID: $branchId)');
          return;
        }
      } catch (e) {
        debugPrint('ℹ️ branches table load notice: $e, trying tally_companies');
      }

      // 2. Fallback to tally_companies
      final response = await supabase
          .from('tally_companies')
          .select('id, company_name, Guid, company_alias, company_number, is_active')
          .eq('is_active', true)
          .limit(1)
          .single();
      
      _activeCompany = normalizeBranchRecord(response);
      if (_allocatedCompanies.isEmpty) {
        _allocatedCompanies = [_activeCompany!];
      }
      
      debugPrint('✅ Active company loaded: $companyName (ID: $companyId, GUID: $guid)');
    } catch (e) {
      debugPrint('❌ Failed to load active branch/company: $e');
      _activeCompany = null;
    } finally {
      _isLoading = false;
    }
  }

  /// Loads all allocated branches/companies for a user and sets the active branch
  Future<List<Map<String, dynamic>>> loadCompaniesForUser(Map<String, dynamic>? user) async {
    if (user == null) {
      clearCache();
      return [];
    }

    try {
      final role = user['role'] as String?;
      final userId = user['id'];

      // 1. Super Admin gets access to ALL branches/companies
      if (role == AppConstants.roleSuperAdmin) {
        final allBranches = await getAllCompanies();
        _allocatedCompanies = allBranches;
        if (_allocatedCompanies.isNotEmpty) {
          Map<String, dynamic>? candidate;
          if (_activeCompany != null) {
            final match = _allocatedCompanies.firstWhere(
              (c) => c['id']?.toString() == _activeCompany!['id']?.toString(),
              orElse: () => <String, dynamic>{},
            );
            if (match.isNotEmpty) candidate = match;
          }
          if (candidate == null) {
            final prefs = await SharedPreferences.getInstance();
            final stored = prefs.getString('selected_company');
            if (stored != null) {
              try {
                final parsed = jsonDecode(stored) as Map<String, dynamic>;
                final match = _allocatedCompanies.firstWhere(
                  (c) => c['id']?.toString() == parsed['id']?.toString(),
                  orElse: () => <String, dynamic>{},
                );
                if (match.isNotEmpty) candidate = match;
              } catch (_) {}
            }
          }
          _activeCompany = candidate ?? _allocatedCompanies.first;
          _persistCompany(_activeCompany!);
        }
        debugPrint('👑 SuperAdmin: Loaded ${_allocatedCompanies.length} branches/companies (Active: $branchName, Format: $branchFormat)');
        return _allocatedCompanies;
      }

      // 2. Regular user: fetch allocated branches from user_branches junction table first
      List<Map<String, dynamic>> userBranchesList = [];

      try {
        final junctionRes = await supabase
            .from('user_branches')
            .select('branch_id, branches(*)')
            .eq('user_id', userId);

        for (var row in junctionRes as List<dynamic>) {
          if (row['branches'] != null && row['branches'] is Map) {
            userBranchesList.add(normalizeBranchRecord(Map<String, dynamic>.from(row['branches'])));
          }
        }

        // If embedded branches wasn't populated, query branches table by branch_ids
        if (userBranchesList.isEmpty && (junctionRes as List).isNotEmpty) {
          final bIds = junctionRes.map((r) => r['branch_id']?.toString()).whereType<String>().toList();
          if (bIds.isNotEmpty) {
            final bRows = await supabase.from('branches').select('*').inFilter('id', bIds);
            userBranchesList = (bRows as List).map((r) => normalizeBranchRecord(Map<String, dynamic>.from(r))).toList();
          }
        }
      } catch (e) {
        debugPrint('ℹ️ user_branches table query notice: $e');
      }

      // 3. Fallback to user_companies junction table if user_branches empty
      if (userBranchesList.isEmpty) {
        try {
          final junctionRes = await supabase
              .from('user_companies')
              .select('company_id, tally_companies(*)')
              .eq('user_id', userId);

          for (var row in junctionRes as List<dynamic>) {
            if (row['tally_companies'] != null && row['tally_companies'] is Map) {
              userBranchesList.add(normalizeBranchRecord(Map<String, dynamic>.from(row['tally_companies'])));
            }
          }

          if (userBranchesList.isEmpty && (junctionRes as List).isNotEmpty) {
            final cIds = junctionRes.map((r) => r['company_id']?.toString()).whereType<String>().toList();
            if (cIds.isNotEmpty) {
              final cRows = await supabase.from('tally_companies').select('*').inFilter('id', cIds);
              userBranchesList = (cRows as List).map((r) => normalizeBranchRecord(Map<String, dynamic>.from(r))).toList();
            }
          }
        } catch (e) {
          debugPrint('ℹ️ user_companies table query notice: $e');
        }
      }

      // 4. Fallback to allocated_branches or allocated_companies json column
      if (userBranchesList.isEmpty) {
        final rawAlloc = user['allocated_branches'] ?? user['allocated_companies'];
        List<dynamic> allocIds = [];
        if (rawAlloc is String) {
          try { allocIds = jsonDecode(rawAlloc); } catch (_) {}
        } else if (rawAlloc is List) {
          allocIds = rawAlloc;
        }

        if (allocIds.isNotEmpty) {
          try {
            final fetched = await supabase
                .from('branches')
                .select('*')
                .inFilter('id', allocIds);
            userBranchesList = (fetched as List).map((r) => normalizeBranchRecord(Map<String, dynamic>.from(r))).toList();
          } catch (_) {
            try {
              final fetched = await supabase
                  .from('tally_companies')
                  .select('id, company_name, Guid, company_alias, company_number, is_active')
                  .inFilter('id', allocIds);
              userBranchesList = (fetched as List).map((r) => normalizeBranchRecord(Map<String, dynamic>.from(r))).toList();
            } catch (_) {}
          }
        }
      }

      // 5. Fallback to user's branch_id / company_id / branch_name / company_name
      if (userBranchesList.isEmpty) {
        final uBranchId = user['branch_id'] ?? user['company_id'];
        final uBranchName = user['branch_name'] ?? user['company_name'] as String?;

        if (uBranchId != null) {
          try {
            final res = await supabase.from('branches').select('*').eq('id', uBranchId).maybeSingle();
            if (res != null) userBranchesList.add(normalizeBranchRecord(res));
          } catch (_) {
            try {
              final res = await supabase.from('tally_companies').select('*').eq('id', uBranchId).maybeSingle();
              if (res != null) userBranchesList.add(normalizeBranchRecord(res));
            } catch (_) {}
          }
        } else if (uBranchName != null && uBranchName.isNotEmpty) {
          try {
            final res = await supabase.from('branches').select('*').eq('branch_name', uBranchName).maybeSingle();
            if (res != null) userBranchesList.add(normalizeBranchRecord(res));
          } catch (_) {
            try {
              final res = await supabase.from('tally_companies').select('*').eq('company_name', uBranchName).maybeSingle();
              if (res != null) userBranchesList.add(normalizeBranchRecord(res));
            } catch (_) {}
          }
        }
      }

      _allocatedCompanies = userBranchesList;

      // Set active branch/company
      if (_allocatedCompanies.isNotEmpty) {
        Map<String, dynamic>? candidate;
        
        // Priority 1: In-memory active company if already set and still valid
        if (_activeCompany != null) {
          final currentId = _activeCompany!['id']?.toString();
          final match = _allocatedCompanies.firstWhere(
            (c) => c['id']?.toString() == currentId,
            orElse: () => <String, dynamic>{},
          );
          if (match.isNotEmpty) candidate = match;
        }

        // Priority 2: Stored preference from SharedPreferences if valid
        if (candidate == null) {
          final prefs = await SharedPreferences.getInstance();
          final stored = prefs.getString('selected_company');
          if (stored != null) {
            try {
              final parsed = jsonDecode(stored) as Map<String, dynamic>;
              final storedId = parsed['id']?.toString();
              final match = _allocatedCompanies.firstWhere(
                (c) => c['id']?.toString() == storedId,
                orElse: () => <String, dynamic>{},
              );
              if (match.isNotEmpty) candidate = match;
            } catch (_) {}
          }
        }

        // Priority 3: Fallback to user's primary branch_id / branch_name from user profile (initial login)
        if (candidate == null) {
          final uBranchId = user['branch_id']?.toString() ?? user['company_id']?.toString();
          final uBranchName = user['branch_name']?.toString() ?? user['company_name']?.toString();
          
          if (uBranchId != null && uBranchId.isNotEmpty) {
            final matchPrimary = _allocatedCompanies.firstWhere(
              (c) => c['id']?.toString() == uBranchId,
              orElse: () => <String, dynamic>{},
            );
            if (matchPrimary.isNotEmpty) candidate = matchPrimary;
          }
          
          if (candidate == null && uBranchName != null && uBranchName.isNotEmpty) {
            final matchPrimary = _allocatedCompanies.firstWhere(
              (c) => (c['branch_name'] ?? c['company_name']).toString().toLowerCase() == uBranchName.toLowerCase(),
              orElse: () => <String, dynamic>{},
            );
            if (matchPrimary.isNotEmpty) candidate = matchPrimary;
          }
        }

        _activeCompany = candidate ?? _allocatedCompanies.first;
        _persistCompany(_activeCompany!);
        debugPrint('🏢 Loaded ${_allocatedCompanies.length} branches for user (Active: $branchName, Format: $branchFormat)');
      } else {
        _activeCompany = null;
        debugPrint('⚠️ User has NO branches allocated (access restricted)');
      }

      return _allocatedCompanies;
    } catch (e) {
      debugPrint('❌ Error loading branches/companies for user: $e');
      return [];
    }
  }

  /// Manually switch the active branch/company (used by Branch/CompanySwitcher badge)
  void setActiveCompany(Map<String, dynamic> company) {
    _activeCompany = normalizeBranchRecord(company);
    debugPrint('✅ Branch switched to: $branchName (ID: $branchId, GUID: $guid)');
    _persistCompany(_activeCompany!);
  }

  Future<void> _persistCompany(Map<String, dynamic> company) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_company', jsonEncode(company));
    } catch (e) {
      debugPrint('⚠️ Failed to persist branch: $e');
    }
  }

  /// Load the persisted branch/company from SharedPreferences
  Future<bool> loadPersistedCompany() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('selected_company');
      if (stored != null) {
        _activeCompany = normalizeBranchRecord(jsonDecode(stored) as Map<String, dynamic>);
        debugPrint('✅ Branch restored from prefs: $branchName (ID: $branchId, GUID: $guid)');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load persisted branch: $e');
    }
    return false;
  }

  /// Add branch_id, branch_name, Guid, and company fields to any data map for insert operations
  Map<String, dynamic> addCompanyFields(Map<String, dynamic> data, {String? tableName}) {
    if (_activeCompany == null) {
      debugPrint('⚠️ No active branch loaded - cannot add branch/company fields');
      return data;
    }

    final result = Map<String, dynamic>.from(data);
    
    final tablesWithBranchFields = {
      'reports', 'bookings', 'service_reminders', 'users', 'payments'
    };
    
    // 1. Primary branch fields (only for tables that actually have branch_id / branch_name)
    if (tableName == null || tablesWithBranchFields.contains(tableName)) {
      if (!result.containsKey('branch_id') && branchId != null) {
        result['branch_id'] = branchId;
      }

      if (!result.containsKey('branch_name') && branchName != null) {
        result['branch_name'] = branchName;
      }
    }

    // 2. Branch GUID (Only attach to tables known to have Guid column in database)
    final tablesWithGuid = {'reports', 'owner_master', 'vehicles', 'vehicle_models', 'branches', 'payments'};
    if ((tableName == null || tablesWithGuid.contains(tableName)) && !result.containsKey('Guid') && guid != null && guid!.isNotEmpty) {
      result['Guid'] = guid;
    }

    // 3. Backward compatibility company fields (Only for tables known to support them)
    final tablesWithLegacyCompany = {'reports', 'bookings', 'payments'};
    if (tableName == null || tablesWithLegacyCompany.contains(tableName)) {
      if (!result.containsKey('company_id') && companyId != null) {
        result['company_id'] = companyId;
      }

      if (!result.containsKey('company_name') && companyName != null) {
        result['company_name'] = companyName;
      }
    }
    
    debugPrint('✅ Added branch/company fields for ${tableName ?? "record"}: branch_id=${result["branch_id"]}, branch_name=${result["branch_name"]}, Guid=${result["Guid"]}');

    return result;
  }

  /// Fetch all branches from branches table (or fallback to tally_companies)
  Future<List<Map<String, dynamic>>> getAllCompanies() async {
    try {
      // Try branches table first
      try {
        final response = await supabase
            .from('branches')
            .select('*')
            .order('branch_name');
        
        final list = (response as List).map((r) => normalizeBranchRecord(Map<String, dynamic>.from(r))).toList();
        if (list.isNotEmpty) return list;
      } catch (e) {
        debugPrint('ℹ️ branches query notice: $e, checking tally_companies');
      }

      // Fallback to tally_companies
      final response = await supabase
          .from('tally_companies')
          .select('*')
          .order('company_name');
      
      return (response as List).map((r) => normalizeBranchRecord(Map<String, dynamic>.from(r))).toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch all branches/companies: $e');
      return [];
    }
  }

  /// Fetch active branches
  Future<List<Map<String, dynamic>>> getActiveCompanies() async {
    return getAllCompanies();
  }

  /// Helper to filter payload for the branches table
  Map<String, dynamic> _cleanBranchPayload(Map<String, dynamic> data) {
    final clean = <String, dynamic>{};
    final allowedFields = {
      'branch_name',
      'branch_code',
      'format',
      'jobcard_prefix',
      'Guid',
      'company_alias',
      'address_line1',
      'address_line2',
      'city',
      'state',
      'pin_code',
      'country',
      'phone_number',
      'email',
      'gst_number',
      'is_active',
      'tally_company_id',
      'tally_company',
      'tally_guid',
      'company_number',
    };

    final branchName = data['branch_name'] ?? data['company_name'];
    if (branchName != null) clean['branch_name'] = branchName;

    final branchCode = data['branch_code'] ?? data['company_number'];
    if (branchCode != null) clean['branch_code'] = branchCode;

    final format = data['format'] ?? data['jobcard_prefix'] ?? data['company_alias'];
    if (format != null) {
      clean['format'] = format.toString().trim().toUpperCase();
      clean['jobcard_prefix'] = format.toString().trim().toUpperCase();
    }

    for (final key in allowedFields) {
      if (data.containsKey(key) && !clean.containsKey(key)) {
        clean[key] = data[key];
      }
    }
    return clean;
  }

  /// Helper to filter payload for the legacy tally_companies table
  Map<String, dynamic> _cleanTallyCompanyPayload(Map<String, dynamic> data) {
    final clean = <String, dynamic>{};
    final allowedFields = {
      'company_name',
      'company_alias',
      'company_number',
      'company_description',
      'Guid',
      'address_line1',
      'address_line2',
      'city',
      'state',
      'pin_code',
      'country',
      'phone_number',
      'email',
      'gst_number',
      'pan_number',
      'is_active',
    };

    final companyName = data['company_name'] ?? data['branch_name'];
    if (companyName != null) clean['company_name'] = companyName;

    final companyNumber = data['company_number'] ?? data['branch_code'];
    if (companyNumber != null) clean['company_number'] = companyNumber;

    for (final key in allowedFields) {
      if (data.containsKey(key) && !clean.containsKey(key)) {
        clean[key] = data[key];
      }
    }
    return clean;
  }

  /// Super Admin: Create a new branch (writes to branches table)
  Future<Map<String, dynamic>> createCompany(Map<String, dynamic> branchData) async {
    try {
      final branchPayload = _cleanBranchPayload(branchData);

      final response = await supabase
          .from('branches')
          .insert(branchPayload)
          .select()
          .single();
      
      debugPrint('✅ Created branch in branches table: ${response['branch_name']}');

      // Sync to tally_companies with the exact same ID so legacy FK constraints (e.g. users_company_id_fkey) are satisfied
      try {
        final tallyPayload = _cleanTallyCompanyPayload(branchData);
        tallyPayload['id'] = response['id'];
        await supabase.from('tally_companies').insert(tallyPayload);
        debugPrint('✅ Synced branch to legacy tally_companies: ${response['id']}');
      } catch (e) {
        debugPrint('ℹ️ Legacy tally_companies sync notice: $e');
      }

      return normalizeBranchRecord(response);
    } catch (e) {
      debugPrint('❌ Error creating branch/company: $e');
      rethrow;
    }
  }

  /// Super Admin: Update an existing branch
  Future<void> updateCompany(String branchId, Map<String, dynamic> branchData) async {
    try {
      final branchPayload = _cleanBranchPayload(branchData);

      try {
        await supabase
            .from('branches')
            .update(branchPayload)
            .eq('id', branchId);
        debugPrint('✅ Updated branch in branches table: $branchId');
      } catch (e) {
        debugPrint('ℹ️ Could not update branches table: $e');
      }

      // Also update tally_companies if record exists there
      try {
        final tallyPayload = _cleanTallyCompanyPayload(branchData);
        await supabase
            .from('tally_companies')
            .update(tallyPayload)
            .eq('id', branchId);
        debugPrint('✅ Updated company in tally_companies table: $branchId');
      } catch (_) {}

      // Update in-memory active branch if this branch is currently active
      if (_activeCompany != null && _activeCompany!['id'].toString() == branchId) {
        _activeCompany = normalizeBranchRecord({..._activeCompany!, ...branchPayload});
        _persistCompany(_activeCompany!);
        debugPrint('✅ Synced active company in memory: ${_activeCompany!['branch_name']} (Prefix: $branchFormat)');
      }
    } catch (e) {
      debugPrint('❌ Error updating branch/company: $e');
      rethrow;
    }
  }

  /// Super Admin: Toggle branch active status
  Future<void> toggleCompanyStatus(String branchId, bool isActive) async {
    try {
      try {
        await supabase
            .from('branches')
            .update({'is_active': isActive})
            .eq('id', branchId);
        debugPrint('✅ Toggled branch $branchId active status to $isActive');
      } catch (_) {}

      try {
        await supabase
            .from('tally_companies')
            .update({'is_active': isActive})
            .eq('id', branchId);
        debugPrint('✅ Toggled company $branchId active status to $isActive');
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ Error toggling branch status: $e');
      rethrow;
    }
  }

  /// Super Admin: Delete a branch
  Future<void> deleteCompany(String branchId) async {
    try {
      // 1. Delete user_branches allocations
      try {
        await supabase.from('user_branches').delete().eq('branch_id', branchId);
      } catch (_) {}
      try {
        await supabase.from('user_companies').delete().eq('company_id', branchId);
      } catch (_) {}

      // 2. Delete branch record from branches & tally_companies
      try {
        await supabase
            .from('branches')
            .delete()
            .eq('id', branchId);
        debugPrint('✅ Deleted branch: $branchId');
      } catch (_) {}

      try {
        await supabase
            .from('tally_companies')
            .delete()
            .eq('id', branchId);
        debugPrint('✅ Deleted company: $branchId');
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ Error deleting branch: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // TALLY COMPANY MASTER & BRANCH ALLOCATION
  // ══════════════════════════════════════════════════════════════

  /// Super Admin: Fetch all Tally Company Masters
  Future<List<Map<String, dynamic>>> getAllTallyCompanyMasters() async {
    try {
      final response = await supabase
          .from('tally_company_master')
          .select('*')
          .order('tally_company_name');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('❌ Error fetching tally_company_master: $e');
      return [];
    }
  }

  /// Super Admin: Create a new Tally Company Master
  Future<Map<String, dynamic>> createTallyCompanyMaster(Map<String, dynamic> data) async {
    try {
      final clean = Map<String, dynamic>.from(data);
      clean.remove('id');
      clean.remove('created_at');
      clean.remove('updated_at');

      final response = await supabase
          .from('tally_company_master')
          .insert(clean)
          .select()
          .single();

      debugPrint('✅ Created tally_company_master: ${response['tally_company_name']} (${response['id']})');
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('❌ Error creating tally_company_master: $e');
      rethrow;
    }
  }

  /// Super Admin: Update an existing Tally Company Master
  Future<Map<String, dynamic>> updateTallyCompanyMaster(String id, Map<String, dynamic> data) async {
    try {
      final clean = Map<String, dynamic>.from(data);
      clean.remove('id');
      clean.remove('created_at');
      clean['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final response = await supabase
          .from('tally_company_master')
          .update(clean)
          .eq('id', id)
          .select()
          .single();

      // If name or guid changed, also sync to allocated branches
      try {
        final tName = response['tally_company_name'] as String?;
        final tGuid = response['tally_guid'] as String?;
        final cNum = response['company_number'] as String?;
        await supabase.from('branches').update({
          'tally_company': tName,
          'tally_guid': tGuid,
          'company_number': cNum,
        }).eq('tally_company_id', id);
      } catch (_) {}

      debugPrint('✅ Updated tally_company_master: $id');
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('❌ Error updating tally_company_master: $e');
      rethrow;
    }
  }

  /// Super Admin: Delete a Tally Company Master (unlinks branches first)
  Future<void> deleteTallyCompanyMaster(String id) async {
    try {
      // 1. Unlink any branches pointing to this tally company master
      try {
        await supabase.from('branches').update({
          'tally_company_id': null,
          'tally_company': null,
          'tally_guid': null,
        }).eq('tally_company_id', id);
        debugPrint('✅ Unlinked branches from tally_company_master: $id');
      } catch (e) {
        debugPrint('⚠️ Notice unlinking branches: $e');
      }

      // 2. Delete the tally company master record
      await supabase.from('tally_company_master').delete().eq('id', id);
      debugPrint('✅ Deleted tally_company_master: $id');
    } catch (e) {
      debugPrint('❌ Error deleting tally_company_master: $e');
      rethrow;
    }
  }

  /// Super Admin: Allocate/link multiple branches to a Tally Company Master
  Future<void> allocateBranchesToTallyCompany({
    required String tallyCompanyMasterId,
    required List<String> branchIds,
    Map<String, dynamic>? tallyCompanyData,
  }) async {
    try {
      // Fetch tally company master details if not provided
      Map<String, dynamic>? master = tallyCompanyData;
      if (master == null) {
        final row = await supabase
            .from('tally_company_master')
            .select('id, tally_company_name, tally_guid, company_number')
            .eq('id', tallyCompanyMasterId)
            .maybeSingle();
        if (row != null) master = Map<String, dynamic>.from(row);
      }

      final tName = master?['tally_company_name'] as String?;
      final tGuid = master?['tally_guid'] as String?;
      final cNum = master?['company_number'] as String?;

      // 1. Unlink branches that were previously allocated to this tally company but are no longer selected
      final existingAllocated = await supabase
          .from('branches')
          .select('id')
          .eq('tally_company_id', tallyCompanyMasterId);

      final List<dynamic> existingList = existingAllocated as List;
      final existingIds = existingList.map((r) => r['id'].toString()).toSet();
      final newSelectedIds = branchIds.toSet();

      final toUnlink = existingIds.difference(newSelectedIds);
      if (toUnlink.isNotEmpty) {
        for (final bId in toUnlink) {
          try {
            await supabase.from('branches').update({
              'tally_company_id': null,
              'tally_company': null,
              'tally_guid': null,
            }).eq('id', bId);
          } catch (_) {}
        }
        debugPrint('✅ Unlinked ${toUnlink.length} branches from tally company $tallyCompanyMasterId');
      }

      // 2. Link all selected branches to this tally company
      if (branchIds.isNotEmpty) {
        for (final bId in branchIds) {
          try {
            await supabase.from('branches').update({
              'tally_company_id': tallyCompanyMasterId,
              'tally_company': tName,
              'tally_guid': tGuid,
              'company_number': cNum,
            }).eq('id', bId);
          } catch (linkErr) {
            // Fallback in case columns are partial
            try {
              await supabase.from('branches').update({
                'tally_company_id': tallyCompanyMasterId,
              }).eq('id', bId);
            } catch (_) {}
          }
        }
        debugPrint('✅ Linked ${branchIds.length} branches to tally company $tallyCompanyMasterId ($tName)');
      }
    } catch (e) {
      debugPrint('❌ Error allocating branches to tally company: $e');
      rethrow;
    }
  }

  /// Get branch IDs currently allocated to a specific Tally Company Master
  Future<List<String>> getBranchIdsForTallyCompany(String tallyCompanyMasterId) async {
    try {
      final rows = await supabase
          .from('branches')
          .select('id')
          .eq('tally_company_id', tallyCompanyMasterId);
      return List<String>.from((rows as List).map((r) => r['id'].toString()));
    } catch (e) {
      debugPrint('ℹ️ Could not query branches for tally company: $e');
      return [];
    }
  }

  /// Fetch branch IDs allocated to a user
  Future<List<String>> getUserCompanyIds(int userId) async {
    try {
      // 1. Try user_branches
      try {
        final rows = await supabase
            .from('user_branches')
            .select('branch_id')
            .eq('user_id', userId);
        
        if (rows.isNotEmpty) {
          return List<String>.from(rows.map((r) => r['branch_id'].toString()));
        }
      } catch (e) {
        debugPrint('ℹ️ user_branches select notice: $e');
      }

      // 2. Fallback to user_companies
      try {
        final rows = await supabase
            .from('user_companies')
            .select('company_id')
            .eq('user_id', userId);
        
        if (rows.isNotEmpty) {
          return List<String>.from(rows.map((r) => r['company_id'].toString()));
        }
      } catch (_) {}

      // 3. Fallback to users table allocated_branches / branch_id
      try {
        final userRow = await supabase
            .from('users')
            .select('branch_id, allocated_branches')
            .eq('id', userId)
            .maybeSingle();

        if (userRow != null) {
          final raw = userRow['allocated_branches'];
          if (raw is List && raw.isNotEmpty) {
            return List<String>.from(raw.map((e) => e.toString()));
          }
          if (userRow['branch_id'] != null) {
            return [userRow['branch_id'].toString()];
          }
        }
      } catch (_) {}

      return [];
    } catch (e) {
      debugPrint('ℹ️ Could not query user branch allocations: $e');
      return [];
    }
  }

  /// Super Admin: Allocate branches to a user
  Future<void> setUserCompanyAllocations(
    int userId, 
    List<String> branchIds, {
    String? primaryCompanyName, 
    dynamic primaryCompanyId,
  }) async {
    try {
      final pId = primaryCompanyId?.toString();
      final pName = primaryCompanyName;

      // 1. Update user record with primary branch and allocated_branches json
      final updateData = <String, dynamic>{
        'allocated_branches': branchIds,
      };
      if (pId != null) {
        updateData['branch_id'] = pId;
      }
      if (pName != null) {
        updateData['branch_name'] = pName;
        updateData['company_name'] = pName;
      }

      try {
        await supabase.from('users').update(updateData).eq('id', userId);
      } catch (e) {
        debugPrint('⚠️ Could not update branch fields in users table: $e');
      }

      // 2. Sync user_branches junction table
      try {
        await supabase.from('user_branches').delete().eq('user_id', userId);

        if (branchIds.isNotEmpty) {
          final inserts = branchIds.map((bId) => {
            'user_id': userId,
            'branch_id': bId,
          }).toList();

          await supabase.from('user_branches').insert(inserts);
        }
      } catch (e) {
        debugPrint('⚠️ user_branches sync notice: $e');
      }

      // 3. Also sync user_companies for backwards compatibility
      try {
        await supabase.from('user_companies').delete().eq('user_id', userId);

        if (branchIds.isNotEmpty) {
          final inserts = branchIds.map((cId) => {
            'user_id': userId,
            'company_id': cId,
          }).toList();

          await supabase.from('user_companies').insert(inserts);
        }
      } catch (e) {
        debugPrint('⚠️ user_companies sync notice: $e');
      }

      debugPrint('✅ Allocated ${branchIds.length} branches to user $userId');
    } catch (e) {
      debugPrint('❌ Error setting user branch allocations: $e');
      rethrow;
    }
  }

  /// Super Admin: Delete a user cleanly by unlinking foreign key references first
  Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      // 1. Delete allocations
      try {
        await supabase.from('user_branches').delete().eq('user_id', userId);
      } catch (_) {}
      try {
        await supabase.from('user_companies').delete().eq('user_id', userId);
      } catch (_) {}

      // 2. Unlink nullable FK references in bookings
      try {
        await supabase.from('bookings').update({'assigned_pudo_id': null}).eq('assigned_pudo_id', userId);
      } catch (_) {}

      // 3. Unlink nullable FK references in reports
      final reportColumns = [
        'created_by_pudo_id',
        'executive_id',
        'inspector_id',
        'feedback_sent_by',
        'billed_by',
        'alignment_tech_id',
        'installation_tech_id',
      ];

      for (var col in reportColumns) {
        try {
          await supabase.from('reports').update({col: null}).eq(col, userId);
        } catch (_) {}
      }

      // 4. Try hard delete from users table
      try {
        await supabase.from('users').delete().eq('id', userId);
        debugPrint('✅ User $userId permanently deleted from users table');
        return {'hardDeleted': true, 'message': 'User deleted successfully.'};
      } catch (deleteError) {
        debugPrint('⚠️ Hard delete constraint: $deleteError, soft-deactivating user');
        
        // 5. Fallback: Deactivate user
        await supabase.from('users').update({
          'is_active': false,
          'branch_name': null,
          'company_name': null,
          'allocated_branches': [],
          'allocated_companies': [],
        }).eq('id', userId);

        return {'hardDeleted': false, 'message': 'User has historical records; account was deactivated.'};
      }
    } catch (e) {
      debugPrint('❌ Error in deleteUser: $e');
      rethrow;
    }
  }

  /// Clear cached branch/company data (for logout)
  void clearCache() {
    _activeCompany = null;
    _allocatedCompanies = [];
    debugPrint('🗑️ Branch/Company cache cleared');
    SharedPreferences.getInstance().then((prefs) => prefs.remove('selected_company'));
  }
}
