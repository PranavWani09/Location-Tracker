import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location_tracker/Screens/dashboard.dart';
import 'package:location_tracker/Screens/login.dart';

// Config class for consistent API URL
class Config {
  static const String apiBaseUrl = 'http://172.20.10.2:8001';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Workmanager with callbackDispatcher from dashboard.dart
  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  print("📅 Workmanager initialized");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _checkLoginStatus() async {
    try {
      const storage = FlutterSecureStorage();
      final apiKey = await storage.read(key: 'api_key');
      final apiSecret = await storage.read(key: 'api_secret');
      final isLoggedIn = (apiKey != null && apiKey.isNotEmpty && apiSecret != null && apiSecret.isNotEmpty);
      print("🔍 Login status check: isLoggedIn=$isLoggedIn, apiKey=$apiKey, apiSecret=$apiSecret");
      return isLoggedIn;
    } catch (e, stack) {
      print("🔥 Error checking login status: $e");
      print("🔥 Stack: $stack");
      return false;
    }
  }

  Future<void> _requestPermissions() async {
    try {
      if (await Permission.location.isDenied) {
        await Permission.location.request();
      }
      if (await Permission.locationAlways.isDenied) {
        await Permission.locationAlways.request();
      }
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
      print("✅ Permissions requested");
    } catch (e, stack) {
      print("🔥 Error requesting permissions: $e");
      print("🔥 Stack: $stack");
    }
  }

  @override
  Widget build(BuildContext context) {
    _requestPermissions();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Location Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: FutureBuilder<bool>(
        future: _checkLoginStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else {
            if (snapshot.hasError || snapshot.data != true) {
              print("🔍 Login check failed or user not logged in: ${snapshot.error}");
              return const LoginPage();
            } else {
              print("🔍 User is logged in, navigating to Dashboard");
              return const DashboardPage();
            }
          }
        },
      ),
      routes: {
        '/home': (context) => const DashboardPage(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}