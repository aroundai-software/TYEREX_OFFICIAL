// lib/screens/login_screen.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/admin_settings_provider.dart';
import '../providers/report_provider.dart';
import 'main_dashboard.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import 'admin/admin_dashboard_screen.dart';
import 'accountant/accountant_dashboard_screen.dart';
import 'warranty/warranty_dashboard_screen.dart';
import 'super_admin/super_admin_dashboard_screen.dart';

import '../utils/validators.dart';
import '../utils/app_constants.dart';
import '../utils/app_exceptions.dart';
import '../services/biometric_auth_service.dart';
import '../providers/user_preferences_provider.dart';
import '../widgets/modern_page_route.dart';
import '../widgets/modern_input.dart';
import '../widgets/modern_button.dart';
import '../services/company_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  final supabase = Supabase.instance.client;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      late final Map<String, dynamic> userRecord;

      // Check Super Admin master credentials (purely in-memory, ZERO database footprint)
      final isSuperAdminCreds = username.toLowerCase() == 'superadmin' && password == 'Supabase1234#';

      if (isSuperAdminCreds) {
        // Pure in-memory Super Admin session:
        // No row is created, queried, or updated in Supabase users table.
        userRecord = {
          'id': 999999,
          'username': 'superadmin',
          'role': AppConstants.roleSuperAdmin,
          'is_active': true,
        };
      } else {
        // Standard user database lookup
        final response = await supabase
            .from('users')
            .select()
            .ilike('username', username)
            .single();

        if (response['is_active'] == false) {
          throw AuthenticationException('Account is disabled. Please contact administrator.');
        }

        if (response['password'] != password) {
          throw AuthenticationException('Invalid credentials');
        }

        userRecord = response;
      }

      final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            AppConstants.cacheKeyCurrentUser, jsonEncode(userRecord));

        if (!mounted) return;
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final reportProvider = Provider.of<ReportProvider>(context, listen: false);
        final settingsProvider = context.read<AdminSettingsProvider>();

        // Clear report cache
        reportProvider.clearCache();

        // Load and assign companies for this user
        final allocatedBranches = await CompanyService().loadCompaniesForUser(userRecord);

        // If user is not Super Admin and has NO branches allocated, block login!
        if (userRecord['role'] != AppConstants.roleSuperAdmin && allocatedBranches.isEmpty) {
          CompanyService().clearCache();
          throw AuthenticationException(
            'Access Denied: No branch has been allocated to your account. Please contact your administrator.',
          );
        }

        // Set user in provider
        userProvider.setUser(userRecord);

        // Save FCM token if ID is a real DB user
        if (userRecord['id'] != null && userRecord['id'] is int && userRecord['id'] != 999999) {
          _saveFcmToken(userRecord['id']);
        }

        // Load settings
        await settingsProvider.loadSettings();

        if (!mounted) return;
        final role = userRecord['role'];

        Widget targetScreen;

        switch (role) {
          case AppConstants.roleSuperAdmin:
            targetScreen = const SuperAdminDashboardScreen();
            break;
          case AppConstants.roleAdmin:
            targetScreen = const AdminDashboardScreen();
            break;
          case AppConstants.roleAccountant:
            targetScreen = const AccountantDashboardScreen();
            break;
          case AppConstants.roleWarranty:
            targetScreen = const WarrantyDashboardScreen();
            break;
          case AppConstants.roleExecutive:
          default:
            targetScreen = const MainDashboard();
            break;
        }

        context.pushReplacementModern(
          targetScreen,
          transition: RouteTransitionType.fadeScale,
        );
    } on PostgrestException catch (e) {
      _showErrorSnackBar('Login failed: ${e.message}');
    } on AuthenticationException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (error) {
      _showErrorSnackBar('Invalid credentials or network error.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveFcmToken(int userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) {
        await supabase.from('users').update({'fcm_token': token}).eq('id', userId);
        debugPrint('✅ FCM token saved for user $userId');
      }
    } catch (e) {
      debugPrint('⚠️ FCM token save failed (non-critical): $e');
    }
  }

  Future<void> _biometricLogin() async {
    try {
      final biometricService = BiometricAuthService();
      final authenticated = await biometricService.authenticate(
        localizedReason: 'Authenticate to login to TyreX',
      );

      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        final cachedUserJson = prefs.getString(AppConstants.cacheKeyCurrentUser);

        if (cachedUserJson != null) {
          final cachedUser = jsonDecode(cachedUserJson);

          try {
            final response = await supabase.from('users').select().eq('id', cachedUser['id']).single();
            if (response['is_active'] == false) {
              _showErrorSnackBar('Account is disabled. Please contact administrator.');
              return;
            }
          } catch (_) {}

          if (!mounted) return;
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          final reportProvider = Provider.of<ReportProvider>(context, listen: false);
          final settingsProvider = context.read<AdminSettingsProvider>();

          reportProvider.clearCache();

          // Load allocated company for user
          await CompanyService().loadCompaniesForUser(cachedUser);

          // Set user
          userProvider.setUser(cachedUser);

          // Load settings
          await settingsProvider.loadSettings();

          if (!mounted) return;
          final role = cachedUser['role'];

          Widget targetScreen;

          switch (role) {
            case AppConstants.roleSuperAdmin:
              targetScreen = const SuperAdminDashboardScreen();
              break;
            case AppConstants.roleAdmin:
              targetScreen = const AdminDashboardScreen();
              break;
            case AppConstants.roleAccountant:
              targetScreen = const AccountantDashboardScreen();
              break;
            case AppConstants.roleWarranty:
              targetScreen = const WarrantyDashboardScreen();
              break;
            case AppConstants.roleExecutive:
            default:
              targetScreen = const MainDashboard();
              break;
          }

          context.pushReplacementModern(
            targetScreen,
            transition: RouteTransitionType.fadeScale,
          );
        } else {
          _showErrorSnackBar('Please login with username and password first');
        }
      }
    } catch (error) {
      _showErrorSnackBar('Biometric authentication failed');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLg),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Logo (TyreGuru Branding - Extra Large & Prominent)
                    Container(
                      height: 220,
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Transform.scale(
                        scale: 1.35,
                        child: Image.asset(
                          'assets/images/TYREGURU.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ).animate().fadeIn(duration: 400.ms),

                    // Welcome Headline
                    const Text(
                      'Welcome Back!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 6),
                    const Text(
                      'Sign in to continue to TyreX',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 150.ms).slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 24),

                    // Main Login Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Username Field
                            ModernTextField(
                              controller: _usernameController,
                              label: 'Username',
                              hint: 'Enter your username',
                              prefixIcon: const Icon(Icons.person_outline),
                              validator: (value) => Validators.validateRequired(
                                value,
                                fieldName: 'Username',
                              ),
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                            ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideX(begin: -0.1, end: 0),
                            const SizedBox(height: 16),

                            // Password Field
                            ModernTextField(
                              controller: _passwordController,
                              label: 'Password',
                              hint: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0xFF8F9BB3),
                                  size: 22,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              validator: (value) => Validators.validateRequired(
                                value,
                                fieldName: 'Password',
                              ),
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _login(),
                            ).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideX(begin: 0.1, end: 0),
                            const SizedBox(height: 24),

                            // Sign In Button
                            ModernButton(
                              text: 'Sign In',
                              icon: Icons.login,
                              onPressed: _login,
                              isLoading: _isLoading,
                              width: double.infinity,
                            ).animate().fadeIn(duration: 400.ms, delay: 400.ms).scale(begin: const Offset(0.95, 0.95)),

                            // Biometric Login Option
                            Consumer2<UserPreferencesProvider, AdminSettingsProvider>(
                              builder: (context, prefsProvider, adminSettingsProvider, child) {
                                if (!adminSettingsProvider.featureBiometricAuth) {
                                  return const SizedBox.shrink();
                                }
                                if (!prefsProvider.biometricEnabled) {
                                  return const SizedBox.shrink();
                                }
                                return FutureBuilder<bool>(
                                  future: BiometricAuthService().canCheckBiometrics(),
                                  builder: (context, snapshot) {
                                    if (snapshot.data != true) {
                                      return const SizedBox.shrink();
                                    }
                                    return Column(
                                      children: [
                                        const SizedBox(height: 18),
                                        Row(
                                          children: [
                                            Expanded(child: Divider(color: Colors.grey.shade200)),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 14),
                                              child: Text(
                                                'OR',
                                                style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Expanded(child: Divider(color: Colors.grey.shade200)),
                                          ],
                                        ),
                                        const SizedBox(height: 18),
                                        ModernButton(
                                          text: 'Login with Biometrics',
                                          icon: Icons.fingerprint,
                                          onPressed: _biometricLogin,
                                          isOutlined: true,
                                          width: double.infinity,
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(begin: 0.15, end: 0),

                    const SizedBox(height: 28),

                    // Professional Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 15, color: Colors.blueGrey.shade400),
                        const SizedBox(width: 6),
                        Text(
                          'TyreX Enterprise Management Portal',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade600,
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 400.ms, delay: 500.ms),
                    const SizedBox(height: 6),
                    Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
