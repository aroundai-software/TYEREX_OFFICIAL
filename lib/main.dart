// lib/main.dart
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Providers
import './providers/admin_settings_provider.dart';
import './providers/user_provider.dart';
import './providers/report_provider.dart';
import './providers/user_preferences_provider.dart';

// Screens
import './screens/login_screen.dart';
import './screens/admin/admin_dashboard_screen.dart';
import './screens/main_dashboard.dart';
import './screens/accountant/accountant_dashboard_screen.dart';
import './screens/warranty/warranty_dashboard_screen.dart';
import './screens/super_admin/super_admin_dashboard_screen.dart';

// Theme & Utils
import './theme/app_theme.dart';
import './utils/app_constants.dart';
import './services/local_media_service.dart';
import './services/notification_service.dart';

// Firebase background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background messages are handled automatically by the OS
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LocalMediaService.initialize();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Initialize notifications (requires Firebase to be initialized first)
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Firebase initialization failed (probably missing web options): $e');
  }

  await Supabase.initialize(
    url: 'https://nodzljxarvnhwrzakwyz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vZHpsanhhcnZuaHdyemFrd3l6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NDg4MjYsImV4cCI6MjEwNTAyNDgyNn0.ZlnBAoF3MTZUp0xUxArST0w_XgQgIWITfzaynHaGgcg',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AdminSettingsProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ReportProvider()),
        ChangeNotifierProvider(create: (_) => UserPreferencesProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TyreX',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      home: const StartupRouter(),
    );
  }
}

class StartupRouter extends StatefulWidget {
  const StartupRouter({super.key});

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapSession());
  }

  Future<void> _bootstrapSession() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUserJson = prefs.getString(AppConstants.cacheKeyCurrentUser);

    // Initialize UserProvider and load active company regardless of login status
    await context.read<UserProvider>().initialize();

    if (!mounted) return;

    if (storedUserJson == null) {
      _navigateTo(const LoginScreen());
      return;
    }

    try {
      final storedUser = jsonDecode(storedUserJson) as Map<String, dynamic>;
      Map<String, dynamic> activeUser = storedUser;
      
      // Verify is_active status and get fresh user data including latest branch allocations for DB users
      if (storedUser['role'] != AppConstants.roleSuperAdmin && storedUser['id'] != 999999) {
        try {
          final response = await Supabase.instance.client
              .from('users')
              .select()
              .eq('id', storedUser['id'])
              .single();
              
          if (response['is_active'] == false) {
            await prefs.remove(AppConstants.cacheKeyCurrentUser);
            if (!mounted) return;
            _navigateTo(const LoginScreen());
            return;
          }

          activeUser = response;
          await prefs.setString(AppConstants.cacheKeyCurrentUser, jsonEncode(response));
        } catch (e) {
          debugPrint('Could not verify is_active status during bootstrap: $e');
        }
      }

      final userProvider = context.read<UserProvider>();
      userProvider.setUser(activeUser);

      await context.read<AdminSettingsProvider>().loadSettings();

      if (!mounted) return;
      final destination = _screenForRole(activeUser['role'] as String?);
      _navigateTo(destination);
    } catch (_) {
      await prefs.remove(AppConstants.cacheKeyCurrentUser);
      if (!mounted) return;
      _navigateTo(const LoginScreen());
    }
  }

  Widget _screenForRole(String? role) {
    final normalizedRole = _normalizeRole(role);

    switch (normalizedRole) {
      case AppConstants.roleSuperAdmin:
        return const SuperAdminDashboardScreen();
      case AppConstants.roleAdmin:
        return const AdminDashboardScreen();
      case AppConstants.roleAccountant:
        return const AccountantDashboardScreen();
      case AppConstants.roleWarranty:
        return const WarrantyDashboardScreen();

      case AppConstants.roleExecutive:
      default:
        return const MainDashboard();
    }
  }

  void _navigateTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  String _normalizeRole(String? role) {
    switch (role) {
      case 'tele_caller':
      case 'telecaller':
        return AppConstants.roleTeleCaller;
      case 'pudo':
        return AppConstants.rolePickupDropoff;
      default:
        return role ?? AppConstants.roleExecutive;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}