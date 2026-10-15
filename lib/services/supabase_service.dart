// lib/services/supabase_service.dart (Improved Version)
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/admin_setting_model.dart';
import '../utils/vehicle_number_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_exceptions.dart';
import '../utils/app_constants.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'company_service.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetches a single vehicle's details by its vehicle number.
  /// Includes the latest odometer reading from the most recent report.
  Future<Map<String, dynamic>?> searchVehicle(String vehicleNumber, {String? companyName}) async {
    try {
      // Normalize and generate candidate variations for lookup
      final candidates = VehicleNumberUtils.generateSearchCandidates(vehicleNumber);

      // First, find the vehicle and its model information
      var vehicleQuery = _client
          .from('vehicles')
          .select('*, vehicle_models!inner(brand, "Model name"), owner_id');

      // Apply company filter if company is specified
      if (companyName != null && companyName.isNotEmpty) {
        vehicleQuery = vehicleQuery.eq('company_name', companyName);
      }

      PostgrestFilterBuilder? filtered;
      if (candidates.length == 1) {
        filtered = vehicleQuery.eq('"Vehicle Number"', candidates.first);
      } else {
        final orFilter = candidates.map((c) => '"Vehicle Number".eq.$c').join(',');
        filtered = vehicleQuery.or(orFilter);
      }

      final vehicleResponse = await filtered.maybeSingle();

      if (vehicleResponse == null) {
        // Fallback: Check if vehicle registration exists in tally_ledgers
        return await searchTallyLedgerVehicle(vehicleNumber);
      }

      // After finding the vehicle, get its most recent report to find the last odometer reading
      var reportQuery = _client
          .from('reports')
          .select('odometer_reading, client_phone, "Owner name"') // ✅ Fetch client details too
          .eq('vehicle_id', vehicleResponse['id']);
      
      // Apply company filter to reports as well
      if (companyName != null && companyName.isNotEmpty) {
        reportQuery = reportQuery.eq('company_name', companyName);
      }
      
      final latestReport = await reportQuery
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // Fetch owner details from owner_master table if available
      Map<String, dynamic>? ownerDetails;
      
      // First try to get owner details via owner_id if it exists
      if (vehicleResponse['owner_id'] != null) {
        var ownerQuery = _client
            .from('owner_master')
            .select('id, "Owner name", "PhoneNumber", "MobileNumber", "Address Line1", "Address Line2", "Address Line3", state, country, pincode, email')
            .eq('id', vehicleResponse['owner_id']);
        
        // Apply company filter to owner_master as well
        if (companyName != null && companyName.isNotEmpty) {
          ownerQuery = ownerQuery.eq('company_name', companyName);
        }
        
        ownerDetails = await ownerQuery.maybeSingle();
      }
      
      // If no owner_id or no owner found, try by MobileNumber
      if (ownerDetails == null) {
        final mobileNumber = latestReport?['client_phone'] ?? vehicleResponse['MobileNumber'];
        if (mobileNumber != null && mobileNumber.isNotEmpty) {
          var ownerQuery = _client
              .from('owner_master')
              .select('id, "Owner name", "PhoneNumber", "MobileNumber", "Address Line1", "Address Line2", "Address Line3", state, country, pincode, email')
              .eq('MobileNumber', mobileNumber);
          
          // Apply company filter to owner_master as well
          if (companyName != null && companyName.isNotEmpty) {
            ownerQuery = ownerQuery.eq('company_name', companyName);
          }
          
          ownerDetails = await ownerQuery.maybeSingle();
        }
      }

      // Prioritize details from the latest report if available
      final latestOdometer = latestReport?['odometer_reading'] ?? vehicleResponse['odometer'];
      final latestClientPhone = latestReport?['client_phone'] ?? vehicleResponse['MobileNumber'];
      final latestClientName = latestReport?['Owner name'] ?? vehicleResponse['Owner name'];

      // Add/Overwrite details in the response map
      vehicleResponse['latest_odometer'] = latestOdometer;
      vehicleResponse['latest_client_phone'] = latestClientPhone; // Use a distinct key
      vehicleResponse['latest_client_name'] = latestClientName; // Client name from latest report
      vehicleResponse['owner_details'] = ownerDetails; // Add owner details

      return vehicleResponse;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error searching vehicle: ${e.message}');
      }
      throw FileStorageException(
        'Failed to search vehicle: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error searching vehicle: $e');
      }
      return null;
    }
  }

  /// Searches for a vehicle registration number in tally_ledgers table
  /// (Tally stores vehicle model in address lines and customer name/phone in name/mobile)
  Future<Map<String, dynamic>?> searchTallyLedgerVehicle(String vehicleNumber) async {
    try {
      final normalized = VehicleNumberUtils.normalize(vehicleNumber);
      if (normalized.length < 4) return null;

      // Extract parts (e.g. State: KL, District: 58, Series: AL, Number: 9696)
      final regExp = RegExp(r'^([A-Z]{2})(\d{1,2})([A-Z]{1,2})?(\d{1,4})$');
      final match = regExp.firstMatch(normalized);

      final searchTerms = <String>{};
      searchTerms.add(normalized);
      searchTerms.add(VehicleNumberUtils.formatForDisplay(normalized));

      if (match != null) {
        final state = match.group(1)!;
        final district = match.group(2)!;
        final series = match.group(3) ?? '';
        final number = match.group(4)!;

        // Space variations
        searchTerms.add('$state $district $series $number'.replaceAll(RegExp(r'\s+'), ' ').trim());
        searchTerms.add('$state$district $series $number'.replaceAll(RegExp(r'\s+'), ' ').trim());
        searchTerms.add('$state $district$series $number'.replaceAll(RegExp(r'\s+'), ' ').trim());
        searchTerms.add('$state$district$series $number'.replaceAll(RegExp(r'\s+'), ' ').trim());
        searchTerms.add('$state $district $series$number'.replaceAll(RegExp(r'\s+'), ' ').trim());
        
        // Without leading zero in district code
        final unpaddedDistrict = district.replaceFirst(RegExp(r'^0'), '');
        if (unpaddedDistrict != district) {
          searchTerms.add('$state $unpaddedDistrict $series $number'.replaceAll(RegExp(r'\s+'), ' ').trim());
          searchTerms.add('$state$unpaddedDistrict $series $number'.replaceAll(RegExp(r'\s+'), ' ').trim());
          searchTerms.add('$state$unpaddedDistrict$series$number');
          searchTerms.add('$state $unpaddedDistrict$series $number'.replaceAll(RegExp(r'\s+'), ' ').trim());
        }
      }

      final orClauses = <String>[];
      for (final term in searchTerms) {
        if (term.isEmpty) continue;
        orClauses.add('address_line1.ilike.%$term%');
        orClauses.add('address_line2.ilike.%$term%');
        orClauses.add('address_line3.ilike.%$term%');
        orClauses.add('name.ilike.%$term%');
      }

      if (orClauses.isEmpty) return null;

      final res = await _client
          .from('tally_ledgers')
          .select()
          .or(orClauses.join(','))
          .limit(10);

      if (res.isEmpty) return null;

      // Find the best match among rows by normalizing address lines
      Map<String, dynamic>? bestRow;
      String? matchedVehicleLine;

      for (final row in res) {
        for (final field in ['address_line1', 'address_line2', 'address_line3', 'name']) {
          final val = (row[field] ?? '').toString().trim();
          if (val.isEmpty) continue;
          final normVal = VehicleNumberUtils.normalize(val);
          if (normVal == normalized || VehicleNumberUtils.areEqual(normVal, normalized)) {
            bestRow = row;
            matchedVehicleLine = field;
            break;
          }
        }
        if (bestRow != null) break;
      }

      bestRow ??= res.first;

      return _parseTallyLedgerToVehicleResult(bestRow, normalized, matchedVehicleLine);
    } catch (e) {
      if (kDebugMode) print('Error searching tally_ledgers for vehicle: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseTallyLedgerToVehicleResult(
    Map<String, dynamic> row,
    String normalizedVehNo,
    String? matchedVehicleLine,
  ) {
    final addr1 = (row['address_line1'] ?? '').toString().trim();
    final addr2 = (row['address_line2'] ?? '').toString().trim();
    final addr3 = (row['address_line3'] ?? '').toString().trim();

    final allLines = [
      if (addr1.isNotEmpty) addr1,
      if (addr2.isNotEmpty) addr2,
      if (addr3.isNotEmpty) addr3,
    ];

    String detectedModel = '';
    int? detectedOdometer;
    String detectedVehNo = VehicleNumberUtils.formatForDisplay(normalizedVehNo);

    // Identify which line is vehicle number, odometer, or model
    for (final line in allLines) {
      final norm = VehicleNumberUtils.normalize(line);
      final isVehNo = norm == normalizedVehNo ||
          VehicleNumberUtils.areEqual(norm, normalizedVehNo) ||
          RegExp(r'^[A-Z]{2}\d{1,2}[A-Z]{1,2}\d{1,4}$').hasMatch(norm);

      if (isVehNo) {
        detectedVehNo = line;
        continue;
      }

      // Check if this line is an odometer reading (e.g. "41278 KM", "29196KM", "KM-128009", "126849")
      final hasKm = line.toLowerCase().contains('km');
      final isPureDigits = RegExp(r'^\d{4,7}$').hasMatch(line);

      if (hasKm && detectedOdometer == null) {
        final digitsMatch = RegExp(r'(\d{3,7})').firstMatch(line);
        if (digitsMatch != null) {
          detectedOdometer = int.tryParse(digitsMatch.group(1)!);
          continue;
        }
      } else if (isPureDigits && detectedOdometer == null) {
        detectedOdometer = int.tryParse(line);
        continue;
      }

      // Otherwise this line is the vehicle model / description (e.g. "AUDI A4", "MG ZS EV", "MICRA", "POLO", "JAZZ")
      if (detectedModel.isEmpty && !hasKm && !isPureDigits) {
        detectedModel = line;
      }
    }

    // Extract customer name & mobile
    final rawName = (row['name'] ?? row['mailing_name'] ?? '').toString().trim();
    String cleanName = rawName;
    String? phone = (row['phone'] ?? row['mobile'])?.toString().trim();
    String? mobile = (row['mobile'] ?? row['phone'])?.toString().trim();

    // If name is like "NIHAL 9633333396", extract phone from name if phone is empty or clean up name
    final namePhoneMatch = RegExp(r'^(.+?)\s+(\d{10})$').firstMatch(rawName);
    if (namePhoneMatch != null) {
      cleanName = namePhoneMatch.group(1)!.trim();
      final extractedPhone = namePhoneMatch.group(2)!.trim();
      if (phone == null || phone.isEmpty) phone = extractedPhone;
      if (mobile == null || mobile.isEmpty) mobile = extractedPhone;
    }

    return {
      'id': null, // Not yet in vehicles table
      'from_tally': true,
      'Vehicle Number': detectedVehNo.isNotEmpty ? detectedVehNo : VehicleNumberUtils.formatForDisplay(normalizedVehNo),
      'tally_company': row['tally_company'],
      'tally_company_guid': row['tally_company_guid'],
      'tally_ledger_name': rawName,
      'detected_model': detectedModel,
      'latest_odometer': detectedOdometer,
      'latest_client_name': cleanName.isNotEmpty ? cleanName : rawName,
      'latest_client_phone': phone ?? '',
      'owner_details': {
        'Owner name': cleanName.isNotEmpty ? cleanName : rawName,
        'PhoneNumber': phone ?? '',
        'MobileNumber': mobile ?? '',
        'GST Number': (row['gstin'] ?? '').toString().trim(),
        'Address Line1': addr1,
        'Address Line2': addr2,
        'Address Line3': addr3,
        'state': row['state'],
        'country': row['country'] ?? 'India',
        'pincode': row['pincode'],
        'email': row['email'],
      },
    };
  }

  /// Fetches all vehicle brands and models from the database.
  Future<List<Map<String, dynamic>>> getVehicleModels() async {
    try {
      final response = await _client
          .from('vehicle_models')
          .select('id, brand, "Model name"')
          .order('brand');

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching vehicle models: ${e.message}');
      }
      throw FileStorageException(
        'Failed to load vehicle models',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching vehicle models: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Updates a specific setting in the database using the model.
  Future<void> updateAdminSetting(AdminSettingModel setting) async {
    try {
      await _client
          .from('app_settings')
          .update({'setting_value': setting.toJsonValue()})
          .eq('setting_key', setting.key);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error updating setting ${setting.key}: ${e.message}');
      }
      throw FileStorageException(
        'Failed to update setting',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error updating setting ${setting.key}: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all settings and parses them into AdminSettingModel for the Admin UI.
  /// Uses local cache (SharedPreferences) if network request fails.
  Future<List<AdminSettingModel>> getAdminSettings() async {
    try {
      final response = await _client
          .from('app_settings')
          .select(
              'setting_key, setting_value, label, description, category, display_order, input_type, input_config, default_value, created_at, updated_at')
          .order('display_order', ascending: true);

      // Cache the response as a JSON string
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.cacheKeySettings, jsonEncode(response));

      return (response as List)
          .map((row) => AdminSettingModel.fromSupabase(row))
          .toList();
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching admin settings: ${e.message}');
      }

      // Fallback to cache
      return _getAdminSettingsFromCache();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching admin settings: $e');
      }

      // Fallback to cache
      return _getAdminSettingsFromCache();
    }
  }

  Future<List<AdminSettingModel>> _getAdminSettingsFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(AppConstants.cacheKeySettings);

    if (cached != null) {
      final data = jsonDecode(cached) as List;
      return data
          .map((row) => AdminSettingModel.fromSupabase(row as Map<String, dynamic>))
          .toList();
    }

    throw FileStorageException('Failed to load admin settings and no cache available.');
  }

  Future<void> saveReport(Map<String, dynamic> reportData, {String? companyName}) async {
    try {
      // Auto-fill company fields using the active company
      final dataWithCompany = CompanyService().addCompanyFields(reportData, tableName: 'reports');
      await _client.from('reports').insert(dataWithCompany);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error saving report: ${e.message}');
      }
      throw FileStorageException(
        'Failed to save the job card',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error saving report: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getAllReportsForUser(int userId, {dynamic companyId, String? companyName, String? guid}) async {
    final activeBranchId = CompanyService().branchId ?? companyId?.toString();
    final activeBranchName = CompanyService().branchName ?? companyName;
    debugPrint('🔵 Supabase: Fetching reports for user $userId (branchId: $activeBranchId, branchName: $activeBranchName, guid: $guid)');
    try {
      var query = _client
          .from('reports')
          .select('''
            id, vehicle_id, job_card_id, created_at, started_at, completed_at, status, complaint, suggested, approved,
            client_phone, odometer_reading, "Owner name",
            customer_feedback_text, customer_feedback_audio,
            marks, gdrive_folder_url, booking_id, created_by_pudo_id,
            inspection_remarks, barcode, photo_urls, after_photo_urls,
            branch_id, branch_name, company_id, company_name, "Guid",
            billing_status, tally_sync_status, tally_synced_at, is_converted,
            vehicles!reports_vehicle_fk(
              id, "Guid", "Vehicle Number", vehicle_name, "Color", "Engine Number", "Chasis Number",
              vehicle_models!inner(brand, "Model name")
            ),
            executive:executive_id(username),
            created_by_pudo:created_by_pudo_id(username)
          ''')
          .eq('executive_id', userId);
      
      // Apply comprehensive branch/company filter
      final filterConditions = <String>[];
      if (activeBranchId != null && activeBranchId.isNotEmpty) {
        filterConditions.add('branch_id.eq.$activeBranchId');
        filterConditions.add('company_id.eq.$activeBranchId');
      }
      if (guid != null && guid.isNotEmpty) filterConditions.add('Guid.eq.$guid');
      if (activeBranchName != null && activeBranchName.isNotEmpty) {
        filterConditions.add('branch_name.eq."$activeBranchName"');
        filterConditions.add('company_name.eq."$activeBranchName"');
      }

      if (filterConditions.isNotEmpty) {
        query = query.or(filterConditions.join(','));
      }
      
      final response = await query.order('created_at', ascending: false).limit(150);

      debugPrint('✅ Supabase returned ${response.length} reports');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('❌ Supabase error: $e');
      if (kDebugMode) {
        print('Supabase error fetching reports: ${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching all reports for user: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getAllCompanyReports({dynamic companyId, String? companyName, String? guid}) async {
    final activeBranchId = CompanyService().branchId ?? companyId?.toString();
    final activeBranchName = CompanyService().branchName ?? companyName;
    debugPrint('🔵 Supabase: Fetching all reports for branch: $activeBranchName (branchId: $activeBranchId, guid: $guid)');
    try {
      var query = _client
          .from('reports')
          .select('''
            id, vehicle_id, job_card_id, created_at, started_at, completed_at, status, complaint, suggested, approved,
            client_phone, odometer_reading, "Owner name",
            customer_feedback_text, customer_feedback_audio,
            marks, gdrive_folder_url, booking_id, created_by_pudo_id,
            inspection_remarks, barcode, photo_urls, after_photo_urls,
            branch_id, branch_name, company_id, company_name, "Guid",
            billing_status, tally_sync_status, tally_synced_at, is_converted,
            vehicles!reports_vehicle_fk(
              id, "Guid", "Vehicle Number", vehicle_name, "Color", "Engine Number", "Chasis Number",
              vehicle_models(brand, "Model name")
            ),
            executive:executive_id(username),
            created_by_pudo:created_by_pudo_id(username)
          ''');
      
      final filterConditions = <String>[];
      if (activeBranchId != null && activeBranchId.isNotEmpty) {
        filterConditions.add('branch_id.eq.$activeBranchId');
        filterConditions.add('company_id.eq.$activeBranchId');
      }
      if (guid != null && guid.isNotEmpty) filterConditions.add('Guid.eq.$guid');
      if (activeBranchName != null && activeBranchName.isNotEmpty) {
        filterConditions.add('branch_name.eq."$activeBranchName"');
        filterConditions.add('company_name.eq."$activeBranchName"');
      }

      // If no active branch filter is present, fallback to all allocated branches
      if (filterConditions.isEmpty) {
        final allocated = CompanyService().allocatedCompanies;
        for (final b in allocated) {
          final bId = (b['id'] ?? b['branch_id'])?.toString();
          final bName = (b['branch_name'] ?? b['company_name'])?.toString();
          final bGuid = (b['Guid'] ?? b['guid'])?.toString();
          if (bId != null && bId.isNotEmpty) {
            filterConditions.add('branch_id.eq.$bId');
            filterConditions.add('company_id.eq.$bId');
          }
          if (bGuid != null && bGuid.isNotEmpty) filterConditions.add('Guid.eq.$bGuid');
          if (bName != null && bName.isNotEmpty) {
            filterConditions.add('branch_name.eq."$bName"');
            filterConditions.add('company_name.eq."$bName"');
          }
        }
      }

      if (filterConditions.isNotEmpty) {
        query = query.or(filterConditions.toSet().join(','));
      }
      
      final response = await query.order('created_at', ascending: false).limit(200);

      debugPrint('✅ Supabase returned ${response.length} company reports');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('❌ Supabase error: $e');
      if (kDebugMode) {
        print('Supabase error fetching company reports: ${e.message}');
      }
      rethrow;
    } catch (e) {
      debugPrint('❌ Supabase exception: $e');
      if (kDebugMode) {
        print('Error fetching company reports: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all reports that have not been assigned to an executive yet.
  Future<List<Map<String, dynamic>>> getUnassignedReports({dynamic companyId, String? companyName, String? guid}) async {
    final activeBranchId = CompanyService().branchId ?? companyId?.toString();
    final activeBranchName = CompanyService().branchName ?? companyName;
    try {
      var query = _client
          .from('reports')
          .select('''
          id, vehicle_id, job_card_id, created_at, started_at, completed_at, status, complaint,
          client_phone, odometer_reading, "Owner name", barcode, photo_urls, after_photo_urls,
          branch_id, branch_name, company_id, company_name, "Guid",
          billing_status, tally_sync_status, tally_synced_at, is_converted,
          vehicles!reports_vehicle_fk(
            id, "Guid", "Vehicle Number", vehicle_name,
            vehicle_models!inner(brand, "Model name")
          )
        ''')
          .filter('executive_id', 'is', null)
          .filter('created_by_pudo_id', 'is', null);

      final filterConditions = <String>[];
      if (activeBranchId != null && activeBranchId.isNotEmpty) {
        filterConditions.add('branch_id.eq.$activeBranchId');
        filterConditions.add('company_id.eq.$activeBranchId');
      }
      if (guid != null && guid.isNotEmpty) filterConditions.add('Guid.eq.$guid');
      if (activeBranchName != null && activeBranchName.isNotEmpty) {
        filterConditions.add('branch_name.eq."$activeBranchName"');
        filterConditions.add('company_name.eq."$activeBranchName"');
      }

      if (filterConditions.isNotEmpty) {
        query = query.or(filterConditions.join(','));
      }

      final response = await query.order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching unassigned reports: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch unassigned reports',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching unassigned reports: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Assigns a job to an executive by updating the executive_id.
// FIX: Change executiveId parameter from String to int
  Future<void> claimJob(int reportId, int executiveId) async {
    try {
      // // --- ADD DEBUG PRINTS ---
      // if (kDebugMode) {
      //   print('--- SupabaseService.claimJob ---');
      //   print('reportId: $reportId (Type: ${reportId.runtimeType})');
      //   print('executiveId: $executiveId (Type: ${executiveId.runtimeType})');
      //   print('-------------------------------');
      // }
      // // --- END DEBUG PRINTS ---
      await _client
          .from('reports')
      // The update now correctly uses an integer
          .update({'executive_id': executiveId})
          .eq('id', reportId);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error claiming job: ${e.message}');
      }
      throw FileStorageException(
        'Failed to claim job',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error claiming job: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }


  // --- Tele-caller Functions ---

  /// Creates a new booking entry.
  Future<void> createBooking(Map<String, dynamic> bookingData, {String? companyName}) async {
    try {
      // bookings table doesn't have company fields, use data as-is
      final dataWithCompany = bookingData;
      await _client.from('bookings').insert(dataWithCompany);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error creating booking: ${e.message}');
      }
      throw FileStorageException(
        'Failed to create booking',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error creating booking: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all bookings that are not yet completed.
  Future<List<Map<String, dynamic>>> getOpenBookings() async {
    try {
      var query = _client.from('bookings').select('*, assigned_pudo:assigned_pudo_id(username)').neq('status', AppConstants.statusCompleted);
      final companyName = CompanyService().companyName;
      if (companyName != null && companyName.isNotEmpty) {
        query = query.eq('company_name', companyName);
      }
      final response = await query.order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching open bookings: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch open bookings',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching open bookings: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all users with the 'pickup_dropoff' role.
  Future<List<Map<String, dynamic>>> getPudoUsers() async {
    try {
      final response = await _client
          .from('users')
          .select('id, username')
          .eq('role', AppConstants.rolePickupDropoff);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching PUDO users: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch PUDO users',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching PUDO users: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Assigns a booking to a specific pickup/drop-off user.
  // ✅ FIX: Change pudoId parameter from String to int
  Future<void> assignBooking(int bookingId, int pudoId) async {
    try {
      await _client
          .from('bookings')
          // The update now correctly uses an integer
          .update({'assigned_pudo_id': pudoId, 'status': 'Assigned'})
          .eq('id', bookingId);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error assigning booking: ${e.message}');
      }
      throw FileStorageException(
        'Failed to assign booking',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error assigning booking: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all users with the 'executive' role.
  Future<List<Map<String, dynamic>>> getExecutiveUsers() async {
    try {
      final response = await _client
          .from('users')
          .select('id, username')
          .eq('role', AppConstants.roleExecutive);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching executive users: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch executive users',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching executive users: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }
  /// Fetches users by a specific role.
  Future<List<Map<String, dynamic>>> getTechniciansByRole(String role) async {
    try {
      final response = await _client
          .from('users')
          .select('id, username')
          .eq('role', role);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching technicians for role $role: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch technicians for role $role',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching technicians for role $role: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all technicians across all tech roles.
  Future<List<Map<String, dynamic>>> getAllTechnicians() async {
    try {
      final response = await _client
          .from('users')
          .select('id, username, role')
          .inFilter('role', AppConstants.techRoles);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching all technicians: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch all technicians',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching all technicians: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches each executive and the count of their active jobs.
  Future<List<Map<String, dynamic>>> getExecutiveWorkload() async {
    try {
      final response = await _client.rpc('get_executive_workload');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching executive workload: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch workload',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching executive workload: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches bookings assigned to a specific PUDO user.
  // ✅ FIX: Change pudoId parameter from String to int
  Future<List<Map<String, dynamic>>> getAssignedPickups(int pudoId) async {
    try {
      final response = await _client
          .from('bookings')
          .select()
          .eq('assigned_pudo_id', pudoId) // Correctly uses int
          .neq('status', AppConstants.statusCompleted)
          .neq('status', 'Job Card Created') // Exclude pickups where job card has been created
          .order('scheduled_time', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching assigned pickups: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch assigned pickups',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching assigned pickups: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Get jobs created by a PUDO user
  Future<List<Map<String, dynamic>>> getJobsCreatedByPudo(int pudoId) async { // ✅ int, not String
    try {
      final response = await _client
          .from('reports')
          .select('''
          *,
          vehicles!reports_vehicle_fk(
            "Guid", "Vehicle Number",
            vehicle_name,
            vehicle_models(brand, "Model name")
          ),
          executive:executive_id(username)
        ''')
          .eq('created_by_pudo_id', pudoId) // ✅ Now correctly an int
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching PUDO jobs: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch jobs created by PUDO',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching PUDO jobs: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches each PUDO user and the count of their active bookings.
  Future<List<Map<String, dynamic>>> getPudoWorkload() async {
    try {
      final response = await _client.rpc('get_pudo_workload');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching PUDO workload: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch PUDO workload',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching PUDO workload: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  // ===== SERVICE REMINDER METHODS =====

  /// Creates a service reminder when a job is completed
  Future<void> createServiceReminder(int reportId, {String? companyName}) async {
    try {
      // Get the completed report details (status can be 'Completed' or 'Delivered')
      // Include Owner name so we can populate customer_name in service_reminders
      var reportQuery = _client
          .from('reports')
          .select('''
            id, vehicle_id, "Owner name", client_phone, created_at,
            vehicles!reports_vehicle_fk("Guid", "Vehicle Number", vehicle_models!inner(brand, "Model name"))
          ''')
          .eq('id', reportId);
      
      // Apply company filter if provided
      if (companyName != null && companyName.isNotEmpty) {
        reportQuery = reportQuery.eq('company_name', companyName);
      }
      
      final report = await reportQuery.single();

      // Calculate next service date (1 day from completion - FOR TESTING)
      final completionDate = DateTime.parse(report['created_at']);
      final nextServiceDate = DateTime(
  completionDate.year,
  completionDate.month + 3,
  completionDate.day,
);

      // Create service reminder record
      // service_reminders.customer_name and customer_phone are NOT NULL
      final reminderData = {
        'report_id': reportId,
        'vehicle_id': report['vehicle_id'],
        'customer_name': report['Owner name'] ?? 'Unknown',
        'customer_phone': report['client_phone'] ?? '',
        'vehicle_number': report['vehicles']['Vehicle Number'],
        'vehicle_brand': report['vehicles']['vehicle_models']['brand'],
        'vehicle_model': report['vehicles']['vehicle_models']['Model name'],
        'last_service_date': completionDate.toIso8601String(),
        'next_service_due_date': nextServiceDate.toIso8601String(),
        'follow_up_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      };
      
      // service_reminders table doesn't have company fields, use data as-is
      final dataWithCompany = reminderData;

      if (kDebugMode) {
        print('🔵 Attempting to create service reminder with data: $dataWithCompany');
      }

      await _client.from('service_reminders').insert(dataWithCompany);

      if (kDebugMode) {
        print('✅ Service reminder created for report $reportId');
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('🔴 Supabase error creating service reminder: ${e.message}');
        print('🔴 Error code: ${e.code}');
        print('🔴 Error details: ${e.details}');
      }
      throw FileStorageException(
        'Failed to create service reminder: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('🔴 General error creating service reminder: $e');
        print('🔴 Error type: ${e.runtimeType}');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches service reminders that are due (past next_service_due_date)
  Future<List<Map<String, dynamic>>> getDueServiceReminders() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD format
      
      final response = await _client
          .from('service_reminders')
          .select('''
            id, customer_name, customer_phone, vehicle_number,
            vehicle_brand, vehicle_model, last_service_date,
            next_service_due_date, follow_up_status, notes,
            contacted_at, created_at
          ''')
          .lte('next_service_due_date', today)
          .neq('follow_up_status', 'completed')
          .order('next_service_due_date', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching due service reminders: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch due service reminders',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching due service reminders: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Updates the follow-up status of a service reminder
  Future<void> updateServiceReminderStatus(
    int reminderId,
    String status, {
    String? notes,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'follow_up_status': status,
        'contacted_at': DateTime.now().toIso8601String(),
      };

      if (notes != null && notes.isNotEmpty) {
        updateData['notes'] = notes;
      }

      await _client
          .from('service_reminders')
          .update(updateData)
          .eq('id', reminderId);

      if (kDebugMode) {
        print('✅ Service reminder $reminderId updated to status: $status');
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error updating service reminder: ${e.message}');
      }
      throw FileStorageException(
        'Failed to update service reminder',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error updating service reminder: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Gets all service reminders (for admin/management view)
  Future<List<Map<String, dynamic>>> getAllServiceReminders() async {
    try {
      final response = await _client
          .from('service_reminders')
          .select('''
            id, customer_name, customer_phone, vehicle_number,
            vehicle_brand, vehicle_model, last_service_date,
            next_service_due_date, follow_up_status, notes,
            contacted_at, created_at
          ''')
          .order('next_service_due_date', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching all service reminders: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch all service reminders',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching all service reminders: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches jobs created by PUDO that are awaiting executive assignment
  Future<List<Map<String, dynamic>>> getJobsAwaitingExecutiveAssignment() async {
    try {
      final response = await _client
          .from('reports')
          .select('''
          id, job_card_id, created_at, started_at, completed_at, complaint, client_phone, "Owner name",
          vehicles!reports_vehicle_fk(
            "Guid", "Vehicle Number", vehicle_name,
            vehicle_models!inner(brand, "Model name")
          ),
          created_by_pudo:created_by_pudo_id(username)
        ''')
          .eq('status', AppConstants.statusNotStarted)
          .filter('executive_id', 'is', null)
          .not('created_by_pudo_id', 'is', null)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching jobs awaiting assignment: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch jobs awaiting assignment',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching jobs awaiting assignment: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Assigns a job to an executive by telecaller (changes status from awaiting assignment to not started)
  Future<void> assignJobToExecutive(int reportId, int executiveId) async {
    try {
      await _client
          .from('reports')
          .update({
            'executive_id': executiveId,
            'status': AppConstants.statusNotStarted,
          })
          .eq('id', reportId);
      
      if (kDebugMode) {
        print('✅ Job $reportId assigned to executive $executiveId');
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error assigning job to executive: ${e.message}');
      }
      throw FileStorageException(
        'Failed to assign job to executive',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error assigning job to executive: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Get bookings assigned to a specific executive
  Future<List<Map<String, dynamic>>> getAssignedBookingsForExecutive(int executiveId) async {
    try {
      // First get the executive's username to match against status
      final executiveResponse = await _client
          .from('users')
          .select('username')
          .eq('id', executiveId)
          .single();
      
      final username = executiveResponse['username'] as String;
      
      final response = await _client
          .from('bookings')
          .select('''
            id, customer_name, customer_phone, 
            created_at, status
          ''')
          .like('status', 'Assigned to Executive - $username%')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching assigned bookings: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch assigned bookings',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching assigned bookings: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all active materials from the database
  /// Returns a list of materials organized by category
  Future<List<Map<String, dynamic>>> getAllMaterials() async {
    try {
      final List<Map<String, dynamic>> all = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('materials')
            .select('id, name, category, unit, description')
            .eq('is_active', true)
            .order('category')
            .order('name')
            .range(from, from + pageSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);
        all.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }

      return all;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching materials: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch materials',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching materials: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Searches materials by name (case-insensitive)
  /// Returns matching materials
  Future<List<Map<String, dynamic>>> searchMaterials(String query) async {
    try {
      if (query.isEmpty) {
        return await getAllMaterials();
      }

      final List<Map<String, dynamic>> all = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('materials')
            .select('id, name, category, unit, description')
            .eq('is_active', true)
            .ilike('name', '%$query%')
            .order('category')
            .order('name')
            .range(from, from + pageSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);
        all.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }

      return all;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error searching materials: ${e.message}');
      }
      throw FileStorageException(
        'Failed to search materials',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error searching materials: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches materials by category
  /// Returns materials for the specified category
  Future<List<Map<String, dynamic>>> getMaterialsByCategory(String category) async {
    try {
      final List<Map<String, dynamic>> all = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('materials')
            .select('id, name, category, unit, description')
            .eq('is_active', true)
            .eq('category', category)
            .order('name')
            .range(from, from + pageSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);
        all.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }

      return all;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching materials by category: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch materials by category',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching materials by category: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all unique material categories
  /// Returns a list of category names
  Future<List<String>> getMaterialCategories() async {
    try {
      final categories = <String>{};
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('materials')
            .select('category')
            .eq('is_active', true)
            .order('category')
            .range(from, from + pageSize - 1);

        for (var item in response) {
          final category = item['category'] as String?;
          if (category != null && category.isNotEmpty) {
            categories.add(category);
          }
        }

        if ((response as List).length < pageSize) break;
        from += pageSize;
      }

      return categories.toList();
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching material categories: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch material categories',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching material categories: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches jobs completed 3 or more days ago for feedback collection
  /// Returns a list of completed jobs with customer and vehicle details
  Future<List<Map<String, dynamic>>> getJobsForFeedback() async {
    try {
      // Calculate the date 3 days ago
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final threeDaysAgoIso = threeDaysAgo.toIso8601String();

      final response = await _client
          .from('reports')
          .select('''
            id, 
            client_phone, 
            "Owner name",
            completed_at,
            vehicles!reports_vehicle_fk("Guid", "Vehicle Number", vehicle_models(brand, "Model name"))
          ''')
          .eq('status', 'Completed')
          .lte('completed_at', threeDaysAgoIso)
          .order('completed_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching jobs for feedback: ${e.message}');
      }
      throw FileStorageException(
        'Failed to fetch jobs for feedback',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching jobs for feedback: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Creates or updates an owner in the owner_master table
  /// Returns the owner ID
  Future<String> createOrUpdateOwner(Map<String, dynamic> ownerData, {String? companyName}) async {
    try {
      final cleanOwnerData = Map<String, dynamic>.from(ownerData);
      cleanOwnerData.remove('company_id');
      cleanOwnerData.remove('company_name');
      cleanOwnerData.remove('branch_id');
      cleanOwnerData.remove('branch_name');

      final dataWithCompany = CompanyService().addCompanyFields(cleanOwnerData, tableName: 'owner_master');
      dataWithCompany.remove('company_id');
      dataWithCompany.remove('company_name');
      dataWithCompany.remove('branch_id');
      dataWithCompany.remove('branch_name');

      final mobile = (dataWithCompany['MobileNumber'] as String?)?.trim();
      final phone = (dataWithCompany['PhoneNumber'] as String?)?.trim();

      final String? lookupField;
      final String? lookupValue;
      if (mobile != null && mobile.isNotEmpty) {
        lookupField = 'MobileNumber';
        lookupValue = mobile;
      } else if (phone != null && phone.isNotEmpty) {
        lookupField = 'PhoneNumber';
        lookupValue = phone;
      } else {
        lookupField = null;
        lookupValue = null;
      }

      // Check if owner already exists by phone number
      Map<String, dynamic>? existingOwner;
      if (lookupField != null && lookupValue != null) {
        final ownerQuery = _client
            .from('owner_master')
            .select('id')
            .eq(lookupField, lookupValue);

        existingOwner = await ownerQuery.limit(1).maybeSingle();
      }

      if (existingOwner != null) {
        // Update existing owner
        await _client
            .from('owner_master')
            .update(dataWithCompany)
            .eq('id', existingOwner['id']);
        return existingOwner['id'] as String;
      } else {
        // Insert new owner
        final response = await _client
            .from('owner_master')
            .insert(dataWithCompany)
            .select('id')
            .single();
        return response['id'] as String;
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error creating/updating owner: ${e.message}');
      }
      throw FileStorageException(
        'Failed to create/update owner',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error creating/updating owner: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Updates owner details by owner ID
  Future<void> updateOwner(String ownerId, Map<String, dynamic> ownerData) async {
    try {
      await _client
          .from('owner_master')
          .update(ownerData)
          .eq('id', ownerId);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error updating owner: ${e.message}');
      }
      throw FileStorageException(
        'Failed to update owner',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error updating owner: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Fetches all vehicle brands and models from the database with pagination.
  /// Handles large datasets (22k+ records) by fetching in batches.
  Future<List<Map<String, dynamic>>> getAllVehicleModels() async {
    try {
      final List<Map<String, dynamic>> all = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('vehicle_models')
            .select('id, brand, "Model name"')
            .order('brand')
            .order('"Model name"')
            .range(from, from + pageSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);
        all.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }

      if (kDebugMode) {
        print('✅ Fetched ${all.length} vehicle models');
      }

      return all;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error fetching all vehicle models: ${e.message}');
      }
      throw FileStorageException(
        'Failed to load vehicle models',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching all vehicle models: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Searches vehicle models by brand name starting with a specific letter.
  /// Returns all brands and models starting with the given letter.
  Future<List<Map<String, dynamic>>> searchVehicleModelsByLetter(String letter) async {
    try {
      final List<Map<String, dynamic>> all = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('vehicle_models')
            .select('id, brand, "Model name"')
            .ilike('brand', '$letter%')
            .order('brand')
            .order('"Model name"')
            .range(from, from + pageSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);
        all.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }

      return all;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error searching vehicle models by letter: ${e.message}');
      }
      throw FileStorageException(
        'Failed to search vehicle models',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error searching vehicle models by letter: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }

  /// Searches vehicle models by brand or model name (case-insensitive).
  /// Returns matching vehicle models.
  Future<List<Map<String, dynamic>>> searchVehicleModels(String query) async {
    try {
      if (query.isEmpty) {
        return await getAllVehicleModels();
      }

      final List<Map<String, dynamic>> all = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('vehicle_models')
            .select('id, brand, "Model name"')
            .or('brand.ilike.%$query%,"Model name".ilike.%$query%')
            .order('brand')
            .order('"Model name"')
            .range(from, from + pageSize - 1);

        final batch = List<Map<String, dynamic>>.from(response);
        all.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }

      return all;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('Supabase error searching vehicle models: ${e.message}');
      }
      throw FileStorageException(
        'Failed to search vehicle models',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error searching vehicle models: $e');
      }
      throw ExceptionHandler.handleError(e);
    }
  }
  // ==========================================
  // Storage Methods
  // ==========================================

  Future<String?> uploadJobMedia(Uint8List bytes, String fileName) async {
    try {
      final String path = 'job_photos/$fileName';
      
      Uint8List uploadBytes = bytes;
      // Compress images > 150 KB to reduce storage and egress bandwidth by ~85%
      if (bytes.lengthInBytes > 150 * 1024) {
        try {
          final compressed = await FlutterImageCompress.compressWithList(
            bytes,
            minWidth: 1280,
            minHeight: 1280,
            quality: 75,
            format: CompressFormat.jpeg,
          );
          if (compressed.isNotEmpty && compressed.lengthInBytes < bytes.lengthInBytes) {
            uploadBytes = compressed;
          }
        } catch (e) {
          debugPrint('Image compression skipped: $e');
        }
      }
      
      await _client.storage.from('job_photos').uploadBinary(
        path,
        uploadBytes,
        fileOptions: const FileOptions(
          cacheControl: '31536000, public, immutable',
          upsert: true,
        ),
      );
      
      final String publicUrl = _client.storage.from('job_photos').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading media to Supabase Storage: $e');
      return null;
    }
  }

  // ==========================================
  // Tyre Catalog Methods
  // ==========================================

  Future<List<Map<String, dynamic>>> searchOwners(String query, {int limit = 40}) async {
    try {
      final q = query.trim().replaceAll('%', '').replaceAll(',', ' ');
      final select =
          'id, "Owner name", alias, PhoneNumber, MobileNumber, "GST Number", "Address Line1", state, pincode';
      final byId = <String, Map<String, dynamic>>{};

      Future<void> addRows(dynamic response) async {
        for (final row in List<Map<String, dynamic>>.from(response)) {
          final id = row['id']?.toString();
          if (id != null) byId[id] = row;
        }
      }

      if (q.isEmpty) {
        final response = await _client.from('owner_master').select(select).order('Owner name').limit(limit);
        return List<Map<String, dynamic>>.from(response);
      }

      final byName = await _client
          .from('owner_master')
          .select(select)
          .ilike('Owner name', '%$q%')
          .order('Owner name')
          .limit(limit);
      await addRows(byName);

      final digits = q.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4) {
        final byPhone = await _client
            .from('owner_master')
            .select(select)
            .or('PhoneNumber.ilike.%$digits%,MobileNumber.ilike.%$digits%')
            .limit(limit);
        await addRows(byPhone);
      }

      return byId.values.take(limit).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error searching owners: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTyreCatalog({String? companyName}) async {
    try {
      final List<Map<String, dynamic>> all = [];
      const int pageSize = 1000;
      int from = 0;
      while (true) {
        final response = await _client
            .from('tyre_catalog')
            .select()
            .order('brand')
            .order('model')
            .order('size')
            .range(from, from + pageSize - 1);
        final batch = List<Map<String, dynamic>>.from(response);
        all.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }
      return all;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching tyre catalog: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAlloyCatalog() async {
    try {
      final List<Map<String, dynamic>> all = [];
      
      // 1. Fetch from tally_stock_items for Alloy-Cars / Wheels
      try {
        final tallyAlloys = await _client
            .from('tally_stock_items')
            .select()
            .or('category.ilike.%alloy%,stock_group.ilike.%wheel%,category.ilike.%wheel%,stock_group.ilike.%alloy%')
            .order('name');
        final items = List<Map<String, dynamic>>.from(tallyAlloys);
        all.addAll(items);
      } catch (e) {
        if (kDebugMode) print('Error fetching tally alloy items: $e');
      }

      // 2. Also check alloy_catalog table if present
      try {
        final alloyCatalogRes = await _client
            .from('alloy_catalog')
            .select()
            .order('brand');
        final items = List<Map<String, dynamic>>.from(alloyCatalogRes);
        all.addAll(items);
      } catch (_) {}

      return all;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching alloy catalog: $e');
      }
      return [];
    }
  }

  Future<void> addAlloyCatalogItem(String brand, String model, String size, {double? billingPrice}) async {
    try {
      await _client.from('alloy_catalog').insert({
        'brand': brand,
        'model': model,
        'size': size,
        if (billingPrice != null) 'billing_price': billingPrice,
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error adding alloy catalog item: $e');
      }
    }
  }

  Future<void> addMaterialItem(String name, {String category = 'Custom'}) async {
    try {
      await _client.from('materials').insert({
        'name': name,
        'category': category,
        'unit': 'Nos',
        'is_active': true,
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error adding material: $e');
      }
    }
  }

  Future<void> addTyreCatalogItem(String brand, String model, String size, {String? liSi, double? basicPrice, double? billingPrice}) async {
    try {
      final dataWithCompany = CompanyService().addCompanyFields({
        'brand': brand,
        'model': model,
        'size': size,
        if (liSi != null) 'li_si': liSi,
        if (basicPrice != null) 'basic_price': basicPrice,
        if (billingPrice != null) 'billing_price': billingPrice,
      }, tableName: 'tyre_catalog');
      await _client.from('tyre_catalog').insert(dataWithCompany);
    } catch (e) {
      if (kDebugMode) {
        print('Error adding tyre catalog item: $e');
      }
      rethrow;
    }
  }

  Future<void> updateTyreCatalogItem(int id, String brand, String model, String size, {String? liSi, double? basicPrice, double? billingPrice}) async {
    try {
      await _client.from('tyre_catalog').update({
        'brand': brand,
        'model': model,
        'size': size,
        'li_si': liSi,
        'basic_price': basicPrice,
        'billing_price': billingPrice,
      }).eq('id', id);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating tyre catalog item: $e');
      }
      rethrow;
    }
  }

  Future<void> deleteTyreCatalogItem(int id) async {
    try {
      await _client.from('tyre_catalog').delete().eq('id', id);
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting tyre catalog item: $e');
      }
      rethrow;
    }
  }

  // ==========================================
  // Service Catalog Methods
  // ==========================================

  Future<List<Map<String, dynamic>>> getServiceCatalog() async {
    try {
      final List<Map<String, dynamic>> all = [];
      
      // 1. Fetch from tally_sales_accounts (contains services synced from Tally)
      try {
        final res = await _client
            .from('tally_sales_accounts')
            .select()
            .order('name');
        if (res.isNotEmpty) {
          for (final row in res) {
            final accType = (row['account_type'] ?? '').toString().toLowerCase();
            if (accType == 'group') continue;

            final parentGroup = (row['parent_group'] ?? 'Services').toString().trim();
            // Ensure no customer ledgers / sundry debtors appear in service catalog
            final parentLower = parentGroup.toLowerCase();
            if (parentLower.contains('debtor') || parentLower.contains('creditor') || parentLower.contains('bank') || parentLower.contains('cash')) {
              continue;
            }

            final name = (row['name'] ?? '').toString().trim();
            if (name.isNotEmpty && !all.any((s) => s['name'].toString().toLowerCase() == name.toLowerCase())) {
              all.add({
                'id': row['id'],
                'name': name,
                'category': parentGroup.isNotEmpty ? parentGroup : 'Service Income',
                'default_price': null, // Entered manually by user
                'gst_rate': row['gst_rate'],
                'hsn_code': row['hsn_code'],
                'gst_type_of_supply': row['gst_type_of_supply'],
                'raw': row,
              });
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error fetching tally_sales_accounts: $e');
      }

      // If tally accounts have data, return that!
      if (all.isNotEmpty) {
        return all;
      }

      // 2. Fallback to service_catalog table only if no tally ledgers found
      try {
        final legacy = await _client.from('service_catalog').select().order('name');
        for (final row in legacy) {
          final name = (row['name'] ?? '').toString().trim();
          if (name.isNotEmpty && !all.any((s) => s['name'].toString().toLowerCase() == name.toLowerCase())) {
            all.add(Map<String, dynamic>.from(row));
          }
        }
      } catch (_) {}

      return all;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching service catalog: $e');
      }
      return [];
    }
  }

  /// Fetches Sundry Debtors (customer/party master) from tally_ledgers
  Future<List<Map<String, dynamic>>> getSundryDebtors({String? query, int limit = 50}) async {
    try {
      var q = _client.from('tally_ledgers').select().order('name').limit(limit);
      if (query != null && query.trim().isNotEmpty) {
        q = _client.from('tally_ledgers').select().or('name.ilike.%${query.trim()}%,phone.ilike.%${query.trim()}%,mobile.ilike.%${query.trim()}%').limit(limit);
      }
      final res = await q;
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      if (kDebugMode) print('Error fetching sundry debtors: $e');
      return [];
    }
  }

  Future<void> addServiceCatalogItem(String name, double? defaultPrice) async {
    try {
      final payload = CompanyService().addCompanyFields({
        'name': name,
        'default_price': defaultPrice,
      }, tableName: 'service_catalog');
      await _client.from('service_catalog').insert(payload);
    } catch (e) {
      if (kDebugMode) {
        print('Error adding service catalog item: $e');
      }
      rethrow;
    }
  }

  Future<void> updateServiceCatalogItem(int id, String name, double? defaultPrice) async {
    try {
      await _client.from('service_catalog').update({
        'name': name,
        'default_price': defaultPrice,
      }).eq('id', id);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating service catalog item: $e');
      }
      rethrow;
    }
  }

  Future<void> deleteServiceCatalogItem(int id) async {
    try {
      await _client.from('service_catalog').delete().eq('id', id);
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting service catalog item: $e');
      }
      rethrow;
    }
  }
}