// lib/providers/user_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/company_service.dart';
import '../services/auth_helper.dart';
import '../utils/app_constants.dart';

class UserProvider extends ChangeNotifier with WidgetsBindingObserver {
  Timer? _pollingTimer;

  UserProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIsActiveStatus();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // Poll every 3 minutes
    _pollingTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _checkIsActiveStatus();
    });
  }

  Future<void> _checkIsActiveStatus() async {
    if (_user == null) return;
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', _user!['id'])
          .single();
          
      if (response['is_active'] == false) {
        debugPrint('User is inactive. Logging out forcefully.');
        await AuthHelper.logout();
      }
    } catch (e) {
      // Ignore errors silently (could be offline or column doesn't exist yet)
    }
  }
  // Private variable to hold the current user data.
  Map<String, dynamic>? _user;
  
  // Public getter to safely expose the user data to the rest of the app.
  Map<String, dynamic>? get user => _user;
  
  bool get isSuperAdmin => _user?['role'] == AppConstants.roleSuperAdmin;
  bool get isAdmin => _user?['role'] == AppConstants.roleAdmin || _user?['role'] == AppConstants.roleSuperAdmin;

  /// Sets the current user (e.g., on login or session restore).
  /// Pass `null` to log out.
  void setUser(Map<String, dynamic>? userData) async {
    _user = userData;
    notifyListeners();
    
    if (userData == null) {
      _pollingTimer?.cancel();
      // Clear company cache on logout
      CompanyService().clearCache();
    } else {
      _startPolling();
      _checkIsActiveStatus(); // Initial check
      try {
        await CompanyService().loadCompaniesForUser(userData);
      } catch (e) {
        debugPrint('⚠️ Failed to sync branch for user in setUser: $e');
      }
    }
  }
  
  int? get userId => _user?['id'] as int?;

  /// Switches to another user (used during Quick Access impersonation).
  void switchToUser(Map<String, dynamic> user) async {
    _user = user;
    notifyListeners();
    try {
      await CompanyService().loadCompaniesForUser(user);
    } catch (e) {
      debugPrint('⚠️ Failed to sync branch in switchToUser: $e');
    }
  }

  /// Restores the original admin session after Quick Access.
  void restoreOriginalAdmin(Map<String, dynamic> adminUser) async {
    _user = adminUser;
    notifyListeners();
    try {
      await CompanyService().loadCompaniesForUser(adminUser);
    } catch (e) {
      debugPrint('⚠️ Failed to sync branch in restoreOriginalAdmin: $e');
    }
  }

  /// Initialize provider and load active company (called during app startup)
  Future<void> initialize() async {
    if (_user != null) {
      await CompanyService().loadCompaniesForUser(_user);
    } else if (!CompanyService().hasActiveCompany) {
      final restored = await CompanyService().loadPersistedCompany();
      if (!restored) {
        try {
          await CompanyService().loadActiveCompany();
        } catch (e) {
          debugPrint('⚠️ Failed to load active company during initialization: $e');
        }
      }
    }
  }
}