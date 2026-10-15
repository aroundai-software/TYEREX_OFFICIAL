// lib/services/vehicle_service.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_constants.dart';
import '../providers/user_provider.dart';
import 'company_service.dart';

/// Comprehensive service for all vehicle-related operations
/// Company filtering has been removed - operations work across all data
class VehicleService {
  static final VehicleService _instance = VehicleService._internal();
  factory VehicleService() => _instance;
  VehicleService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  /// ===== VEHICLE OPERATIONS =====

  /// Create or update vehicle with auto-filled company fields
  Future<void> createOrUpdateVehicle(BuildContext context, Map<String, dynamic> vehicleData) async {
    // Auto-fill company fields for new vehicles
    final dataWithCompany = CompanyService().addCompanyFields(vehicleData, tableName: 'vehicles');
    final vehicleNumber = (vehicleData['Vehicle Number'] ?? '').toString();

    try {
      // Check if vehicle already exists by vehicle number
      final existingVehicle = await _client
          .from('vehicles')
          .select('id')
          .eq('"Vehicle Number"', vehicleNumber)
          .maybeSingle();

      if (existingVehicle != null) {
        // Update existing vehicle
        final updateData = CompanyService().addCompanyFields(vehicleData, tableName: 'vehicles');
        try {
          await _client
              .from('vehicles')
              .update(updateData)
              .eq('id', existingVehicle['id']);
        } catch (e) {
          if (e.toString().contains('42883') || e.toString().contains('uuid') || e.toString().contains('operator does not exist')) {
            final sanitized = Map<String, dynamic>.from(updateData);
            sanitized.remove('owner_id');
            sanitized.remove('branch_id');
            sanitized.remove('company_id');
            await _client
                .from('vehicles')
                .update(sanitized)
                .eq('id', existingVehicle['id']);
          } else {
            rethrow;
          }
        }
      } else {
        // Insert new vehicle with company fields
        try {
          await _client.from('vehicles').insert(dataWithCompany);
        } catch (e) {
          if (e.toString().contains('42883') || e.toString().contains('uuid') || e.toString().contains('operator does not exist')) {
            final sanitized = Map<String, dynamic>.from(dataWithCompany);
            sanitized.remove('owner_id');
            sanitized.remove('branch_id');
            sanitized.remove('company_id');
            await _client.from('vehicles').insert(sanitized);
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      throw Exception('Failed to create/update vehicle: $e');
    }
  }

  /// Search vehicle without company filtering
  Future<Map<String, dynamic>?> searchVehicle(BuildContext context, String vehicleNumber) async {
    // Company selection has been removed, search across all vehicles
    try {
      final response = await _client
          .from('vehicles')
          .select('*')
          .eq('"Vehicle Number"', vehicleNumber)
          .maybeSingle();

      return response;
    } catch (e) {
      throw Exception('Failed to search vehicle: $e');
    }
  }

  /// Get all vehicles without company filtering
  Future<List<Map<String, dynamic>>> getCompanyVehicles(BuildContext context) async {
    // Company selection has been removed, fetch all vehicles
    try {
      final response = await _client
          .from('vehicles')
          .select('*, vehicle_models(brand, "Model name")')
          .order('"Vehicle Number"');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch vehicles: $e');
    }
  }

  /// ===== REPORT/JOB CARD OPERATIONS =====

  /// Create report with auto-filled branch/company fields and formatted job_card_id
  Future<Map<String, dynamic>> createReport(BuildContext context, Map<String, dynamic> reportData) async {
    // 1. Ensure branch is loaded from user or persisted prefs if not already active
    try {
      if (!CompanyService().hasActiveCompany) {
        final user = Provider.of<UserProvider>(context, listen: false).user;
        if (user != null) {
          await CompanyService().loadCompaniesForUser(user);
        } else {
          await CompanyService().loadPersistedCompany();
        }
      }
    } catch (_) {}

    final payload = Map<String, dynamic>.from(reportData);

    // 2. Auto-generate formatted job_card_id if not present
    if (payload['job_card_id'] == null || payload['job_card_id'].toString().trim().isEmpty) {
      payload['job_card_id'] = await CompanyService().generateJobCardId(overrideBranchId: payload['branch_id']?.toString());
    }

    // 3. Auto-fill branch/company fields for new reports
    final dataWithCompany = CompanyService().addCompanyFields(payload, tableName: 'reports');

    // 4. Prefix is already correctly resolved by generateJobCardId() using the branch's own configured prefix.

    try {
      final response = await _client.from('reports').insert(dataWithCompany).select().single();
      debugPrint('🟢 VehicleService: Report inserted successfully with job_card_id=${response['job_card_id']}');
      return response;
    } catch (e) {
      debugPrint('🔴 VehicleService: Failed to insert report: $e');
      throw Exception('Failed to create report: $e');
    }
  }

  /// Update report without company filtering
  Future<void> updateReport(BuildContext context, int reportId, Map<String, dynamic> updateData) async {
    // Company selection has been removed, proceed without company filtering
    final dataWithCompany = updateData; // Use data as-is without adding company

    try {
      // Update report directly without company validation
      await _client.from('reports').update(dataWithCompany).eq('id', reportId);
    } catch (e) {
      throw Exception('Failed to update report: $e');
    }
  }

  /// Get all reports with active company filtering
  Future<List<Map<String, dynamic>>> getCompanyReports(BuildContext context, {int? executiveId}) async {
    try {
      var query = _client
          .from('reports')
          .select('''
            id, created_at, status, complaint, suggested, approved,
            client_phone, odometer_reading,
            customer_feedback_text, customer_feedback_audio,
            marks, gdrive_folder_url, booking_id, created_by_pudo_id,
            inspection_remarks,
            vehicles!reports_vehicle_fk(
              "Guid", "Vehicle Number", vehicle_name, "Color", "Engine Number", "Chasis Number",
              vehicle_models!inner(brand, "Model name")
            ),
            executive:executive_id(username)
          ''');

      if (executiveId != null) {
        query = query.eq('executive_id', executiveId);
      }

      final companyId = CompanyService().companyId;
      final companyName = CompanyService().companyName;
      final guid = CompanyService().guid;

      final filterConditions = <String>[];
      if (companyId != null) filterConditions.add('company_id.eq.$companyId');
      if (guid != null && guid.isNotEmpty) filterConditions.add('Guid.eq.$guid');
      if (companyName != null && companyName.isNotEmpty) filterConditions.add('company_name.eq."$companyName"');

      if (filterConditions.isNotEmpty) {
        query = query.or(filterConditions.join(','));
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch reports: $e');
    }
  }

  /// ===== OWNER OPERATIONS =====

  /// Create or update owner with auto-filled company fields
  Future<String> createOrUpdateOwner(BuildContext context, Map<String, dynamic> ownerData) async {
    // Sanitize ownerData to ensure nonexistent columns are not passed to owner_master table
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

    try {
      final mobile = (dataWithCompany['MobileNumber'] as String?)?.trim();
      final phone = (dataWithCompany['PhoneNumber'] as String?)?.trim();
      final guid = (dataWithCompany['Guid'] as String?)?.trim();

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
        var ownerQuery = _client
            .from('owner_master')
            .select('id')
            .eq(lookupField, lookupValue);

        if (guid != null && guid.isNotEmpty) {
          ownerQuery = ownerQuery.eq('Guid', guid);
        }

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
        try {
          // Insert new owner with company fields
          final response = await _client
              .from('owner_master')
              .insert(dataWithCompany)
              .select('id')
              .single();
          return response['id'] as String;
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            // Duplicate key — owner already exists but initial lookup missed them.
            // Try multiple fallback strategies to find the existing owner.
            Map<String, dynamic>? fallback;

            // Fallback 1: lookup by phone/mobile without company filter
            if (lookupField != null && lookupValue != null) {
              try {
                fallback = await _client
                    .from('owner_master')
                    .select('id')
                    .eq(lookupField, lookupValue)
                    .limit(1)
                    .maybeSingle();
              } catch (_) {}
            }

            // Fallback 2: lookup by Owner name + Guid
            final ownerName = (dataWithCompany['Owner name'] as String?)?.trim();
            if (fallback == null && ownerName != null && ownerName.isNotEmpty && guid != null && guid.isNotEmpty) {
              try {
                fallback = await _client
                    .from('owner_master')
                    .select('id')
                    .eq('Owner name', ownerName)
                    .eq('Guid', guid)
                    .limit(1)
                    .maybeSingle();
              } catch (_) {}
            }

            // Fallback 3: lookup by Guid alone (first match)
            if (fallback == null && guid != null && guid.isNotEmpty) {
              try {
                fallback = await _client
                    .from('owner_master')
                    .select('id')
                    .eq('Guid', guid)
                    .limit(1)
                    .maybeSingle();
              } catch (_) {}
            }

            if (fallback != null) {
              debugPrint('⚠️ Owner already exists (duplicate key), using existing id=${fallback['id']}');
              return fallback['id'] as String;
            }
            rethrow;
          }
          rethrow;
        }
      }
    } on PostgrestException catch (e) {
      throw Exception('Failed to create/update owner: $e');
    } catch (e) {
      throw Exception('Failed to create/update owner: $e');
    }
  }

  /// ===== BOOKING OPERATIONS =====

  /// Create booking without company filtering
  Future<void> createBooking(BuildContext context, Map<String, dynamic> bookingData) async {
    // bookings table doesn't have company fields, use data as-is
    final dataWithCompany = bookingData;

    try {
      await _client.from('bookings').insert(dataWithCompany);
    } catch (e) {
      throw Exception('Failed to create booking: $e');
    }
  }

  /// Get all bookings without company filtering
  Future<List<Map<String, dynamic>>> getCompanyBookings(BuildContext context) async {
    // Company selection has been removed, fetch all bookings
    try {
      final response = await _client
          .from('bookings')
          .select('*, assigned_pudo:assigned_pudo_id(username)')
          .neq('status', AppConstants.statusCompleted)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch bookings: $e');
    }
  }

  /// ===== SERVICE REMINDER OPERATIONS =====

  /// Create service reminder without company filtering
  Future<void> createServiceReminder(BuildContext context, Map<String, dynamic> reminderData) async {
    // Company selection has been removed, proceed without company filtering
    final dataWithCompany = reminderData; // Use data as-is without adding company

    try {
      await _client.from('service_reminders').insert(dataWithCompany);
    } catch (e) {
      throw Exception('Failed to create service reminder: $e');
    }
  }

  /// Get all service reminders without company filtering
  Future<List<Map<String, dynamic>>> getCompanyServiceReminders(BuildContext context) async {
    // Company selection has been removed, fetch all service reminders
    try {
      final response = await _client
          .from('service_reminders')
          .select('*')
          .order('next_service_due_date', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch service reminders: $e');
    }
  }

  /// ===== UTILITY METHODS =====

  /// Validate data (company validation disabled)
  bool validateDataOwnership(BuildContext context, Map<String, dynamic> data) {
    // Company selection has been removed, always return true
    return true;
  }

  /// Filter data (company filtering disabled)
  List<Map<String, dynamic>> filterByCurrentCompany(BuildContext context, List<Map<String, dynamic>> data) {
    // Company selection has been removed, return data as-is
    return data;
  }

  /// Get company name (disabled)
  String? getCurrentCompanyName(BuildContext context) {
    // Company selection has been removed
    return null;
  }
}
